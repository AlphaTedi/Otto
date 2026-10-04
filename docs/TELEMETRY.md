# Otto telemetry and feedback

Anonymous, opt-in usage counts, so Marcello can see how many people use Otto,
how they get through the onboarding and how they open the notch. Built from
the "Telemetria, Update e Feedback" PRD (2026-09-27), trimmed to what was
decided: no appcast proxy yet (the Sparkle feed stays on raw GitHub until
there is a domain), and feedback relayed by email rather than stored.

## The rule

**No user content ever leaves the Mac** — with one deliberate exception: a
feedback the user writes and sends to us. To-dos, notes, steps, list names and
calendar events stay local. Two locks enforce it for telemetry:

1. In the app, `AnalyticsEvent` is a closed enum whose props are enum raw
   values, Bools, Ints and buckets (`AnalyticsValue`). No case takes a string
   the user typed.
2. On the server, `server/src/events.ts` whitelists every event and its props,
   and every string value must look like an enum case (`^[a-z0-9][a-z0-9_.-]{0,39}$`).
   A sentence is refused with a 400.

Change the catalogue in both files together.

## Consent

`AppSettings.analyticsConsent`: `nil` = never asked, `.granted`, `.denied`.
Nothing is sent unless it is `.granted`.

- Onboarding, permissions step ("Connect your day"): a "Share usage data"
  switch, **on by default** (Marcello, 2026-09-27; key `U`). Its state is
  recorded when the flow finishes. Asked once — never again after updates.
- People who update without seeing the onboarding are not asked and stay at
  `nil`: nothing of theirs is sent unless they turn it on in Settings. (A
  one-time panel card existed for them in 1.65.0 and was removed.)
- Settings › General › Privacy: the switch, "Show what is sent" (the queue
  file), "Reset ID", and the full anonymous ID to quote for deletion.
- Note: under EU case law (CJEU Planet49, 2019) a pre-ticked box is not valid
  consent for device identifiers. Accepted knowingly for now; an unticked
  default is the compliant alternative.

Before the question is answered, events wait in memory only (so a yes on the
permissions step can still send the onboarding's own funnel); a no or a quit
drops them. The lab build never sends (`AppBuild.analyticsEnabled`).

## App side

- `Otto/Telemetry/AnalyticsEvent.swift` — the catalogue.
- `Otto/Telemetry/Analytics.swift` — `Analytics.track`, consent, identity,
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
- `POST /v1/feedback` — relays one feedback to `FEEDBACK_TO` through Resend
  (secret `RESEND_API_KEY`), attachments ≤ 10 MB total; nothing is stored.
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
npx wrangler secret put RESEND_API_KEY           # feedback delivery
npx wrangler d1 execute otto-telemetry --remote --file=schema.sql
```

## Feedback

"Send feedback" in the gear menu opens `FeedbackWindowController`: category,
description (required), up to 5 attachments (10 MB total), optional reply
email, "Include diagnostic info". Send posts it to `/v1/feedback`; the Worker
emails it to ottoapp.feedback@gmail.com (the user's email as Reply-To) and
keeps nothing. Offline, `FeedbackOutbox` keeps it as a JSON file in
Application Support and retries at launch and every 5 minutes. Independent of
the telemetry consent; `install_id` is attached only when usage data is shared.
With consent, `feedback_sent` records the category and the number of
attachments — never the words.
