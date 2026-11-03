// The app, install by install: who started and finished the onboarding, who
// stopped and where, what each install did and when (its timeline), and the
// breakdowns behind them.

import { page } from "./shared";

const body = `
  <section class="grid kpis" id="kpis"></section>
  <section class="grid two">
    <div class="card"><h2>Installs using Otto</h2><p class="sub">Installs that sent anything in each period</p><div id="active"></div></div>
    <div class="card"><h2>Onboarding started and finished</h2><p class="sub">Installs, by when they did it</p><div id="ob-chart"></div></div>
  </section>
  <section class="grid">
    <div class="card"><h2>Installs, one by one</h2>
      <p class="sub">Every install seen in <span class="rw"></span>, newest first. Click one to see everything it did, latest first.</p>
      <div class="table"><table>
        <thead><tr><th>Install</th><th>First seen</th><th>Onboarding</th><th>Furthest step</th><th class="num">Took</th>
          <th>Permissions</th><th>Version</th><th>macOS</th><th class="num">Launches</th><th class="num">Notch opens</th>
          <th class="num">To-dos</th><th class="num">Days used</th><th>Last seen</th></tr></thead>
        <tbody id="installs"></tbody>
      </table></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Onboarding, step by step</h2>
      <p class="sub">Installs that started onboarding in <span class="rw"></span>; the time is the median spent on that step</p>
      <div id="funnel" class="rows"></div></div>
    <div class="card"><h2>Permissions</h2><div id="permissions" class="rows"></div>
      <h2 style="margin-top:18px">Display style chosen</h2><div id="styles" class="rows"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Errors</h2><div id="errors" class="rows"></div></div>
    <div class="card"><h2>App versions</h2><p class="sub">Installs active in the period, by the version they run now</p><div id="versions" class="rows"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>How the notch is opened</h2><div id="triggers" class="rows"></div></div>
    <div class="card"><h2>What people do</h2><div id="usage" class="rows"></div>
      <h2 style="margin-top:18px">Feedback sent</h2><div id="feedback" class="rows"></div></div>
  </section>
  <p class="note">Only installs that share anonymous usage data; no to-do, note or calendar event is ever sent. Up to
    1.75.7 an install reports only once its onboarding is finished, so "Stopped" can only show up for versions that
    report from the start. An install stopped when it began onboarding, didn't finish, and sent nothing for 30 minutes.</p>
`;

const script = `
const STEP_NAMES = ["welcome", "discover", "style", "shortcut", "permissions", "done"];
const LABELS = {
  app_launched: "Opened Otto", app_active_day: "Active day", update_installed: "Updated",
  onboarding_started: "Started onboarding", onboarding_step_viewed: "Onboarding step", onboarding_step_completed: "Finished step",
  onboarding_discover_viewed: "Saw", onboarding_style_selected: "Chose style", onboarding_shortcut_fired: "Tried the shortcut",
  onboarding_shortcut_skipped: "Skipped the shortcut", onboarding_permission: "Permission", onboarding_completed: "Finished onboarding",
  onboarding_abandoned: "Left onboarding", notch_opened: "Opened the notch", notch_closed: "Closed the notch",
  panel_mode_entered: "Panel mode", todo_created: "Added a to-do", todo_completed: "Completed a to-do", todo_deleted: "Deleted a to-do",
  step_added: "Added a step", step_completed: "Completed a step", section_created: "Added a section", space_switched: "Switched space",
  note_created: "Wrote a note", meeting_alert_shown: "Meeting alert", calendar_connected: "Connected a calendar",
  shortcut_used: "Used a shortcut", shortcuts_overlay_opened: "Opened the shortcuts", settings_changed: "Changed a setting",
  feedback_opened: "Opened feedback", feedback_sent: "Sent feedback", error: "Error",
};
const USAGE = { todo_created: "To-dos added", todo_completed: "To-dos completed", note_created: "Notes written",
  step_added: "Steps added", section_created: "Sections added", shortcut_used: "Shortcuts used",
  meeting_alert_shown: "Meeting alerts", calendar_connected: "Calendars connected", space_switched: "Spaces switched" };
const PERMS = { calendar: "Calendar", login: "Open at login" };

function status(r) {
  if (r.ob_finished) return ["Finished", "ok"];
  if (r.ob_left) return ["Left onboarding", "warn"];
  if (r.ob_started) return Date.now() - Date.parse(r.last_event) > 30 * 60000 ? ["Stopped", "bad"] : ["In onboarding now", "live"];
  return ["Not shown", "dim"];
}
const permText = (p) => { const parts = p.split(":"); return (PERMS[parts[0]] || parts[0]) + " " + (parts[1] === "granted" || parts[1] === "on" ? "✓" : "✗"); };

async function load() { return api("/api/summary"); }

function draw(d) {
  const t = d.totals, p = d.previous;
  const stopped = d.installs.filter((r) => status(r)[0] === "Stopped").length;
  const fresh = d.installs.filter((r) => Date.parse(r.first_seen) >= d.from).length;
  $("kpis").replaceChildren(
    kpi("Installs using Otto", n(t.active), change(t.active, p.active)),
    kpi("New installs", n(t.new), change(t.new, p.new)),
    kpi("Finished onboarding", n(t.finished), change(t.finished, p.finished)),
    kpi("Stopped in onboarding", n(stopped), stopped ? "See the table below" : "None", stopped ? "bad" : ""),
    kpi("Used it again another day", n(t.returned), fresh ? "of " + n(fresh) + " new in the period" : "No new installs"),
    kpi("Errors", n(t.errors), t.errors ? (() => { const k = d.errors.reduce((s, r) => s + r.installs, 0); return "From " + n(k) + (k === 1 ? " install" : " installs"); })() : "None reported", t.errors ? "bad" : ""),
    kpi("All installs", n(t.installs), n(t.active_7d) + " active in the last 7 days"),
  );
  barChart($("active"), d.buckets, d.step, [{ key: "active", label: "Installs using Otto", color: "var(--violet)" }]);
  barChart($("ob-chart"), d.buckets, d.step, [
    { key: "started", label: "Started", color: "var(--blue)" }, { key: "finished", label: "Finished", color: "var(--green)" }]);

  // the installs table, and each one's timeline under it
  const body = $("installs");
  if (!d.installs.length) {
    const tr = el("tr"), td = el("td", "muted", "No install sent anything in " + RANGE_WORDS[range] + ".");
    td.colSpan = 13; tr.append(td); body.replaceChildren(tr);
  } else body.replaceChildren(...d.installs.map((r) => {
    const tr = el("tr", "row");
    const s = status(r), pill = el("span", "pill " + s[1], s[0]);
    const cells = [
      el("td", "mono", r.id.slice(0, 8)), el("td", "", when(r.first_seen)), el("td"),
      el("td", "", r.ob_furthest === null || r.ob_furthest === undefined ? "—" : STEP_NAMES[r.ob_furthest]),
      el("td", "num", r.ob_ms ? dur(r.ob_ms) : "—"),
      el("td", "", r.permissions.length ? r.permissions.map(permText).join("  ") : "—"),
      el("td", "", r.last_version + (r.first_version !== r.last_version ? " (from " + r.first_version + ")" : "")),
      el("td", "", r.os || "—"), el("td", "num", n(r.launches)), el("td", "num", n(r.opens)),
      el("td", "num", n(r.todos)), el("td", "num", n(r.active_days)), el("td", "", ago(r.last_event || r.last_seen)),
    ];
    cells[0].title = r.id;
    cells[2].append(pill);
    tr.append(...cells);
    tr.addEventListener("click", () => toggle(tr, r));
    return tr;
  }));

  const steps = STEP_NAMES.map((key) => ({ key, n: (d.onboarding.steps.find((s) => s.key === key || s.step === key) || { n: 0 }).n }));
  rows($("funnel"), d.onboarding.started ? steps : [], {
    color: "var(--violet)", empty: "Nobody started onboarding in " + RANGE_WORDS[range],
    value: (r) => { const ms = d.onboarding.step_ms[r.key]; const w = el("span", "", n(r.n)); if (ms) w.append(el("small", "", " " + dur(ms))); return w; },
  });
  rows($("permissions"), d.permissions, { label: (r) => permText(r.key.replace(" ", "")) });
  rows($("styles"), d.styles);
  rows($("errors"), d.errors, { color: "var(--pink)", empty: "No errors reported",
    value: (r) => { const w = el("span", "", n(r.n)); w.append(el("small", "", " " + n(r.installs) + (r.installs === 1 ? " install" : " installs"))); return w; } });
  rows($("versions"), d.versions, { label: (r) => r.key + (r.key === d.latest_version ? " (latest)" : "") });
  rows($("triggers"), d.triggers);
  rows($("usage"), d.usage, { label: (r) => USAGE[r.key] || r.key,
    value: (r) => { const w = el("span", "", n(r.n)); w.append(el("small", "", " by " + n(r.installs))); return w; } });
  rows($("feedback"), d.feedback, { empty: "No feedback sent" });
}

const open = {};
async function toggle(tr, r) {
  const next = tr.nextElementSibling;
  if (next && next.classList.contains("detail")) { next.remove(); tr.classList.remove("open"); delete open[r.id]; return; }
  tr.classList.add("open");
  open[r.id] = true;
  const detail = el("tr", "detail"), td = el("td");
  td.colSpan = 13;
  const box = el("div", "timeline", "Loading…");
  td.append(box); detail.append(td); tr.after(detail);
  try {
    const res = await fetch("/api/install?id=" + encodeURIComponent(r.id), { headers: { authorization: "Bearer " + (store.get(PW) || "") } });
    if (!res.ok) throw new Error("server error " + res.status);
    timeline(box, await res.json());
  } catch (err) { box.textContent = "Couldn't load this install: " + err.message; }
}

function timeline(box, data) {
  const i = data.install;
  box.replaceChildren();
  const meta = el("div", "meta");
  const bit = (label, value) => { meta.append(document.createTextNode(label + " ")); meta.append(el("b", "", value)); meta.append(document.createTextNode("   ")); };
  bit("ID", i.install_id); bit("First seen", when(i.first_seen)); bit("macOS", i.os || "—"); bit("Language", i.lang || "—");
  bit("Layout", i.layout || "—"); bit("Version", i.first_version === i.last_version ? i.last_version : i.first_version + " → " + i.last_version);
  box.append(meta);
  if (!data.events.length) { box.append(el("p", "empty", "No events.")); return; }
  let day = "";
  data.events.forEach((e) => {
    const t = new Date(e.ts), dayLabel = F.day.format(t);
    if (dayLabel !== day) { day = dayLabel; box.append(el("div", "day", dayLabel)); }
    let props = {};
    try { props = JSON.parse(e.props || "{}") || {}; } catch {}
    const cls = e.name === "error" ? "err" : e.name === "onboarding_completed" ? "done" : e.name.indexOf("onboarding") === 0 ? "ob" : "";
    const row = el("div", "ev " + cls);
    const details = Object.keys(props).map((k) => {
      const v = props[k];
      if (/_ms$/.test(k)) return dur(v);
      if (typeof v === "boolean") return (v ? "" : "not ") + k.split("_").join(" ");
      return (k === "step" || k === "item" || k === "mode" || k === "trigger" ? "" : k.split("_").join(" ") + " ") + v;
    }).join(" · ");
    row.append(el("span", "tm", F.secs.format(t)), el("span", "what", LABELS[e.name] || e.name), el("span", "props", details));
    box.append(row);
  });
  if (data.events.length >= 500) box.append(el("p", "empty", "Showing the latest 500 events."));
}

boot(load, (d) => {
  draw(d);
  // keep the timelines that were open across a refresh
  document.querySelectorAll("#installs tr.row").forEach((tr, i) => { const r = d.installs[i]; if (r && open[r.id]) { delete open[r.id]; toggle(tr, r); } });
});
`;

export const appHTML = page({ title: "App", tab: "app", body, script });
