// Overview: is Otto being adopted, and is anything going wrong? Website
// visitors → downloads → installs → used again, the checks worth a look, and
// downloads against installs over time.

import { page } from "./shared";

const body = `
  <p class="lede" id="lede"></p>
  <section class="grid two">
    <div class="card"><h2>From visit to daily use</h2>
      <p class="sub">People at each step in <span class="rw"></span></p>
      <div id="funnel" class="rows"></div></div>
    <div class="card"><h2>Worth a look</h2><ul class="checks" id="checks"></ul></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Downloads and new installs</h2>
      <p class="sub">A download that never turns into an install is someone who didn't open Otto or got stuck</p>
      <div id="dl-installs"></div></div>
    <div class="card"><h2>Installs using Otto</h2>
      <p class="sub">Installs that sent anything in each period</p>
      <div id="active"></div></div>
  </section>
  <section class="grid">
    <div class="card"><h2>Visitors</h2><p class="sub">People on ottotofive.com</p><div id="visitors"></div></div>
  </section>
  <p class="note">The website counts people per day without cookies; the app counts installs that share anonymous
    usage data. The two can't be matched person by person, so the steps above are totals side by side. Up to
    1.75.7, Otto reports an install only once its onboarding is finished: someone who stops halfway is visible
    only as a download without an install.</p>
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
  const visitors = site ? site.totals.visitors : null, downloaders = site ? site.totals.downloaders : null;

  const lede = $("lede");
  lede.replaceChildren();
  const add = (text, value) => { lede.append(document.createTextNode(text)); if (value !== undefined) lede.append(el("b", "", value)); };
  add("In " + RANGE_WORDS[range] + ": ");
  if (site) { add("", n(visitors)); add(" people visited the site, "); add("", n(downloaders)); add(" downloaded Otto, "); }
  add("", n(t.new_finished)); add(t.new_finished === 1 ? " new install finished onboarding, and " : " new installs finished onboarding, and ");
  add("", n(t.active)); add(t.active === 1 ? " install used Otto." : " installs used Otto.");

  // the funnel: each step against the one before
  const steps = [];
  if (site) steps.push({ key: "Visited the site", n: visitors }, { key: "Downloaded Otto", n: downloaders });
  steps.push({ key: "Opened Otto", n: t.new }, { key: "Finished onboarding", n: t.new_finished },
             { key: "Used it again another day", n: t.returned });
  rows($("funnel"), steps, {
    color: "var(--violet)",
    value: (r) => {
      const i = steps.indexOf(r), wrap = el("span", "", n(r.n));
      if (i > 0 && steps[i - 1].n) wrap.append(el("small", "", " " + pct(r.n / steps[i - 1].n)));
      return wrap;
    },
  });

  // the checks
  const checks = [];
  const check = (level, what, why) => checks.push({ level, what, why });
  if (site) {
    const gap = downloaders - t.new_finished;
    if (!downloaders) check("dim", "No downloads in " + RANGE_WORDS[range]);
    else if (gap > 0) check("warn", n(gap) + " of " + n(downloaders) + " people who downloaded haven't finished onboarding",
      "They may not have opened Otto yet, or they stopped during onboarding. Up to 1.75.7 Otto reports an install only once its onboarding is finished, so they can't be told apart.");
    else check("ok", "Every download in " + RANGE_WORDS[range] + " became an install that finished onboarding");
  } else check("dim", "Website numbers didn't load");
  const stopped = app.installs.filter(stuck), now = app.installs.filter(inOnboarding);
  if (stopped.length) check("bad", n(stopped.length) + (stopped.length === 1 ? " install stopped" : " installs stopped") + " during onboarding",
    "Furthest step: " + stopped.map((r) => STEP_NAMES[r.ob_furthest] || "start").join(", ") + ". See them on the App page.");
  if (now.length) check("live", n(now.length) + (now.length === 1 ? " install is" : " installs are") + " going through onboarding right now");
  const left = app.onboarding.abandoned.reduce((s, r) => s + r.n, 0);
  if (left) check("warn", n(left) + " left onboarding before the end",
    "At: " + app.onboarding.abandoned.map((r) => r.key + " (" + r.n + ")").join(", ") + ". They came back later and finished, or they would not be counted.");
  if (t.errors) check("bad", n(t.errors) + (t.errors === 1 ? " error" : " errors") + " reported",
    "Most often: " + app.errors[0].key + " (" + n(app.errors[0].n) + " from " + n(app.errors[0].installs) + (app.errors[0].installs === 1 ? " install)" : " installs)"));
  else check("ok", "No errors reported");
  const denied = app.permissions.filter((p) => /denied$/.test(p.key));
  if (denied.length) check("warn", denied.map((p) => n(p.n) + " denied " + p.key.split(":")[0]).join(", "),
    "Without the calendar, meeting alerts can't work.");
  if (app.latest_version && app.versions.length > 1) {
    const behind = app.versions.filter((v) => v.key !== app.latest_version).reduce((s, v) => s + v.n, 0);
    if (behind) check("dim", n(behind) + " of " + n(behind + app.versions[0].n) + " installs active in this period run a version older than " + app.latest_version);
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

  const combined = app.buckets.map((b, i) => ({ start: b.start,
    values: { downloaders: site && site.buckets[i] ? site.buckets[i].values.downloaders : 0, new: b.values.new } }));
  barChart($("dl-installs"), combined, app.step, site
    ? [{ key: "downloaders", label: "People who downloaded", color: "var(--green)" }, { key: "new", label: "New installs", color: "var(--violet)" }]
    : [{ key: "new", label: "New installs", color: "var(--violet)" }]);
  barChart($("active"), app.buckets, app.step, [{ key: "active", label: "Installs using Otto", color: "var(--violet)" }]);
  if (site) barChart($("visitors"), site.buckets, site.step, [{ key: "visitors", label: "Visitors", color: "var(--blue)" }]);
  else $("visitors").replaceChildren(el("p", "empty", "Website numbers didn't load"));
}

boot(load, draw);
`;

export const overviewHTML = page({ title: "Overview", tab: "overview", body, script });
