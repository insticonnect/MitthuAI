# MitthuAI 🧠

Your Mac's memory. MitthuAI lives in the menu bar, passively logs what you do
(apps, window titles, and the **text on your screen** via macOS accessibility),
and turns it into:

- **A timeline** — "what did I do today / last Tuesday?"
- **A searchable memory** — hybrid semantic + keyword search over everything you've seen ("that video about transformers", "the electricity bill")
- **A brain** — bills, deadlines, and watched videos are auto-extracted into tasks with due dates
- **Spaced-repetition reminders** — watched a lecture? Get revision nudges after 1/3/7/14/30 days
- **An MCP server** — plug your memory into Claude Code, Claude Desktop, or any MCP client as a first-class tool

**100% local.** SQLite on your disk, on-device Apple embeddings, server bound to
`127.0.0.1` with a bearer token. No cloud, no telemetry.

> **Naming:** the app is **MitthuAI** 🦜 everywhere — bundle, menu bar, dashboard
> and data folder. Only the *GitHub repository* is still called `HelloMac`, so
> the clone URL below keeps the old name.
>
> **Coming from an old HelloMac build?** This release starts fresh — it no
> longer carries data over from `~/Library/Application Support/HelloMac/`.
> Delete that folder and the old `build/HelloMac.app` (two instances would
> fight over port 4789), then grant **Accessibility** to MitthuAI in System
> Settings → Privacy & Security and remove the stale `HelloMac` entry there.

---

## Quick start (new here? start at step 1)

**Requirements:** a Mac running macOS 12 or newer. Nothing else — no Node, no
Homebrew, no package manager. The app is plain Swift against system frameworks.

**1. Install Xcode command line tools** (skip if `swiftc --version` already works):

```bash
xcode-select --install
```

**2. Clone the repo:**

```bash
git clone https://github.com/insticonnect/HelloMac.git
cd HelloMac
```

**3. Build it** (takes about a minute; everything lands in `build/`):

```bash
./build.sh
```

If you get `permission denied`, run `chmod +x build.sh` first.

**4. Launch it:**

```bash
open build/MitthuAI.app
```

A 🦜 parrot icon appears in your menu bar — that's the app. There's no dock icon
and no window; everything happens from the menu bar and the dashboard.

On its first launch MitthuAI adds itself as a **login item**, so it starts on
its own every time you log in or restart the Mac (System Settings → General →
Login Items lists it). Turn that off — or back on — from the dashboard's
Settings → Startup.

**5. Grant permissions (first run):**

1. **Accessibility** (required) — System Settings → Privacy & Security → Accessibility → enable MitthuAI. This is how window titles and on-screen text are read (the same API VoiceOver uses). **Quit and relaunch the app after granting**, or capture stays empty.
2. **Automation** (optional) — prompted the first time a browser URL is read. Powers per-tab URLs in the timeline.
3. **Notifications** (optional) — for revision/deadline reminders.

**6. Open the dashboard:** click the 🦜 menu bar icon → **Open Dashboard**. It
opens `http://localhost:4789/` with your access token attached. Give it a few
minutes of normal use before expecting the timeline to fill in.

## Updating to a newer version

Pull the latest code and rebuild — same two commands every time:

```bash
git pull
./build.sh
```

Then quit the app from the menu bar (🦜 → Quit) and `open build/MitthuAI.app`
again. Quitting first is the safe order, since the rebuild replaces the binary
the running app is using.

**Your data survives updates.** Everything lives in
`~/Library/Application Support/MitthuAI/mitthuai.db`, which the build never
touches — your access token, settings, rules, and history all carry over, so
you don't need to reconnect Claude after an update. (Coming from a pre-1.0
build? Delete that folder first; this release expects a database it created.)

## Dashboard

Click the 🦜 menu bar icon → **Open Dashboard** (it opens `http://localhost:4789/`
with your access token). Tabs:

- **Today** — active/idle time, focus-vs-multitasking score, tracked-event count, category-distribution donut, top-apps chart, and a full session timeline. Each timeline row has inline **Study / Entertainment / Work / Other** chips — tap one to teach MitthuAI how to categorize that title. Switching tabs inside one app stays a single row, shown under the tab you spent the most time on with a **· N tabs** marker (hover for the full list); switching *apps* always starts a new row, and every raw switch is still stored.
- **Search** — semantic + keyword search with date filters
- **Brain** — open items (bills/deadlines/watched/notes), upcoming reminders. Add your own items with a due **date and time** (defaults to 9:00 AM); watched-video titles link straight to the video. Every item takes your own **note** — a subtitle you edit inline with **✎ note**, for when the page title ("… :: IITM Online Degree") doesn't say which lecture it was. The note follows the item into the History calendar and into the reminder notification itself, and each row also shows when it was captured. Watched videos are **one entry per video per 24 hours, identified by URL** (title when the browser exposes none) — two lectures on a portal that never changes its page title still get separate entries — and each shows the **total time watched**, which keeps adding up when you finish the second half later. A re-watch more than a day later is a fresh entry with its own revision ladder; a same-day continuation never resets the ladder. Marking an item **done** here also shows it as done in the History calendar — even items without a due date land on the day you completed them.
- **History** — a revision calendar with Week / Month / 3-Month views (◀ ▶ to move between periods). Shows when you watched each video, which revisions you did, missed, or have coming up, with summary cards vs the previous period and a month-by-month comparison table + chart in the 3-month view. Video titles are clickable everywhere — reopen the video straight from the calendar to rewatch or revise. Click any day to see details and mark a revision **did it ✓**. **Export .ics** downloads the upcoming schedule for Google Calendar (Settings → Import & export), Apple Calendar, or Outlook — events carry the video link; each upcoming item also has a one-click **+ GCal** link.
- **Rules** — create categorization rules (app + title-contains → category). A new rule re-tags matching history immediately, including same-title activity within ±10 minutes so a video you flicked away from and back to lands in one bucket. Delete any rule to re-categorize affected activity.
- **Settings** — pause, open at login, video sources, excluded apps, capture toggles, data purge, MCP setup

### How a video gets spotted

MitthuAI doesn't rely on a list of famous sites — a lecture on your college
portal is caught the same way a YouTube video is. When a window has held the
screen long enough, it weighs signals it already collects:

| Signal | Weight |
|---|---|
| A player timecode on screen (`12:34 / 45:07`, or a seek bar's `0:14 of 12:45`) | 3 |
| A native player app (VLC, IINA, QuickTime…) | 3 |
| Player controls — play/pause buttons with fullscreen, mute or speed | 2 |
| Sound actually playing on the Mac | 2 |
| The display being held awake (what video playback does) | 2 |
| A video-shaped link (`/watch`, `/lecture`, `/embed/`…) | 2 |
| A known video site, built-in list or your own | 2 |
| A learning host (`.edu`, `.ac.in`, Moodle, Canvas…) | 1 |

Player buttons and seek sliders are read through the same accessibility tree
as everything else, so an **embedded** player — a YouTube iframe inside a
college portal like IITM SEEK, a Physics Wallah player, an audio-only
lecture — is recognised even though the page URL and title never say "video".

Three points make it a video — including at least one signal from the window
itself (a timecode, controls, a player app, a video link), so a video call or
background music can't turn plain browsing into "watched". Strong evidence
(5+) counts after 1 minute, anything weaker still needs the full 5 minutes —
so a page you left open isn't a video, and neither is the YouTube homepage you
never pressed play on. Tab-switching away doesn't reset the clock: watch time
for a title keeps adding up across gaps of up to 10 minutes.

**Settings → Video sources** also shows the last 20 detection decisions with
their scores and reasons — if something you watched didn't appear in Brain,
the line there says exactly why.

It then enrols in the **1/3/7/14/30-day revision ladder** if it looks like study
material: a learning host (`.edu`, `.ac.in`, Moodle, Canvas, Classroom, NPTEL,
Coursera…), a title that reads like coursework (lecture, module, chapter, week,
lab, exam…), or anything one of your own rules files under **Study**. Turn the
auto-enrolment off with *Auto spaced-repetition* in Settings.

Missing a site? Add its domain under **Settings → Video sources** and it always
counts. Note that browser URLs come from Apple Events, which only Safari, Chrome,
Brave, Edge, Vivaldi and Arc support — in Firefox detection leans on the
on-screen signals instead.

### How a deadline gets read

Dates come from **NSDataDetector** — the same on-device parser macOS uses for
"Add to Calendar" in Mail — so "Sep 12, 2026", "12th Sept", "12/09/2026",
"2026-09-12" and "next Friday" all work, in your Mac's own region format.
Three rules make it right for deadlines specifically:

- **Anchored to the deadline word.** In *"open for Sep 2026 term, Last date to
  Apply : Sep 12, 2026"* the date nearest **after** "last date" wins — the 12th,
  not the 20 hiding inside "2026".
- **A written year is never second-guessed.** A mail about "January 2024" is
  stale, so it produces nothing; only a date with *no* year at all may roll
  forward to next year. Nothing more than two years out is accepted.
- **Ambiguity is admitted, not guessed.** "12/09/2026" is read with your
  region's order and marked **check date** in Brain, where 📅 fixes it in a
  click. Settings → Deadlines & dates pins the order to day-first or
  month-first if you'd rather not rely on the region.

A line only becomes a task if it is **specific enough to act on**: marketing
urgency ("Shop now before it's too late", "sale ends") and clipped fragments
("Expires today") are dropped, and at most six deadlines are taken from the
screen per hour. A date said in words counts too, as long as something is being
asked of you — *"lets meet tomorrow over meet"* is `meet` + `tomorrow`, so it
lands in Brain with tomorrow's date. Word stems are matched, so *meet* also
finds *meets* and *meeting* without *book* matching *facebook*.

**One mail, one item.** A message shows up on screen several times over — the
tab title, a heading, the sentence in the body — so each screen contributes at
most one item per kind per due day, chosen from the subject where there is one,
and it is checked against Brain again before being added. Different things due
the same day stay separate: two exams, a bill and a meeting, all survive.

Mail items carry **who sent it** in the note — the sender's name and address
(your own account address is never mistaken for the sender) plus a Google
Meet/Zoom/Teams link when the mail has one, so the reminder tells you who and
where. Your own edits to a note are never overwritten.

Settings also lists the recent date and video decisions with their reasons, so
an odd deadline explains itself. Optionally, **Apple's on-device model** can be
switched on to read lines the parser can't — only those lines, never ordinary
capture, and every date it returns is checked against the source text (the day
must actually appear there) before it becomes a reminder. It needs macOS 26
with Apple Intelligence; Settings shows whether it's available.

### Categories & focus score

Activity rolls up into four buckets — **Study, Entertainment, Work, Other** — chosen by your rules first, then a built-in heuristic. Study + Work count as *focus*; the focus-vs-multitasking score is focus time over total categorized time. You can type any custom category on a rule; the donut and chips adapt.

## Connect Claude (MCP)

The Settings tab shows ready-to-copy commands with your token filled in:

**Claude Code:**
```bash
claude mcp add --transport http mitthuai http://localhost:4789/mcp \
  --header "Authorization: Bearer <your-token>"
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "mitthuai": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:4789/mcp",
               "--header", "Authorization: Bearer <your-token>"]
    }
  }
}
```

Then ask Claude things like *"what did I do today?"*, *"when did I watch that
GPU video?"*, *"what's important today?"*, *"remind me to pay the bill in 4 days"*.

### MCP tools exposed

| Tool | What it does |
|---|---|
| `search_memory` | Hybrid search over captured screen text, with time filters |
| `get_timeline` | Sessions + stats for a day |
| `get_important` | Bills/deadlines due soon + revisions firing today |
| `get_daily_digest` | Readable end-of-day review |
| `create_reminder` | Add a task/reminder with a due date |
| `complete_item` | Mark an item done |
| `add_revision` | Enroll an item in the 1/3/7/14/30-day revision ladder |

## Search quality & embeddings

- **Default:** on-device Apple embeddings — private, free, offline, English.
- **Turbo (opt-in):** paste your own OpenAI API key in Settings to use
  `text-embedding-3-small` (multilingual, higher accuracy). The key is stored in
  the **macOS Keychain** (never in the database), text is sent to OpenAI only
  while enabled, and OpenAI bills you directly.
- **Retrieval** is hybrid (BM25 keyword + vector cosine, reciprocal-rank fusion)
  with **multi-query** support (Claude can pass several angles), a **rerank**
  pass adding lexical-overlap and recency signals, and **time filters**.
- **No duplicate bloat:** identical screens are hashed out, and *near-identical*
  screens (embedding cosine > 0.95 within an app) are suppressed before storage.
- Vectors are tagged with the model that produced them, so switching backends
  never corrupts search over older history.

The MCP server also advertises a retrieval **playbook** (via the `initialize`
`instructions` field) telling connected AI clients to fetch comprehensively.

## Privacy

- Everything stays in `~/Library/Application Support/MitthuAI/mitthuai.db`
- Server binds `127.0.0.1` only; every request needs the bearer token
- Password managers are excluded by default (editable list); secure text fields and private/incognito windows are never read
- Pause anytime from the menu bar; delete any date range from Settings

## Architecture

```
menu bar app (SwiftUI)
  ├─ Tracker         1s sampling: frontmost app/window/idle → events table
  ├─ ContentCapture  10s: AX text of focused window → chunks (dedup, ~800 chars)
  │    ├─ Embeddings on-device NLEmbedding vectors → embeddings table
  │    └─ Extractors bills/deadlines/watched → facts (+ auto reminders)
  ├─ ReminderScheduler due reminders → macOS notifications
  └─ HttpServer (127.0.0.1:4789, bearer token)
       ├─ /            dashboard (embedded SPA)
       ├─ /api/*       REST for the dashboard
       └─ /mcp         MCP streamable-HTTP endpoint
storage: SQLite (WAL) + FTS5 + vector blobs — one file
```

## Branding

The mitthuai.com parrot lives in **one** place: `Sources/MitthuAI/BrandLogo.swift`.
The artwork is written as vector paths in SVG coordinates and rendered wherever
it's needed — inline SVG in the dashboard header, an `NSImage` for the popover,
a white template image for the menu bar, and the `.icns` app icon via
`Tools/MakeIcon.swift`. Edit the paths there and every surface moves together.

The **MitthuAI** wordmark is Plus Jakarta Sans Bold at 20px on `#FFFFFF`, the
same as the site. `Resources/Fonts/MitthuAIWordmark.ttf` is that face subset to
the wordmark's glyphs and renamed (SIL Open Font License 1.1 —
`Resources/Fonts/OFL.txt`); the app registers it privately through
`ATSApplicationFontsPath`, and the dashboard carries the same face inline as
base64 WOFF2 so the page still needs no network.

See `PLAN.md` for the full roadmap (OCR fallback, encryption at rest, local LLM digests…).
