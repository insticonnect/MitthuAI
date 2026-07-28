import Foundation

/// The web dashboard, embedded as a single self-contained page (no CDNs —
/// works fully offline). Served at "/" with the access token in the URL;
/// the page stores the token in localStorage and uses it for API calls.
enum DashboardHTML {
    static let page = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MitthuAI — Memory</title>
<style>
  :root {
    --bg: #0e0f13; --panel: #16181f; --panel2: #1d2029; --line: #262a36;
    --text: #e8eaf0; --dim: #8a90a3; --accent: #7c6cff; --accent2: #4fd1a5;
    --warn: #ffb454; --danger: #ff6b6b;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font: 14px/1.5 -apple-system, "SF Pro Text", Helvetica, Arial, sans-serif; }
  header { display: flex; align-items: center; gap: 16px; padding: 14px 22px; border-bottom: 1px solid var(--line); position: sticky; top: 0; background: var(--bg); z-index: 5;}
  header h1 { font-size: 17px; font-weight: 700; letter-spacing: .3px; }
  header h1 span { color: var(--accent); }
  nav { display: flex; gap: 4px; margin-left: 12px; }
  nav button { background: none; border: none; color: var(--dim); font: inherit; font-weight: 600; padding: 8px 14px; border-radius: 8px; cursor: pointer; }
  nav button.active { color: var(--text); background: var(--panel2); }
  nav button:hover { color: var(--text); }
  #statusdot { margin-left: auto; display: flex; align-items: center; gap: 8px; color: var(--dim); font-size: 12px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--accent2); }
  .dot.paused { background: var(--warn); }
  main { max-width: 1060px; margin: 0 auto; padding: 22px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 14px; margin-bottom: 20px; }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px 18px; }
  .card .k { color: var(--dim); font-size: 12px; text-transform: uppercase; letter-spacing: .6px; margin-bottom: 6px; }
  .card .v { font-size: 24px; font-weight: 700; }
  .section { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 18px 20px; margin-bottom: 18px; }
  .section h2 { font-size: 14px; margin-bottom: 12px; color: var(--dim); text-transform: uppercase; letter-spacing: .6px; }
  .sechead { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
  .sechead h2 { margin-bottom: 12px; }
  .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
  .bar-row .name { width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar-row .bar { flex: 1; height: 10px; background: var(--panel2); border-radius: 5px; overflow: hidden; }
  .bar-row .bar > div { height: 100%; background: linear-gradient(90deg, var(--accent), #a08bff); border-radius: 5px; }
  .bar-row .time { width: 70px; text-align: right; color: var(--dim); font-variant-numeric: tabular-nums; }
  .sess { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 10px; padding: 10px 4px; border-bottom: 1px solid var(--line); }
  .sess:last-child { border-bottom: none; }
  .sess .t { color: var(--dim); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .sess .app { font-weight: 600; white-space: nowrap; }
  .sess .title { color: var(--dim); flex: 1 1 180px; min-width: 120px; overflow-wrap: anywhere; }
  .sess .dur { color: var(--accent2); white-space: nowrap; font-variant-numeric: tabular-nums; }
  .sess.idle { opacity: .45; }
  input[type=text], input[type=date], input[type=time], textarea {
    background: var(--panel2); border: 1px solid var(--line); color: var(--text);
    border-radius: 10px; padding: 10px 14px; font: inherit; width: 100%;
  }
  input:focus, textarea:focus { outline: none; border-color: var(--accent); }
  .row { display: flex; gap: 10px; align-items: center; }
  button.btn { background: var(--accent); border: none; color: #fff; font: inherit; font-weight: 600; padding: 10px 18px; border-radius: 10px; cursor: pointer; white-space: nowrap; }
  button.btn.ghost { background: var(--panel2); color: var(--text); }
  button.btn.small { padding: 5px 10px; font-size: 12px; border-radius: 8px; }
  button.btn.danger { background: var(--danger); }
  .result { padding: 12px 4px; border-bottom: 1px solid var(--line); }
  .result:last-child { border-bottom: none; }
  .result .meta { color: var(--dim); font-size: 12px; margin-bottom: 4px; }
  .result .meta b { color: var(--text); }
  .result .snippet { color: #c6cad6; font-size: 13px; }
  .fact { display: flex; gap: 10px; align-items: center; padding: 10px 4px; border-bottom: 1px solid var(--line); }
  .fact:last-child { border-bottom: none; }
  .pill { font-size: 11px; font-weight: 700; text-transform: uppercase; padding: 3px 8px; border-radius: 20px; background: var(--panel2); color: var(--dim); white-space: nowrap; }
  .pill.bill { color: var(--warn); } .pill.deadline { color: var(--danger); }
  .pill.watched { color: var(--accent2); } .pill.note { color: var(--accent); }
  .fact .title { flex: 1; }
  .fact .sub { display: block; color: var(--dim); font-size: 12px; margin-top: 3px; }
  .fact .sub .note { color: var(--accent2); }
  .fact .noteedit { display: flex; gap: 6px; margin-top: 5px; }
  .fact .noteedit input { font-size: 12px; padding: 5px 8px; }
  .fact .due { color: var(--dim); font-size: 12px; white-space: nowrap; }
  .fact .due.over { color: var(--danger); font-weight: 700; }
  pre.digest { background: var(--panel2); border-radius: 10px; padding: 16px; white-space: pre-wrap; font: 13px/1.6 ui-monospace, Menlo, monospace; color: #c6cad6; }
  .toggle-row { display: flex; align-items: center; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--line); }
  .toggle-row:last-child { border-bottom: none; }
  .hint { color: var(--dim); font-size: 12px; margin-top: 4px; }
  code.inline { background: var(--panel2); padding: 2px 7px; border-radius: 6px; font: 12px ui-monospace, Menlo, monospace; word-break: break-all; }
  .empty { color: var(--dim); padding: 18px 0; text-align: center; }
  .hidden { display: none; }
  select { background: var(--panel2); border: 1px solid var(--line); color: var(--text); border-radius: 10px; padding: 10px 14px; font: inherit; font-weight: 600; cursor: pointer; }
  select:focus { outline: none; border-color: var(--accent); }
  .chartbox { width: 100%; overflow-x: auto; }
  .chartbox svg { display: block; min-width: 320px; }
  .chartlegend { display: flex; gap: 18px; margin-bottom: 10px; font-size: 12px; color: var(--dim); }
  .chartlegend i.sw { display: inline-block; width: 11px; height: 11px; border-radius: 3px; margin-right: 6px; vertical-align: -1px; }
  .cols2 { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-bottom: 18px; }
  .cols2 .section { margin-bottom: 0; }
  .donut-wrap { display: flex; align-items: center; gap: 22px; flex-wrap: wrap; justify-content: center; }
  .legend { display: flex; flex-direction: column; gap: 8px; }
  .legend .li { display: flex; align-items: center; gap: 8px; font-size: 13px; }
  .legend .sw { width: 12px; height: 12px; border-radius: 3px; }
  .legend .lt { color: var(--dim); font-variant-numeric: tabular-nums; margin-left: auto; padding-left: 12px; }
  .rule-form { display: grid; grid-template-columns: 1fr 1fr 1fr auto; gap: 12px; align-items: end; }
  .rule-form label { display: block; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .5px; color: var(--dim); margin-bottom: 5px; }
  table.rules { width: 100%; border-collapse: collapse; }
  table.rules th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .5px; color: var(--dim); padding: 10px 8px; border-bottom: 1px solid var(--line); }
  table.rules td { padding: 12px 8px; border-bottom: 1px solid var(--line); }
  table.rules tr:last-child td { border-bottom: none; }
  table.rules .any { color: var(--dim); }
  .chip { display: inline-block; font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 20px; background: var(--panel2); color: #cdb9ff; }
  .catpick { display: inline-flex; gap: 4px; flex-shrink: 0; white-space: nowrap; }
  .catpick button { background: var(--panel2); border: 1px solid var(--line); color: var(--dim); font-size: 11px; padding: 2px 8px; border-radius: 12px; cursor: pointer; }
  .catpick button:hover { color: var(--text); border-color: var(--accent); }
  .catpick button.on { background: var(--accent); color: #fff; border-color: var(--accent); }
  .del { color: var(--danger); background: none; border: none; cursor: pointer; font: inherit; font-weight: 600; }
  .seg { display: inline-flex; background: var(--panel2); border: 1px solid var(--line); border-radius: 10px; padding: 3px; gap: 2px; }
  .seg button { background: none; border: none; color: var(--dim); font: inherit; font-weight: 600; padding: 6px 14px; border-radius: 8px; cursor: pointer; }
  .seg button.on { background: var(--accent); color: #fff; }
  .callegend { display: flex; gap: 14px; flex-wrap: wrap; font-size: 11px; color: var(--dim); margin-bottom: 12px; }
  .callegend i { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 5px; }
  .cal-head { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; margin-bottom: 6px; }
  .cal-head div { text-align: center; font-size: 11px; color: var(--dim); text-transform: uppercase; }
  .cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; }
  .cal-cell { background: var(--panel2); border: 1px solid var(--line); border-radius: 10px; min-height: 74px; padding: 6px 8px; cursor: pointer; }
  .cal-cell:hover { border-color: var(--accent); }
  .cal-cell.blank { background: none; border: none; cursor: default; }
  .cal-cell.today { border-color: var(--accent2); }
  .cal-cell.sel { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); }
  .cal-cell .dn, .wk-col .dn { font-size: 12px; font-weight: 700; color: var(--dim); margin-bottom: 5px; }
  .cal-cell.today .dn, .wk-col.today .dn { color: var(--accent2); }
  .cal-dots { display: flex; flex-wrap: wrap; gap: 3px; }
  .cal-dots i { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
  .cal-more { font-size: 10px; color: var(--dim); margin-top: 3px; }
  .wk-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
  .wk-col { background: var(--panel2); border: 1px solid var(--line); border-radius: 10px; padding: 8px; min-height: 130px; cursor: pointer; overflow: hidden; }
  .wk-col:hover { border-color: var(--accent); }
  .wk-col.today { border-color: var(--accent2); }
  .wk-col.sel { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); }
  .hchip { display: flex; align-items: center; gap: 5px; font-size: 11px; margin-bottom: 5px; color: #c6cad6; }
  .hchip i { flex: none; width: 8px; height: 8px; border-radius: 50%; }
  .hchip span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .mini3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
  .mini-cal .mc-title { text-align: center; font-weight: 700; font-size: 13px; margin-bottom: 8px; }
  .mini-cal .cal-head { gap: 2px; margin-bottom: 2px; }
  .mini-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; }
  .mini-cell { aspect-ratio: 1; border-radius: 5px; background: var(--panel2); cursor: pointer; font-size: 10px; color: var(--dim); display: flex; align-items: center; justify-content: center; }
  .mini-cell:hover { outline: 1px solid var(--accent); }
  .mini-cell.blank { background: none; cursor: default; }
  .mini-cell.blank:hover { outline: none; }
  .mini-cell.today { outline: 1px solid var(--accent2); color: var(--accent2); font-weight: 700; }
  details.drop > summary { cursor: pointer; list-style: none; color: var(--dim); font-size: 12px; font-weight: 600; padding: 8px 12px; background: var(--panel2); border: 1px solid var(--line); border-radius: 10px; user-select: none; }
  details.drop > summary:hover { color: var(--text); border-color: var(--accent); }
  details.drop > summary::-webkit-details-marker { display: none; }
  details.drop > summary::before { content: '\25B8  '; }
  details.drop[open] > summary::before { content: '\25BE  '; }
  details.drop > .dropbody { padding: 2px 4px 0; }
  a.tlink { color: inherit; text-decoration: underline dotted; text-underline-offset: 3px; }
  a.tlink:hover { color: var(--accent); }
  @media (max-width: 760px) { .cols2 { grid-template-columns: 1fr; } .rule-form { grid-template-columns: 1fr 1fr; } .mini3 { grid-template-columns: 1fr; } .wk-grid { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 640px) { .bar-row .name { width: 110px; } .cal-cell { min-height: 52px; padding: 4px 5px; } }
</style>
</head>
<body>
<header>
  <h1>🦜 Mitthu<span>AI</span></h1>
  <nav>
    <button id="tab-today" class="active" onclick="show('today')">Today</button>
    <button id="tab-trends" onclick="show('trends')">Trends</button>
    <button id="tab-search" onclick="show('search')">Search</button>
    <button id="tab-brain" onclick="show('brain')">Brain</button>
    <button id="tab-history" onclick="show('history')">History</button>
    <button id="tab-rules" onclick="show('rules')">Rules</button>
    <button id="tab-settings" onclick="show('settings')">Settings</button>
  </nav>
  <div id="statusdot"><div class="dot" id="dot"></div><span id="statustext">tracking</span></div>
</header>
<main>

<div id="view-today">
  <div class="row" style="margin-bottom:16px">
    <input type="date" id="daypick" style="max-width:180px" onchange="loadToday()">
    <button class="btn ghost" onclick="shiftDay(-1)">&larr;</button>
    <button class="btn ghost" onclick="shiftDay(1)">&rarr;</button>
    <button class="btn ghost" onclick="loadDigest()">Daily review</button>
  </div>
  <div class="grid">
    <div class="card"><div class="k">Active screen time</div><div class="v" id="stat-active">–</div><div class="hint">Focused active screen time.</div></div>
    <div class="card"><div class="k">Away (idle)</div><div class="v" id="stat-idle">–</div><div class="hint">Time spent away from keyboard.</div></div>
    <div class="card"><div class="k">Focus vs multitasking</div><div class="v" id="stat-focus" style="color:var(--accent2)">–</div><div class="hint" id="stat-focus-sub">&nbsp;</div></div>
    <div class="card"><div class="k">Tracked events</div><div class="v" id="stat-events" style="color:var(--accent)">–</div><div class="hint">Activity switches logged today.</div></div>
  </div>
  <div class="section hidden" id="digest-box"><h2>Daily review</h2><pre class="digest" id="digest-text"></pre></div>
  <div class="cols2">
    <div class="section"><h2>Category distribution</h2>
      <div class="donut-wrap"><svg id="donut" viewBox="0 0 200 200" width="200" height="200"></svg>
        <div id="donut-legend" class="legend"></div>
      </div>
    </div>
    <div class="section"><h2>Top applications</h2><div id="top-apps"><div class="empty">no data yet</div></div></div>
  </div>
  <div class="section">
    <div class="sechead"><h2>Timeline</h2><button class="btn small ghost" id="sortbtn" onclick="toggleSort()">Newest first ↓</button></div>
    <p class="hint" style="margin-bottom:8px">Tap a category chip on any row to teach MitthuAI. <b>That row</b> moves in full — every tab in it, and any stretch played fullscreen — so the donut and focus score above agree with what you just said, and identical activity within ±10 min follows it. Other days keep their own labels; tap them if you want them changed. The title also becomes a rule, so the same page is tagged on sight from now on.</p>
    <div id="timeline"><div class="empty">no activity logged for this day</div></div>
  </div>
</div>

<div id="view-trends" class="hidden">
  <div class="row" style="margin-bottom:16px">
    <select id="range" onchange="loadTrends()">
      <option value="7">This week</option>
      <option value="30">This month</option>
      <option value="90">Last 3 months</option>
    </select>
  </div>
  <div class="grid">
    <div class="card"><div class="k" id="t-active-k">Active time</div><div class="v" id="t-active">–</div><div class="hint" id="t-active-d">&nbsp;</div></div>
    <div class="card"><div class="k" id="t-focus-k">Focus score</div><div class="v" id="t-focus" style="color:var(--accent2)">–</div><div class="hint" id="t-focus-d">&nbsp;</div></div>
    <div class="card"><div class="k" id="t-idle-k">Idle time</div><div class="v" id="t-idle">–</div><div class="hint" id="t-idle-d">&nbsp;</div></div>
  </div>
  <div class="cols2">
    <div class="section"><h2>Focus vs multitasking trend</h2><div id="chart-line" class="chartbox"><div class="empty">no data</div></div></div>
    <div class="section"><h2>Daily activity pattern</h2>
      <div class="chartlegend"><span><i class="sw" style="background:#5b8def"></i>Active (min)</span><span><i class="sw" style="background:#4a4f5e"></i>Away (min)</span></div>
      <div id="chart-bars" class="chartbox"><div class="empty">no data</div></div>
    </div>
  </div>
  <div class="section"><h2>Category summary</h2>
    <div class="donut-wrap"><svg id="donut2" viewBox="0 0 200 200" width="200" height="200"></svg>
      <div id="donut-legend2" class="legend"></div>
    </div>
  </div>
</div>

<div id="view-search" class="hidden">
  <div class="section">
    <div class="row">
      <input type="text" id="q" placeholder="Search your memory — e.g. 'that video about transformers', 'electricity bill'…" onkeydown="if(event.key==='Enter')doSearch()">
      <button class="btn" onclick="doSearch()">Search</button>
    </div>
    <div class="row" style="margin-top:10px">
      <label class="hint">From <input type="date" id="q-from" style="width:auto"></label>
      <label class="hint">To <input type="date" id="q-to" style="width:auto"></label>
      <span class="hint" id="q-mode"></span>
    </div>
  </div>
  <div class="section"><h2>Results</h2><div id="results"><div class="empty">search across everything you've seen on this Mac</div></div></div>
</div>

<div id="view-brain" class="hidden">
  <div class="section">
    <h2>Add item</h2>
    <div class="row">
      <input type="text" id="new-title" placeholder="e.g. Pay electricity bill">
      <input type="text" id="new-note" placeholder="note (optional) — what this actually is" style="max-width:280px">
      <input type="date" id="new-due" style="max-width:180px">
      <input type="time" id="new-time" lang="en-US" style="max-width:150px" title="Reminder time (default 9:00 AM)">
      <button class="btn" onclick="createFact()">Add</button>
    </div>
    <p class="hint" style="margin-top:6px">Pick a date and (optionally) a time — you'll get the reminder at that exact time; without a time it defaults to 9:00 AM.</p>
  </div>
  <div class="section"><h2>Open items</h2><div id="facts"><div class="empty">nothing here yet — bills and deadlines you see on screen appear automatically</div></div></div>
  <div class="section"><h2>Upcoming reminders</h2><div id="reminders"><div class="empty">no reminders scheduled</div></div></div>
</div>

<div id="view-history" class="hidden">
  <div class="row" style="margin-bottom:16px; flex-wrap:wrap">
    <div class="seg" id="hist-seg">
      <button data-m="week" class="on" onclick="setHistMode('week')">Week</button>
      <button data-m="month" onclick="setHistMode('month')">Month</button>
      <button data-m="3mo" onclick="setHistMode('3mo')">3 Months</button>
    </div>
    <button class="btn ghost" onclick="histShift(-1)">&larr;</button>
    <b id="hist-label" style="min-width:170px;text-align:center"></b>
    <button class="btn ghost" onclick="histShift(1)">&rarr;</button>
    <button class="btn ghost" onclick="histToday()">Today</button>
    <span style="flex:1"></span>
    <button class="btn ghost" onclick="exportICS()">📅 Export .ics</button>
  </div>
  <div class="grid">
    <div class="card"><div class="k">Videos watched</div><div class="v" id="h-watched" style="color:#22d3ee">–</div><div class="hint" id="h-watched-d">&nbsp;</div></div>
    <div class="card"><div class="k">Revisions done</div><div class="v" id="h-done" style="color:var(--accent2)">–</div><div class="hint" id="h-done-d">&nbsp;</div></div>
    <div class="card"><div class="k">Revisions missed</div><div class="v" id="h-missed" style="color:var(--danger)">–</div><div class="hint" id="h-missed-d">&nbsp;</div></div>
    <div class="card"><div class="k">Completion rate</div><div class="v" id="h-rate">–</div><div class="hint" id="h-rate-d">&nbsp;</div></div>
  </div>
  <div class="section">
    <div class="sechead"><h2 id="hist-cal-title">Calendar</h2></div>
    <div class="callegend">
      <span><i style="background:#22d3ee"></i>Watched</span>
      <span><i style="background:#4fd1a5"></i>Revised</span>
      <span><i style="background:#ff6b6b"></i>Missed</span>
      <span><i style="background:#ffb454"></i>Due today</span>
      <span><i style="background:#7c6cff"></i>Upcoming</span>
      <span><i style="background:#5b6274"></i>Closed early <b>(kept out of the calendar)</b></span>
    </div>
    <div id="hist-cal"><div class="empty">loading…</div></div>
    <p class="hint" style="margin-top:10px">Click any day to see exactly what happened — and mark revisions as done.</p>
    <details class="drop hidden" id="hist-closed" style="margin-top:12px">
      <summary>Closed early <span id="hist-closed-n"></span> — steps that never came round, because you finished or dismissed the item first</summary>
      <div class="dropbody" id="hist-closed-items"></div>
    </details>
  </div>
  <div class="section hidden" id="hist-day-box">
    <h2 id="hist-day-title">Day</h2>
    <div id="hist-day-items"></div>
  </div>
  <div class="section hidden" id="hist-cmp-box"><h2>Month-by-month comparison</h2><div id="hist-cmp"></div></div>
  <div class="section">
    <h2>Google Calendar sync</h2>
    <p class="hint">“Export .ics” downloads your entire upcoming revision &amp; deadline schedule as a standard calendar file. Import it at calendar.google.com → ⚙ Settings → Import &amp; export → Import (Apple Calendar and Outlook open the file directly). Individual upcoming items also have a “+ GCal” button in the day view to add just that one event. Everything stays local — nothing is sent anywhere.</p>
  </div>
</div>

<div id="view-rules" class="hidden">
  <div class="section">
    <h2>Create categorization rule</h2>
    <p class="hint" style="margin-bottom:12px">Automatically tag activity. Group related study portals and videos under the same category so they count as focus, not multitasking. Leave a field blank to match anything.</p>
    <p class="hint" style="margin-bottom:12px"><b>A rule applies from now on.</b> Days already recorded keep the labels they were given, so writing a rule today never redraws last week's numbers behind your back — and deleting a rule doesn't change past days either.</p>
    <div class="rule-form">
      <div><label>Application name</label><input type="text" id="rule-app" placeholder="e.g. Safari"></div>
      <div><label>Window title contains</label><input type="text" id="rule-title" placeholder="e.g. YouTube"></div>
      <div><label>Category / topic</label>
        <input type="text" id="rule-cat" list="cat-list" placeholder="e.g. Study">
        <datalist id="cat-list"></datalist>
      </div>
      <button class="btn" onclick="addRule()">Apply rule</button>
    </div>
    <label class="hint" style="display:flex;align-items:flex-start;gap:8px;margin-top:14px;cursor:pointer">
      <input type="checkbox" id="rule-backfill" style="width:auto;margin-top:2px">
      <span>Also apply to past activity — re-labels every day already recorded that matches this rule. Anything you tagged by hand on the timeline is left alone. <b>This can't be undone by deleting the rule.</b></span>
    </label>
    <p class="hint" id="rule-msg" style="margin-top:10px">&nbsp;</p>
  </div>
  <div class="section">
    <h2>Active categorization rules</h2>
    <div id="rules-table"><div class="empty">no rules yet</div></div>
  </div>
</div>

<div id="view-settings" class="hidden">
  <div class="section">
    <h2>Capture</h2>
    <div class="toggle-row"><div><b>Pause tracking</b><div class="hint">Stops all logging until resumed.</div></div><input type="checkbox" id="set-paused" onchange="saveSettings()"></div>
    <div class="toggle-row"><div><b>Capture on-screen text</b><div class="hint">Reads visible text via macOS accessibility — powers memory search.</div></div><input type="checkbox" id="set-text" onchange="saveSettings()"></div>
    <div class="toggle-row"><div><b>Capture browser URLs</b><div class="hint">Uses Apple Events (asks permission once per browser).</div></div><input type="checkbox" id="set-urls" onchange="saveSettings()"></div>
    <div class="toggle-row"><div><b>Auto spaced-repetition for study videos</b><div class="hint">Watched lectures/tutorials get revision reminders after 1/3/7/14/30 days.</div></div><input type="checkbox" id="set-revise" onchange="saveSettings()"></div>
  </div>
  <div class="section">
    <h2>Startup</h2>
    <div class="toggle-row"><div><b>Open MitthuAI at login</b><div class="hint">macOS starts MitthuAI automatically after every login or restart, so tracking is never silently off. Appears in System Settings → General → Login Items.</div></div><input type="checkbox" id="set-login" onchange="saveSettings()"></div>
  </div>
  <div class="section">
    <h2>Search quality (embeddings)</h2>
    <p class="hint" style="margin-bottom:10px">Active model: <span id="emb-model" class="chip">–</span></p>
    <div class="toggle-row"><div><b>Turbo accuracy (bring your own OpenAI key)</b><div class="hint">Uses OpenAI text-embedding-3-small for higher-accuracy, multilingual search. Sends captured text to OpenAI — opt-in. Your key is stored in the macOS Keychain, never in the database, and you're billed by OpenAI directly.</div></div><input type="checkbox" id="set-turbo" onchange="saveSettings()"></div>
    <div class="row" style="margin-top:10px">
      <input type="text" id="set-openai" placeholder="sk-… (leave blank to keep existing; clears if emptied on save)">
      <button class="btn" onclick="saveSettings()">Save key</button>
    </div>
    <p class="hint" id="openai-status" style="margin-top:6px">&nbsp;</p>
  </div>
  <div class="section">
    <h2>Deadlines &amp; dates</h2>
    <p class="hint" style="margin-bottom:10px">Dates are read with the same on-device parser macOS uses for “Add to Calendar”, anchored to the deadline word — so “Last date to Apply : Sep 12, 2026” lands on the 12th, not on a year digit. A date it isn’t sure about is marked <b>check date</b> in Brain, where 📅 fixes it.</p>
    <div class="row" style="align-items:center">
      <label class="hint">Numeric dates like 12/09/2026 mean:</label>
      <select id="set-dateorder" onchange="saveSettings()" style="max-width:260px">
        <option value="auto">Auto — follow this Mac’s region</option>
        <option value="dmy">Day first — 12 September</option>
        <option value="mdy">Month first — December 9</option>
      </select>
    </div>
    <div class="toggle-row" style="margin-top:12px"><div><b>Let Apple’s on-device model read tricky dates</b><div class="hint">Only for deadline lines the parser can’t resolve on its own — never for ordinary capture. Everything it returns is checked against the text before it becomes a reminder, and nothing leaves this Mac. Status: <b id="model-status">–</b></div></div><input type="checkbox" id="set-model" onchange="saveSettings()"></div>
  </div>
  <div class="section">
    <h2>Video sources (always count as video)</h2>
    <p class="hint" style="margin-bottom:10px">MitthuAI spots a playing video on its own — the player's timecode and controls on screen, /watch-style links, the display staying awake — so most sites work with nothing listed here. Add a domain or keyword to force it anyway, e.g. your college portal. One per line.</p>
    <textarea id="set-video" rows="4" placeholder="learn.mycollege.edu"></textarea>
    <div class="row" style="margin-top:10px"><button class="btn" onclick="saveSettings()">Save</button></div>
    <p class="hint" style="margin-top:14px;margin-bottom:6px"><b>Recent detections (videos &amp; dates)</b> — every decision with its reasons, so a missed lecture or an odd deadline explains itself:</p>
    <div id="detection-log" class="hint" style="white-space:pre-wrap;font-family:ui-monospace,monospace;font-size:11px">–</div>
  </div>
  <div class="section">
    <h2>Excluded apps (never captured)</h2>
    <textarea id="set-excluded" rows="5" placeholder="One app name per line"></textarea>
    <div class="row" style="margin-top:10px"><button class="btn" onclick="saveSettings()">Save</button></div>
  </div>
  <div class="section">
    <h2>Claude.ai web access (mitthuai account)</h2>
    <p class="hint" style="margin-bottom:8px">Sign in with your mitthuai account to use MitthuAI from Claude on the web. Login happens on mitthuai.com (Google Sign-In, identity only — we never read your email). Your memory stays on this Mac; the account only lets Claude reach it through a secure tunnel.</p>
    <p class="hint" style="margin-bottom:8px">Status: <b id="acct-status">…</b></p>
    <div class="row"><button class="btn" id="acct-btn" onclick="toggleAccount()">Connect account</button></div>
  </div>
  <div class="section">
    <h2>Connect AI clients (MCP) — local</h2>
    <p class="hint" style="margin-bottom:8px">Claude Code (terminal):</p>
    <code class="inline" id="mcp-code">…</code>
    <p class="hint" style="margin-top:12px;margin-bottom:8px">Claude Desktop — add to <code class="inline">claude_desktop_config.json</code>:</p>
    <code class="inline" id="mcp-desktop">…</code>
  </div>
  <div class="section">
    <h2>Data</h2>
    <p class="hint" id="data-counts">–</p>
    <div class="row" style="margin-top:10px">
      <label class="hint">Delete range: <input type="date" id="purge-from" style="width:auto"></label>
      <label class="hint">to <input type="date" id="purge-to" style="width:auto"></label>
      <button class="btn danger" onclick="purge()">Delete</button>
    </div>
  </div>
</div>

</main>
<script>
(function(){
  const p = new URLSearchParams(location.search);
  if (p.get('token')) { localStorage.setItem('hm_token', p.get('token')); history.replaceState({}, '', '/'); }
})();
const TOKEN = localStorage.getItem('hm_token') || '';
async function api(path, opts) {
  opts = opts || {};
  opts.headers = Object.assign({'Authorization': 'Bearer ' + TOKEN}, opts.headers || {});
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error('api ' + r.status);
  return r.json();
}
function fmtDur(s) { s = Math.round(s); const h = Math.floor(s/3600), m = Math.floor((s%3600)/60); return h > 0 ? h + 'h ' + m + 'm' : m + 'm'; }
// 12-hour clock with AM/PM, built by hand so it reads the same on every
// machine regardless of the browser's locale.
function fmtTime(ts) {
  const d = new Date(ts*1000);
  const h = d.getHours(), m = d.getMinutes();
  return ((h % 12) || 12) + ':' + String(m).padStart(2, '0') + ' ' + (h < 12 ? 'AM' : 'PM');
}
function fmtDate(ts) { return todayStr(new Date(ts*1000)) + ' ' + fmtTime(ts); }
function esc(s) { const d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
// Title that opens its source (e.g. the watched video) when we have a URL.
function linkTitle(title, url) {
  return (url && (url.indexOf('http://') === 0 || url.indexOf('https://') === 0))
    ? '<a class="tlink" href="' + esc(url) + '" target="_blank" rel="noopener" onclick="event.stopPropagation()">' + esc(title) + ' ↗</a>'
    : esc(title);
}
function todayStr(d) { d = d || new Date(); const off = d.getTimezoneOffset(); return new Date(d.getTime() - off*60000).toISOString().slice(0,10); }

const CAT_COLORS = {'Study':'#4fd1a5','Entertainment':'#7c6cff','Work':'#ffb454','Other':'#5b6274','Idle':'#3a3f4d','Uncategorized':'#5b6274'};
const PALETTE = ['#7c6cff','#4fd1a5','#ffb454','#ff6b6b','#5b8def','#e879f9','#22d3ee','#a3e635'];
function catColor(c, i) { return CAT_COLORS[c] || PALETTE[(i||0) % PALETTE.length]; }
let CATEGORIES = ['Study','Entertainment','Work','Other'];

function show(tab) {
  ['today','trends','search','brain','history','rules','settings'].forEach(t => {
    document.getElementById('view-' + t).classList.toggle('hidden', t !== tab);
    document.getElementById('tab-' + t).classList.toggle('active', t === tab);
  });
  if (tab === 'today') loadToday();
  if (tab === 'trends') loadTrends();
  if (tab === 'brain') loadBrain();
  if (tab === 'history') loadHistory();
  if (tab === 'rules') loadRules();
  if (tab === 'settings') loadSettings();
}

function renderDonut(cats, svgId, legendId) {
  const svg = document.getElementById(svgId || 'donut');
  const legend = document.getElementById(legendId || 'donut-legend');
  // Accept either [{category,total}] (from the API) or {name: seconds}.
  let pairs;
  if (Array.isArray(cats)) {
    pairs = cats.map(r => [r.category || 'Other', +r.total || 0]);
  } else {
    pairs = Object.entries(cats).map(([k, v]) => [k, +v || 0]);
  }
  const entries = pairs.filter(([k]) => k !== 'Idle').sort((a,b) => b[1]-a[1]);
  const total = entries.reduce((s,[,v]) => s+v, 0);
  if (!total) { svg.innerHTML = '<circle cx="100" cy="100" r="70" fill="none" stroke="#1d2029" stroke-width="26"/>'; legend.innerHTML = '<span class="empty">no data</span>'; return; }
  const C = 2 * Math.PI * 70;
  let offset = 0, paths = '';
  entries.forEach(([name, val], i) => {
    const frac = val/total, len = frac * C;
    paths += '<circle cx="100" cy="100" r="70" fill="none" stroke="' + catColor(name,i) + '" stroke-width="26" ' +
      'stroke-dasharray="' + len + ' ' + (C-len) + '" stroke-dashoffset="' + (-offset) + '" transform="rotate(-90 100 100)"></circle>';
    offset += len;
  });
  svg.innerHTML = paths;
  legend.innerHTML = entries.map(([name,val],i) =>
    '<div class="li"><span class="sw" style="background:' + catColor(name,i) + '"></span>' +
    esc(name) + '<span class="lt">' + fmtDur(val) + '</span></div>').join('');
}

function jsAttr(s) {
  return (s || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/"/g, '&quot;');
}
// `from`/`to` are the row's own span: tapping a chip means "this stretch of my
// day was Study", and a row holds every tab visited in that app plus any
// fullscreen stretch macOS reported without a title. Sending the span moves all
// of those minutes together, instead of only the tab on show.
function catChips(app, title, current, from, to) {
  if (!title && !app) return '';
  const t = jsAttr(title);
  const a = jsAttr(app);
  const f = +from || 0, e = +to || 0;
  return '<span class="catpick">' + CATEGORIES.map(c =>
    '<button class="' + (c === current ? 'on' : '') + '" title="Count this whole row as ' + c + '" ' +
    'onclick="tagTitle(\'' + a + '\',\'' + t + '\',\'' + c + '\',' + f + ',' + e + ')">' + c + '</button>').join('') + '</span>';
}

async function tagTitle(app, title, cat, from, to) {
  const body = {app:app, title:title, category:cat};
  if (from && to && to > from) { body.from = from; body.to = to; }
  await api('/api/categorize', {method:'POST', body: JSON.stringify(body)});
  loadToday();
}

function shiftDay(n) {
  const el = document.getElementById('daypick');
  const d = new Date(el.value || todayStr());
  d.setDate(d.getDate() + n);
  el.value = todayStr(d);
  loadToday();
}

async function loadToday() {
  const el = document.getElementById('daypick');
  if (!el.value) el.value = todayStr();
  document.getElementById('digest-box').classList.add('hidden');
  try {
    const o = await api('/api/overview?date=' + el.value);
    document.getElementById('stat-active').textContent = fmtDur(o.active_secs);
    document.getElementById('stat-idle').textContent = fmtDur(o.idle_secs);
    document.getElementById('stat-events').textContent = o.event_count;

    const totalFocusable = o.focus_secs + o.multitask_secs;
    const pct = totalFocusable > 0 ? Math.round(100 * o.focus_secs / totalFocusable) : 0;
    document.getElementById('stat-focus').textContent = pct + '%';
    document.getElementById('stat-focus-sub').textContent =
      'Focus: ' + fmtDur(o.focus_secs) + ' | Multitask: ' + fmtDur(o.multitask_secs);

    renderDonut(o.categories || {});

    const apps = document.getElementById('top-apps');
    if (o.top_apps.length) {
      const max = o.top_apps[0].total;
      apps.innerHTML = o.top_apps.map(a =>
        '<div class="bar-row"><div class="name">' + esc(a.app) + '</div>' +
        '<div class="bar"><div style="width:' + Math.max(2, 100*a.total/max) + '%"></div></div>' +
        '<div class="time">' + fmtDur(a.total) + '</div></div>').join('');
    } else apps.innerHTML = '<div class="empty">no data yet</div>';

    lastSessions = o.sessions || [];
    renderTimeline();
  } catch(e) { console.error(e); }
}

let lastSessions = [];
let timelineSort = 'desc'; // 'desc' = newest first

function renderTimeline() {
  const tl = document.getElementById('timeline');
  const btn = document.getElementById('sortbtn');
  if (btn) btn.textContent = timelineSort === 'desc' ? 'Newest first ↓' : 'Oldest first ↑';
  if (!lastSessions.length) { tl.innerHTML = '<div class="empty">no activity logged for this day</div>'; return; }
  const arr = lastSessions.slice().sort((a, b) =>
    timelineSort === 'desc' ? b.ts_start - a.ts_start : a.ts_start - b.ts_start);
  tl.innerHTML = arr.map(s => {
    // The session shows the tab that held the most time; every switched-to
    // title stays visible in the hover tooltip.
    const tabs = s.titles || [];
    const tabHint = tabs.length > 1 ? ' <span class="hint">· ' + tabs.length + ' tabs</span>' : '';
    const tip = tabs.length > 1 ? ' title="' + esc(tabs.join('\n')).replace(/"/g, '&quot;') + '"' : '';
    return '<div class="sess' + (s.is_idle ? ' idle' : '') + '">' +
    '<span class="t">' + fmtTime(s.ts_start) + '–' + fmtTime(s.ts_end) + '</span>' +
    '<span class="app">' + esc(s.app) + '</span>' +
    '<span class="title"' + tip + '>' + esc(s.title) + tabHint + mixedHint(s) + '</span>' +
    '<span class="dur">' + fmtDur(s.duration) + '</span>' +
    (s.is_idle ? '' : catChips(s.app, s.title, s.category, s.ts_start, s.ts_end)) + '</div>';
  }).join('');
}

// A row whose minutes are split between buckets says so, and hovering breaks it
// down. The chip shows where most of the row sits; without this a part-Study
// row looked wholly Study while the donut counted the rest elsewhere.
function mixedHint(s) {
  const cs = s.category_secs || {};
  const names = Object.keys(cs).filter(k => cs[k] > 0);
  if (names.length < 2) return '';
  if ((cs[s.category] || 0) >= s.duration * 0.98) return '';
  const detail = names.sort((a, b) => cs[b] - cs[a]).map(k => k + ' ' + fmtDur(cs[k])).join('\n');
  return ' <span class="hint" title="' + esc(detail).replace(/"/g, '&quot;') + '">· mixed</span>';
}

function toggleSort() {
  timelineSort = timelineSort === 'desc' ? 'asc' : 'desc';
  renderTimeline();
}

async function loadRules() {
  const r = await api('/api/rules');
  CATEGORIES = r.categories && r.categories.length ? r.categories : CATEGORIES;
  document.getElementById('cat-list').innerHTML = CATEGORIES.map(c => '<option value="' + esc(c) + '">').join('');
  const box = document.getElementById('rules-table');
  if (!r.rules.length) { box.innerHTML = '<div class="empty">no rules yet</div>'; return; }
  box.innerHTML = '<table class="rules"><thead><tr><th>Application</th><th>Title contains</th><th>Category / topic</th><th style="text-align:right">Action</th></tr></thead><tbody>' +
    r.rules.map(x =>
      '<tr><td><b>' + (x.app ? esc(x.app) : '<span class="any">Any</span>') + '</b></td>' +
      '<td>' + (x.title_pattern ? esc(x.title_pattern) : '<span class="any">Any</span>') + '</td>' +
      '<td><span class="chip" style="color:' + catColor(x.category) + '">' + esc(x.category) + '</span></td>' +
      '<td style="text-align:right"><button class="del" onclick="delRule(' + x.id + ')">Delete</button></td></tr>').join('') +
    '</tbody></table>';
}

async function addRule() {
  const app = document.getElementById('rule-app').value.trim();
  const title = document.getElementById('rule-title').value.trim();
  const cat = document.getElementById('rule-cat').value.trim();
  if (!cat || (!app && !title)) { alert('Enter a category and at least an app or title.'); return; }
  const backfill = document.getElementById('rule-backfill').checked;
  if (backfill && !confirm('Re-label every past day matching this rule as "' + cat + '"?\n\nDeleting the rule afterwards will not undo it.')) return;
  const r = await api('/api/rules', {method:'POST',
    body: JSON.stringify({app:app, title_pattern:title, category:cat, backfill:backfill})});
  document.getElementById('rule-app').value = '';
  document.getElementById('rule-title').value = '';
  document.getElementById('rule-cat').value = '';
  document.getElementById('rule-backfill').checked = false;
  const n = (r && r.retagged) || 0;
  document.getElementById('rule-msg').textContent = backfill
    ? 'Rule saved — ' + n + ' recorded event' + (n === 1 ? '' : 's') + ' re-labelled ' + cat + '.'
    : 'Rule saved — it tags activity from now on. Days already recorded are unchanged.';
  loadRules();
}

async function delRule(id) {
  if (!confirm('Delete this rule? New activity stops matching it. Days already recorded keep the labels they were given — deleting a rule never changes the past.')) return;
  await api('/api/rules/delete', {method:'POST', body: JSON.stringify({id:id})});
  document.getElementById('rule-msg').textContent = 'Rule deleted — past days are untouched.';
  loadRules();
}

async function loadDigest() {
  const el = document.getElementById('daypick');
  const d = await api('/api/digest?date=' + (el.value || todayStr()));
  document.getElementById('digest-text').textContent = d.text;
  document.getElementById('digest-box').classList.remove('hidden');
}

function deltaDur(s) { return (s >= 0 ? '+' : '-') + fmtDur(Math.abs(s)); }

async function loadTrends() {
  const days = parseInt(document.getElementById('range').value) || 7;
  const label = days <= 7 ? 'Weekly' : (days <= 31 ? 'Monthly' : '3-month');
  document.getElementById('t-active-k').textContent = label + ' active time';
  document.getElementById('t-focus-k').textContent = label + ' focus score';
  document.getElementById('t-idle-k').textContent = label + ' idle time';
  let r;
  try { r = await api('/api/report?days=' + days); } catch(e) { return; }
  const T = r.totals, P = r.prior;
  document.getElementById('t-active').textContent = fmtDur(T.active);
  document.getElementById('t-idle').textContent = fmtDur(T.idle);
  const fs = (T.focus + T.multitask) > 0 ? Math.round(100 * T.focus / (T.focus + T.multitask)) : 0;
  const pfs = (P.focus + P.multitask) > 0 ? Math.round(100 * P.focus / (P.focus + P.multitask)) : 0;
  document.getElementById('t-focus').textContent = fs + '%';
  document.getElementById('t-active-d').textContent = deltaDur(T.active - P.active) + ' vs last period';
  document.getElementById('t-idle-d').textContent = deltaDur(T.idle - P.idle) + ' vs last period';
  document.getElementById('t-focus-d').textContent = ((fs - pfs) >= 0 ? '+' : '') + (fs - pfs) + '% vs last period';
  document.getElementById('chart-line').innerHTML = svgLine(r.daily);
  document.getElementById('chart-bars').innerHTML = svgBars(r.daily);
  renderDonut(r.categories, 'donut2', 'donut-legend2');
}

function svgLine(daily) {
  const W = 600, H = 200, pL = 30, pR = 12, pT = 12, pB = 24, n = daily.length;
  if (!n) return '<div class="empty">no data</div>';
  const xOf = (i) => pL + (n <= 1 ? (W - pL - pR) / 2 : (W - pL - pR) * i / (n - 1));
  const yOf = (pct) => pT + (H - pT - pB) * (1 - pct / 100);
  let grid = '';
  [0, 25, 50, 75, 100].forEach(gy => {
    const y = yOf(gy);
    grid += '<line x1="' + pL + '" y1="' + y + '" x2="' + (W - pR) + '" y2="' + y + '" stroke="#262a36"/>' +
            '<text x="' + (pL - 6) + '" y="' + (y + 3) + '" fill="#8a90a3" font-size="9" text-anchor="end">' + gy + '</text>';
  });
  const pts = daily.map((d, i) => {
    const tot = d.focus + d.multitask;
    const pct = tot > 0 ? 100 * d.focus / tot : 0;
    return [xOf(i), yOf(pct)];
  });
  const poly = pts.map(p => p[0].toFixed(1) + ',' + p[1].toFixed(1)).join(' ');
  const dots = pts.map(p => '<circle cx="' + p[0].toFixed(1) + '" cy="' + p[1].toFixed(1) + '" r="3" fill="#4fd1a5"/>').join('');
  const step = Math.ceil(n / 7);
  const xl = daily.map((d, i) => i % step === 0
    ? '<text x="' + xOf(i).toFixed(1) + '" y="' + (H - 8) + '" fill="#8a90a3" font-size="9" text-anchor="middle">' + d.date.slice(5) + '</text>' : '').join('');
  return '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%">' + grid +
         '<polyline points="' + poly + '" fill="none" stroke="#4fd1a5" stroke-width="2"/>' + dots + xl + '</svg>';
}

function svgBars(daily) {
  const W = 600, H = 220, pL = 34, pR = 12, pT = 12, pB = 24, n = daily.length;
  if (!n) return '<div class="empty">no data</div>';
  const maxMin = Math.max(1, ...daily.map(d => Math.max(d.active, d.idle) / 60));
  const band = (W - pL - pR) / n;
  const bw = Math.max(3, Math.min(14, band / 2 - 2));
  const hOf = (min) => (H - pT - pB) * (min / maxMin);
  let grid = '';
  for (let k = 0; k <= 4; k++) {
    const v = maxMin * k / 4, y = pT + (H - pT - pB) * (1 - k / 4);
    grid += '<line x1="' + pL + '" y1="' + y + '" x2="' + (W - pR) + '" y2="' + y + '" stroke="#262a36"/>' +
            '<text x="' + (pL - 6) + '" y="' + (y + 3) + '" fill="#8a90a3" font-size="9" text-anchor="end">' + Math.round(v) + '</text>';
  }
  let bars = '';
  daily.forEach((d, i) => {
    const cx = pL + band * i + band / 2;
    const ah = hOf(d.active / 60), wh = hOf(d.idle / 60);
    bars += '<rect x="' + (cx - bw - 1).toFixed(1) + '" y="' + (H - pB - ah).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + ah.toFixed(1) + '" fill="#5b8def" rx="1"/>';
    bars += '<rect x="' + (cx + 1).toFixed(1) + '" y="' + (H - pB - wh).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + wh.toFixed(1) + '" fill="#4a4f5e" rx="1"/>';
  });
  const step = Math.ceil(n / 7);
  const xl = daily.map((d, i) => i % step === 0
    ? '<text x="' + (pL + band * i + band / 2).toFixed(1) + '" y="' + (H - 8) + '" fill="#8a90a3" font-size="9" text-anchor="middle">' + d.date.slice(5) + '</text>' : '').join('');
  return '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%">' + grid + bars + xl + '</svg>';
}

async function doSearch() {
  const q = document.getElementById('q').value.trim();
  if (!q) return;
  let url = '/api/search?q=' + encodeURIComponent(q);
  const f = document.getElementById('q-from').value, t = document.getElementById('q-to').value;
  if (f) url += '&from=' + (new Date(f).getTime()/1000);
  if (t) url += '&to=' + (new Date(t).getTime()/1000 + 86400);
  const box = document.getElementById('results');
  box.innerHTML = '<div class="empty">searching…</div>';
  try {
    const r = await api(url);
    if (!r.results.length) { box.innerHTML = '<div class="empty">no matches</div>'; return; }
    box.innerHTML = r.results.map(x =>
      '<div class="result"><div class="meta"><b>' + esc(x.app) + '</b> · ' + esc(x.title) +
      ' · ' + fmtDate(x.ts) + (x.url ? ' · <a style="color:var(--accent)" href="' + esc(x.url) + '" target="_blank">link</a>' : '') + '</div>' +
      '<div class="snippet">' + esc(x.snippet) + '</div></div>').join('');
  } catch(e) { box.innerHTML = '<div class="empty">search failed</div>'; }
}

let lastBrain = {facts: [], reminders: []};
let editingNote = null;   // fact id whose note is being edited
let editingDue = null;    // fact id whose due date is being corrected

async function loadBrain() {
  lastBrain = await api('/api/brain');
  renderBrain();
}

function renderBrain() {
  const b = lastBrain;
  const facts = document.getElementById('facts');
  const now = Date.now()/1000;
  if (b.facts.length) {
    facts.innerHTML = b.facts.map(f => {
      const due = f.due_ts ? '<span class="due' + (f.due_ts < now ? ' over' : '') + '">due ' + fmtDate(f.due_ts) + '</span>' : '';
      // A date the extractor wasn't sure of — say so instead of quietly
      // scheduling the wrong nudge.
      const review = f.needs_review ? '<span class="pill" style="color:var(--danger)" title="MitthuAI was not certain of this date — check it against the source">check date</span>' : '';
      const dueBtn = (f.kind !== 'watched')
        ? '<button class="btn small ghost" title="Fix the date" onclick="editDue(' + f.id + ')">📅</button>' : '';
      // Hand this one item to the on-device model to re-read its source line.
      const fixBtn = (f.kind !== 'watched' && MODEL_READY)
        ? '<button class="btn small ghost" title="Let the on-device model re-read this item" onclick="modelFix(' + f.id + ')">✨</button>' : '';
      const revBtn = f.kind === 'watched' ? '<button class="btn small ghost" onclick="factAction(' + f.id + ',\'revise\')">revise</button>' : '';
      // Second line: your own note plus when this was captured — between them
      // they answer "which video was this?" months later.
      let second;
      if (editingDue === f.id) {
        const d = f.due_ts ? new Date(f.due_ts*1000) : new Date();
        const pad = n => String(n).padStart(2,'0');
        const dv = d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate());
        const tv = pad(d.getHours()) + ':' + pad(d.getMinutes());
        second = '<span class="noteedit">' +
          '<input type="date" id="due-date-' + f.id + '" value="' + dv + '" style="max-width:160px">' +
          '<input type="time" id="due-time-' + f.id + '" lang="en-US" value="' + tv + '" style="max-width:140px">' +
          '<button class="btn small" onclick="saveDue(' + f.id + ')">Save date</button>' +
          '<button class="btn small ghost" onclick="editingDue=null;renderBrain()">Cancel</button></span>';
      } else if (editingNote === f.id) {
        second = '<span class="noteedit">' +
          '<input type="text" id="note-input-' + f.id + '" value="' + esc(f.note || '').replace(/"/g, '&quot;') + '" ' +
          'placeholder="e.g. Week 3 — Fourier series, phase shift part" ' +
          'onkeydown="noteKey(event,' + f.id + ')">' +
          '<button class="btn small" onclick="saveNote(' + f.id + ')">Save</button>' +
          '<button class="btn small ghost" onclick="editingNote=null;renderBrain()">Cancel</button></span>';
      } else {
        const parts = [];
        if (f.note) parts.push('<span class="note">' + esc(f.note) + '</span>');
        if (f.created_ts) parts.push((f.kind === 'watched' ? 'watched ' : 'added ') + fmtDate(f.created_ts));
        if (f.kind === 'watched' && f.watch_secs >= 30) parts.push(fmtDur(f.watch_secs) + ' total');
        second = parts.length ? '<span class="sub">' + parts.join(' · ') + '</span>' : '';
      }
      const noteBtn = editingNote === f.id ? '' :
        '<button class="btn small ghost" title="Add a note so you remember what this was" ' +
        'onclick="editNote(' + f.id + ')">✎ ' + (f.note ? 'edit note' : 'note') + '</button>';
      return '<div class="fact"><span class="pill ' + esc(f.kind) + '">' + esc(f.kind) + '</span>' +
        '<span class="title">' + linkTitle(f.title, f.detail) + second + '</span>' + review + due + dueBtn + fixBtn + noteBtn + revBtn +
        '<button class="btn small" onclick="factAction(' + f.id + ',\'complete\')">done</button>' +
        '<button class="btn small ghost" onclick="factAction(' + f.id + ',\'dismiss\')">✕</button></div>';
    }).join('');
  } else facts.innerHTML = '<div class="empty">nothing here yet — bills and deadlines you see on screen appear automatically</div>';

  const rem = document.getElementById('reminders');
  if (b.reminders.length) {
    rem.innerHTML = b.reminders.map(r =>
      '<div class="fact"><span class="pill ' + esc(r.kind) + '">' + esc(r.kind) + '</span>' +
      '<span class="title">' + esc(r.title) + (r.remaining > 1 ? ' <span class="hint">(' + r.remaining + ' scheduled)</span>' : '') +
      (r.note ? '<span class="sub"><span class="note">' + esc(r.note) + '</span></span>' : '') + '</span>' +
      '<span class="due">next ' + fmtDate(r.fire_ts) + '</span></div>').join('');
  } else rem.innerHTML = '<div class="empty">no reminders scheduled</div>';
}

let MODEL_READY = false;   // set from /api/status; gates the ✨ button

async function modelFix(id) {
  const r = await api('/api/fact', {method:'POST', body: JSON.stringify({action:'model_fix', id:id})});
  if (r && r.ok === false) { alert(r.error || 'could not run the on-device model'); return; }
  // The model answers on its own schedule; give it a moment, then refresh.
  setTimeout(loadBrain, 2500);
}

function editDue(id) {
  editingDue = id; editingNote = null;
  renderBrain();
}

async function saveDue(id) {
  const d = document.getElementById('due-date-' + id).value;
  const t = document.getElementById('due-time-' + id).value || '09:00';
  const body = {action:'due', id:id};
  if (d) body.due_ts = new Date(d + 'T' + t).getTime()/1000;
  await api('/api/fact', {method:'POST', body: JSON.stringify(body)});
  editingDue = null;
  loadBrain();
}

function editNote(id) {
  editingNote = id; editingDue = null;
  renderBrain();
  const el = document.getElementById('note-input-' + id);
  if (el) { el.focus(); el.select(); }
}

function noteKey(e, id) {
  if (e.key === 'Enter') saveNote(id);
  if (e.key === 'Escape') { editingNote = null; renderBrain(); }
}

async function saveNote(id) {
  const el = document.getElementById('note-input-' + id);
  const note = el ? el.value.trim() : '';
  await api('/api/fact', {method:'POST', body: JSON.stringify({action:'note', id:id, note:note})});
  editingNote = null;
  loadBrain();
}

async function factAction(id, action) {
  await api('/api/fact', {method:'POST', body: JSON.stringify({action:action, id:id})});
  loadBrain();
}

async function createFact() {
  const title = document.getElementById('new-title').value.trim();
  if (!title) return;
  const due = document.getElementById('new-due').value;
  const time = document.getElementById('new-time').value; // "HH:MM" or ""
  const body = {action:'create', title:title, note:document.getElementById('new-note').value.trim()};
  // Local date + chosen time (09:00 when no time picked).
  if (due) body.due_ts = new Date(due + 'T' + (time || '09:00')).getTime()/1000;
  await api('/api/fact', {method:'POST', body: JSON.stringify(body)});
  document.getElementById('new-title').value = '';
  document.getElementById('new-note').value = '';
  document.getElementById('new-time').value = '';
  loadBrain();
}

// ---------- History / revision calendar ----------
let histMode = 'week';          // 'week' | 'month' | '3mo'
let histAnchor = new Date();    // any date inside the displayed period
let histByDay = {};             // 'yyyy-mm-dd' -> [items]
let histSelDay = null;
const HIST_COLORS = {watched:'#22d3ee', done:'#4fd1a5', missed:'#ff6b6b', due:'#ffb454', upcoming:'#7c6cff', closed:'#5b6274'};
const HIST_LABELS = {watched:'watched', done:'revised', missed:'missed', due:'due today', upcoming:'upcoming', closed:'closed early'};
const MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const DOW = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

function histColor(it) { return HIST_COLORS[it.status] || '#5b6274'; }
function histIcon(it) {
  if (it.type === 'watched') return '🎬';
  if (it.type === 'revision') return '🔁';
  return it.kind === 'bill' ? '💸' : (it.kind === 'deadline' ? '⏰' : '📝');
}
// 'done' reads as 'revised' only for revision steps; tasks read as 'done'.
function histStatusLabel(it) {
  if (it.status === 'done' && it.type !== 'revision') return 'done';
  return HIST_LABELS[it.status] || it.status;
}

function setHistMode(m) {
  histMode = m; histSelDay = null;
  document.querySelectorAll('#hist-seg button').forEach(b => b.classList.toggle('on', b.dataset.m === m));
  loadHistory();
}
function histShift(n) {
  const a = new Date(histAnchor);
  if (histMode === 'week') a.setDate(a.getDate() + 7 * n);
  else if (histMode === 'month') a.setMonth(a.getMonth() + n, 1);
  else a.setMonth(a.getMonth() + 3 * n, 1);
  histAnchor = a; histSelDay = null;
  loadHistory();
}
function histToday() { histAnchor = new Date(); histSelDay = null; loadHistory(); }

function startOfWeek(d) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - (x.getDay() + 6) % 7); // Monday start
  return x;
}
function histRange() {
  const a = histAnchor;
  if (histMode === 'week') { const s = startOfWeek(a); return [s, new Date(s.getFullYear(), s.getMonth(), s.getDate() + 7)]; }
  if (histMode === 'month') return [new Date(a.getFullYear(), a.getMonth(), 1), new Date(a.getFullYear(), a.getMonth() + 1, 1)];
  return [new Date(a.getFullYear(), a.getMonth() - 2, 1), new Date(a.getFullYear(), a.getMonth() + 1, 1)];
}
function fmtMD(d) { return d.toLocaleDateString(undefined, {month:'short', day:'numeric'}); }
function histLabel(s, e) {
  const last = new Date(e.getTime() - 86400000);
  if (histMode === 'week') return fmtMD(s) + ' – ' + fmtMD(last) + ', ' + last.getFullYear();
  if (histMode === 'month') return MONTH_NAMES[s.getMonth()] + ' ' + s.getFullYear();
  return MONTH_NAMES[s.getMonth()] + ' – ' + MONTH_NAMES[last.getMonth()] + ' ' + last.getFullYear();
}

async function loadHistory() {
  const [s, e] = histRange();
  document.getElementById('hist-label').textContent = histLabel(s, e);
  const prevStart = new Date(s.getTime() - (e.getTime() - s.getTime()));
  let cur, prev;
  try {
    cur = await api('/api/history?from=' + s.getTime()/1000 + '&to=' + e.getTime()/1000);
    prev = await api('/api/history?from=' + prevStart.getTime()/1000 + '&to=' + s.getTime()/1000);
  } catch (err) { console.error(err); return; }
  histByDay = {};
  (cur.items || []).forEach(it => {
    const k = todayStr(new Date(it.ts * 1000));
    (histByDay[k] = histByDay[k] || []).push(it);
  });
  renderHistCards(histStats(cur.items || []), histStats(prev.items || []));
  document.getElementById('hist-cmp-box').classList.toggle('hidden', histMode !== '3mo');
  renderClosed();
  redrawCal(s);
  if (histMode === '3mo') renderCmp(s);
  if (histSelDay) showDay(histSelDay);
  else document.getElementById('hist-day-box').classList.add('hidden');
}

function redrawCal(s) {
  s = s || histRange()[0];
  const cal = document.getElementById('hist-cal');
  if (histMode === 'week') cal.innerHTML = weekHTML(s);
  else if (histMode === 'month') cal.innerHTML = monthHTML(s.getFullYear(), s.getMonth(), false);
  else cal.innerHTML = threeMoHTML(s);
}

// A step that was closed early never happened and never will — it is there to
// explain a gap, not to fill the calendar. The days keep only what you actually
// did or still owe; the closed ones wait in the dropdown below.
function dayItems(k) { return (histByDay[k] || []).filter(it => it.status !== 'closed'); }

function renderClosed() {
  const all = [];
  Object.keys(histByDay).forEach(k => histByDay[k].forEach(it => {
    if (it.status === 'closed') all.push(it);
  }));
  all.sort((a, b) => a.ts - b.ts);
  const box = document.getElementById('hist-closed');
  box.classList.toggle('hidden', all.length === 0);
  if (!all.length) { box.open = false; return; }
  document.getElementById('hist-closed-n').textContent = '(' + all.length + ')';
  document.getElementById('hist-closed-items').innerHTML = all.map(it => {
    const k = todayStr(new Date(it.ts * 1000));
    return '<div class="fact" style="cursor:pointer" onclick="showDay(\'' + k + '\')">' +
      '<span class="hint" style="min-width:130px">' + esc(k) + ' ' + fmtTime(it.ts) + '</span>' +
      '<span class="title">' + histIcon(it) + ' ' + linkTitle(it.title, it.url) +
      ((it.type === 'revision' && it.interval_idx >= 0)
        ? ' <span class="hint">revision ' + (it.interval_idx + 1) + ' of 5</span>' : '') +
      (it.note ? '<span class="sub"><span class="note">' + esc(it.note) + '</span></span>' : '') +
      '</span></div>';
  }).join('');
}

function histStats(items) {
  const st = {watched:0, done:0, missed:0, due:0, upcoming:0};
  items.forEach(it => {
    if (it.type === 'watched') st.watched++;
    else if (it.type === 'revision' && st[it.status] !== undefined) st[it.status]++;
  });
  st.rate = (st.done + st.missed) > 0 ? Math.round(100 * st.done / (st.done + st.missed)) : null;
  return st;
}
function deltaN(a, b) { const d = a - b; return (d >= 0 ? '+' : '') + d; }
function renderHistCards(c, p) {
  document.getElementById('h-watched').textContent = c.watched;
  document.getElementById('h-watched-d').textContent = deltaN(c.watched, p.watched) + ' vs previous period';
  document.getElementById('h-done').textContent = c.done;
  document.getElementById('h-done-d').textContent = deltaN(c.done, p.done) + ' vs previous period';
  document.getElementById('h-missed').textContent = c.missed;
  document.getElementById('h-missed-d').textContent = deltaN(c.missed, p.missed) + ' vs previous period';
  document.getElementById('h-rate').textContent = c.rate === null ? '–' : c.rate + '%';
  document.getElementById('h-rate-d').textContent = (c.rate === null || p.rate === null)
    ? 'revisions done ÷ (done + missed)' : deltaN(c.rate, p.rate) + '% vs previous period';
}

function weekHTML(s) {
  const t = todayStr();
  let cols = '';
  for (let i = 0; i < 7; i++) {
    const d = new Date(s.getFullYear(), s.getMonth(), s.getDate() + i);
    const k = todayStr(d);
    const items = dayItems(k).slice().sort((a, b) => a.ts - b.ts);
    const chips = items.slice(0, 8).map(it =>
      '<div class="hchip"><i style="background:' + histColor(it) + '"></i><span>' + histIcon(it) + ' ' + linkTitle(it.title, it.url) + '</span></div>').join('') +
      (items.length > 8 ? '<div class="cal-more">+' + (items.length - 8) + ' more</div>' : '');
    cols += '<div class="wk-col' + (k === t ? ' today' : '') + (k === histSelDay ? ' sel' : '') + '" onclick="showDay(\'' + k + '\')">' +
      '<div class="dn">' + DOW[i] + ' ' + d.getDate() + '</div>' +
      (chips || '<div class="cal-more" style="opacity:.5">—</div>') + '</div>';
  }
  return '<div class="wk-grid">' + cols + '</div>';
}

function monthHTML(y, mo, mini) {
  const t = todayStr();
  const lead = (new Date(y, mo, 1).getDay() + 6) % 7;
  const nDays = new Date(y, mo + 1, 0).getDate();
  const head = DOW.map(w => '<div>' + (mini ? w[0] : w) + '</div>').join('');
  let cells = '';
  for (let i = 0; i < lead; i++) cells += mini ? '<div class="mini-cell blank"></div>' : '<div class="cal-cell blank"></div>';
  for (let d = 1; d <= nDays; d++) {
    const k = todayStr(new Date(y, mo, d));
    const items = dayItems(k);
    if (mini) {
      let bg = '';
      if (items.some(i => i.status === 'missed')) bg = HIST_COLORS.missed;
      else if (items.some(i => i.status === 'done')) bg = HIST_COLORS.done;
      else if (items.some(i => i.status === 'due')) bg = HIST_COLORS.due;
      else if (items.some(i => i.type === 'watched')) bg = HIST_COLORS.watched;
      else if (items.some(i => i.status === 'upcoming')) bg = HIST_COLORS.upcoming;
      cells += '<div class="mini-cell' + (k === t ? ' today' : '') + '" title="' + k + (items.length ? ' · ' + items.length + ' item' + (items.length > 1 ? 's' : '') : '') + '"' +
        (bg ? ' style="background:' + bg + '26;box-shadow:inset 0 -2px 0 ' + bg + '"' : '') +
        ' onclick="showDay(\'' + k + '\')">' + d + '</div>';
    } else {
      const dots = items.slice(0, 10).map(it => '<i style="background:' + histColor(it) + '" title="' + esc(histStatusLabel(it)) + '"></i>').join('');
      cells += '<div class="cal-cell' + (k === t ? ' today' : '') + (k === histSelDay ? ' sel' : '') + '" onclick="showDay(\'' + k + '\')">' +
        '<div class="dn">' + d + '</div><div class="cal-dots">' + dots + '</div>' +
        (items.length > 10 ? '<div class="cal-more">+' + (items.length - 10) + '</div>' : '') + '</div>';
    }
  }
  return '<div class="cal-head">' + head + '</div><div class="' + (mini ? 'mini-grid' : 'cal-grid') + '">' + cells + '</div>';
}

function threeMoHTML(s) {
  let out = '<div class="mini3">';
  for (let i = 0; i < 3; i++) {
    const d = new Date(s.getFullYear(), s.getMonth() + i, 1);
    out += '<div class="mini-cal"><div class="mc-title">' + MONTH_NAMES[d.getMonth()] + ' ' + d.getFullYear() + '</div>' +
      monthHTML(d.getFullYear(), d.getMonth(), true) + '</div>';
  }
  return out + '</div>';
}

function renderCmp(s) {
  const stats = [];
  for (let i = 0; i < 3; i++) {
    const d = new Date(s.getFullYear(), s.getMonth() + i, 1);
    const from = d.getTime(), to = new Date(d.getFullYear(), d.getMonth() + 1, 1).getTime();
    const items = [];
    Object.keys(histByDay).forEach(k => histByDay[k].forEach(it => {
      const t = it.ts * 1000;
      if (t >= from && t < to) items.push(it);
    }));
    const st = histStats(items);
    st.name = MONTH_NAMES[d.getMonth()] + ' ' + d.getFullYear();
    stats.push(st);
  }
  const rows = [
    ['Videos watched', stats.map(x => x.watched)],
    ['Revisions done', stats.map(x => x.done)],
    ['Revisions missed', stats.map(x => x.missed)],
    ['Still scheduled', stats.map(x => x.upcoming + x.due)],
    ['Completion rate', stats.map(x => x.rate === null ? '–' : x.rate + '%')]
  ];
  let html = '<table class="rules"><thead><tr><th></th>' + stats.map(x => '<th>' + x.name + '</th>').join('') + '</tr></thead><tbody>';
  rows.forEach(r => {
    html += '<tr><td><b>' + r[0] + '</b></td>' + r[1].map((v, i) => {
      let dl = '';
      if (i > 0 && typeof v === 'number' && typeof r[1][i-1] === 'number' && v !== r[1][i-1]) {
        const dd = v - r[1][i-1];
        dl = ' <span class="hint">(' + (dd > 0 ? '+' : '') + dd + ')</span>';
      }
      return '<td>' + v + dl + '</td>';
    }).join('') + '</tr>';
  });
  html += '</tbody></table>' + cmpBars(stats);
  document.getElementById('hist-cmp').innerHTML = html;
}

function cmpBars(stats) {
  const W = 600, H = 190, pL = 30, pR = 10, pT = 14, pB = 26;
  const maxV = Math.max(1, ...stats.map(s => Math.max(s.watched, s.done, s.missed)));
  const series = [['watched', HIST_COLORS.watched, 'Watched'], ['done', HIST_COLORS.done, 'Revised'], ['missed', HIST_COLORS.missed, 'Missed']];
  const band = (W - pL - pR) / stats.length;
  const bw = Math.min(34, (band - 40) / 3);
  let out = '';
  for (let k = 0; k <= 4; k++) {
    const v = maxV * k / 4, y = pT + (H - pT - pB) * (1 - k / 4);
    out += '<line x1="' + pL + '" y1="' + y + '" x2="' + (W - pR) + '" y2="' + y + '" stroke="#262a36"/>' +
           '<text x="' + (pL - 6) + '" y="' + (y + 3) + '" fill="#8a90a3" font-size="9" text-anchor="end">' + Math.round(v) + '</text>';
  }
  stats.forEach((s, i) => {
    const cx = pL + band * i + band / 2;
    series.forEach((sr, j) => {
      const v = s[sr[0]], h = (H - pT - pB) * v / maxV;
      const x = cx + (j - 1) * (bw + 4) - bw / 2;
      out += '<rect x="' + x.toFixed(1) + '" y="' + (H - pB - h).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + h.toFixed(1) + '" rx="2" fill="' + sr[1] + '"/>' +
        (v ? '<text x="' + (x + bw / 2).toFixed(1) + '" y="' + (H - pB - h - 4).toFixed(1) + '" fill="#8a90a3" font-size="9" text-anchor="middle">' + v + '</text>' : '');
    });
    out += '<text x="' + cx.toFixed(1) + '" y="' + (H - 8) + '" fill="#8a90a3" font-size="10" text-anchor="middle">' + s.name.split(' ')[0] + '</text>';
  });
  return '<div class="chartlegend" style="margin-top:16px">' +
    series.map(sr => '<span><i class="sw" style="background:' + sr[1] + '"></i>' + sr[2] + '</span>').join('') + '</div>' +
    '<div class="chartbox"><svg viewBox="0 0 ' + W + ' ' + H + '" width="100%">' + out + '</svg></div>';
}

function showDay(k) {
  histSelDay = k;
  const box = document.getElementById('hist-day-box');
  const items = (histByDay[k] || []).slice().sort((a, b) => a.ts - b.ts);
  const d = new Date(k + 'T00:00:00');
  document.getElementById('hist-day-title').textContent =
    d.toLocaleDateString(undefined, {weekday:'long', year:'numeric', month:'long', day:'numeric'});
  box.classList.remove('hidden');
  function rowHTML(it) {
    const revN = (it.type === 'revision' && it.interval_idx >= 0)
      ? ' <span class="hint">revision ' + (it.interval_idx + 1) + ' of 5</span>' : '';
    const wsecs = (it.type === 'watched' && it.watch_secs >= 30)
      ? ' <span class="hint">' + fmtDur(it.watch_secs) + '</span>' : '';
    let actions = '';
    if (it.type === 'revision' && (it.status === 'due' || it.status === 'missed' || it.status === 'upcoming'))
      actions += '<button class="btn small" onclick="markRevDone(' + it.reminder_id + ')">did it ✓</button>';
    if (it.status === 'upcoming' || it.status === 'due')
      actions += '<a class="btn small ghost" style="text-decoration:none" target="_blank" href="' + gcalUrl(it) + '">+ GCal</a>';
    // Your note from Brain rides along, so the calendar says which lecture
    // an entry actually was.
    const sub = it.note ? '<span class="sub"><span class="note">' + esc(it.note) + '</span></span>' : '';
    return '<div class="fact"><span class="pill" style="color:' + histColor(it) + '">' + histStatusLabel(it) + '</span>' +
      '<span class="hint" style="min-width:70px">' + fmtTime(it.ts) + '</span>' +
      '<span class="title">' + histIcon(it) + ' ' + linkTitle(it.title, it.url) + revN + wsecs + sub + '</span>' + actions + '</div>';
  }
  const live = items.filter(it => it.status !== 'closed');
  const closed = items.filter(it => it.status === 'closed');
  let html = live.length ? live.map(rowHTML).join('') : '<div class="empty">nothing on this day</div>';
  if (closed.length) {
    html += '<details class="drop" style="margin-top:12px"><summary>' + closed.length + ' closed early' +
      ' — scheduled for this day, then dropped when you finished or dismissed the item</summary>' +
      '<div class="dropbody">' + closed.map(rowHTML).join('') + '</div></details>';
  }
  document.getElementById('hist-day-items').innerHTML = html;
  if (histMode !== '3mo') redrawCal(); // refresh the selection highlight
}

async function markRevDone(id) {
  await api('/api/fact', {method:'POST', body: JSON.stringify({action:'reminder_done', id:id})});
  loadHistory();
}

function gcalUrl(it) {
  const p = d => d.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
  const st = new Date(it.ts * 1000), en = new Date(it.ts * 1000 + 1800000);
  const text = it.type === 'revision' ? 'Revise: ' + it.title : it.title;
  const details = 'Scheduled by MitthuAI' + (it.url ? '\n' + it.url : '');
  return 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=' + encodeURIComponent(text) +
    '&dates=' + p(st) + '/' + p(en) + '&details=' + encodeURIComponent(details);
}

function exportICS() { location.href = '/api/calendar.ics?token=' + encodeURIComponent(TOKEN); }

async function loadSettings() {
  const s = await api('/api/status');
  document.getElementById('set-paused').checked = s.paused;
  document.getElementById('set-text').checked = s.capture_text;
  document.getElementById('set-urls').checked = s.capture_urls;
  document.getElementById('set-revise').checked = s.auto_revise;
  document.getElementById('set-login').checked = s.launch_at_login;
  document.getElementById('set-turbo').checked = s.turbo_embeddings;
  document.getElementById('emb-model').textContent = s.embeddings_model || '–';
  document.getElementById('openai-status').textContent = s.openai_key_set ? 'A key is saved in Keychain.' : 'No key saved.';
  document.getElementById('set-excluded').value = s.excluded_apps.join('\n');
  document.getElementById('set-video').value = (s.video_sources || []).join('\n');
  document.getElementById('set-dateorder').value = s.date_order || 'auto';
  document.getElementById('set-model').checked = !!s.model_assist;
  document.getElementById('model-status').textContent = s.model_status || '–';
  MODEL_READY = !!s.model_assist && s.model_status === 'ready';
  document.getElementById('detection-log').textContent =
    (s.detection_log && s.detection_log.length) ? s.detection_log.slice().reverse().join('\n')
                                                : 'nothing decided yet — play something for a minute';
  document.getElementById('q-mode').textContent = s.embeddings ? 'semantic + keyword search' : 'keyword search only';
  const mcp = 'claude mcp add --transport http mitthuai http://localhost:' + s.port + '/mcp --header "Authorization: Bearer ' + s.token + '"';
  document.getElementById('mcp-code').textContent = mcp;
  document.getElementById('mcp-desktop').textContent = JSON.stringify({mcpServers:{mitthuai:{command:'npx',args:['mcp-remote','http://localhost:' + s.port + '/mcp','--header','Authorization: Bearer ' + s.token]}}});
  const paired = s.account_paired;
  document.getElementById('acct-status').textContent = paired ? 'connected — Claude.ai web can reach this Mac' : 'not connected';
  document.getElementById('acct-btn').textContent = paired ? 'Disconnect account' : 'Connect account';
  const c = s.counts;
  document.getElementById('data-counts').textContent =
    c.events + ' events · ' + c.chunks + ' text chunks (' + c.embedded + ' embedded) · ' +
    c.facts + ' facts · ' + (c.db_bytes/1048576).toFixed(1) + ' MB on disk';
  updateDot(s.paused);
}

async function saveSettings() {
  const body = {
    paused: document.getElementById('set-paused').checked,
    capture_text: document.getElementById('set-text').checked,
    capture_urls: document.getElementById('set-urls').checked,
    auto_revise: document.getElementById('set-revise').checked,
    launch_at_login: document.getElementById('set-login').checked,
    turbo_embeddings: document.getElementById('set-turbo').checked,
    excluded_apps: document.getElementById('set-excluded').value.split('\n').map(x => x.trim()).filter(Boolean),
    video_sources: document.getElementById('set-video').value.split('\n').map(x => x.trim()).filter(Boolean),
    date_order: document.getElementById('set-dateorder').value,
    model_assist: document.getElementById('set-model').checked
  };
  // Only send the key when the user typed one (never auto-clear on toggles).
  const key = document.getElementById('set-openai').value.trim();
  if (key) body.openai_api_key = key;
  await api('/api/settings', {method:'POST', body: JSON.stringify(body)});
  document.getElementById('set-openai').value = '';
  updateDot(body.paused);
  loadSettings();
}

async function toggleAccount() {
  const s = await api('/api/status');
  if (s.account_paired) {
    if (!confirm('Disconnect this Mac from your mitthuai account? Claude.ai web will no longer reach it.')) return;
    await api('/api/account/disconnect', {method:'POST'});
  } else {
    await api('/api/account/connect', {method:'POST'});
    alert('Opening mitthuai.com to sign in. After you finish, this Mac connects automatically within a minute.');
  }
  setTimeout(loadSettings, 1500);
}

async function purge() {
  const f = document.getElementById('purge-from').value, t = document.getElementById('purge-to').value;
  if (!f || !t) { alert('Pick both dates.'); return; }
  if (!confirm('Permanently delete all captured data from ' + f + ' to ' + t + '?')) return;
  await api('/api/purge', {method:'POST', body: JSON.stringify({from: new Date(f).getTime()/1000, to: new Date(t).getTime()/1000 + 86400})});
  loadSettings();
}

function updateDot(paused) {
  document.getElementById('dot').className = 'dot' + (paused ? ' paused' : '');
  document.getElementById('statustext').textContent = paused ? 'paused' : 'tracking';
}

loadToday();
api('/api/rules').then(r => { if (r.categories && r.categories.length) CATEGORIES = r.categories; }).catch(()=>{});
api('/api/status').then(s => {
  updateDot(s.paused);
  MODEL_READY = !!s.model_assist && s.model_status === 'ready';
}).catch(()=>{});
setInterval(() => { if (!document.getElementById('view-today').classList.contains('hidden')) loadToday(); }, 60000);
</script>
</body>
</html>
"""#
}
