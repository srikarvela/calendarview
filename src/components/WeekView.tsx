"use client";

import { useEffect, useMemo, useRef } from "react";
import type { CalEvent } from "@/lib/types";
import { allDayFor, hourWindow, layoutDay, weekDays, type Positioned } from "@/lib/layout";
import { dayKey, fmtTime, parseEnd, parseStart } from "@/lib/time";

const HOUR_PX = 62;

export default function WeekView({
  events,
  now,
  anchor,
}: {
  events: CalEvent[];
  now: Date;
  anchor: Date;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const days = useMemo(() => weekDays(anchor), [anchor]);

  const perDay = useMemo(() => days.map((d) => layoutDay(events, d)), [days, events]);
  const [fromHour, toHour] = useMemo(() => hourWindow(perDay), [perDay]);
  const hours = useMemo(
    () => Array.from({ length: toHour - fromHour }, (_, i) => fromHour + i),
    [fromHour, toHour],
  );

  const allDayRows = useMemo(() => days.map((d) => allDayFor(events, d)), [days, events]);
  const hasAllDay = allDayRows.some((r) => r.length > 0);

  const todayKey = dayKey(now);
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const nowInWindow = nowMin >= fromHour * 60 && nowMin <= toHour * 60;
  const showsToday = days.some((d) => dayKey(d) === todayKey);

  // Open on the current hour rather than the top of the window.
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const target = (nowMin - fromHour * 60) * (HOUR_PX / 60) - el.clientHeight * 0.38;
    el.scrollTo({ top: Math.max(0, target), behavior: "smooth" });
    // Only on mount / week change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [anchor.getTime(), fromHour]);

  return (
    <div className="flex h-full min-h-0 flex-col">
      {/* Day headers */}
      <div className="grid shrink-0 grid-cols-[3.4rem_repeat(7,minmax(0,1fr))] border-b border-white/[0.06]">
        <div />
        {days.map((d) => {
          const isToday = dayKey(d) === todayKey;
          return (
            <div key={d.toISOString()} className="px-2 pb-2.5 pt-1 text-center">
              <div
                className={`text-[0.62rem] font-medium tracking-[0.16em] ${
                  isToday ? "text-[#8ab4f8]" : "text-white/28"
                }`}
              >
                {d.toLocaleDateString(undefined, { weekday: "short" }).toUpperCase()}
              </div>
              <div
                className={`nums mx-auto mt-1.5 flex h-8 w-8 items-center justify-center rounded-full text-[1.05rem] font-light transition-colors ${
                  isToday ? "bg-[#8ab4f8] text-[#06070a]" : "text-white/70"
                }`}
              >
                {d.getDate()}
              </div>
            </div>
          );
        })}
      </div>

      {/* All-day band */}
      {hasAllDay && (
        <div className="grid shrink-0 grid-cols-[3.4rem_repeat(7,minmax(0,1fr))] border-b border-white/[0.06] py-1.5">
          <div className="whitespace-nowrap pr-2 text-right text-[0.55rem] font-medium leading-6 tracking-[0.1em] text-white/25">
            ALL-DAY
          </div>
          {allDayRows.map((row, i) => (
            <div key={i} className="space-y-1 px-1">
              {row.map((e) => (
                <div
                  key={e.id}
                  title={e.title}
                  className="truncate rounded-md px-2 py-[3px] text-[0.72rem] font-normal"
                  style={{
                    background: `${e.color}26`,
                    color: e.color,
                    boxShadow: `inset 0 0 0 1px ${e.color}33`,
                  }}
                >
                  {e.title}
                </div>
              ))}
            </div>
          ))}
        </div>
      )}

      {/* Time grid */}
      <div ref={scroller} className="no-scrollbar relative min-h-0 flex-1 overflow-y-auto">
        <div
          className="relative grid grid-cols-[3.4rem_repeat(7,minmax(0,1fr))]"
          style={{ height: hours.length * HOUR_PX }}
        >
          {/* Hour rules + labels */}
          <div className="relative">
            {hours.map((h, i) => (
              <div
                key={h}
                className="nums absolute right-2 -translate-y-1/2 text-[0.62rem] font-light tracking-[0.06em] text-white/30"
                style={{ top: i * HOUR_PX }}
              >
                {i === 0 ? "" : label(h)}
              </div>
            ))}
          </div>

          {days.map((d, di) => (
            <div
              key={d.toISOString()}
              className="relative border-l border-white/[0.05]"
              style={{
                background:
                  dayKey(d) === todayKey ? "linear-gradient(#8ab4f80f,#8ab4f80f)" : undefined,
              }}
            >
              {hours.map((h, i) => (
                <div
                  key={h}
                  className="absolute inset-x-0 border-t border-white/[0.045]"
                  style={{ top: i * HOUR_PX }}
                />
              ))}

              {perDay[di].map((p) => (
                <EventBlock key={p.event.id} p={p} fromHour={fromHour} now={now} day={d} />
              ))}

              {showsToday && nowInWindow && dayKey(d) === todayKey && (
                <div
                  className="pointer-events-none absolute inset-x-0 z-20"
                  style={{ top: (nowMin - fromHour * 60) * (HOUR_PX / 60) }}
                >
                  <div className="relative h-px bg-[#f28b82] shadow-[0_0_8px_#f28b8299]">
                    <span className="absolute -left-[3.5px] -top-[3.5px] h-[8px] w-[8px] rounded-full bg-[#f28b82] shadow-[0_0_8px_#f28b82]" />
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function label(h: number) {
  const s = fmtTime(new Date(2000, 0, 1, h, 0));
  return `${s.time} ${s.suffix.toUpperCase()}`;
}

function EventBlock({
  p,
  fromHour,
  now,
  day,
}: {
  p: Positioned;
  fromHour: number;
  now: Date;
  day: Date;
}) {
  const top = (p.startMin - fromHour * 60) * (HOUR_PX / 60);
  const height = Math.max(18, ((p.endMin - p.startMin) * HOUR_PX) / 60 - 2);
  const width = 100 / p.cols;
  const e = p.event;

  const past = parseEnd(e) <= now;
  const live = parseStart(e) <= now && parseEnd(e) > now && dayKey(day) === dayKey(now);
  const compact = height < 34;

  const s = fmtTime(parseStart(e));

  return (
    <div
      className="absolute z-10 overflow-hidden rounded-[6px] px-2 py-[3px] transition-opacity"
      title={`${e.title} · ${s.time}${s.suffix}`}
      style={{
        top,
        height,
        left: `calc(${p.col * width}% + 2px)`,
        width: `calc(${width}% - 4px)`,
        background: live ? `${e.color}33` : `${e.color}1f`,
        boxShadow: `inset 2px 0 0 ${e.color}${live ? "" : "cc"}${
          live ? `, 0 0 18px ${e.color}30` : ""
        }`,
        opacity: past && !live ? 0.4 : 1,
        borderTopLeftRadius: p.continuesBefore ? 0 : undefined,
        borderBottomLeftRadius: p.continuesAfter ? 0 : undefined,
      }}
    >
      <div
        className={`truncate text-[0.74rem] leading-[1.15] ${
          live ? "font-medium text-white" : "font-normal"
        }`}
        style={{ color: live ? undefined : "#e8eaed" }}
      >
        {e.title}
      </div>
      {!compact && (
        <div className="nums truncate text-[0.64rem] font-light leading-tight text-white/45">
          {s.time}
          {s.suffix}
          {e.location ? ` · ${e.location}` : ""}
        </div>
      )}
    </div>
  );
}
