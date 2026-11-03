// The dashboard's second page: visits to ottotofive.com and downloads of the
// DMG. The site's own Worker (otto-site, repo AlphaTedi/website) counts them —
// no cookies, no IP kept, bots and link previews left out — and mirrors the
// daily totals to the D1 database otto-site-stats, bound here as SITE and only
// ever read. Same password and same look as the app page (dashboard.ts).

import { STYLE } from "./dashboard";

const TZ = "Europe/Amsterdam"; // the site counts its days in Amsterdam time
const DAY_MS = 86_400_000;

interface SiteDay { day: string; visitors: number; views: number; downloaders: number; downloads: number }

const amsterdamDay = (date = new Date()): string =>
  new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
const shift = (day: string, n: number): string =>
  new Date(Date.parse(day + "T00:00:00Z") + n * DAY_MS).toISOString().slice(0, 10);

/** The numbers behind /dashboard/website, for the last `days` days. */
export async function siteSummary(db: D1Database, days: number) {
  const today = amsterdamDay();
  const since = shift(today, -(days - 1));
  // the range, and at least the 14 days the week-on-week figures need
  const from = since < shift(today, -13) ? since : shift(today, -13);
  const rows = (await db.prepare(
    `SELECT day, visitors, views, downloaders, downloads FROM daily WHERE day >= ? ORDER BY day`
  ).bind(from).all<SiteDay>()).results;
  const all = await db.prepare(
    `SELECT MIN(day) AS first, COALESCE(SUM(visitors), 0) AS visitors, COALESCE(SUM(downloaders), 0) AS downloaders FROM daily`
  ).first<{ first: string | null; visitors: number; downloaders: number }>();

  const sum = (key: keyof SiteDay, lo: string, hi = today) =>
    rows.filter((r) => r.day >= lo && r.day <= hi).reduce((total, r) => total + Number(r[key]), 0);
  const week = shift(today, -6), lastWeek = shift(today, -13), lastWeekEnd = shift(today, -7);

  return {
    days, since, today, first: all?.first ?? null,
    daily: rows.filter((r) => r.day >= since),
    totals: {
      visitors_today: sum("visitors", today),
      visitors_7d: sum("visitors", week),
      visitors_prev_7d: sum("visitors", lastWeek, lastWeekEnd),
      downloaders_today: sum("downloaders", today),
      downloaders_7d: sum("downloaders", week),
      downloaders_prev_7d: sum("downloaders", lastWeek, lastWeekEnd),
      visitors_range: sum("visitors", since),
      views_range: sum("views", since),
      downloaders_range: sum("downloaders", since),
      downloads_range: sum("downloads", since),
      visitors_all: all?.visitors ?? 0,
      downloaders_all: all?.downloaders ?? 0,
    },
  };
}

export const websiteHTML = /* html */ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Otto · Website</title>
<style>${STYLE}
  .kpi .d { color: var(--faint); font-size: 12px; margin-top: 2px; font-variant-numeric: tabular-nums; }
  .kpi .d .up { color: var(--green); }
  .kpi .d .down { color: #ff9ec7; }
  .bars div { background: var(--violet); }
  #downloaders .bars div { background: var(--green); }
  .grid > .card { min-width: 0; }
  .table { max-height: 360px; overflow: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; font-variant-numeric: tabular-nums; }
  th, td { text-align: right; padding: 6px 8px; border-bottom: 1px solid var(--line); white-space: nowrap; }
  th:first-child, td:first-child { text-align: left; }
  th { position: sticky; top: 0; background: var(--panel); color: var(--dim); font-weight: 600; font-size: 12px; }
</style>
</head>
<body>
<form id="gate" hidden>
  <h1>Otto</h1>
  <p>Private dashboard.</p>
  <input id="password" type="password" placeholder="Password" autocomplete="current-password" autofocus>
  <button type="submit">Open</button>
  <div id="error"></div>
</form>
<main id="app" hidden>
  <header>
    <div class="head-left">
      <h1>Otto</h1>
      <nav class="tabs"><a href="/dashboard">App</a><a href="/dashboard/website" aria-current="page">Website</a></nav>
    </div>
    <select id="range">
      <option value="7">Last 7 days</option>
      <option value="30" selected>Last 30 days</option>
      <option value="90">Last 90 days</option>
      <option value="365">Last year</option>
    </select>
  </header>
  <section class="grid kpis" id="kpis"></section>
  <section class="grid two">
    <div class="card"><h2>Visitors per day</h2><div id="visitors"></div></div>
    <div class="card"><h2>People who downloaded per day</h2><div id="downloaders"></div></div>
  </section>
  <section class="grid">
    <div class="card"><h2>Every day</h2>
      <div class="table"><table>
        <thead><tr><th>Day</th><th>Visitors</th><th>Page views</th><th>People who downloaded</th><th>Downloads</th></tr></thead>
        <tbody id="days"></tbody>
      </table></div>
    </div>
  </section>
  <p class="note">ottotofive.com, counted by the site itself: no cookies, no IP addresses kept, daily totals only;
    crawlers and link previews are left out. A visitor is one person on one day, so someone who comes back the
    next day counts again. Downloads are clicks on Download, repeats included; people who downloaded count each
    person once a day. Days in Amsterdam time.</p>
</main>
<script>
const $ = (id) => document.getElementById(id);
const store = { get: () => { try { return sessionStorage.getItem("otto.pw") } catch { return null } },
                set: (v) => { try { sessionStorage.setItem("otto.pw", v) } catch {} } };
const int = new Intl.NumberFormat("en");
const pct = (v) => v === null ? "—" : (v * 100).toFixed(1) + "%";
const rate = (d, v) => v ? d / v : null;
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; };
const shift = (day, n) => new Date(Date.parse(day + "T00:00:00Z") + n * 86400000).toISOString().slice(0, 10);

async function load(password) {
  const res = await fetch("/api/site?days=" + $("range").value,
                          { headers: { authorization: "Bearer " + password } });
  if (res.status === 401) throw new Error("Wrong password");
  if (!res.ok) throw new Error("Server error " + res.status);
  return res.json();
}

// a change against the 7 days before: signed, green when up
function change(now, before, points) {
  const span = el("span");
  if (now === null || before === null) { span.textContent = "—"; return span; }
  const d = now - before;
  span.textContent = points ? (d >= 0 ? "+" : "") + (d * 100).toFixed(1) + " pts" : (d > 0 ? "+" : "") + int.format(d);
  if (d > 0) span.className = "up"; else if (d < 0) span.className = "down";
  return span;
}

function kpis(t) {
  const r7 = rate(t.downloaders_7d, t.visitors_7d), rPrev = rate(t.downloaders_prev_7d, t.visitors_prev_7d);
  const items = [
    ["Visitors today", int.format(t.visitors_today), "All time " + int.format(t.visitors_all)],
    ["Visitors · 7 days", int.format(t.visitors_7d), change(t.visitors_7d, t.visitors_prev_7d)],
    ["Downloaded · 7 days", int.format(t.downloaders_7d), change(t.downloaders_7d, t.downloaders_prev_7d)],
    ["Download rate · 7 days", pct(r7), change(r7, rPrev, true)],
    ["Visitors in range", int.format(t.visitors_range), "Page views " + int.format(t.views_range)],
    ["Downloaded in range", int.format(t.downloaders_range), "Downloads " + int.format(t.downloads_range)],
  ];
  $("kpis").replaceChildren(...items.map(([label, value, note]) => {
    const card = el("div", "card kpi");
    card.append(el("div", "v", value), el("div", "l", label));
    const d = el("div", "d");
    if (typeof note === "string") d.textContent = note;
    else { d.append(note, document.createTextNode(" vs the week before")); }
    card.append(d);
    return card;
  }));
}

function filled(data) {
  const map = new Map(data.daily.map((r) => [r.day, r]));
  const out = [];
  for (let i = 0; i < data.days; i++) {
    const day = shift(data.since, i);
    out.push(map.get(day) || { day, visitors: 0, views: 0, downloaders: 0, downloads: 0 });
  }
  return out;
}

function series(id, days, key) {
  const max = Math.max(1, ...days.map((r) => r[key]));
  const bars = el("div", "bars");
  days.forEach((r) => {
    const bar = el("div");
    bar.style.height = (r[key] / max * 100) + "%";
    bar.dataset.tip = r.day + ": " + int.format(r[key]);
    bars.append(bar);
  });
  const axis = el("div", "axis");
  axis.append(el("span", "", days[0].day), el("span", "", days[days.length - 1].day));
  $(id).replaceChildren(bars, axis);
}

function table(days, first) {
  const rows = days.filter((r) => first && r.day >= first).reverse();
  if (!rows.length) {
    const tr = el("tr"); const td = el("td", "empty", "Nothing counted yet"); td.colSpan = 5; tr.append(td);
    $("days").replaceChildren(tr); return;
  }
  $("days").replaceChildren(...rows.map((r) => {
    const tr = el("tr");
    tr.append(el("td", "", r.day), ...["visitors", "views", "downloaders", "downloads"].map((k) => el("td", "", int.format(r[k]))));
    return tr;
  }));
}

async function render(password) {
  const data = await load(password);
  const days = filled(data);
  kpis(data.totals);
  series("visitors", days, "visitors");
  series("downloaders", days, "downloaders");
  table(days, data.first);
}

async function start() {
  const saved = store.get();
  if (saved) {
    try { await render(saved); $("app").hidden = false; return; } catch {}
  }
  $("gate").hidden = false;
}

$("gate").addEventListener("submit", async (e) => {
  e.preventDefault();
  const pw = $("password").value;
  try { await render(pw); store.set(pw); $("gate").hidden = true; $("app").hidden = false; }
  catch (err) { $("error").textContent = err.message; }
});
$("range").addEventListener("change", () => render(store.get()).catch(() => {}));
start();
</script>
</body>
</html>`;
