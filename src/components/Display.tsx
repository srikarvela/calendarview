"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { rememberView, useNow, useStoredView, type View } from "@/lib/client-state";
import type { Actions, Snapshot } from "@/lib/source";
import type { CalEvent } from "@/lib/types";
import WeekView from "./WeekView";
import { weekDays } from "@/lib/layout";
import {
  dayKey,
  dayLabel,
  fmtDuration,
  fmtRange,
  fmtClock,
  fmtTime,
  parseEnd,
  parseStart,
  untilLabel,
} from "@/lib/time";

const IDLE_MS = 3_000;

export default function Display({
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
  const now = useNow();
  const events = snapshot.events;
  const stale = Boolean(snapshot.stale);
  const [idle, setIdle] = useState(false);
  const [offset, setOffset] = useState(0); // weeks from the current week
  const nowRef = useRef<HTMLDivElement>(null);

  // An explicit ?view= beats this browser's saved preference, which beats the default.
  const storedView = useStoredView();
  const [chosenView, setChosenView] = useState<View | null>(initialView ?? null);
  const view: View = chosenView ?? storedView ?? "day";

  const setView = useCallback((next: View) => {
    setChosenView(next);
    rememberView(next);
  }, []);

  const load = actions.refresh;

  // Hide the cursor and the controls once you stop touching it.
  useEffect(() => {
    let timer = setTimeout(() => setIdle(true), IDLE_MS);
    const wake = () => {
      setIdle(false);
      clearTimeout(timer);
      timer = setTimeout(() => setIdle(true), IDLE_MS);
    };
    window.addEventListener("mousemove", wake);
    window.addEventListener("keydown", wake);
    return () => {
      clearTimeout(timer);
      window.removeEventListener("mousemove", wake);
      window.removeEventListener("keydown", wake);
    };
  }, []);

  // The whole interface is the keyboard: d/w switch views, arrows move weeks.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      switch (e.key) {
        case "f":
          if (document.fullscreenElement) {
            document.exitFullscreen().catch(() => {});
          } else {
            document.documentElement.requestFullscreen().catch(() => {});
          }
          break;
        case "r":
          load();
          break;
        case "d":
          setView("day");
          setOffset(0);
          break;
        case "w":
          setView("week");
          break;
        case "t":
          setOffset(0);
          break;
        case "ArrowLeft":
          if (view === "week") setOffset((o) => o - 1);
          break;
        case "ArrowRight":
          if (view === "week") setOffset((o) => o + 1);
          break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [load, view, setView]);

  // Re-anchor when the calendar day changes, not on every tick of the clock.
  const todayKey = now ? dayKey(now) : null;
  const anchor = useMemo(() => {
    const [y, m, d] = (todayKey ?? dayKey(new Date())).split("-").map(Number);
    const date = new Date(y, m - 1, d);
    date.setDate(date.getDate() + offset * 7);
    return date;
  }, [offset, todayKey]);

  const model = useMemo(() => buildModel(events, now), [events, now]);

  useEffect(() => {
    nowRef.current?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [model.currentId]);

  return (
    <main className={`relative h-dvh w-screen overflow-hidden bg-void ${idle ? "idle" : ""}`}>
      <Ambience accent={model.accent} />

      {view === "day" ? (
        <div className="relative grid h-full grid-cols-1 gap-10 px-[4.5vw] py-[5vh] lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] lg:gap-16">
          <Clock now={now} model={model} />
          <Agenda model={model} now={now} nowRef={nowRef} />
        </div>
      ) : (
        <div className="relative flex h-full flex-col px-[2.5vw] pb-[3vh] pt-[4vh]">
          <WeekHeader now={now} anchor={anchor} offset={offset} />
          <div className="min-h-0 flex-1">
            {now && <WeekView events={events} now={now} anchor={anchor} />}
          </div>
        </div>
      )}

      <Controls
        idle={idle}
        demo={demo}
        stale={stale}
        view={view}
        onRefresh={load}
        onSignOut={actions.signOut}
      />
    </main>
  );
}

/* ------------------------------------------------------------------ model */

type DayGroup = { key: string; label: string; timed: CalEvent[]; allDay: CalEvent[] };

type Model = {
  days: DayGroup[];
  current: CalEvent | null;
  currentId: string | null;
  next: CalEvent | null;
  accent: string;
  todayCount: number;
  bookedMs: number;
  freeAfter: Date | null;
};

function buildModel(events: CalEvent[], now: Date | null): Model {
  const empty: Model = {
    days: [],
    current: null,
    currentId: null,
    next: null,
    accent: "#5b9dff",
    todayCount: 0,
    bookedMs: 0,
    freeAfter: null,
  };
  if (!now) return empty;

  const todayKey = dayKey(now);
  const groups = new Map<string, DayGroup>();

  for (const e of events) {
    const start = parseStart(e);
    const end = parseEnd(e);
    // Drop anything that finished before today.
    if (dayKey(end) < todayKey && !e.allDay) continue;

    const key = dayKey(start) < todayKey ? todayKey : dayKey(start);
    if (!groups.has(key)) {
      groups.set(key, { key, label: dayLabel(key, now), timed: [], allDay: [] });
    }
    groups.get(key)![e.allDay ? "allDay" : "timed"].push(e);
  }

  const days = [...groups.values()]
    .filter((g) => g.key >= todayKey)
    .sort((a, b) => a.key.localeCompare(b.key));

  const timedToday = days.find((d) => d.key === todayKey)?.timed ?? [];

  const current =
    timedToday.find((e) => parseStart(e) <= now && parseEnd(e) > now) ?? null;

  const next =
    days.flatMap((d) => d.timed).find((e) => parseStart(e) > now) ?? null;

  const bookedMs = timedToday.reduce(
    (sum, e) => sum + (parseEnd(e).getTime() - parseStart(e).getTime()),
    0,
  );

  const remaining = timedToday.filter((e) => parseEnd(e) > now);
  const freeAfter = remaining.length
    ? remaining.reduce(
        (latest, e) => (parseEnd(e) > latest ? parseEnd(e) : latest),
        parseEnd(remaining[0]),
      )
    : null;

  return {
    days,
    current,
    currentId: current?.id ?? next?.id ?? null,
    next,
    accent: current?.color ?? next?.color ?? "#5b9dff",
    todayCount: timedToday.length,
    bookedMs,
    freeAfter,
  };
}

/* ------------------------------------------------------------------- view */

function Ambience({ accent }: { accent: string }) {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0">
      <div
        className="absolute -left-[15%] -top-[25%] h-[70vh] w-[70vh] rounded-full blur-[130px] transition-colors duration-[2000ms]"
        style={{ background: `radial-gradient(circle, ${accent}3a, transparent 66%)` }}
      />
      <div className="absolute -bottom-[30%] right-[-10%] h-[60vh] w-[60vh] rounded-full bg-[radial-gradient(circle,#ffffff12,transparent_70%)] blur-[120px]" />
      <div className="absolute inset-0 bg-[linear-gradient(180deg,transparent,#00000055)]" />
    </div>
  );
}

function Clock({ now, model }: { now: Date | null; model: Model }) {
  const t = now ? fmtClock(now) : null;

  return (
    <section className="flex min-w-0 flex-col justify-between">
      <div className="rise">
        <div className="flex items-baseline gap-3">
          <h1 className="nums text-[clamp(4.5rem,11vw,10.5rem)] font-extralight leading-[0.85] tracking-[-0.045em] text-white">
            {t ? t.time : "--:--"}
          </h1>
          <span className="text-[clamp(1rem,1.7vw,1.6rem)] font-light lowercase text-white/50">
            {t?.suffix}
          </span>
        </div>

        <p className="mt-5 text-[clamp(0.95rem,1.35vw,1.35rem)] font-light tracking-[0.02em] text-white/60">
          {now
            ? now.toLocaleDateString(undefined, {
                weekday: "long",
                month: "long",
                day: "numeric",
              })
            : ""}
        </p>
      </div>

      <NowCard model={model} now={now} />

      <div className="nums flex flex-wrap items-center gap-x-5 gap-y-1 text-[0.78rem] font-light tracking-[0.08em] text-white/45">
        <span>{model.todayCount === 0 ? "NOTHING SCHEDULED" : `${model.todayCount} EVENTS`}</span>
        {model.bookedMs > 0 && <span>{fmtDuration(model.bookedMs).toUpperCase()} BOOKED</span>}
        {model.freeAfter && (
          <span>
            FREE AFTER {fmtTime(model.freeAfter).time}
            {fmtTime(model.freeAfter).suffix.toUpperCase()}
          </span>
        )}
      </div>
    </section>
  );
}

function NowCard({ model, now }: { model: Model; now: Date | null }) {
  const { current, next } = model;
  if (!now) return <div />;

  if (current) {
    const start = parseStart(current);
    const end = parseEnd(current);
    const pct = Math.min(
      100,
      Math.max(0, ((now.getTime() - start.getTime()) / (end.getTime() - start.getTime())) * 100),
    );

    return (
      <div className="rise my-8 max-w-xl">
        <div className="mb-3 flex items-center gap-2.5">
          <span
            className="pulse-dot h-[7px] w-[7px] rounded-full"
            style={{ background: current.color, boxShadow: `0 0 16px ${current.color}, 0 0 5px ${current.color}` }}
          />
          <span className="text-[0.7rem] font-medium tracking-[0.24em] text-white/70">
            HAPPENING NOW
          </span>
        </div>

        <p className="text-[clamp(1.5rem,2.7vw,2.6rem)] font-light leading-tight tracking-[-0.02em] text-white">
          {current.title}
        </p>

        <p className="nums mt-2.5 text-[0.95rem] font-light text-white/60">
          {fmtRange(current)} · {fmtDuration(end.getTime() - now.getTime())} left
        </p>

        <div className="mt-5 h-[3px] w-full max-w-md overflow-hidden rounded-full bg-white/12">
          <div
            className="h-full rounded-full transition-[width] duration-1000 ease-linear"
            style={{ width: `${pct}%`, background: current.color }}
          />
        </div>
      </div>
    );
  }

  if (next) {
    return (
      <div className="rise my-8 max-w-xl">
        <div className="mb-3 flex items-center gap-2.5">
          <span
            className="h-[7px] w-[7px] rounded-full"
            style={{ background: next.color, boxShadow: `0 0 12px ${next.color}` }}
          />
          <span className="text-[0.7rem] font-medium tracking-[0.24em] text-white/60">
            UP NEXT · {untilLabel(now, parseStart(next)).toUpperCase()}
          </span>
        </div>
        <p className="text-[clamp(1.4rem,2.4vw,2.3rem)] font-light leading-tight tracking-[-0.02em] text-white/95">
          {next.title}
        </p>
        <p className="nums mt-2.5 text-[0.95rem] font-light text-white/55">{fmtRange(next)}</p>
      </div>
    );
  }

  return (
    <div className="rise my-8">
      <p className="text-[clamp(1.3rem,2.2vw,2rem)] font-light tracking-[-0.02em] text-white/45">
        Clear for the rest of the day.
      </p>
    </div>
  );
}

function Agenda({
  model,
  now,
  nowRef,
}: {
  model: Model;
  now: Date | null;
  nowRef: React.RefObject<HTMLDivElement | null>;
}) {
  if (!now) return <section />;

  return (
    <section className="no-scrollbar relative min-w-0 overflow-y-auto [mask-image:linear-gradient(180deg,transparent,#000_3%,#000_94%,transparent)]">
      {model.days.length === 0 && (
        <p className="mt-[30vh] text-center text-[1rem] font-light text-white/35">
          No events in the next week.
        </p>
      )}

      {model.days.map((day, di) => (
        <div key={day.key} className="rise mb-9" style={{ animationDelay: `${di * 60}ms` }}>
          <h2 className="sticky top-0 z-10 bg-void/85 py-2 text-[0.7rem] font-medium tracking-[0.24em] text-white/50 backdrop-blur-sm">
            {day.label.toUpperCase()}
          </h2>

          {day.allDay.length > 0 && (
            <div className="mb-3 mt-1 flex flex-wrap gap-2">
              {day.allDay.map((e) => (
                <span
                  key={e.id}
                  className="rounded-full px-3 py-1 text-[0.8rem] font-light"
                  style={{
                    background: `${e.color}26`,
                    color: e.color,
                    boxShadow: `inset 0 0 0 1px ${e.color}59, 0 0 14px ${e.color}26`,
                  }}
                >
                  {e.title}
                </span>
              ))}
            </div>
          )}

          <ul className="mt-1">
            {day.timed.map((e) => (
              <EventRow
                key={e.id}
                event={e}
                now={now}
                isCurrent={e.id === model.current?.id}
                rowRef={e.id === model.currentId ? nowRef : undefined}
              />
            ))}
          </ul>
        </div>
      ))}
    </section>
  );
}

function EventRow({
  event,
  now,
  isCurrent,
  rowRef,
}: {
  event: CalEvent;
  now: Date;
  isCurrent: boolean;
  rowRef?: React.RefObject<HTMLDivElement | null>;
}) {
  const start = parseStart(event);
  const end = parseEnd(event);
  const past = end <= now;
  const s = fmtTime(start);

  const meta = [
    event.location,
    event.meetLink ? "Meet" : null,
    event.attendees > 1 ? `${event.attendees} people` : null,
  ].filter(Boolean) as string[];

  return (
    <li>
      <div
        ref={rowRef}
        className={`group relative flex gap-5 rounded-xl px-4 py-3.5 transition-colors duration-500 ${
          isCurrent ? "bg-white/[0.07]" : ""
        } ${past ? "opacity-45" : ""}`}
      >
        <span
          aria-hidden
          className="absolute left-0 top-3 bottom-3 w-[3px] rounded-full transition-all"
          style={{
            background: event.color,
            opacity: isCurrent ? 1 : 0.85,
            boxShadow: isCurrent
              ? `0 0 18px ${event.color}, 0 0 6px ${event.color}`
              : `0 0 10px ${event.color}66`,
          }}
        />

        <div className="nums w-[4.5rem] shrink-0 pt-[0.15rem] text-right">
          <span className="text-[1.05rem] font-light text-white/90">{s.time}</span>
          <span className="ml-0.5 text-[0.7rem] font-light text-white/50">{s.suffix}</span>
        </div>

        <div className="min-w-0 flex-1">
          <p
            className={`truncate text-[1.08rem] font-light tracking-[-0.01em] ${
              isCurrent ? "text-white" : "text-white/92"
            }`}
          >
            {event.title}
          </p>
          <p className="nums mt-1 truncate text-[0.8rem] font-light text-white/50">
            {fmtDuration(end.getTime() - start.getTime())}
            {meta.length > 0 && ` · ${meta.join(" · ")}`}
          </p>
        </div>
      </div>
    </li>
  );
}

function WeekHeader({
  now,
  anchor,
  offset,
}: {
  now: Date | null;
  anchor: Date;
  offset: number;
}) {
  const t = now ? fmtClock(now) : null;
  const week = weekDays(anchor);
  const spansMonths = week[0].getMonth() !== week[6].getMonth();
  const title = spansMonths
    ? `${week[0].toLocaleDateString(undefined, { month: "long" })} – ${week[6].toLocaleDateString(
        undefined,
        { month: "long", year: "numeric" },
      )}`
    : week[0].toLocaleDateString(undefined, { month: "long", year: "numeric" });

  return (
    <div className="mb-5 flex shrink-0 items-baseline justify-between px-1">
      <div className="flex items-baseline gap-4">
        <h1 className="text-[clamp(1.3rem,2vw,1.9rem)] font-extralight tracking-[-0.02em] text-white">
          {title}
        </h1>
        {offset !== 0 && (
          <span className="nums text-[0.7rem] font-light tracking-[0.14em] text-white/25">
            {offset > 0 ? `+${offset}` : offset} WEEK{Math.abs(offset) === 1 ? "" : "S"}
          </span>
        )}
      </div>
      <div className="nums flex items-baseline gap-1 text-white/45">
        <span className="text-[clamp(1.1rem,1.6vw,1.5rem)] font-extralight tracking-[-0.02em]">
          {t?.time ?? ""}
        </span>
        <span className="text-[0.7rem] font-light lowercase text-white/25">{t?.suffix}</span>
      </div>
    </div>
  );
}

function Controls({
  idle,
  demo,
  stale,
  view,
  onRefresh,
  onSignOut,
}: {
  idle: boolean;
  demo: boolean;
  stale: boolean;
  view: "day" | "week";
  onRefresh: () => void;
  onSignOut: () => void;
}) {
  return (
    <div
      className={`absolute bottom-5 right-6 flex items-center gap-4 text-[0.72rem] font-light tracking-[0.1em] text-white/45 transition-opacity duration-700 ${
        idle ? "pointer-events-none opacity-0" : "opacity-100"
      }`}
    >
      {stale && <span className="text-[#ffd60a]/80">OFFLINE</span>}
      {demo && <span className="text-white/40">DEMO DATA</span>}
      <button onClick={onRefresh} className="transition-colors hover:text-white/70">
        REFRESH
      </button>
      <span className="text-white/30">
        {view === "day" ? "W WEEK" : "D DAY · ← → WEEKS"} · F FULLSCREEN
      </span>
      {!demo && (
        <button onClick={onSignOut} className="transition-colors hover:text-white/70">
          SIGN OUT
        </button>
      )}
    </div>
  );
}
