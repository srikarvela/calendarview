import type { CalEvent } from "./types";

/**
 * Sample day used by the public demo (and by the README screenshots).
 * Built relative to "now" so the display always looks live.
 */
export function demoEvents(now = new Date()): CalEvent[] {
  const at = (dayOffset: number, h: number, m = 0) => {
    const d = new Date(now);
    d.setDate(d.getDate() + dayOffset);
    d.setHours(h, m, 0, 0);
    return d.toISOString();
  };
  const dayStr = (dayOffset: number) => {
    const d = new Date(now);
    d.setDate(d.getDate() + dayOffset);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
      d.getDate(),
    ).padStart(2, "0")}`;
  };

  const mk = (
    id: string,
    title: string,
    start: string,
    end: string,
    extra: Partial<CalEvent> = {},
  ): CalEvent => ({
    id,
    title,
    start,
    end,
    allDay: false,
    attendees: 0,
    color: "#5b9dff",
    calendar: "Work",
    declined: false,
    ...extra,
  });

  // Anchor the "happening now" event to the current hour so the demo always
  // shows the live state.
  const h = now.getHours();
  const nowStart = new Date(now);
  nowStart.setMinutes(now.getMinutes() - 18, 0, 0);
  const nowEnd = new Date(now);
  nowEnd.setMinutes(now.getMinutes() + 27, 0, 0);

  return [
    mk("d0", "Design review — ambient display", nowStart.toISOString(), nowEnd.toISOString(), {
      color: "#c77dff",
      attendees: 5,
      meetLink: "https://meet.google.com/demo",
      calendar: "Design",
    }),
    mk("d1", "Focus block: calendar sync", at(0, Math.min(h + 1, 22)), at(0, Math.min(h + 3, 23)), {
      color: "#2ee6a8",
      calendar: "Personal",
    }),
    mk("d2", "1:1 with Priya", at(0, Math.min(h + 4, 23)), at(0, Math.min(h + 4, 23), 30), {
      color: "#ffd60a",
      attendees: 2,
      location: "Corner room",
    }),
    mk("d3", "Standup", at(1, 9, 30), at(1, 9, 45), { attendees: 8, color: "#22d3ee" }),
    mk("d4", "Quarterly planning", at(1, 11), at(1, 12, 30), {
      color: "#ff9f45",
      attendees: 12,
      location: "Studio B",
    }),
    mk("d5", "Dinner with Sam", at(1, 19), at(1, 21), {
      color: "#ff5c5c",
      calendar: "Personal",
      location: "Nopa",
    }),
    {
      id: "d6",
      title: "Offsite",
      start: dayStr(2),
      end: dayStr(3),
      allDay: true,
      attendees: 0,
      color: "#5b9dff",
      calendar: "Work",
      declined: false,
    },
    mk("d7", "Flight to SFO", at(2, 7, 5), at(2, 13, 40), {
      color: "#a8b3c4",
      calendar: "Travel",
      location: "JFK T4",
    }),
  ].sort((a, b) => a.start.localeCompare(b.start));
}
