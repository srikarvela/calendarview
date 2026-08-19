import type { CalEvent } from "./types";
import { parseEnd, parseStart } from "./time";

export type Positioned = {
  event: CalEvent;
  /** Minutes from midnight, clamped to the day being rendered. */
  startMin: number;
  endMin: number;
  col: number;
  cols: number;
  continuesBefore: boolean;
  continuesAfter: boolean;
};

const DAY_MIN = 24 * 60;
/** Below this, a block is too short to read — Google pads short events too. */
const MIN_BLOCK_MIN = 20;

/**
 * Lay out one day's timed events: clip to the day, then pack overlapping
 * events into side-by-side columns the way Google Calendar does.
 */
export function layoutDay(events: CalEvent[], day: Date): Positioned[] {
  const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
  const dayEnd = dayStart + DAY_MIN * 60_000;

  const clipped = events
    .filter((e) => !e.allDay)
    .map((e) => {
      const s = parseStart(e).getTime();
      const en = parseEnd(e).getTime();
      return { e, s, en };
    })
    .filter(({ s, en }) => en > dayStart && s < dayEnd)
    .map(({ e, s, en }) => ({
      event: e,
      startMin: Math.max(0, Math.round((s - dayStart) / 60_000)),
      endMin: Math.min(DAY_MIN, Math.round((en - dayStart) / 60_000)),
      continuesBefore: s < dayStart,
      continuesAfter: en > dayEnd,
    }))
    .sort((a, b) => a.startMin - b.startMin || b.endMin - a.endMin);

  // Padded span used only for overlap math, so two back-to-back short events
  // don't get stacked into the same visual slot.
  const span = (p: { startMin: number; endMin: number }) => ({
    from: p.startMin,
    to: Math.max(p.endMin, p.startMin + MIN_BLOCK_MIN),
  });

  const out: Positioned[] = [];
  let cluster: typeof clipped = [];
  let clusterEnd = -1;

  const flush = () => {
    if (!cluster.length) return;
    const colEnds: number[] = [];
    const assigned = cluster.map((p) => {
      const { from, to } = span(p);
      let col = colEnds.findIndex((end) => end <= from);
      if (col === -1) {
        col = colEnds.length;
        colEnds.push(to);
      } else {
        colEnds[col] = to;
      }
      return { p, col };
    });
    const cols = colEnds.length;
    for (const { p, col } of assigned) out.push({ ...p, col, cols });
    cluster = [];
    clusterEnd = -1;
  };

  for (const p of clipped) {
    const { from, to } = span(p);
    if (cluster.length && from >= clusterEnd) flush();
    cluster.push(p);
    clusterEnd = Math.max(clusterEnd, to);
  }
  flush();

  return out.sort((a, b) => a.startMin - b.startMin || a.col - b.col);
}

/** Sunday-start week containing `d`, as seven local dates. */
export function weekDays(d: Date, weekStartsOn = 0): Date[] {
  const base = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const diff = (base.getDay() - weekStartsOn + 7) % 7;
  base.setDate(base.getDate() - diff);
  return Array.from({ length: 7 }, (_, i) => {
    const day = new Date(base);
    day.setDate(base.getDate() + i);
    return day;
  });
}

/** All-day events overlapping `day`. Google's all-day end date is exclusive. */
export function allDayFor(events: CalEvent[], day: Date): CalEvent[] {
  const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
  const dayEnd = dayStart + DAY_MIN * 60_000;
  return events.filter((e) => {
    if (!e.allDay) return false;
    return parseStart(e).getTime() < dayEnd && parseEnd(e).getTime() > dayStart;
  });
}

/** Hour window to render: tight around the events, never narrower than 8am–8pm. */
export function hourWindow(positioned: Positioned[][]): [number, number] {
  let min = 8;
  let max = 20;
  for (const day of positioned) {
    for (const p of day) {
      min = Math.min(min, Math.floor(p.startMin / 60));
      max = Math.max(max, Math.ceil(p.endMin / 60));
    }
  }
  return [Math.max(0, min - 1), Math.min(24, Math.max(max + 1, min + 6))];
}
