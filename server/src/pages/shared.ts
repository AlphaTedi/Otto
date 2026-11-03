// What the three dashboard pages share: the look, the password gate, the
// header with its tabs and period, and small helpers for charts and lists.
// Static pages, no framework, no CDN: everything comes from /api/*.
//
// The page scripts live inside template literals, so they never use
// backticks, "${" or backslashes: they are written with plain string joins.

export const STYLE = `
  :root {
    --bg: #0b0b0f; --panel: #15151c; --line: rgba(255,255,255,.08);
    --text: #f2f1f5; --dim: rgba(242,241,245,.62); --faint: rgba(242,241,245,.4);
    --violet: #9d8bff; --green: #7fe3a8; --amber: #ffc98a; --pink: #ff9ec7; --blue: #8ccaff;
  }
  * { box-sizing: border-box; }
  /* display:flex on #gate would otherwise beat the hidden attribute. */
  [hidden] { display: none !important; }
  body { margin: 0; background: var(--bg); color: var(--text);
         font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 1180px; margin: 0 auto; padding: 28px 20px 64px; }
  header.top { display: flex; align-items: center; justify-content: space-between; gap: 12px 16px; flex-wrap: wrap; }
  .head-left { display: flex; align-items: baseline; gap: 18px; flex-wrap: wrap; }
  h1 { font-size: 22px; font-weight: 600; margin: 0; letter-spacing: -.01em; }
  .tabs { display: flex; gap: 4px; }
  .tabs a { color: var(--dim); text-decoration: none; font-size: 13px; font-weight: 600;
       padding: 5px 10px; border-radius: 8px; border: 1px solid transparent; }
  .tabs a:hover { color: var(--text); }
  .tabs a[aria-current="page"] { color: var(--text); background: var(--panel); border-color: var(--line); }
  .controls { display: flex; align-items: center; gap: 10px; }
  .updated { color: var(--faint); font-size: 12px; }
  h2 { font-size: 13px; font-weight: 600; color: var(--dim); margin: 0 0 12px;
       text-transform: uppercase; letter-spacing: .04em; }
  .sub { color: var(--faint); font-size: 12.5px; margin: -6px 0 12px; }
  .lede { color: var(--dim); font-size: 16px; margin: 20px 0 0; max-width: 60rem; }
  .lede b { color: var(--text); font-weight: 600; font-variant-numeric: tabular-nums; }
  .banner { background: rgba(255,158,199,.1); border: 1px solid rgba(255,158,199,.3); color: var(--pink);
       border-radius: 10px; padding: 10px 14px; margin: 16px 0 0; }
  select, input, button { font: inherit; color: var(--text); background: var(--panel);
       border: 1px solid var(--line); border-radius: 8px; padding: 7px 10px; }
  button { background: var(--text); color: #111; border: 0; font-weight: 600; cursor: pointer; }
  .grid { display: grid; gap: 12px; margin-top: 16px; }
  .grid > .card { min-width: 0; }
  .kpis { grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); margin-top: 20px; }
  .two { grid-template-columns: repeat(auto-fit, minmax(min(100%, 420px), 1fr)); }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
  .kpi .v { font-size: 28px; font-weight: 600; letter-spacing: -.02em; font-variant-numeric: tabular-nums; }
  .kpi .l { color: var(--dim); font-size: 12.5px; }
  .kpi .d { color: var(--faint); font-size: 12px; margin-top: 4px; font-variant-numeric: tabular-nums; }
  .kpi.warn { border-color: rgba(255,201,138,.35); } .kpi.warn .v { color: var(--amber); }
  .kpi.bad { border-color: rgba(255,158,199,.35); } .kpi.bad .v { color: var(--pink); }
  .up { color: var(--green); } .down { color: var(--pink); }

  .chart { position: relative; }
  .chart svg { display: block; overflow: visible; touch-action: pan-y; }
  .chart text { fill: var(--faint); font-size: 11px; font-variant-numeric: tabular-nums; }
  .chart .grid-line { stroke: rgba(255,255,255,.06); }
  .chart .axis-line { stroke: rgba(255,255,255,.16); }
  .legend { display: flex; gap: 14px; flex-wrap: wrap; font-size: 12px; color: var(--dim); margin: -4px 0 8px; }
  .legend i, .tip i { display: inline-block; width: 9px; height: 9px; border-radius: 2px; margin-right: 6px; }
  .tip { position: absolute; pointer-events: none; background: #050507; border: 1px solid var(--line);
       border-radius: 8px; padding: 6px 9px; font-size: 12px; white-space: nowrap; z-index: 2;
       font-variant-numeric: tabular-nums; }
  .tip .t { color: var(--faint); margin-bottom: 2px; }

  .rows > div { display: grid; grid-template-columns: minmax(90px, 160px) 1fr minmax(64px, auto); gap: 10px; align-items: center;
       padding: 4px 0; font-size: 13px; }
  .rows .k { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .rows .track { background: rgba(255,255,255,.06); border-radius: 4px; height: 8px; overflow: hidden; }
  .rows .fill { display: block; height: 100%; background: var(--green); border-radius: 4px; }
  .rows .n { text-align: right; color: var(--dim); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .rows .n small { color: var(--faint); font-size: 11px; }

  .checks { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
  .checks li { display: grid; grid-template-columns: 10px 1fr; gap: 10px; align-items: start; }
  .checks .dot { width: 8px; height: 8px; border-radius: 50%; margin-top: 6px; background: var(--faint); }
  .checks .ok .dot { background: var(--green); } .checks .warn .dot { background: var(--amber); }
  .checks .bad .dot { background: var(--pink); } .checks .live .dot { background: var(--blue); }
  .checks .what { font-weight: 600; } .checks .why { color: var(--faint); font-size: 12.5px; margin-top: 2px; }

  .pill { display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: 12px; font-weight: 600; white-space: nowrap; }
  .pill.ok { background: rgba(127,227,168,.13); color: var(--green); }
  .pill.warn { background: rgba(255,201,138,.13); color: var(--amber); }
  .pill.bad { background: rgba(255,158,199,.13); color: var(--pink); }
  .pill.live { background: rgba(140,202,255,.13); color: var(--blue); }
  .pill.dim { background: rgba(255,255,255,.06); color: var(--dim); }

  .table { overflow: auto; max-height: 560px; }
  .table.short { max-height: 420px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; font-variant-numeric: tabular-nums; }
  th, td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; vertical-align: top; }
  th { position: sticky; top: 0; background: var(--panel); color: var(--dim); font-weight: 600; font-size: 12px; z-index: 1; }
  td.num, th.num { text-align: right; }
  td.muted { color: var(--faint); }
  tr.row { cursor: pointer; }
  tr.row:hover td { background: rgba(255,255,255,.03); }
  tr.row.open td { background: rgba(157,139,255,.08); }
  tr.detail td { white-space: normal; background: rgba(0,0,0,.25); padding: 12px 14px 16px; }
  .mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 12px; }

  .timeline .meta { color: var(--dim); font-size: 12.5px; margin-bottom: 8px; }
  .timeline .meta b { color: var(--text); font-weight: 600; }
  .timeline .day { color: var(--dim); font-weight: 600; font-size: 12px; margin: 12px 0 4px; }
  .timeline .ev { display: grid; grid-template-columns: 64px minmax(150px, 220px) 1fr; gap: 10px; font-size: 12.5px; padding: 2px 0; }
  .timeline .tm { color: var(--faint); font-variant-numeric: tabular-nums; }
  .timeline .props { color: var(--faint); }
  .timeline .ob .what { color: var(--violet); }
  .timeline .done .what { color: var(--green); }
  .timeline .err .what { color: var(--pink); }

  .empty { color: var(--faint); font-size: 13px; margin: 0; }
  .note { color: var(--faint); font-size: 12px; margin-top: 28px; max-width: 60rem; }
  #gate { max-width: 320px; margin: 18vh auto; display: flex; flex-direction: column; gap: 10px; }
  #gate p { color: var(--dim); margin: 0 0 6px; }
  #error { color: var(--pink); font-size: 13px; min-height: 18px; }
  @media (max-width: 600px) {
    main { padding: 20px 14px 48px; }
    .rows > div { grid-template-columns: minmax(80px, 120px) 1fr minmax(52px, auto); }
    .timeline .ev { grid-template-columns: 58px 1fr; }
    .timeline .ev .props { grid-column: 2; }
  }
`;

export const COMMON_JS = `
const $ = (id) => document.getElementById(id);
const PW = "otto.pw", RANGE_KEY = "otto.range";
const store = {
  get: (k) => { try { return sessionStorage.getItem(k) } catch { return null } },
  set: (k, v) => { try { sessionStorage.setItem(k, v) } catch {} },
  del: (k) => { try { sessionStorage.removeItem(k) } catch {} },
};
const RANGES = [["2h", "Last 2 hours"], ["24h", "Last 24 hours"], ["7d", "Last 7 days"], ["30d", "Last 30 days"],
                ["90d", "Last 90 days"], ["365d", "Last year"]];
const RANGE_WORDS = { "2h": "the last 2 hours", "24h": "the last 24 hours", "7d": "the last 7 days",
                      "30d": "the last 30 days", "90d": "the last 90 days", "365d": "the last year" };
const PREV_WORDS = { "2h": "the 2 hours before", "24h": "the day before", "7d": "the week before",
                     "30d": "the 30 days before", "90d": "the 90 days before", "365d": "the year before" };
let range = new URLSearchParams(location.search).get("range") || store.get(RANGE_KEY) || "24h";
if (!RANGES.some((r) => r[0] === range)) range = "24h";

const int = new Intl.NumberFormat("en");
const n = (v) => int.format(Number(v) || 0);
const pct = (v) => v === null || v === undefined || !isFinite(v) ? "—" : (v * 100).toFixed(v < 0.1 && v > 0 ? 1 : 0) + "%";
const ratio = (a, b) => b ? a / b : null;
const dtf = (o) => new Intl.DateTimeFormat("en-GB", o);
const F = { time: dtf({ hour: "2-digit", minute: "2-digit" }), secs: dtf({ hour: "2-digit", minute: "2-digit", second: "2-digit" }),
            day: dtf({ weekday: "short", day: "numeric", month: "short" }), short: dtf({ day: "numeric", month: "short" }),
            when: dtf({ weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) };
const bucketLabel = (ms, step) => step === "day" ? F.short.format(ms) : F.time.format(ms);
function bucketTitle(ms, step) {
  if (step === "day") return F.day.format(ms);
  return F.day.format(ms) + ", " + F.time.format(ms) + "–" + F.time.format(ms + (step === "min5" ? 300000 : 3600000));
}
const when = (iso) => iso ? F.when.format(new Date(iso)) : "—";
// just the time for today, the day too for earlier
const whenShort = (iso) => { if (!iso) return "—"; const t = new Date(iso); return t.toDateString() === new Date().toDateString() ? F.time.format(t) : F.short.format(t) + ", " + F.time.format(t); };
function ago(iso) {
  if (!iso) return "—";
  const s = (Date.now() - Date.parse(iso)) / 1000;
  if (s < 90) return "just now";
  if (s < 3600) return Math.round(s / 60) + " min ago";
  if (s < 86400 * 2) return Math.round(s / 3600) + " h ago";
  return Math.round(s / 86400) + " days ago";
}
function dur(ms) {
  if (ms === null || ms === undefined || !isFinite(ms)) return "—";
  const s = ms / 1000;
  if (s < 60) return Math.round(s) + " s";
  if (s < 3600) return (s / 60).toFixed(s < 600 ? 1 : 0) + " min";
  return (s / 3600).toFixed(1) + " h";
}
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}
function fillWords() { document.querySelectorAll(".rw").forEach((s) => { s.textContent = RANGE_WORDS[range]; }); }

async function api(path) {
  const res = await fetch(path + (path.indexOf("?") < 0 ? "?" : "&") + "range=" + range,
                          { headers: { authorization: "Bearer " + (store.get(PW) || "") } });
  if (res.status === 401) { const e = new Error("Wrong password"); e.auth = true; throw e; }
  if (!res.ok) throw new Error("server error " + res.status);
  return res.json();
}

// a change against the period before: signed, green when up (pink when down, unless lower is better)
function change(now, before, opts) {
  opts = opts || {};
  if (now === null || now === undefined || before === null || before === undefined) return null;
  const d = now - before;
  const good = opts.lowerIsBetter ? d < 0 : d > 0, bad = opts.lowerIsBetter ? d > 0 : d < 0;
  const wrap = el("span");
  wrap.append(el("span", good ? "up" : bad ? "down" : "",
                 (d > 0 ? "+" : "") + (opts.points ? (d * 100).toFixed(1) + " pts" : n(d))),
              document.createTextNode(" vs " + PREV_WORDS[range]));
  return wrap;
}
function kpi(label, value, note, cls) {
  const card = el("div", "card kpi" + (cls ? " " + cls : ""));
  card.append(el("div", "v", value), el("div", "l", label));
  if (note) { const d = el("div", "d"); if (typeof note === "string") d.textContent = note; else d.append(note); card.append(d); }
  return card;
}

const NS = "http://www.w3.org/2000/svg";
function svg(tag, attrs, parent) {
  const e = document.createElementNS(NS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (parent) parent.append(e);
  return e;
}
function niceTop(max) {
  if (max <= 4) return 4;
  const p = Math.pow(10, Math.floor(Math.log10(max))), m = max / p;
  return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
}
// bars per bucket, one per series side by side; hover shows the bucket's numbers
function barChart(box, buckets, step, series) {
  box.replaceChildren();
  box.classList.add("chart");
  if (series.length > 1) {
    const legend = el("div", "legend");
    series.forEach((s) => { const item = el("span"); const sw = el("i"); sw.style.background = s.color; item.append(sw, document.createTextNode(s.label)); legend.append(item); });
    box.append(legend);
  }
  const W = Math.max(280, box.clientWidth), H = 190, T = 10, B = 24;
  const max = Math.max(0, ...buckets.map((b) => Math.max(...series.map((s) => b.values[s.key] || 0))));
  const top = niceTop(max);
  const ticks = [0, top / 4, top / 2, top * 3 / 4, top].filter((t) => Number.isInteger(t));
  const root = svg("svg", { width: "100%", height: H, viewBox: "0 0 " + W + " " + H }, box);
  const probe = svg("text", {}, root);
  let L = 0;
  ticks.forEach((t) => { probe.textContent = n(t); L = Math.max(L, probe.getComputedTextLength()); });
  probe.remove();
  L = Math.ceil(L) + 10;
  const y = (v) => T + (H - T - B) * (1 - v / top);
  const slot = (W - L) / buckets.length;
  const hl = svg("rect", { x: 0, y: T, width: slot, height: H - T - B, fill: "rgba(255,255,255,.05)", visibility: "hidden" }, root);
  ticks.forEach((t) => {
    svg("line", { x1: L, x2: W, y1: y(t), y2: y(t), class: t === 0 ? "axis-line" : "grid-line" }, root);
    svg("text", { x: L - 6, y: y(t) + 4, "text-anchor": "end" }, root).textContent = n(t);
  });
  const inner = Math.min(slot * 0.78, 16 * series.length + 2);
  const bw = inner / series.length;
  buckets.forEach((b, i) => series.forEach((s, j) => {
    const v = b.values[s.key] || 0;
    if (v <= 0) return;
    svg("rect", { x: L + i * slot + (slot - inner) / 2 + j * bw, y: y(v), width: Math.max(1, bw - (series.length > 1 ? 1 : 0)),
                  height: Math.max(1, y(0) - y(v)), rx: Math.min(3, bw / 3), fill: s.color }, root);
  }));
  // dates or times along the bottom, counted back from now, never touching
  const every = Math.max(1, Math.ceil(buckets.length / Math.max(2, Math.floor((W - L) / 72))));
  let leftEdge = Infinity;
  for (let i = buckets.length - 1; i >= 0; i -= every) {
    const cx = L + i * slot + slot / 2;
    const t = svg("text", { x: cx, y: H - 6, "text-anchor": "middle" }, root);
    t.textContent = bucketLabel(buckets[i].start, step);
    const w = t.getComputedTextLength();
    const x = Math.min(W - w / 2, Math.max(L + w / 2, cx));
    if (x + w / 2 > leftEdge - 8) { t.remove(); continue; }
    t.setAttribute("x", x);
    leftEdge = x - w / 2;
  }
  const tip = el("div", "tip");
  tip.hidden = true;
  box.append(tip);
  const hide = () => { tip.hidden = true; hl.setAttribute("visibility", "hidden"); };
  root.addEventListener("pointermove", (ev) => {
    const r = root.getBoundingClientRect();
    const i = Math.floor(((ev.clientX - r.left) * (W / r.width) - L) / slot);
    if (i < 0 || i >= buckets.length) return hide();
    const b = buckets[i];
    hl.setAttribute("x", L + i * slot);
    hl.setAttribute("visibility", "visible");
    tip.replaceChildren(el("div", "t", bucketTitle(b.start, step)));
    series.forEach((s) => {
      const line = el("div"); const sw = el("i"); sw.style.background = s.color;
      line.append(sw, document.createTextNode(s.label + ": " + n(b.values[s.key])));
      tip.append(line);
    });
    tip.hidden = false;
    const bx = box.getBoundingClientRect();
    const left = Math.max(0, Math.min(ev.clientX - bx.left + 12, box.clientWidth - tip.offsetWidth));
    const above = ev.clientY - bx.top - tip.offsetHeight - 10;
    tip.style.left = left + "px";
    tip.style.top = (above < 0 ? ev.clientY - bx.top + 16 : above) + "px";
  });
  root.addEventListener("pointerleave", hide);
}
// horizontal bars, one row per key
function rows(box, list, opts) {
  opts = opts || {};
  if (!list || !list.length) { box.replaceChildren(el("p", "empty", opts.empty || "Nothing in this period")); return; }
  const max = Math.max(1, ...list.map((r) => Number(r.n) || 0));
  box.replaceChildren(...list.map((r) => {
    const row = el("div");
    const label = opts.label ? opts.label(r) : (r.key === null || r.key === undefined || r.key === "" ? "—" : String(r.key));
    const k = el("span", "k", label); k.title = label;
    const track = el("span", "track"), fill = el("span", "fill");
    fill.style.width = ((Number(r.n) || 0) / max * 100) + "%";
    if (opts.color) fill.style.background = opts.color;
    track.append(fill);
    const v = el("span", "n");
    if (opts.value) v.append(opts.value(r)); else v.textContent = n(r.n);
    row.append(k, track, v);
    return row;
  }));
}

// the gate, the period, the tabs, refreshing: each page gives load() and draw(data)
function boot(load, draw) {
  const sel = $("range");
  RANGES.forEach((r) => { const o = el("option", "", r[1]); o.value = r[0]; sel.append(o); });
  sel.value = range;
  const links = () => document.querySelectorAll(".tabs a").forEach((a) => { a.href = a.dataset.path + "?range=" + range; });
  links();
  let last = null, timer = null;
  async function run() {
    const data = await load();
    last = data;
    $("gate").hidden = true;
    $("app").hidden = false;
    $("banner").hidden = true;
    fillWords();
    draw(data);
    $("updated").textContent = "Updated " + F.time.format(Date.now());
  }
  function fail(err) {
    if (err && err.auth) { store.del(PW); $("app").hidden = true; $("gate").hidden = false; $("error").textContent = err.message; return; }
    $("app").hidden = false;
    $("banner").textContent = "Couldn't load the numbers: " + (err && err.message);
    $("banner").hidden = false;
  }
  function every() {
    clearInterval(timer);
    // the short periods follow along on their own, once a minute
    if (range === "2h" || range === "24h") timer = setInterval(() => { if (!document.hidden) run().catch(fail); }, 60000);
  }
  sel.addEventListener("change", () => {
    range = sel.value;
    store.set(RANGE_KEY, range);
    history.replaceState(null, "", location.pathname + "?range=" + range);
    links();
    run().catch(fail);
    every();
  });
  $("gate").addEventListener("submit", (e) => {
    e.preventDefault();
    store.set(PW, $("password").value);
    run().then(every).catch(fail);
  });
  let resize = null;
  window.addEventListener("resize", () => { clearTimeout(resize); resize = setTimeout(() => { if (last) draw(last); }, 150); });
  if (store.get(PW)) run().then(every).catch(fail);
  else $("gate").hidden = false;
}
`;

type Tab = "overview" | "app" | "website";

export function page(o: { title: string; tab: Tab; body: string; script: string }): string {
  const tab = (path: string, id: Tab, label: string) =>
    `<a data-path="${path}" href="${path}"${o.tab === id ? ' aria-current="page"' : ""}>${label}</a>`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Otto · ${o.title}</title>
<style>${STYLE}</style>
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
  <header class="top">
    <div class="head-left">
      <h1>Otto</h1>
      <nav class="tabs">${tab("/dashboard", "overview", "Overview")}${tab("/dashboard/app", "app", "App")}${tab("/dashboard/website", "website", "Website")}</nav>
    </div>
    <div class="controls"><span class="updated" id="updated"></span><select id="range" aria-label="Period"></select></div>
  </header>
  <p id="banner" class="banner" hidden></p>
${o.body}
</main>
<script>
${COMMON_JS}
${o.script}
</script>
</body>
</html>`;
}
