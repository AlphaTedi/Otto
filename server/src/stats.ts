// The numbers behind the dashboard (docs/TELEMETRY.md): the app's, from the
// otto-telemetry database, and the website's, from otto-site-stats (SITE),
// which the site's own Worker fills and this Worker only reads.
//
// Every view takes a range — the last 2 or 24 hours, or 7 to 365 days — and
// splits it into buckets: 5 minutes, an hour, or a day in Amsterdam time.

import type { Env } from "./index";

const TZ = "Europe/Amsterdam";
const DAY_MS = 86_400_000;

// MARK: Ranges

export type Step = "min5" | "hour" | "day";
export interface Bucket { key: string | number; start: number }
export interface Range {
  id: string; step: Step; from: number; to: number; prevFrom: number;
  buckets: Bucket[]; days: string[]; prevDays: string[];
}

const HOURS: Record<string, { seconds: number; n: number }> = {
  "2h": { seconds: 300, n: 24 },
  "24h": { seconds: 3600, n: 24 },
};
const DAYS: Record<string, number> = { "7d": 7, "30d": 30, "90d": 90, "365d": 365 };

/** Amsterdam's offset from UTC at instant `t`, in ms. */
function offsetMs(t: number): number {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: TZ, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(new Date(t)).map((p) => [p.type, p.value]));
  const asUTC = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  return asUTC - Math.floor(t / 1000) * 1000;
}
export const amsterdamDay = (t = Date.now()): string => new Date(t + offsetMs(t)).toISOString().slice(0, 10);
const shiftDay = (day: string, n: number) => new Date(Date.parse(day + "T00:00:00Z") + n * DAY_MS).toISOString().slice(0, 10);
/** The instant an Amsterdam day starts. */
function midnight(day: string): number {
  const guess = Date.parse(day + "T00:00:00Z");
  return guess - offsetMs(guess - offsetMs(guess));
}

export function parseRange(raw: string | null, now = Date.now()): Range {
  const id = raw && (raw in HOURS || raw in DAYS) ? raw : "24h";
  if (id in HOURS) {
    const { seconds, n } = HOURS[id];
    const last = Math.floor(now / 1000 / seconds) * seconds;
    const buckets = Array.from({ length: n }, (_, i) => {
      const key = last - (n - 1 - i) * seconds;
      return { key, start: key * 1000 };
    });
    const from = buckets[0].start;
    return { id, step: seconds === 300 ? "min5" : "hour", from, to: now, prevFrom: from - n * seconds * 1000,
             buckets, days: [], prevDays: [] };
  }
  const n = DAYS[id];
  const today = amsterdamDay(now);
  const days = Array.from({ length: n }, (_, i) => shiftDay(today, i - (n - 1)));
  const prevDays = Array.from({ length: n }, (_, i) => shiftDay(today, i - (2 * n - 1)));
  return { id, step: "day", from: midnight(days[0]), to: now, prevFrom: midnight(prevDays[0]),
           buckets: days.map((day) => ({ key: day, start: midnight(day) })), days, prevDays };
}

const iso = (ms: number) => new Date(ms).toISOString();

/** The SQL that puts a timestamp column in its bucket: epoch seconds, or an Amsterdam day. */
function bucketSQL(step: Step, col: string): string {
  if (step === "min5") return `(CAST(strftime('%s', ${col}) AS INTEGER) / 300) * 300`;
  if (step === "hour") return `(CAST(strftime('%s', ${col}) AS INTEGER) / 3600) * 3600`;
  return amsterdamDaySQL(col);
}
/** date() in Amsterdam time: +2 h from the last Sunday of March to the last of October (01:00 UTC). */
function amsterdamDaySQL(col: string): string {
  const y = `strftime('%Y', ${col})`;
  const start = `datetime(date(${y} || '-03-31', '-6 days', 'weekday 0'), '+1 hour')`;
  const end = `datetime(date(${y} || '-10-31', '-6 days', 'weekday 0'), '+1 hour')`;
  return `date(${col}, CASE WHEN datetime(${col}) >= ${start} AND datetime(${col}) < ${end} THEN '+2 hours' ELSE '+1 hour' END)`;
}

/** One row per bucket, with every series filled (0 where nothing happened). */
function fill(range: Range, series: Record<string, Map<string | number, number>>) {
  return range.buckets.map((b) => {
    const values: Record<string, number> = {};
    for (const [name, map] of Object.entries(series)) values[name] = map.get(b.key) ?? 0;
    return { start: b.start, values };
  });
}
const toMap = (rows: { b: string | number; n: number }[]) => new Map(rows.map((r) => [r.b, Number(r.n)]));

// MARK: The app

/** `env = 'prod'` and none of the excluded installs (Marcello's own Macs). */
export function scope(env: Env, alias = ""): { sql: string; binds: string[] } {
  const ids = env.EXCLUDED_INSTALLS.split(",").map((s) => s.trim()).filter(Boolean);
  const column = alias ? `${alias}.install_id` : "install_id";
  const envColumn = alias ? `${alias}.env` : "env";
  const sql = `${envColumn} = 'prod'` + (ids.length ? ` AND ${column} NOT IN (${ids.map(() => "?").join(",")})` : "");
  return { sql, binds: ids };
}

const STEP_INDEX = `CASE json_extract(props, '$.step') WHEN 'welcome' THEN 0 WHEN 'discover' THEN 1 WHEN 'style' THEN 2
  WHEN 'shortcut' THEN 3 WHEN 'permissions' THEN 4 WHEN 'done' THEN 5 END`;

const median = (values: number[]) => {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const versionKey = (v: string | null) => (v ?? "").split(".").map((p) => p.padStart(4, "0")).join(".");

export async function appSummary(env: Env, range: Range) {
  const s = scope(env), se = scope(env, "e"), si = scope(env, "i");
  const q = <T>(sql: string, binds: unknown[]) => env.DB.prepare(sql).bind(...binds).all<T>().then((r) => r.results);
  const first = async <T>(sql: string, binds: unknown[]) => (await q<T>(sql, binds))[0];
  const from = iso(range.from), prevFrom = iso(range.prevFrom);
  const B = (col: string) => bucketSQL(range.step, col);
  type Row = { b: string | number; n: number };

  const [active, fresh, onboarding, totals, prev, prevFresh, installs, everyone] = await Promise.all([
    q<Row>(`SELECT ${B("ts")} AS b, COUNT(DISTINCT install_id) AS n FROM events WHERE ts >= ? AND ${s.sql} GROUP BY b`,
           [from, ...s.binds]),
    q<Row>(`SELECT ${B("first_seen")} AS b, COUNT(*) AS n FROM installs WHERE first_seen >= ? AND ${s.sql} GROUP BY b`,
           [from, ...s.binds]),
    q<Row & { name: string }>(
      `SELECT ${B("ts")} AS b, name, COUNT(DISTINCT install_id) AS n FROM events
       WHERE ts >= ? AND name IN ('onboarding_started', 'onboarding_completed') AND ${s.sql} GROUP BY b, name`,
      [from, ...s.binds]),
    first<{ active: number; finished: number; started: number }>(
      `SELECT COUNT(DISTINCT install_id) AS active,
              COUNT(DISTINCT CASE WHEN name = 'onboarding_completed' THEN install_id END) AS finished,
              COUNT(DISTINCT CASE WHEN name = 'onboarding_started' THEN install_id END) AS started
       FROM events WHERE ts >= ? AND ${s.sql}`, [from, ...s.binds]),
    first<{ active: number; finished: number }>(
      `SELECT COUNT(DISTINCT install_id) AS active,
              COUNT(DISTINCT CASE WHEN name = 'onboarding_completed' THEN install_id END) AS finished
       FROM events WHERE ts >= ? AND ts < ? AND ${s.sql}`, [prevFrom, from, ...s.binds]),
    first<{ n: number }>(`SELECT COUNT(*) AS n FROM installs WHERE first_seen >= ? AND first_seen < ? AND ${s.sql}`,
                         [prevFrom, from, ...s.binds]),
    // one row per install seen in the range: an anonymous id, and how far it got
    q<Record<string, unknown>>(
      `SELECT i.install_id AS id, i.first_seen, i.last_seen, i.first_version, i.last_version, i.os, i.lang, i.layout,
              MIN(e.ts) AS first_event, MAX(e.ts) AS last_event,
              MIN(CASE WHEN e.name = 'onboarding_started' THEN e.ts END) AS ob_started,
              MAX(CASE WHEN e.name = 'onboarding_completed' THEN e.ts END) AS ob_finished,
              MAX(CASE WHEN e.name = 'onboarding_completed' THEN json_extract(e.props, '$.total_ms') END) AS ob_ms,
              MAX(CASE WHEN e.name = 'onboarding_abandoned' THEN e.ts END) AS ob_left,
              MAX(CASE WHEN e.name = 'onboarding_step_viewed' THEN ${STEP_INDEX.replace(/props/g, "e.props")} END) AS ob_furthest,
              GROUP_CONCAT(DISTINCT CASE WHEN e.name = 'onboarding_permission'
                THEN json_extract(e.props, '$.perm') || ':' || json_extract(e.props, '$.result') END) AS permissions,
              MAX(CASE WHEN e.name = 'onboarding_style_selected' THEN json_extract(e.props, '$.mode') END) AS style,
              SUM(e.name = 'app_launched') AS launches, SUM(e.name = 'notch_opened') AS opens,
              SUM(e.name = 'todo_created') AS todos, SUM(e.name = 'todo_completed') AS done,
              SUM(e.name = 'note_created') AS notes, SUM(e.name = 'error') AS errors,
              COUNT(DISTINCT e.day) AS active_days
       FROM installs i LEFT JOIN events e ON e.install_id = i.install_id AND e.env = 'prod'
       WHERE ${si.sql} AND (i.last_seen >= ? OR i.first_seen >= ?)
       GROUP BY i.install_id ORDER BY i.first_seen DESC LIMIT 300`, [...si.binds, from, from]),
    first<{ installs: number; active7: number }>(
      `SELECT COUNT(*) AS installs, COALESCE(SUM(last_seen >= ?), 0) AS active7 FROM installs WHERE ${s.sql}`,
      [iso(Date.now() - 7 * DAY_MS), ...s.binds]),
  ]);

  // older than the 90 days of raw events: what the nightly rollup kept (UTC days)
  const activeMap = toMap(active);
  if (range.step === "day" && range.from < Date.now() - 89 * DAY_MS) {
    const archived = await q<Row>(`SELECT day AS b, value AS n FROM daily_rollups WHERE metric = 'active' AND day >= ?`,
                                  [range.days[0]]);
    for (const row of archived) if (!activeMap.has(row.b)) activeMap.set(row.b, Number(row.n));
  }
  const started = toMap(onboarding.filter((r) => r.name === "onboarding_started"));
  const finished = toMap(onboarding.filter((r) => r.name === "onboarding_completed"));

  // the onboarding, for the installs that started it in the range
  const [funnel, stepTimes, totalTimes] = await Promise.all([
    q<{ step: string; n: number }>(
      `WITH st AS (SELECT DISTINCT install_id FROM events WHERE name = 'onboarding_started' AND ts >= ? AND ${s.sql})
       SELECT json_extract(e.props, '$.step') AS step, COUNT(DISTINCT e.install_id) AS n
       FROM events e JOIN st ON st.install_id = e.install_id
       WHERE e.name = 'onboarding_step_viewed' AND e.ts >= ? AND ${se.sql} GROUP BY step`,
      [from, ...s.binds, from, ...se.binds]),
    q<{ step: string; ms: number }>(
      `SELECT json_extract(props, '$.step') AS step, json_extract(props, '$.duration_ms') AS ms FROM events
       WHERE name = 'onboarding_step_completed' AND ts >= ? AND ${s.sql} LIMIT 5000`, [from, ...s.binds]),
    q<{ ms: number }>(
      `SELECT json_extract(props, '$.total_ms') AS ms FROM events
       WHERE name = 'onboarding_completed' AND ts >= ? AND ${s.sql} LIMIT 5000`, [from, ...s.binds]),
  ]);
  const byStep = new Map<string, number[]>();
  for (const row of stepTimes) {
    if (typeof row.ms !== "number") continue;
    byStep.set(row.step, [...(byStep.get(row.step) ?? []), row.ms]);
  }

  type Count = { key: string; n: number; installs?: number };
  const count = (sql: string) => q<Count>(sql, [from, ...s.binds]);
  const [styles, permissions, triggers, usage, feedback, errors, abandoned, versions] = await Promise.all([
    count(`SELECT json_extract(props, '$.mode') AS key, COUNT(DISTINCT install_id) AS n FROM events
           WHERE name = 'onboarding_style_selected' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`),
    count(`SELECT json_extract(props, '$.perm') || ': ' || json_extract(props, '$.result') AS key,
                  COUNT(DISTINCT install_id) AS n FROM events
           WHERE name = 'onboarding_permission' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY key`),
    count(`SELECT json_extract(props, '$.trigger') AS key, COUNT(*) AS n FROM events
           WHERE name = 'notch_opened' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`),
    count(`SELECT name AS key, COUNT(*) AS n, COUNT(DISTINCT install_id) AS installs FROM events WHERE ts >= ? AND ${s.sql}
           AND name IN ('todo_created','todo_completed','note_created','step_added','section_created',
                        'shortcut_used','meeting_alert_shown','calendar_connected','space_switched')
           GROUP BY name ORDER BY n DESC`),
    count(`SELECT json_extract(props, '$.category') AS key, COUNT(*) AS n FROM events
           WHERE name = 'feedback_sent' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`),
    count(`SELECT json_extract(props, '$.domain') || ' ' || json_extract(props, '$.code') AS key, COUNT(*) AS n,
                  COUNT(DISTINCT install_id) AS installs FROM events
           WHERE name = 'error' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC LIMIT 20`),
    count(`SELECT json_extract(props, '$.last_step') AS key, COUNT(DISTINCT install_id) AS n FROM events
           WHERE name = 'onboarding_abandoned' AND ts >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`),
    count(`SELECT last_version AS key, COUNT(*) AS n FROM installs WHERE last_seen >= ? AND ${s.sql} GROUP BY key`),
  ]);
  versions.sort((a, b) => versionKey(b.key).localeCompare(versionKey(a.key)));

  const installRows = installs.map((r) => ({
    ...r,
    permissions: typeof r.permissions === "string" ? (r.permissions as string).split(",") : [],
  }));
  // of the installs that arrived in the range, how many were used again on another day
  const arrived = installRows.filter((r) => String(r.first_seen) >= from);
  const returned = arrived.filter((r) => Number(r.active_days) >= 2).length;
  const arrivedFinished = arrived.filter((r) => r.ob_finished).length;

  return {
    range: range.id, step: range.step, from: range.from, to: range.to,
    buckets: fill(range, { active: activeMap, new: toMap(fresh), started, finished }),
    totals: {
      active: Number(totals?.active ?? 0), new: fresh.reduce((sum, r) => sum + Number(r.n), 0),
      finished: Number(totals?.finished ?? 0), started: Number(totals?.started ?? 0), returned,
      new_finished: arrivedFinished,
      installs: Number(everyone?.installs ?? 0), active_7d: Number(everyone?.active7 ?? 0),
      errors: errors.reduce((sum, r) => sum + Number(r.n), 0),
    },
    previous: { active: Number(prev?.active ?? 0), new: Number(prevFresh?.n ?? 0), finished: Number(prev?.finished ?? 0) },
    installs: installRows,
    onboarding: {
      started: Number(totals?.started ?? 0),
      steps: funnel,
      step_ms: Object.fromEntries([...byStep].map(([step, list]) => [step, median(list)])),
      total_ms: median(totalTimes.map((r) => Number(r.ms)).filter(Number.isFinite)),
      abandoned,
    },
    styles, permissions, triggers, usage, feedback, errors, versions,
    latest_version: versions[0]?.key ?? null,
    excluded: s.binds.length,
  };
}

/** Everything one install sent, newest first: what it did, never what it wrote. */
export async function installTimeline(env: Env, id: string) {
  const install = await env.DB.prepare(`SELECT * FROM installs WHERE install_id = ?`).bind(id).first();
  if (!install) return null;
  const events = await env.DB.prepare(
    `SELECT ts, name, props, app_version, substr(session_id, 1, 8) AS session FROM events
     WHERE install_id = ? ORDER BY ts DESC, id DESC LIMIT 500`
  ).bind(id).all().then((r) => r.results);
  return { install, events };
}

// MARK: The website

interface Hit { ts: string; kind: string; fresh: number; source: string | null; country: string | null; device: string | null }

export async function siteSummary(db: D1Database, range: Range) {
  const from = iso(range.from), prevFrom = iso(range.prevFrom);
  const B = bucketSQL(range.step, "ts");
  const logged = await db.prepare(`SELECT MIN(ts) AS first FROM hits`).first<{ first: string | null }>();

  // the counts: from single hits for hours, from the daily totals for days (they go back further)
  type Totals = { visitors: number; views: number; downloaders: number; downloads: number };
  let totals: Totals, previous: Totals, buckets;
  const hitTotals = (lo: string, hi: string) => db.prepare(
    `SELECT COALESCE(SUM(kind = 'view' AND fresh), 0) AS visitors, COALESCE(SUM(kind = 'view'), 0) AS views,
            COALESCE(SUM(kind = 'download' AND fresh), 0) AS downloaders, COALESCE(SUM(kind = 'download'), 0) AS downloads
     FROM hits WHERE ts >= ? AND ts < ?`).bind(lo, hi).first<Totals>();
  const dayTotals = (days: string[]) => db.prepare(
    `SELECT COALESCE(SUM(visitors), 0) AS visitors, COALESCE(SUM(views), 0) AS views,
            COALESCE(SUM(downloaders), 0) AS downloaders, COALESCE(SUM(downloads), 0) AS downloads
     FROM daily WHERE day >= ? AND day <= ?`).bind(days[0], days[days.length - 1]).first<Totals>();
  let daily: Record<string, unknown>[] = [];

  if (range.step === "day") {
    const rows = await db.prepare(
      `SELECT day, visitors, views, downloaders, downloads FROM daily WHERE day >= ? ORDER BY day`
    ).bind(range.days[0]).all<Totals & { day: string }>().then((r) => r.results);
    const pick = (key: keyof Totals) => new Map(rows.map((r) => [r.day, Number(r[key])]));
    buckets = fill(range, { visitors: pick("visitors"), views: pick("views"), downloaders: pick("downloaders"), downloads: pick("downloads") });
    [totals, previous] = (await Promise.all([dayTotals(range.days), dayTotals(range.prevDays)])) as [Totals, Totals];
    daily = rows;
  } else {
    const rows = await db.prepare(
      `SELECT ${B} AS b, kind, COUNT(*) AS n, SUM(fresh) AS people FROM hits WHERE ts >= ? GROUP BY b, kind`
    ).bind(from).all<{ b: number; kind: string; n: number; people: number }>().then((r) => r.results);
    const pick = (kind: string, key: "n" | "people") => new Map(rows.filter((r) => r.kind === kind).map((r) => [r.b, Number(r[key])]));
    buckets = fill(range, { visitors: pick("view", "people"), views: pick("view", "n"),
                            downloaders: pick("download", "people"), downloads: pick("download", "n") });
    [totals, previous] = (await Promise.all([hitTotals(from, iso(range.to + 1000)), hitTotals(prevFrom, from)])) as [Totals, Totals];
  }

  const [sources, countries, devices, recent] = await Promise.all([
    db.prepare(`SELECT COALESCE(source, '') AS key, COUNT(*) AS n FROM hits WHERE kind = 'view' AND fresh AND ts >= ?
                GROUP BY key ORDER BY n DESC LIMIT 15`).bind(from).all<{ key: string; n: number }>().then((r) => r.results),
    db.prepare(`SELECT COALESCE(country, '') AS key, COUNT(*) AS n FROM hits WHERE kind = 'view' AND fresh AND ts >= ?
                GROUP BY key ORDER BY n DESC LIMIT 15`).bind(from).all<{ key: string; n: number }>().then((r) => r.results),
    db.prepare(`SELECT COALESCE(device, '') AS key, SUM(kind = 'view' AND fresh) AS n, SUM(kind = 'download' AND fresh) AS downloaded
                FROM hits WHERE ts >= ? GROUP BY key ORDER BY n DESC`).bind(from).all<{ key: string; n: number; downloaded: number }>().then((r) => r.results),
    db.prepare(`SELECT ts, kind, fresh, source, country, device FROM hits WHERE ts >= ? ORDER BY ts DESC LIMIT 150`)
      .bind(from).all<Hit>().then((r) => r.results),
  ]);

  return {
    range: range.id, step: range.step, from: range.from, to: range.to,
    logged_since: logged?.first ?? null,
    totals, previous, buckets, sources, countries, devices, recent, daily,
  };
}
