import { NextResponse } from "next/server";
import { demoEvents } from "@/lib/demo";

export const dynamic = "force-dynamic";

/**
 * Demo data for the development harness. The Mac app talks to Google
 * directly and never calls this.
 */
export async function GET() {
  return NextResponse.json({ events: demoEvents(), fetchedAt: new Date().toISOString() });
}
