import Link from "next/link";

import { signIn } from "@/auth";

/** The only screen with visible chrome — and only until the calendar is linked. */
export default function Gate({ configured }: { configured: boolean }) {
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

        {configured ? (
          <>
            <p className="mx-auto mt-4 max-w-sm text-[0.95rem] font-light leading-relaxed text-white/40">
              Link a Google account once. Read-only — it never writes to your calendar.
            </p>

            <form
              action={async () => {
                "use server";
                await signIn("google", { redirectTo: "/" });
              }}
              className="mt-10"
            >
              <button
                type="submit"
                className="rounded-full bg-white/[0.06] px-7 py-3 text-[0.9rem] font-light tracking-[0.02em] text-white/90 ring-1 ring-white/10 transition-all duration-300 hover:bg-white/[0.1] hover:ring-white/20"
              >
                Connect Google Calendar
              </button>
            </form>

            <Link
              href="/?demo=1"
              className="mt-6 inline-block text-[0.78rem] font-light tracking-[0.08em] text-white/25 transition-colors hover:text-white/50"
            >
              or view the demo
            </Link>
          </>
        ) : (
          <>
            <p className="mx-auto mt-4 max-w-sm text-[0.95rem] font-light leading-relaxed text-white/40">
              Not linked yet. Add these environment variables, then reload:
            </p>

            <div className="mx-auto mt-7 w-full rounded-xl bg-white/[0.03] p-5 text-left ring-1 ring-white/[0.07]">
              <ul className="space-y-2 font-mono text-[0.8rem] font-light text-white/50">
                <li>AUTH_GOOGLE_ID</li>
                <li>AUTH_GOOGLE_SECRET</li>
                <li>AUTH_SECRET</li>
              </ul>
            </div>

            <p className="mt-5 text-[0.78rem] font-light leading-relaxed text-white/25">
              Setup steps are in the README.
            </p>

            <Link
              href="/?demo=1"
              className="mt-8 inline-block rounded-full bg-white/[0.06] px-7 py-3 text-[0.9rem] font-light text-white/90 ring-1 ring-white/10 transition-all hover:bg-white/[0.1]"
            >
              View the demo
            </Link>
          </>
        )}
      </div>
    </main>
  );
}
