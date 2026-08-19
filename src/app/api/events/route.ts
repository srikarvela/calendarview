import { NextResponse } from "next/server";
import { auth } from "@/auth";
import type { CalEvent } from "@/lib/types";
import { demoEvents } from "@/lib/demo";

export const dynamic = "force-dynamic";

const API = "https://www.googleapis.com/calendar/v3";

// Google's palette skews bright; these are the same hues tuned for a dark display.
const COLOR_MAP: Record<string, string> = {
  "1": "#8ab4f8", "2": "#7ddba3", "3": "#c58af9", "4": "#ff8a80",
  "5": "#fdd663", "6": "#ffa76a", "7": "#78d9ec", "8": "#9aa0a6",
  "9": "#7a9dfb", "10": "#81c995", "11": "#f28b82",
};
const FALLBACK = "#8ab4f8";

type GCal = {
  id: string;
  summary?: string;
  selected?: boolean;
  primary?: boolean;
  colorId?: string;
  backgroundColor?: string;
};

type GEvent = {
  id: string;
  summary?: string;
  status?: string;
  location?: string;
  hangoutLink?: string;
  colorId?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  attendees?: { self?: boolean; responseStatus?: string }[];
};

async function gfetch<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`${API}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!res.ok) {
    throw Object.assign(new Error(`google ${res.status}`), { status: res.status });
  }
  return res.json() as Promise<T>;
}

export async function GET(req: Request) {
  // Public demo: lets anyone see the display (and powers the README shots).
  if (new URL(req.url).searchParams.get("demo") === "1") {
    return NextResponse.json({ events: demoEvents(), fetchedAt: new Date().toISOString() });
  }

  const session = await auth();

  if (!session?.accessToken) {
    return NextResponse.json({ error: "unauthenticated" }, { status: 401 });
  }
  if (session.error) {
    return NextResponse.json({ error: session.error }, { status: 401 });
  }

  const token = session.accessToken;

  // Window: a little into the past so "happening now" survives a late start,
  // and a week ahead so the display can show what's coming.
  const timeMin = new Date(Date.now() - 12 * 3600_000).toISOString();
  const timeMax = new Date(Date.now() + 8 * 24 * 3600_000).toISOString();

  try {
    const list = await gfetch<{ items?: GCal[] }>("/users/me/calendarList", token);
    const calendars = (list.items ?? []).filter((c) => c.selected !== false);

    const perCalendar = await Promise.all(
      calendars.map(async (cal) => {
        const params = new URLSearchParams({
          timeMin,
          timeMax,
          singleEvents: "true",
          orderBy: "startTime",
          maxResults: "250",
        });

        try {
          // Page through, so a busy week is never silently truncated.
          const items: GEvent[] = [];
          let pageToken: string | undefined;
          do {
            const q = new URLSearchParams(params);
            if (pageToken) q.set("pageToken", pageToken);
            const page = await gfetch<{ items?: GEvent[]; nextPageToken?: string }>(
              `/calendars/${encodeURIComponent(cal.id)}/events?${q}`,
              token,
            );
            items.push(...(page.items ?? []));
            pageToken = page.nextPageToken;
          } while (pageToken && items.length < 1000);

          const data = { items };

          const calColor =
            (cal.colorId && COLOR_MAP[cal.colorId]) || cal.backgroundColor || FALLBACK;

          return (data.items ?? [])
            .filter((e) => e.status !== "cancelled" && (e.start?.dateTime || e.start?.date))
            .map<CalEvent>((e) => {
              const allDay = !e.start?.dateTime;
              const self = e.attendees?.find((a) => a.self);
              return {
                id: `${cal.id}:${e.id}`,
                title: e.summary?.trim() || "(no title)",
                start: (e.start?.dateTime ?? e.start?.date)!,
                end: (e.end?.dateTime ?? e.end?.date)!,
                allDay,
                location: e.location,
                meetLink: e.hangoutLink,
                attendees: e.attendees?.length ?? 0,
                color: (e.colorId && COLOR_MAP[e.colorId]) || calColor,
                calendar: cal.summary ?? cal.id,
                declined: self?.responseStatus === "declined",
              };
            });
        } catch {
          // One unreadable calendar shouldn't blank the whole display.
          return [];
        }
      }),
    );

    const events = perCalendar
      .flat()
      .filter((e) => !e.declined)
      .sort((a, b) => a.start.localeCompare(b.start));

    return NextResponse.json({ events, fetchedAt: new Date().toISOString() });
  } catch (err) {
    const status = (err as { status?: number }).status ?? 500;
    return NextResponse.json({ error: "calendar_fetch_failed" }, { status });
  }
}
