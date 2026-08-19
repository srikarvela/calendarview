"use client";

import { useCallback, useEffect, useState } from "react";
import type { CalEvent } from "./types";

export type Phase = "loading" | "signedOut" | "ready" | "error";

export type Snapshot = {
  phase: Phase;
  events: CalEvent[];
  account?: string;
  error?: string;
  /** Set when a refresh failed but we still have events worth showing. */
  stale?: boolean;
};

export type Actions = {
  signIn: () => void;
  signOut: () => void;
  refresh: () => void;
};

/* ---------------------------------------------------------------- native */

type NativeBridge = { postMessage: (msg: unknown) => void };

declare global {
  interface Window {
    webkit?: { messageHandlers?: { calendarview?: NativeBridge } };
    __calendarview_push?: (snapshot: Snapshot) => void;
  }
}

export function isNative(): boolean {
  return typeof window !== "undefined" && !!window.webkit?.messageHandlers?.calendarview;
}

function send(type: string) {
  window.webkit?.messageHandlers?.calendarview?.postMessage({ type });
}

/**
 * In the Mac app the native side owns the Google session and the syncing;
 * it pushes a whole snapshot whenever anything changes.
 */
export function useNativeSource(): [Snapshot, Actions] {
  const [snapshot, setSnapshot] = useState<Snapshot>({ phase: "loading", events: [] });

  useEffect(() => {
    window.__calendarview_push = (next) => setSnapshot(next);
    send("ready");
    return () => {
      delete window.__calendarview_push;
    };
  }, []);

  const actions: Actions = {
    signIn: useCallback(() => send("signIn"), []),
    signOut: useCallback(() => send("signOut"), []),
    refresh: useCallback(() => send("refresh"), []),
  };

  return [snapshot, actions];
}

/* ------------------------------------------------------------------ web */

const REFRESH_MS = 60_000;

/** Used by the dev harness (`npm run dev`) to preview against demo data. */
export function useDemoSource(): [Snapshot, Actions] {
  const [snapshot, setSnapshot] = useState<Snapshot>({ phase: "loading", events: [] });

  const refresh = useCallback(async () => {
    try {
      const res = await fetch("/api/events?demo=1", { cache: "no-store" });
      if (!res.ok) throw new Error(String(res.status));
      const data = (await res.json()) as { events: CalEvent[] };
      setSnapshot({ phase: "ready", events: data.events, account: "demo@example.com" });
    } catch {
      setSnapshot((prev) => ({ ...prev, phase: "ready", stale: true }));
    }
  }, []);

  useEffect(() => {
    // refresh() only sets state after awaiting the fetch.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    refresh();
    const id = setInterval(refresh, REFRESH_MS);
    const onVisible = () => document.visibilityState === "visible" && refresh();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", refresh);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", refresh);
    };
  }, [refresh]);

  const noop = useCallback(() => {}, []);
  return [snapshot, { signIn: noop, signOut: noop, refresh }];
}
