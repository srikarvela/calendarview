<div align="center">

<img src="docs/images/icon.png" width="118" alt="CalendarView">

# CalendarView

**Your day, full screen.**

[![Download](https://img.shields.io/badge/Download-CalendarView%201.0.0.dmg-8ab4f8?style=for-the-badge&labelColor=0e1015)](https://github.com/srikarvela/calendarview/releases/latest)
&nbsp;
[![Free](https://img.shields.io/badge/Free-1c1f27?style=for-the-badge&labelColor=1c1f27)](#)

</div>

<div align="center">
<table>
<tr>
<td align="center" width="150"><sub><b>KIND</b></sub><br><br><b>Universal</b><br><sub>Apple Silicon · Intel</sub></td>
<td align="center" width="150"><sub><b>VERSION</b></sub><br><br><b>1.0.0</b><br><sub>August 2026</sub></td>
<td align="center" width="150"><sub><b>REQUIRES</b></sub><br><br><b>macOS 11</b><br><sub>or later</sub></td>
<td align="center" width="150"><sub><b>CATEGORY</b></sub><br><br><b>Productivity</b><br><sub>Calendar</sub></td>
<td align="center" width="150"><sub><b>LANGUAGE</b></sub><br><br><b>EN</b><br><sub>English</sub></td>
<td align="center" width="150"><sub><b>SIZE</b></sub><br><br><b>1.0</b><br><sub>MB</sub></td>
</tr>
</table>
</div>

<br>

<div align="center">

<img src="docs/images/day.png" width="47%" alt="Day view">
&nbsp;&nbsp;
<img src="docs/images/week.png" width="47%" alt="Week view">

<sub>Day view · Week view — shown with demo data</sub>

</div>

<br>

💻 &nbsp;**Mac**

CalendarView turns a spare screen into a calendar you can read from across the room. It signs
into Google Calendar once, then gets out of the way — no toolbars, no tabs, no buttons. Just the
time, what is happening now, and what is coming next, in a dark palette that sits quietly in a
room at night.

It ships two views and nothing else. **Day** is the ambient one: an oversized clock, the event
you are in the middle of with a progress bar running under it, and the rest of the week listed
beneath. **Week** is the precise one: a seven-column time grid with overlapping events packed
side by side and a live line tracking the current minute — the layout Google Calendar uses,
rebuilt for a dark screen.

The Mac app is a menu bar item showing today's date. Click it and the display opens fullscreen;
everything else lives in the menu. The calendar itself is a web app you deploy once to Vercel,
so the same URL works on your phone, on a second Mac, or on a monitor in the corner.

<sub>**Read-only** — the app requests `calendar.readonly` and never writes to your calendar.
No analytics, no third-party services. Your events go from Google to your screen and nowhere
else.</sub>

---

## Install

**The Mac app** — download [`CalendarView-1.0.0.dmg`](https://github.com/srikarvela/calendarview/releases/latest),
open it, drag **CalendarView** to Applications.

The app is signed ad-hoc rather than with a paid Apple Developer certificate, so the first launch
needs one extra step: **right-click the app → Open → Open**. macOS remembers the choice. (Plain
double-clicking shows "unidentified developer" and refuses.) Same steps on Intel and Apple
Silicon — the binary is universal.

On first launch it asks for your server URL. Paste the Vercel address from the next section.

## Deploy the calendar

<div align="center"><img src="docs/images/connect.png" width="70%" alt="Connect screen"></div>

**1. Create a Google OAuth client.** In the [Google Cloud Console](https://console.cloud.google.com),
enable the **Google Calendar API**, then create an **OAuth client ID** of type *Web application*.
Add these redirect URIs:

```
https://YOUR-APP.vercel.app/api/auth/callback/google
http://localhost:3000/api/auth/callback/google
```

**2. Deploy to Vercel.** Import this repo, and set three environment variables:

| Variable | Value |
| --- | --- |
| `AUTH_GOOGLE_ID` | Client ID from step 1 |
| `AUTH_GOOGLE_SECRET` | Client secret from step 1 |
| `AUTH_SECRET` | Any random string — `openssl rand -base64 32` |

**3. Open it and click Connect.** That is the whole setup. While the OAuth app is in *Testing*
mode, add your own address under **Audience → Test users**.

## Keyboard

The interface has no visible controls, so everything is a key.

| Key | |
| --- | --- |
| <kbd>D</kbd> | Day view |
| <kbd>W</kbd> | Week view |
| <kbd>←</kbd> <kbd>→</kbd> | Previous / next week |
| <kbd>T</kbd> | Back to today |
| <kbd>R</kbd> | Refresh now |
| <kbd>F</kbd> | Fullscreen |

The cursor and the few remaining hints fade out after three seconds of stillness. Events refresh
every minute, and again whenever the window regains focus.

## Run it yourself

```bash
npm install
npm run dev
```

Then <http://localhost:3000/?demo=1> for the demo data used in the screenshots above — no Google
account needed.

Build the Mac app:

```bash
./macapp/build.sh
```

That produces `macapp/build/CalendarView.app` and `macapp/build/CalendarView-1.0.0.dmg`. It needs
only the Xcode **Command Line Tools** (`xcode-select --install`) — no Xcode, no developer account.
Both architectures are compiled in one pass, so the DMG you build on an M-series Mac runs on an
Intel one unchanged.

## How it is put together

| | |
| --- | --- |
| `src/app/page.tsx` | Picks between the connect screen and the display |
| `src/components/Display.tsx` | Clock, agenda, view switching, idle handling |
| `src/components/WeekView.tsx` | The seven-day time grid |
| `src/lib/layout.ts` | Overlap packing, day clipping, all-day resolution |
| `src/app/api/events/route.ts` | Google Calendar fetch across every selected calendar |
| `src/auth.ts` | Google OAuth and access-token refresh |
| `macapp/Sources/main.m` | The menu bar app (AppKit + WebKit) |

Next.js 16, React 19, Tailwind v4, Auth.js v5. The Mac app is plain Objective-C so it builds
anywhere with Command Line Tools.

Recurring events are expanded by Google (`singleEvents`), every calendar you have selected is
merged and colour-matched, declined invitations are dropped, all-day events use Google's
exclusive end date, and events crossing midnight are clipped per day.
