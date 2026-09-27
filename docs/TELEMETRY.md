# Otto telemetry and feedback

Anonymous, opt-in usage counts, so Marcello can see how many people use Otto,
how they get through the onboarding and how they open the notch. Built from
the "Telemetria, Update e Feedback" PRD (2026-09-27), trimmed to what was
decided: no appcast proxy yet (the Sparkle feed stays on raw GitHub until
there is a domain), and feedback by email rather than through the server.

## The rule

**No user content ever leaves the Mac.** To-dos, notes, steps, list names,
calendar events and feedback text stay local. Two locks enforce it:

1. In the app, `AnalyticsEvent` is a closed enum whose props are enum raw
   values, Bools, Ints and buckets (`AnalyticsValue`). No case takes a string
   the user typed.
2. On the server, `server/src/events.ts` whitelists every event and its props,
   and every string value must look like an enum case (`^[a-z0-9][a-z0-9_.-]{0,39}$`).
   A sentence is refused with a 400.

Change the catalogue in both files together.

## Consent

`AppSettings.analyticsConsent`: `nil` = never asked, `.granted`, `.denied`.
Opt-in — nothing is sent unless it is `.granted`.

- Onboarding, permissions step: "Share anonymous usage data" switch, off by
  default (key `U`). Finishing without touching it records `.denied`.
- People who update without seeing the onboarding get a one-time card in the
  panel (`ConsentCard`): ⏎ shares (only while the draft is empty), Esc declines.
- Settings › General › Privacy: the switch, "Show what is sent" (the queue
  file), "Reset ID", and the full anonymous ID to quote for deletion.

Before the question is answered, events wait in memory only (so a yes on the
permissions step can still send the onboarding's own funnel); a no or a quit
drops them. The lab build never sends (`AppBuild.analyticsEnabled`).

## App side

- `NotchSnap/App/AnalyticsEvent.swift` — the catalogue.
- `NotchSnap/App/Analytics.swift` — `Analytics.track`, consent, identity,
  `AnalyticsQueue` (JSONL in Application Support, flushed every 60 s / at 20
  events / on quit, batches of 100, exponential back-off to 1 h, capped at
  2,000 events or 7 days), `ConsentCard`.
- Config: `OTTO_SERVICE_HOST` and `OTTO_SERVICE_KEY` in `Config/Local.xcconfig`
  (host without `https://` — `//` starts a comment in an xcconfig). Blank host:
  nothing is ever sent.
- DEBUG: `analytics-dump`, `analytics-consent yes|no|reset`, `analytics-flush`.

## Server (`server/`)

Cloudflare Worker `otto-telemetry` + D1 database `otto-telemetry` in the EU
jurisdiction, free plan. <https://otto-telemetry.otto-telemetry.workers.dev>

- `POST /v1/events` — batches from the app (`X-Otto-Key` header).
- `GET /dashboard` — private dashboard; asks for `DASHBOARD_PASSWORD`.
- `GET /api/summary?days=30` — its numbers (Bearer password).
- Cron 03:00 UTC — daily rollups (kept forever), raw events deleted after 90 days.
- IP addresses are never stored. `env = dev` (Debug builds) is excluded from
  every number; so are the IDs in `EXCLUDED_INSTALLS` (wrangler.toml).

Operations (Node is in `~/.local/node`):

```bash
cd server
npx wrangler deploy                              # publish a change
npx wrangler secret put DASHBOARD_PASSWORD       # set/replace the dashboard password
npx wrangler d1 execute otto-telemetry --remote --file=schema.sql
```

## Feedback

"Send feedback" in the gear menu opens `FeedbackWindowController`: category,
description (required), up to 5 attachments, "Include diagnostic info". Send
hands everything to the user's mail app (`NSSharingService.composeEmail`),
addressed to `OTTO_FEEDBACK_EMAIL`; without a mail account the text is copied
instead. Nothing is uploaded. The item is hidden while `OTTO_FEEDBACK_EMAIL` is
blank. With consent, `feedback_sent` records the category and the number of
attachments — never the words.
