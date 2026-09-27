// Marcello's private dashboard: one static page, no framework, no CDN. It
// asks for the password once per tab (kept in sessionStorage) and reads
// everything from /api/summary.

export const dashboardHTML = /* html */ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Otto · Dashboard</title>
<style>
  :root {
    --bg: #0b0b0f; --panel: #15151c; --line: rgba(255,255,255,.08);
    --text: #f2f1f5; --dim: rgba(242,241,245,.55); --faint: rgba(242,241,245,.35);
    --violet: #9d8bff; --green: #7fe3a8; --amber: #ffc98a;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
         font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 1080px; margin: 0 auto; padding: 32px 20px 64px; }
  header { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
  h1 { font-size: 22px; font-weight: 600; margin: 0; letter-spacing: -.01em; }
  h2 { font-size: 13px; font-weight: 600; color: var(--dim); margin: 0 0 12px;
       text-transform: uppercase; letter-spacing: .04em; }
  select, input, button { font: inherit; color: var(--text); background: var(--panel);
       border: 1px solid var(--line); border-radius: 8px; padding: 7px 10px; }
  button { background: var(--text); color: #111; border: 0; font-weight: 600; cursor: pointer; }
  .grid { display: grid; gap: 12px; margin-top: 20px; }
  .kpis { grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); }
  .two { grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
  .kpi .v { font-size: 28px; font-weight: 600; letter-spacing: -.02em; }
  .kpi .l { color: var(--dim); font-size: 12.5px; }
  .bars { display: flex; align-items: flex-end; gap: 3px; height: 120px; }
  .bars div { flex: 1; background: var(--violet); border-radius: 3px 3px 0 0; min-height: 2px; position: relative; }
  .bars div:hover::after { content: attr(data-tip); position: absolute; bottom: 100%; left: 50%;
       transform: translateX(-50%); background: #000; padding: 3px 6px; border-radius: 5px;
       font-size: 11px; white-space: nowrap; margin-bottom: 4px; }
  .axis { display: flex; justify-content: space-between; color: var(--faint); font-size: 11px; margin-top: 6px; }
  .rows div { display: grid; grid-template-columns: 140px 1fr 48px; gap: 10px; align-items: center;
       padding: 4px 0; font-size: 13px; }
  .rows .track { background: rgba(255,255,255,.06); border-radius: 4px; height: 8px; overflow: hidden; }
  .rows .fill { height: 100%; background: var(--green); border-radius: 4px; }
  .rows .n { text-align: right; color: var(--dim); font-variant-numeric: tabular-nums; }
  .empty { color: var(--faint); font-size: 13px; }
  .note { color: var(--faint); font-size: 12px; margin-top: 28px; }
  #gate { max-width: 320px; margin: 18vh auto; display: flex; flex-direction: column; gap: 10px; }
  #gate p { color: var(--dim); margin: 0 0 6px; }
  #error { color: #ff9ec7; font-size: 13px; min-height: 18px; }
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
    <h1>Otto</h1>
    <select id="range">
      <option value="7">Last 7 days</option>
      <option value="30" selected>Last 30 days</option>
      <option value="90">Last 90 days</option>
      <option value="365">Last year</option>
    </select>
  </header>
  <section class="grid kpis" id="kpis"></section>
  <section class="grid two">
    <div class="card"><h2>Active installs per day</h2><div id="daily"></div></div>
    <div class="card"><h2>New installs per day</h2><div id="new"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Onboarding funnel</h2><div id="funnel" class="rows"></div></div>
    <div class="card"><h2>Display style chosen</h2><div id="styles" class="rows"></div>
      <h2 style="margin-top:18px">Permissions</h2><div id="permissions" class="rows"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>How the notch is opened</h2><div id="triggers" class="rows"></div></div>
    <div class="card"><h2>Usage (events)</h2><div id="usage" class="rows"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Feedback sent</h2><div id="feedback" class="rows"></div></div>
    <div class="card"><h2>App versions (active)</h2><div id="versions" class="rows"></div></div>
  </section>
  <p class="note">Only installs that opted in to anonymous usage data. No user content is ever collected.</p>
</main>
<script>
const $ = (id) => document.getElementById(id);
const store = { get: () => { try { return sessionStorage.getItem("otto.pw") } catch { return null } },
                set: (v) => { try { sessionStorage.setItem("otto.pw", v) } catch {} } };
const STEPS = ["welcome", "discover", "style", "shortcut", "permissions", "done"];

async function load(password) {
  const res = await fetch("/api/summary?days=" + $("range").value,
                          { headers: { authorization: "Bearer " + password } });
  if (res.status === 401) throw new Error("Wrong password");
  if (!res.ok) throw new Error("Server error " + res.status);
  return res.json();
}

function kpis(t) {
  const items = [["Active today", t.active_today], ["Active 7 days", t.active_7d], ["Active 30 days", t.active_30d],
                 ["All installs", t.installs], ["New in range", t.new_in_range],
                 ["Onboarding done", t.onboarding_completed], ["Feedback sent", t.feedback_sent]];
  $("kpis").innerHTML = items.map(([l, v]) =>
    '<div class="card kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>').join("");
}

function series(el, since, days, rows, key) {
  const map = new Map(rows.map((r) => [r.day, r[key]]));
  const out = [];
  const start = new Date(since + "T00:00:00Z");
  for (let i = 0; i < days; i++) {
    const d = new Date(start.getTime() + i * 86400000).toISOString().slice(0, 10);
    out.push([d, map.get(d) || 0]);
  }
  const max = Math.max(1, ...out.map((o) => o[1]));
  $(el).innerHTML = '<div class="bars">' + out.map(([d, v]) =>
    '<div style="height:' + (v / max * 100) + '%" data-tip="' + d + ': ' + v + '"></div>').join("") +
    '</div><div class="axis"><span>' + out[0][0] + '</span><span>' + out[out.length - 1][0] + '</span></div>';
}

function rows(el, list, order) {
  if (order) list = order.map((k) => list.find((r) => r.key === k) || { key: k, n: 0 });
  if (!list.length) { $(el).innerHTML = '<p class="empty">No data yet</p>'; return; }
  const max = Math.max(1, ...list.map((r) => r.n));
  $(el).innerHTML = list.map((r) =>
    '<div><span>' + (r.key ?? "—") + '</span><span class="track"><span class="fill" style="display:block;width:' +
    (r.n / max * 100) + '%"></span></span><span class="n">' + r.n + '</span></div>').join("");
}

async function render(password) {
  const data = await load(password);
  kpis(data.totals);
  const active = data.archived.map((r) => ({ day: r.day, active: r.value })).concat(data.daily);
  series("daily", data.since, data.days, active, "active");
  series("new", data.since, data.days, data.new_daily, "n");
  const funnel = data.funnel.concat([{ key: "done", n: data.totals.onboarding_completed }]);
  rows("funnel", funnel, STEPS);
  rows("styles", data.styles); rows("permissions", data.permissions);
  rows("triggers", data.triggers); rows("usage", data.usage);
  rows("feedback", data.feedback); rows("versions", data.versions);
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
