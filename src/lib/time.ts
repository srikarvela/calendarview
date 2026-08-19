import type { CalEvent } from "./types";

/** All-day events arrive as YYYY-MM-DD; parse them in local time, not UTC. */
export function parseStart(e: CalEvent): Date {
  return e.allDay ? parseLocalDate(e.start) : new Date(e.start);
}

export function parseEnd(e: CalEvent): Date {
  return e.allDay ? parseLocalDate(e.end) : new Date(e.end);
}

function parseLocalDate(s: string): Date {
  const [y, m, d] = s.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function dayKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}

export function fmtTime(d: Date): { time: string; suffix: string } {
  const h = d.getHours();
  const m = d.getMinutes();
  const suffix = h < 12 ? "am" : "pm";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return { time: m === 0 ? `${h12}` : `${h12}:${String(m).padStart(2, "0")}`, suffix };
}

/** Wall clock: always h:mm, unlike fmtTime which drops a zero minute. */
export function fmtClock(d: Date): { time: string; suffix: string } {
  const h = d.getHours();
  const suffix = h < 12 ? "am" : "pm";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return { time: `${h12}:${String(d.getMinutes()).padStart(2, "0")}`, suffix };
}

export function fmtRange(e: CalEvent): string {
  if (e.allDay) return "all day";
  const a = fmtTime(parseStart(e));
  const b = fmtTime(parseEnd(e));
  const left = a.suffix === b.suffix ? a.time : `${a.time}${a.suffix}`;
  return `${left} – ${b.time}${b.suffix}`;
}

export function fmtDuration(ms: number): string {
  const mins = Math.round(ms / 60000);
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/** "in 20 min" / "in 3h 10m" / "tomorrow 9am" — deliberately conversational. */
export function untilLabel(from: Date, target: Date): string {
  const ms = target.getTime() - from.getTime();
  if (ms <= 0) return "now";
  const mins = Math.round(ms / 60000);
  if (mins < 1) return "in under a minute";
  if (mins < 60) return `in ${mins} min`;
  if (mins < 60 * 10) {
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m === 0 ? `in ${h}h` : `in ${h}h ${m}m`;
  }
  const sameDay = dayKey(from) === dayKey(target);
  const t = fmtTime(target);
  if (sameDay) return `at ${t.time}${t.suffix}`;
  const tomorrow = new Date(from);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const prefix =
    dayKey(tomorrow) === dayKey(target)
      ? "tomorrow"
      : target.toLocaleDateString(undefined, { weekday: "long" });
  return `${prefix} ${t.time}${t.suffix}`;
}

export function dayLabel(key: string, today: Date): string {
  const [y, m, d] = key.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  const diff = Math.round(
    (date.getTime() - new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()) /
      86400000,
  );
  if (diff === 0) return "Today";
  if (diff === 1) return "Tomorrow";
  if (diff < 7) return date.toLocaleDateString(undefined, { weekday: "long" });
  return date.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" });
}
