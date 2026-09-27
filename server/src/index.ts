// Otto's monitoring Worker (docs/TELEMETRY.md).
//
//   POST /v1/events   — anonymous event batches from the app (opt-in only)
//   GET  /dashboard   — Marcello's private dashboard (password in a secret)
//   GET  /api/summary — the numbers behind it
//   cron 03:00 UTC    — daily rollups, 90-day raw retention
//
// What it never does: store an IP address, accept free text, receive a
// to-do, a note, a calendar event or a feedback message. Feedback travels by
// email from the user's Mac; only the fact that one was sent arrives here.

import { EVENTS, UUID, validateContext, validateProps } from "./events";
import { dashboardHTML } from "./dashboard";

export interface Env {
  DB: D1Database;
  OTTO_KEY: string;
  EXCLUDED_INSTALLS: string;
  DASHBOARD_PASSWORD?: string;
}

const MAX_EVENTS = 100;
const MAX_BODY = 64 * 1024;
const DAY_MS = 86_400_000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/events" && request.method === "POST") return await ingest(request, env);
      if (url.pathname === "/dashboard" && request.method === "GET") {
        return new Response(dashboardHTML, {
          headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store",
                     "x-robots-tag": "noindex" },
        });
      }
      if (url.pathname === "/api/summary" && request.method === "GET") {
        if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
        return json(await summary(env, clampDays(url.searchParams.get("days"))));
      }
      if (url.pathname === "/") return new Response("Otto telemetry. Nothing to see here.\n");
      return json({ error: "not found" }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: "server error" }, 500);
    }
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await rollup(env, isoDay(Date.now() - DAY_MS));
    await env.DB.prepare("DELETE FROM events WHERE day < ?").bind(isoDay(Date.now() - 90 * DAY_MS)).run();
  },
};

// MARK: Ingest

async function ingest(request: Request, env: Env): Promise<Response> {
  if (request.headers.get("x-otto-key") !== env.OTTO_KEY) return json({ error: "bad key" }, 403);
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY) return json({ error: "too large" }, 413);
  const text = await request.text();
  if (text.length > MAX_BODY) return json({ error: "too large" }, 413);

  let body: any;
  try { body = JSON.parse(text); } catch { return json({ error: "bad json" }, 400); }
  if (!body || !UUID.test(body.install_id ?? "") || !UUID.test(body.session_id ?? "")) {
    return json({ error: "bad ids" }, 400);
  }
  const context = validateContext(body.context);
  if (!context) return json({ error: "bad context" }, 400);
  if (!Array.isArray(body.events) || body.events.length === 0 || body.events.length > MAX_EVENTS) {
    return json({ error: "bad events" }, 400);
  }

  const now = Date.now();
  const receivedAt = new Date(now).toISOString();
  const rows: { name: string; props: string; ts: string; day: string }[] = [];
  for (const event of body.events) {
    const name = event?.name;
    if (typeof name !== "string" || !(name in EVENTS)) return json({ error: `unknown event` }, 400);
    const props = validateProps(name, event.props);
    if (!props) return json({ error: `bad props for ${name}` }, 400);
    const time = Date.parse(event.ts);
    // Queued offline for up to 7 days; a clock a little ahead is tolerated.
    if (!Number.isFinite(time) || time < now - 7 * DAY_MS || time > now + DAY_MS) {
      return json({ error: "bad timestamp" }, 400);
    }
    const ts = new Date(time).toISOString();
    rows.push({ name, props: JSON.stringify(props), ts, day: ts.slice(0, 10) });
  }

  const statements = [
    env.DB.prepare(
      `INSERT INTO installs (install_id, first_seen, last_seen, first_version, last_version, os, lang, layout, env)
       VALUES (?1, ?2, ?2, ?3, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(install_id) DO UPDATE SET last_seen = ?2, last_version = ?3, os = ?4, lang = ?5,
         layout = ?6, env = ?7`
    ).bind(body.install_id, receivedAt, context.app_version, context.os, context.lang, context.layout, context.env),
    ...rows.map((row) =>
      env.DB.prepare(
        `INSERT INTO events (install_id, session_id, name, props, app_version, ts, day, received_at, env)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(body.install_id, body.session_id, row.name, row.props, context.app_version, row.ts, row.day,
             receivedAt, context.env)
    ),
  ];
  await env.DB.batch(statements);
  return json({ ok: true, accepted: rows.length });
}

// MARK: Dashboard API

function authorized(request: Request, env: Env): boolean {
  const password = env.DASHBOARD_PASSWORD;
  if (!password) return false; // No secret set: the dashboard stays shut.
  const given = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (given.length !== password.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ password.charCodeAt(i);
  return diff === 0;
}

function clampDays(raw: string | null): number {
  const days = Number(raw ?? 30);
  return Number.isFinite(days) ? Math.min(365, Math.max(1, Math.round(days))) : 30;
}

/** `AND install_id NOT IN (...)` for the excluded Macs, plus prod only. */
function scope(env: Env, alias = ""): { sql: string; binds: string[] } {
  const ids = env.EXCLUDED_INSTALLS.split(",").map((s) => s.trim()).filter(Boolean);
  const column = alias ? `${alias}.install_id` : "install_id";
  const envColumn = alias ? `${alias}.env` : "env";
  const sql = `${envColumn} = 'prod'` + (ids.length ? ` AND ${column} NOT IN (${ids.map(() => "?").join(",")})` : "");
  return { sql, binds: ids };
}

async function summary(env: Env, days: number) {
  const since = isoDay(Date.now() - (days - 1) * DAY_MS);
  const today = isoDay(Date.now());
  const s = scope(env);
  const all = <T>(sql: string, ...binds: unknown[]) =>
    env.DB.prepare(sql).bind(...binds, ...s.binds).all<T>().then((r) => r.results);
  const one = async <T>(sql: string, ...binds: unknown[]) => (await all<T>(sql, ...binds))[0];

  const activeOn = (from: string) =>
    one<{ n: number }>(`SELECT COUNT(DISTINCT install_id) AS n FROM events WHERE day >= ? AND ${s.sql}`, from);

  const [installs, newInRange, activeToday, active7, active30] = await Promise.all([
    one<{ n: number }>(`SELECT COUNT(*) AS n FROM installs WHERE ${s.sql}`),
    one<{ n: number }>(`SELECT COUNT(*) AS n FROM installs WHERE first_seen >= ? AND ${s.sql}`, since),
    activeOn(today),
    activeOn(isoDay(Date.now() - 6 * DAY_MS)),
    activeOn(isoDay(Date.now() - 29 * DAY_MS)),
  ]);

  const daily = await all<{ day: string; active: number }>(
    `SELECT day, COUNT(DISTINCT install_id) AS active FROM events WHERE day >= ? AND ${s.sql}
     GROUP BY day ORDER BY day`, since);
  const newDaily = await all<{ day: string; n: number }>(
    `SELECT substr(first_seen, 1, 10) AS day, COUNT(*) AS n FROM installs WHERE first_seen >= ? AND ${s.sql}
     GROUP BY day ORDER BY day`, since);
  // Older than the raw window: what the nightly rollup kept.
  const archived = await env.DB.prepare(
    `SELECT day, value FROM daily_rollups WHERE metric = 'active' AND day >= ? ORDER BY day`
  ).bind(since).all<{ day: string; value: number }>().then((r) => r.results);

  const propCount = (name: string, prop: string) =>
    all<{ key: string; n: number }>(
      `SELECT json_extract(props, '$.${prop}') AS key, COUNT(DISTINCT install_id) AS n FROM events
       WHERE name = ? AND day >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`, name, since);

  const [funnel, completed, styles, triggers, feedback, versions, permissions] = await Promise.all([
    propCount("onboarding_step_viewed", "step"),
    one<{ n: number }>(`SELECT COUNT(DISTINCT install_id) AS n FROM events
                        WHERE name = 'onboarding_completed' AND day >= ? AND ${s.sql}`, since),
    propCount("onboarding_style_selected", "mode"),
    all<{ key: string; n: number }>(
      `SELECT json_extract(props, '$.trigger') AS key, COUNT(*) AS n FROM events
       WHERE name = 'notch_opened' AND day >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`, since),
    all<{ key: string; n: number }>(
      `SELECT json_extract(props, '$.category') AS key, COUNT(*) AS n FROM events
       WHERE name = 'feedback_sent' AND day >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`, since),
    all<{ key: string; n: number }>(
      `SELECT last_version AS key, COUNT(*) AS n FROM installs WHERE last_seen >= ? AND ${s.sql}
       GROUP BY key ORDER BY key DESC`, since),
    all<{ key: string; n: number }>(
      `SELECT json_extract(props, '$.perm') || ':' || json_extract(props, '$.result') AS key,
              COUNT(DISTINCT install_id) AS n FROM events
       WHERE name = 'onboarding_permission' AND day >= ? AND ${s.sql} GROUP BY key ORDER BY n DESC`, since),
  ]);

  const usage = await all<{ key: string; n: number }>(
    `SELECT name AS key, COUNT(*) AS n FROM events WHERE day >= ? AND ${s.sql}
     AND name IN ('todo_created','todo_completed','note_created','step_added','section_created',
                  'shortcut_used','meeting_alert_shown','calendar_connected')
     GROUP BY name ORDER BY n DESC`, since);

  return {
    days, since,
    totals: {
      installs: installs?.n ?? 0,
      new_in_range: newInRange?.n ?? 0,
      active_today: activeToday?.n ?? 0,
      active_7d: active7?.n ?? 0,
      active_30d: active30?.n ?? 0,
      onboarding_completed: completed?.n ?? 0,
      feedback_sent: feedback.reduce((sum, row) => sum + row.n, 0),
    },
    daily, new_daily: newDaily, archived,
    funnel, styles, triggers, feedback, versions, permissions, usage,
  };
}

// MARK: Nightly

async function rollup(env: Env, day: string): Promise<void> {
  const s = scope(env);
  const active = await env.DB.prepare(
    `SELECT COUNT(DISTINCT install_id) AS n FROM events WHERE day = ? AND ${s.sql}`
  ).bind(day, ...s.binds).first<{ n: number }>();
  const byName = await env.DB.prepare(
    `SELECT name, COUNT(*) AS n FROM events WHERE day = ? AND ${s.sql} GROUP BY name`
  ).bind(day, ...s.binds).all<{ name: string; n: number }>();
  const put = env.DB.prepare(
    `INSERT INTO daily_rollups (day, metric, dim, value) VALUES (?, ?, ?, ?)
     ON CONFLICT(day, metric, dim) DO UPDATE SET value = excluded.value`);
  await env.DB.batch([
    put.bind(day, "active", "", active?.n ?? 0),
    ...byName.results.map((row) => put.bind(day, "events", row.name, row.n)),
  ]);
}

// MARK: Helpers

function isoDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
