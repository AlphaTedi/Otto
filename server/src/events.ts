// The event catalogue (docs/TELEMETRY.md §3.5), mirrored from the app's
// `AnalyticsEvent`. Anything not listed here is refused, and so is any prop
// the event does not declare — the server is the second lock on the rule
// "no user content ever": even a bug in the app cannot store free text,
// because every string value must look like an enum case.

export type PropType = "enum" | "bool" | "int";

export const EVENTS: Record<string, Record<string, PropType>> = {
  app_launched: { kind: "enum" },
  app_active_day: {},
  update_installed: { from: "enum", to: "enum" },

  onboarding_started: {},
  onboarding_step_viewed: { step: "enum" },
  onboarding_step_completed: { step: "enum", duration_ms: "int" },
  onboarding_discover_viewed: { item: "enum" },
  onboarding_style_selected: { mode: "enum" },
  onboarding_shortcut_fired: { attempts: "int" },
  onboarding_shortcut_skipped: { reason: "enum" },
  onboarding_permission: { perm: "enum", result: "enum" },
  onboarding_completed: { total_ms: "int" },
  onboarding_abandoned: { last_step: "enum" },

  notch_opened: { trigger: "enum", layout: "enum" },
  notch_closed: { reason: "enum", open_ms: "int", interacted: "bool" },
  panel_mode_entered: { mode: "enum" },

  todo_created: { source: "enum", has_due_date: "bool", in_today: "bool" },
  todo_completed: { source: "enum", age: "enum" },
  todo_deleted: {},
  step_added: {},
  step_completed: {},
  section_created: { total: "enum" },
  space_switched: { method: "enum" },
  note_created: { kind: "enum" },

  meeting_alert_shown: { lead: "enum" },
  calendar_connected: { provider: "enum" },

  shortcut_used: { action: "enum" },
  shortcuts_overlay_opened: {},
  settings_changed: { key: "enum", value: "enum" },

  feedback_opened: { source: "enum" },
  feedback_sent: { category: "enum", attachments: "int", diagnostics: "bool" },

  error: { domain: "enum", code: "int" },
};

/** Enum-shaped: lowercase words, digits, `_ . -`. Never a sentence. */
const ENUM = /^[a-z0-9][a-z0-9_.\-]{0,39}$/;

export type Props = Record<string, string | number | boolean>;

/** The event's props if they obey its declaration, otherwise null. */
export function validateProps(name: string, props: unknown): Props | null {
  const spec = EVENTS[name];
  if (!spec) return null;
  if (props === undefined || props === null) return {};
  if (typeof props !== "object" || Array.isArray(props)) return null;
  const out: Props = {};
  for (const [key, value] of Object.entries(props as Record<string, unknown>)) {
    const type = spec[key];
    if (!type) return null;
    if (type === "enum" && typeof value === "boolean") { out[key] = value; continue; } // settings_changed
    if (type === "enum" && typeof value === "number" && Number.isInteger(value)) { out[key] = value; continue; }
    if (type === "enum" && (typeof value !== "string" || !ENUM.test(value))) return null;
    if (type === "bool" && typeof value !== "boolean") return null;
    if (type === "int" && (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 1e9)) return null;
    out[key] = value as string | number | boolean;
  }
  return out;
}

export interface Context {
  app_version: string;
  build: number;
  os: string;
  lang: string;
  layout: string;
  has_notch: boolean;
  calendar: string;
  env: "prod" | "dev";
}

const VERSION = /^[0-9]{1,3}(\.[0-9]{1,4}){0,3}$/;

export function validateContext(raw: unknown): Context | null {
  if (!raw || typeof raw !== "object") return null;
  const c = raw as Record<string, unknown>;
  const str = (v: unknown, re: RegExp) => typeof v === "string" && re.test(v);
  if (!str(c.app_version, VERSION)) return null;
  if (!str(c.os, VERSION)) return null;
  if (!str(c.lang, /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/)) return null;
  if (!str(c.layout, ENUM) || !str(c.calendar, ENUM)) return null;
  if (typeof c.build !== "number" || !Number.isInteger(c.build)) return null;
  if (typeof c.has_notch !== "boolean") return null;
  if (c.env !== "prod" && c.env !== "dev") return null;
  return c as unknown as Context;
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
