"use client";

import CalendarApp from "./CalendarApp";
import { useDemoSource } from "@/lib/source";

/** `npm run dev` harness: the real UI against demo data, no account needed. */
export default function DemoHost({
  initialView,
  gate = false,
}: {
  initialView?: "day" | "week";
  gate?: boolean;
}) {
  const [snapshot, actions] = useDemoSource();

  // ?gate=1 previews the sign-in screen, which the Mac app normally drives.
  const preview = gate ? { ...snapshot, phase: "signedOut" as const } : snapshot;

  return <CalendarApp snapshot={preview} actions={actions} demo initialView={initialView} />;
}
