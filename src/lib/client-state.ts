"use client";

import { useMemo, useSyncExternalStore } from "react";

/* A ticking clock and the saved view preference are both client-only values.
   useSyncExternalStore gives them to us without a hydration mismatch and
   without setting state from an effect. */

let cachedNow = Date.now();

function subscribeClock(onChange: () => void) {
  cachedNow = Date.now();
  const id = setInterval(() => {
    cachedNow = Date.now();
    onChange();
  }, 1000);
  onChange();
  return () => clearInterval(id);
}

const clockSnapshot = () => cachedNow;
const noClockOnServer = () => null;

/** The current time, or null until the client has hydrated. */
export function useNow(): Date | null {
  const ms = useSyncExternalStore(subscribeClock, clockSnapshot, noClockOnServer);
  return useMemo(() => (ms === null ? null : new Date(ms)), [ms]);
}

export const VIEW_KEY = "cb:view";
export type View = "day" | "week";

function subscribeStorage(onChange: () => void) {
  window.addEventListener("storage", onChange);
  return () => window.removeEventListener("storage", onChange);
}

function storedViewSnapshot(): View | null {
  const value = window.localStorage.getItem(VIEW_KEY);
  return value === "day" || value === "week" ? value : null;
}

const noStorageOnServer = () => null;

/** The view this browser used last, or null if it has never picked one. */
export function useStoredView(): View | null {
  return useSyncExternalStore(subscribeStorage, storedViewSnapshot, noStorageOnServer);
}

export function rememberView(view: View) {
  try {
    window.localStorage.setItem(VIEW_KEY, view);
  } catch {
    // Private mode or a locked-down profile — the view still works this session.
  }
}
