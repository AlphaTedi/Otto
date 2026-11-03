// The website: who visits ottotofive.com and who downloads Otto, hour by hour
// down to 5 minutes, the latest visits and downloads with their time, and
// where visitors come from. The site's own Worker (otto-site, repo
// AlphaTedi/website) counts them into the D1 database otto-site-stats — no
// cookies, no IP kept — which this Worker reads as SITE.

import { page } from "./shared";

const body = `
  <section class="grid kpis" id="kpis"></section>
  <section class="grid">
    <div class="card"><h2>Visitors and downloads</h2><p class="sub" id="traffic-sub"></p><div id="traffic"></div></div>
  </section>
  <section class="grid two">
    <div class="card"><h2>Latest visits and downloads</h2><p class="sub" id="recent-sub"></p>
      <div class="table short"><table>
        <thead><tr><th>When</th><th>What</th><th>From</th><th>Country</th><th>Device</th></tr></thead>
        <tbody id="recent"></tbody>
      </table></div></div>
    <div class="card"><h2>Where visitors come from</h2><p class="sub" id="sources-sub"></p><div id="sources" class="rows"></div>
      <h2 style="margin-top:18px">Devices</h2><p class="sub">Otto installs only on a Mac</p><div id="devices" class="rows"></div>
      <h2 style="margin-top:18px">Countries</h2><div id="countries" class="rows"></div></div>
  </section>
  <section class="grid" id="days-card">
    <div class="card"><h2>Every day</h2>
      <div class="table"><table>
        <thead><tr><th>Day</th><th class="num">Visitors</th><th class="num">Page views</th><th class="num">People who downloaded</th>
          <th class="num">Downloads</th><th class="num">Download rate</th></tr></thead>
        <tbody id="days"></tbody>
      </table></div></div>
  </section>
  <p class="note">ottotofive.com, counted by the site itself: no cookies, no IP addresses kept. A visitor is one person
    on one day, so someone who comes back the next day counts again; "again" marks a second visit or download by the
    same person that day. Downloads are clicks on Download. Crawlers and link previews are left out. The time,
    source, country and device of single visits are kept for 90 days.</p>
`;

const script = `
const DEVICES = { mac: "Mac", iphone: "iPhone", ipad: "iPad", android: "Android", windows: "Windows", linux: "Linux", other: "Other", "": "Unknown" };
let regions = null;
try { regions = new Intl.DisplayNames(["en"], { type: "region" }); } catch {}
const country = (c) => { if (!c) return "Unknown"; try { return regions ? regions.of(c.toUpperCase()) : c.toUpperCase(); } catch { return c.toUpperCase(); } };
const source = (s) => s ? s : "Direct or unknown";

async function load() { return api("/api/site"); }

function draw(d) {
  const t = d.totals, p = d.previous;
  const mac = d.devices.find((r) => r.key === "mac"), seen = d.devices.reduce((s, r) => s + Number(r.n), 0);
  $("kpis").replaceChildren(
    kpi("Visitors", n(t.visitors), change(t.visitors, p.visitors)),
    kpi("People who downloaded", n(t.downloaders), change(t.downloaders, p.downloaders)),
    kpi("Download rate", pct(ratio(t.downloaders, t.visitors)),
        ratio(t.downloaders, t.visitors) !== null && ratio(p.downloaders, p.visitors) !== null
          ? change(ratio(t.downloaders, t.visitors), ratio(p.downloaders, p.visitors), { points: true }) : "People who downloaded per visitor"),
    kpi("Visitors on a Mac", seen ? pct(ratio(mac ? Number(mac.n) : 0, seen)) : "—", seen ? n(mac ? mac.n : 0) + " of " + n(seen) : "No visits noted yet"),
    kpi("Page views", n(t.views), change(t.views, p.views)),
    kpi("Downloads", n(t.downloads), change(t.downloads, p.downloads)),
  );

  const since = d.logged_since ? Date.parse(d.logged_since) : null;
  const partial = since && since > d.from;
  $("traffic-sub").textContent = (d.step === "min5" ? "Every 5 minutes" : d.step === "hour" ? "Every hour" : "Every day")
    + (partial && d.step !== "day" ? "; single visits are noted from " + when(d.logged_since) : "");
  barChart($("traffic"), d.buckets, d.step, [
    { key: "visitors", label: "Visitors", color: "var(--blue)" }, { key: "downloaders", label: "People who downloaded", color: "var(--green)" }]);

  const notedFrom = partial ? "Noted from " + when(d.logged_since) + "; " : "";
  $("recent-sub").textContent = notedFrom + "newest first, your local time";
  $("sources-sub").textContent = (partial ? "Noted from " + when(d.logged_since) + ". " : "") + "The site that linked to the visit, or a ?ref= on the link";
  const recent = $("recent");
  if (!d.recent.length) {
    const tr = el("tr"), td = el("td", "muted", "Nothing in " + RANGE_WORDS[range] + ".");
    td.colSpan = 5; tr.append(td); recent.replaceChildren(tr);
  } else recent.replaceChildren(...d.recent.map((h) => {
    const tr = el("tr"), what = el("td");
    what.append(el("span", "pill " + (h.kind === "download" ? "ok" : "dim"), h.kind === "download" ? "Download" : "Visit"));
    if (!h.fresh) what.append(el("span", "muted", " again"));
    tr.append(el("td", "", whenShort(h.ts)), what, el("td", h.source ? "" : "muted", source(h.source)),
              el("td", "", country(h.country)), el("td", "", DEVICES[h.device || ""] || h.device));
    return tr;
  }));
  rows($("sources"), d.sources, { label: (r) => source(r.key), color: "var(--blue)", empty: "No visits noted in this period" });
  rows($("devices"), d.devices.filter((r) => Number(r.n) > 0), { label: (r) => DEVICES[r.key] || r.key, color: "var(--blue)",
    empty: "No visits noted in this period",
    value: (r) => { const w = el("span", "", n(r.n)); if (Number(r.downloaded)) w.append(el("small", "", " · " + n(r.downloaded) + " downloaded")); return w; } });
  rows($("countries"), d.countries, { label: (r) => country(r.key), color: "var(--blue)", empty: "No visits noted in this period" });

  $("days-card").hidden = d.step !== "day";
  if (d.step === "day") {
    const days = d.daily.slice().reverse();
    $("days").replaceChildren(...(days.length ? days.map((r) => {
      const tr = el("tr");
      tr.append(el("td", "", F.day.format(Date.parse(r.day + "T12:00:00Z"))), el("td", "num", n(r.visitors)), el("td", "num", n(r.views)),
                el("td", "num", n(r.downloaders)), el("td", "num", n(r.downloads)), el("td", "num", pct(ratio(r.downloaders, r.visitors))));
      return tr;
    }) : [(() => { const tr = el("tr"), td = el("td", "muted", "Nothing counted in this period."); td.colSpan = 6; tr.append(td); return tr; })()]));
  }
}

boot(load, draw);
`;

export const websiteHTML = page({ title: "Website", tab: "website", body, script });
