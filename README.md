# MitthuAI 🦜

Your Mac's memory. A menu-bar app that passively logs what you do (apps, window
titles, and the **text on your screen** via macOS accessibility) and turns it
into a timeline, a searchable memory, auto-extracted tasks with due dates,
spaced-repetition reminders, and an **MCP server** you can plug into Claude.

**100% local.** SQLite on your disk, on-device Apple embeddings, server bound to
`127.0.0.1` behind a bearer token. No cloud, no telemetry.

---

## Install

macOS 12 or newer, Apple Silicon or Intel:

```bash
curl -fsSL https://mitthuai.com/install.sh | bash
```

That downloads the latest [release](https://github.com/insticonnect/MitthuAI/releases/latest)
disk image, checks it against `SHA256SUMS.txt`, installs `MitthuAI.app` into
`/Applications`, and launches it. Re-run it any time to update — your data stays
put. Or grab `MitthuAI.dmg` from the releases page and drag the app across.

## Build from source

**Requirements:** Xcode command line tools (`xcode-select --install`). No Node,
no Homebrew — plain Swift against system frameworks.

```bash
git clone https://github.com/insticonnect/MitthuAI.git
cd MitthuAI
./build.sh              # ~1 min → build/MitthuAI.app
open build/MitthuAI.app
```

`build.sh` compiles every file in `Sources/MitthuAI/`, stamps `Info.plist`,
generates the parrot icon from `Tools/MakeIcon.swift`, and ad-hoc signs the
bundle with `entitlements.plist`. It wipes `build/` first, so it is always a
clean build. Flags:

| Flag | Effect |
|---|---|
| `--universal` | one bundle for `arm64` + `x86_64` (releases use this) |
| `--dmg` | also package `build/MitthuAI.dmg` (`pip3 install dmgbuild`) |
| `--version X.Y.Z` | stamp that version into the bundle |

`./Tools/verify-bundle.sh build/MitthuAI.app build/MitthuAI.dmg` checks the
result: both architectures, valid `Info.plist`, intact signature, and an app +
Applications link inside the disk image.

**Update a source build:** `git pull && ./build.sh`, quitting from the menu bar
(🦜 → Quit) first. Your data lives in
`~/Library/Application Support/MitthuAI/mitthuai.db` and the build never touches
it — token, settings, rules and history all carry over.

## Releases

Every push builds the app on a macOS runner
([`.github/workflows/build.yml`](.github/workflows/build.yml)) and keeps the disk
image as a CI artifact. Pushing a `v*` tag publishes a GitHub Release with
`MitthuAI.dmg`, `SHA256SUMS.txt` and `install.sh`
([`release.yml`](.github/workflows/release.yml)) — that release is what
mitthuai.com serves. See [docs/RELEASING.md](docs/RELEASING.md) for cutting a
release, wiring the website, and the notarization path.

## First run

A 🦜 icon appears in the menu bar (no dock icon, no window). The app adds itself
as a login item; toggle that from the popover (**Open at Login**) or Settings.

1. **Accessibility** (required) — System Settings → Privacy & Security →
   Accessibility → enable MitthuAI, then **quit and relaunch**, or capture stays
   empty. This is how window titles and on-screen text are read.
2. **Automation** (optional) — browser tab URLs, prompted on first use.
3. **Notifications** (optional) — revision and deadline reminders.

Then 🦜 → **Open Dashboard** (`http://localhost:4789/`, token attached). Give it
a few minutes of use before the timeline fills in.

## Dashboard

- **Today** — active/idle time, focus-vs-multitasking score, category donut, top
  apps, and a session timeline with inline Study/Entertainment/Work/Other chips.
  Tapping a chip moves that whole row — every tab in it, and any stretch played
  fullscreen — so the donut and focus score agree with what you just said.
- **Search** — hybrid semantic + keyword search with date filters.
- **Brain** — open bills, deadlines, watched videos and notes; upcoming
  reminders; editable per-item notes; one entry per video per 24 hours with
  total watch time.
- **History** — revision calendar (Week / Month / 3-Month) with `.ics` export
  and one-click Google Calendar links. Steps closed early — scheduled revisions
  dropped because you finished the item first — sit in a dropdown rather than
  filling the days.
- **Rules** — app + title-contains → category, applied **from now on**: days
  already recorded keep their labels, and deleting a rule doesn't change the
  past either. Tick *also apply to past activity* to re-tag matching history —
  it skips anything you tagged by hand, reports how many events moved, and is
  not undone by deleting the rule.
- **Settings** — pause, login item, video sources, excluded apps, capture
  toggles, data purge, MCP setup, and the recent video/date decisions with the
  score and reason behind each one.

**How things are detected.** Videos are scored from signals the app already
collects — an on-screen player timecode, a native player app, play/pause and
seek controls in the accessibility tree, audio playing, the display held awake,
a video-shaped URL, a known or learning host. Three points (with at least one
signal from the window itself) makes it a video, so an embedded lecture player
counts and an idle YouTube homepage does not. Watch time is tallied per *video*
rather than per window title, so going fullscreen mid-lecture doesn't restart the
clock, and video identity is the address's meaning rather than its letters —
every shape of YouTube link collapses to its video id — so one lecture stays one
entry with all its minutes on it. A video is named by the title that held the
screen longest for it: window titles and browser URLs are read on different
clocks, so the instant after you move to the next lecture the new name is briefly
seen against the old address, and weighing titles by seconds keeps that instant
from deciding what anything is called. Study-looking material auto-enrols in a **1/3/7/14/30-day revision
ladder**. Deadlines come from **NSDataDetector** anchored to the deadline phrase,
never guessing a written year, flagging ambiguous `12/09/2026`-style dates as
*check date*, and capped at one item per kind per due day per screen.

**How categories are decided.** Your own chip taps win, then your rules, then a
built-in heuristic; Study + Work count as *focus*. The label is written when the
activity is captured, so a rule changes what gets recorded next, not what was
recorded already — which does mean a Trends range spanning the day you wrote a
rule mixes old and new labels. Tick **also apply to past activity** on the rule
form when you'd rather have the whole range agree.

## Connect Claude (MCP)

Settings shows these with your token filled in.

```bash
claude mcp add --transport http mitthuai http://localhost:4789/mcp \
  --header "Authorization: Bearer <your-token>"
```

Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`)
uses the same endpoint via `npx mcp-remote`.

Tools: `search_memory`, `get_timeline`, `get_important`, `get_daily_digest`,
`create_reminder`, `complete_item`, `add_revision`.

Retrieval is hybrid (BM25 + vector cosine, reciprocal-rank fusion) with
multi-query, a rerank pass on lexical overlap and recency, and time filters.
Identical and near-identical screens are suppressed before storage, and vectors
are tagged with the model that produced them. On-device Apple embeddings by
default; paste an OpenAI key in Settings for `text-embedding-3-small` (key goes
to the macOS Keychain, never the database).

For access from Claude.ai on the web, `relay/` is a small Node tunnel that does
identity and routing only — see [relay/README.md](relay/README.md).

## Privacy

- Data never leaves `~/Library/Application Support/MitthuAI/mitthuai.db`.
- Server binds `127.0.0.1`; every request needs the bearer token.
- Password managers excluded by default; secure text fields and private windows
  are never read. Pause anytime; purge any date range from Settings.

## Architecture

```
menu bar app (SwiftUI)
  ├─ Tracker         1s sampling: frontmost app/window/idle → events
  ├─ ContentCapture  10s: AX text of focused window → chunks (dedup, ~800 chars)
  │    ├─ Embeddings on-device NLEmbedding vectors → embeddings
  │    └─ Extractors bills/deadlines/watched → facts (+ auto reminders)
  ├─ ReminderScheduler due reminders → macOS notifications
  └─ HttpServer (127.0.0.1:4789, bearer token)
       ├─ /       dashboard (embedded SPA)   ├─ /api/*  REST
       └─ /mcp    MCP streamable-HTTP endpoint
storage: SQLite (WAL) + FTS5 + vector blobs — one file
```
