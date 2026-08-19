"use client";

import Display from "./Display";
import Gate from "./Gate";
import type { Actions, Snapshot } from "@/lib/source";

/** Picks between the sign-in screen and the display, in either host. */
export default function CalendarApp({
  snapshot,
  actions,
  demo = false,
  initialView,
}: {
  snapshot: Snapshot;
  actions: Actions;
  demo?: boolean;
  initialView?: "day" | "week";
}) {
  if (snapshot.phase === "signedOut" || snapshot.phase === "error") {
    return <Gate snapshot={snapshot} onSignIn={actions.signIn} />;
  }

  // First sync of a fresh launch: say so quietly rather than flashing an empty day.
  if (snapshot.phase === "loading" && snapshot.events.length === 0) {
    return (
      <main className="flex h-dvh w-screen items-center justify-center bg-void">
        <p className="rise text-[0.72rem] font-light tracking-[0.22em] text-white/25">
          SYNCING…
        </p>
      </main>
    );
  }

  return (
    <Display snapshot={snapshot} actions={actions} demo={demo} initialView={initialView} />
  );
}
