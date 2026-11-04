// Overview: how many have Otto installed and how many use it, first; then
// downloads against installs, the checks worth a look, and the onboarding.

import { page } from "./shared";

const body = `
  <p class="lede" id="lede"></p>
  <section class="cards3 first" id="headline"></section>
  <section class="two">
    <article class="card"><h2>Installs using Otto</h2><p class="sub" id="active-sub"></p><div id="active"></div></article>
    <article class="card"><h2>Downloads and new installs</h2>
      <p class="sub">A download that never becomes an install is someone who didn't open Otto, or got stuck</p>
      <div id="dl-installs"></div></article>
  </section>
  <section class="two gap">
    <article class="card"><h2>Worth a look</h2><p class="sub Rw"></p><ul class="checks" id="checks"></ul></article>
    <article class="card"><h2>From visit to daily use</h2><p class="sub">People at each step in <span class="rw"></span></p>
      <div id="funnel" class="rows"></div></article>
  </section>
  <section class="two">
    <article class="card"><h2>Onboarding, step by step</h2>
      <p class="sub">Installs that started it in <span class="rw"></span>, and the typical time on each step</p>
      <div id="steps" class="rows"></div></article>
    <article class="card"><h2>Where installs stand</h2><p class="sub">Installs seen in <span class="rw"></span>, by their onboarding</p>
      <div id="stand" class="rows"></div></article>
  </section>
  <p class="note">The website counts people per day without cookies; the app counts installs that share anonymous
    usage data (a person with two Macs is two installs). The two can't be matched person by person, so the steps
    above are totals side by side. Up to 1.75.7, Otto reports an install only once its onboarding is finished: someone
    who stops halfway shows up only as a download without an install.</p>
`;

const script = `
const STEP_NAMES = ["welcome", "discover", "style", "shortcut", "permissions", "done"];
const stuck = (r) => r.ob_started && !r.ob_finished && !r.ob_left && Date.now() - Date.parse(r.last_event) > 30 * 60000;
const inOnboarding = (r) => r.ob_started && !r.ob_finished && !r.ob_left && !stuck(r);

async function load() {
  const results = await Promise.allSettled([api("/api/summary"), api("/api/site")]);
  if (results[0].status === "rejected") throw results[0].reason;
  return { app: results[0].value, site: results[1].status === "fulfilled" ? results[1].value : null };
}

function draw(d) {
  const app = d.app, site = d.site, t = app.totals;

  const lede = $("lede");
  lede.replaceChildren();
  const say = (text) => lede.append(document.createTextNode(text));
  const num = (v) => lede.append(el("b", "", n(v)));
  num(t.installs); say(t.installs === 1 ? " install has Otto, and " : " installs have Otto, and ");
  num(t.active); say(" used it in " + RANGE_WORDS[range] + ".");
  if (t.new) { say(" "); num(t.new); say(t.new === 1 ? " of them is new." : " of them are new."); }
  if (site) { say(" The site had "); num(site.totals.visitors); say(" visitors and "); num(site.totals.downloaders); say(" people downloaded Otto."); }

  const cards = [
    stat({ title: "Installed", sub: "Every install that ever reported", value: n(t.installs),
           change: (() => { const w = el("span"); w.append(el("span", t.new ? "up" : "", "+" + n(t.new)), document.createTextNode(" new in " + RANGE_WORDS[range])); return w; })(),
           items: [["New today", n(t.new_today)], ["7 days", n(t.new_7d)], ["30 days", n(t.new_30d)]] }),
    stat({ title: "Using Otto", sub: "Installs that opened it, " + RANGE_WORDS[range], value: n(t.active),
           change: change(t.active, app.previous.active),
           items: [["Today", n(t.active_today)], ["7 days", n(t.active_7d)], ["30 days", n(t.active_30d)]] }),
  ];
  if (site) cards.push(stat({ title: "People who downloaded", sub: "From ottotofive.com, " + RANGE_WORDS[range], value: n(site.totals.downloaders),
           change: change(site.totals.downloaders, site.previous.downloaders),
           items: [["Visitors", n(site.totals.visitors)], ["Download rate", pct(ratio(site.totals.downloaders, site.totals.visitors))]] }));
  $("headline").replaceChildren(...cards);

  $("active-sub").textContent = STEP_WORDS[app.step] + ", " + RANGE_WORDS[range];
  barChart($("active"), app.buckets, app.step, [{ key: "active", label: "Installs using Otto", color: "var(--c1)" }]);
  const combined = app.buckets.map((b, i) => ({ start: b.start,
    values: { downloaders: site && site.buckets[i] ? site.buckets[i].values.downloaders : 0, new: b.values.new } }));
  barChart($("dl-installs"), combined, app.step, site
    ? [{ key: "downloaders", label: "People who downloaded", color: "var(--c2)" }, { key: "new", label: "New installs", color: "var(--c1)" }]
    : [{ key: "new", label: "New installs", color: "var(--c1)" }]);

  // the checks
  const checks = [];
  const check = (level, what, why) => checks.push({ level, what, why });
  if (site) {
    const downloaders = site.totals.downloaders, gap = downloaders - t.new_finished;
    if (!downloaders) check("dim", "No downloads in " + RANGE_WORDS[range]);
    else if (gap > 0) check("warn", n(gap) + " of " + n(downloaders) + " people who downloaded haven't finished onboarding",
      "They may not have opened Otto yet, or they stopped during onboarding. Up to 1.75.7 Otto reports an install only once its onboarding is finished, so the two can't be told apart.");
    else check("ok", "Every download became an install that finished onboarding");
  } else check("dim", "Website numbers didn't load");
  const stopped = app.installs.filter(stuck), now = app.installs.filter(inOnboarding);
  if (stopped.length) check("bad", plural(stopped.length, "install stopped", "installs stopped") + " during onboarding",
    "Furthest step: " + stopped.map((r) => STEP_NAMES[r.ob_furthest] || "start").join(", ") + ". They're on the App page.");
  if (now.length) check("live", plural(now.length, "install is", "installs are") + " going through onboarding right now");
  const left = app.onboarding.abandoned.reduce((s, r) => s + r.n, 0);
  if (left) check("warn", plural(left, "install", "installs") + " left onboarding before the end",
    "At: " + app.onboarding.abandoned.map((r) => r.key + " (" + r.n + ")").join(", ") + ". They came back later and finished, or they wouldn't be counted.");
  if (t.errors) check("bad", plural(t.errors, "error", "errors") + " reported",
    "Most often: " + app.errors[0].key + " (" + n(app.errors[0].n) + " from " + plural(app.errors[0].installs, "install", "installs") + ")");
  else check("ok", "No errors reported");
  const denied = app.permissions.filter((p) => /denied$/.test(p.key));
  if (denied.length) check("warn", denied.map((p) => plural(p.n, "install", "installs") + " denied " + p.key.split(":")[0]).join(", "),
    "Without the calendar, meeting alerts can't work.");
  if (app.latest_version && app.versions.length > 1) {
    const behind = app.versions.filter((v) => v.key !== app.latest_version).reduce((s, v) => s + v.n, 0);
    if (behind) check("dim", n(behind) + " of " + n(behind + app.versions[0].n) + " installs in use run a version older than " + app.latest_version);
  }
  if (!app.excluded) check("dim", "Your own Macs are counted too",
    "To leave them out, put their anonymous IDs (Otto › Settings › Privacy) in EXCLUDED_INSTALLS in server/wrangler.toml.");
  $("checks").replaceChildren(...checks.map((c) => {
    const li = el("li", c.level), text = el("div");
    text.append(el("div", "what", c.what));
    if (c.why) text.append(el("div", "why", c.why));
    li.append(el("span", "dot"), text);
    return li;
  }));

  // the funnel: each step against the one before
  const steps = [];
  if (site) steps.push({ key: "Visited the site", n: site.totals.visitors }, { key: "Downloaded Otto", n: site.totals.downloaders });
  steps.push({ key: "Opened Otto", n: t.new }, { key: "Finished onboarding", n: t.new_finished },
             { key: "Used it again another day", n: t.returned });
  rows($("funnel"), steps, {
    color: "var(--c1)",
    value: (r) => {
      const i = steps.indexOf(r), w = el("span", "", n(r.n));
      if (i > 0 && steps[i - 1].n) w.append(el("small", "", "  " + pct(r.n / steps[i - 1].n)));
      return w;
    },
  });

  const reached = STEP_NAMES.map((key) => ({ key, n: (app.onboarding.steps.find((s) => s.step === key) || { n: 0 }).n }));
  rows($("steps"), app.onboarding.started ? reached : [], {
    color: "var(--c4)", empty: "Nobody started onboarding in " + RANGE_WORDS[range],
    value: (r) => { const ms = app.onboarding.step_ms[r.key]; const w = el("span", "", n(r.n)); if (ms) w.append(el("small", "", "  " + dur(ms))); return w; },
  });
  const by = (f) => app.installs.filter(f).length;
  rows($("stand"), [
    { key: "Finished onboarding", n: by((r) => r.ob_finished) },
    { key: "In onboarding now", n: now.length },
    { key: "Stopped in onboarding", n: stopped.length },
    { key: "Left onboarding", n: by((r) => r.ob_left && !r.ob_finished) },
    { key: "No onboarding on record", n: by((r) => !r.ob_started) },
  ].filter((r, i) => i < 3 || r.n), { color: "var(--c3)", empty: "No install seen in this period" });
}

boot(load, draw);
`;

export const overviewHTML = page({ title: "Overview", tab: "overview", body, script });
