// Otto's monitoring Worker (docs/TELEMETRY.md).
//
//   POST /v1/events   — anonymous event batches from the app (opt-in only)
//   POST /v1/feedback — a feedback message, forwarded by email, never stored
//   GET  /dashboard, /dashboard/app, /dashboard/website
//                     — Marcello's private dashboard (password in a secret):
//                       overview, the app install by install, the website
//   GET  /api/summary?range=24h — the app's numbers
//   GET  /api/install?id=…      — one install's events, for its timeline
//   GET  /api/site?range=24h    — the website's, read from its own D1 (SITE)
//   cron 03:00 UTC    — daily rollups, 90-day raw retention
//
// What it never does: store an IP address, receive a to-do, a note or a
// calendar event. Feedback is the one message a user writes to us on purpose:
// it is relayed to Marcello's inbox through Resend and not kept here — no
// table holds it, attachments included.

import { relayFeedback } from "./feedback";

import { EVENTS, UUID, validateContext, validateProps } from "./events";
import { appHTML, overviewHTML, websiteHTML } from "./pages";
import { appSummary, installTimeline, parseRange, scope, siteSummary } from "./stats";

export interface Env {
  DB: D1Database;
  /** otto-site-stats: the website's daily totals, written by the otto-site Worker, only read here. */
  SITE?: D1Database;
  OTTO_KEY: string;
  EXCLUDED_INSTALLS: string;
  DASHBOARD_PASSWORD?: string;
  RESEND_API_KEY?: string;
  FEEDBACK_TO: string;
}

const PAGES: Record<string, string> = {
  "/dashboard": overviewHTML,
  "/dashboard/app": appHTML,
  "/dashboard/website": websiteHTML,
};

const MAX_EVENTS = 100;
const MAX_BODY = 64 * 1024;
const DAY_MS = 86_400_000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/events" && request.method === "POST") return await ingest(request, env);
      if (url.pathname === "/v1/feedback" && request.method === "POST") {
        if (request.headers.get("x-otto-key") !== env.OTTO_KEY) return json({ error: "bad key" }, 403);
        const result = await relayFeedback(request, env);
        return json(result.body, result.status);
      }
      const page = PAGES[url.pathname];
      if (page && request.method === "GET") {
        return new Response(page, {
          headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store",
                     "x-robots-tag": "noindex" },
        });
      }
      if (url.pathname.startsWith("/api/") && request.method === "GET") {
        if (!authorized(request, env)) return json({ error: "unauthorized" }, 401);
        const range = parseRange(url.searchParams.get("range"));
        if (url.pathname === "/api/summary") return json(await appSummary(env, range));
        if (url.pathname === "/api/site") {
          if (!env.SITE) return json({ error: "site stats not bound" }, 503);
          return json(await siteSummary(env.SITE, range));
        }
        if (url.pathname === "/api/install") {
          const id = url.searchParams.get("id") ?? "";
          if (!UUID.test(id)) return json({ error: "bad id" }, 400);
          const timeline = await installTimeline(env, id);
          return timeline ? json(timeline) : json({ error: "not found" }, 404);
        }
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
