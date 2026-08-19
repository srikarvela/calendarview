"use client";

import type { Snapshot } from "@/lib/source";

/** The only screen with a visible control — and only until you have signed in. */
export default function Gate({
  snapshot,
  onSignIn,
}: {
  snapshot: Snapshot;
  onSignIn: () => void;
}) {
  const failed = snapshot.phase === "error";
  const busy = snapshot.phase === "loading";

  return (
    <main className="relative flex h-dvh w-screen items-center justify-center overflow-hidden bg-void px-8">
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-1/2 h-[80vh] w-[80vh] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,#8ab4f81f,transparent_65%)] blur-[120px]"
      />

      <div className="rise relative w-full max-w-md text-center">
        <p className="text-[0.7rem] font-medium tracking-[0.28em] text-white/30">CALENDARVIEW</p>

        <h1 className="mt-6 text-[clamp(1.9rem,4vw,2.9rem)] font-extralight leading-tight tracking-[-0.03em] text-white">
          Your day, full screen.
        </h1>

        <p className="mx-auto mt-4 max-w-sm text-[0.95rem] font-light leading-relaxed text-white/40">
          {failed
            ? snapshot.error
            : "Sign in with Google once. Read-only — it never writes to your calendar."}
        </p>

        <button
          onClick={onSignIn}
          disabled={busy}
          className="mt-10 rounded-full bg-white/[0.06] px-7 py-3 text-[0.9rem] font-light tracking-[0.02em] text-white/90 ring-1 ring-white/10 transition-all duration-300 hover:bg-white/[0.1] hover:ring-white/20 disabled:opacity-40"
        >
          {busy ? "Signing in…" : failed ? "Try again" : "Sign in with Google"}
        </button>
      </div>
    </main>
  );
}
