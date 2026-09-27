// POST /v1/feedback — relay one feedback message to Marcello's inbox.
//
// Nothing is written to D1 or anywhere else: the message and its attachments
// exist in this Worker only for the length of the request, then leave as an
// email through Resend (https://resend.com), from its shared sender to
// FEEDBACK_TO. The user's own email, if they gave one, becomes Reply-To.

import type { Env } from "./index";

const CATEGORIES = new Set(["bug", "idea", "love", "other"]);
const MAX_TEXT = 5000;
const MAX_FILES = 5;
const MAX_BYTES = 10 * 1024 * 1024; // all attachments together, decoded
const MAX_BODY = 15 * 1024 * 1024;  // the JSON carrying them (base64 is ~4/3)

interface Attachment { filename: string; content: string }

export async function relayFeedback(request: Request, env: Env): Promise<{ status: number; body: unknown }> {
  if (!env.RESEND_API_KEY) return { status: 503, body: { error: "feedback not configured" } };
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY) return { status: 413, body: { error: "too large" } };
  const text = await request.text();
  if (text.length > MAX_BODY) return { status: 413, body: { error: "too large" } };

  let input: any;
  try { input = JSON.parse(text); } catch { return { status: 400, body: { error: "bad json" } }; }

  const category = String(input?.category ?? "");
  const message = typeof input?.body === "string" ? input.body.trim() : "";
  if (!CATEGORIES.has(category) || !message || message.length > MAX_TEXT) {
    return { status: 400, body: { error: "bad feedback" } };
  }
  const replyTo = typeof input.email === "string" && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(input.email)
    ? input.email.slice(0, 200) : undefined;
  const diagnostics = typeof input.diagnostics === "string" ? input.diagnostics.slice(0, 2000) : "";
  const installID = typeof input.install_id === "string" ? input.install_id.slice(0, 40) : "";

  const files: Attachment[] = [];
  let bytes = 0;
  for (const file of Array.isArray(input.attachments) ? input.attachments.slice(0, MAX_FILES) : []) {
    if (typeof file?.filename !== "string" || typeof file?.content !== "string") continue;
    bytes += Math.floor(file.content.length * 3 / 4);
    if (bytes > MAX_BYTES) return { status: 413, body: { error: "attachments too large" } };
    files.push({ filename: file.filename.replace(/[\/\\]/g, "_").slice(0, 120), content: file.content });
  }

  const label: Record<string, string> = { bug: "Bug", idea: "Idea", love: "Something I like", other: "Other" };
  const lines = [message, "", "—"];
  if (diagnostics) lines.push(diagnostics);
  if (installID) lines.push(`Anonymous ID: ${installID}`);
  if (replyTo) lines.push(`Reply to: ${replyTo}`);

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: "Otto Feedback <onboarding@resend.dev>",
      to: [env.FEEDBACK_TO],
      subject: `Otto feedback · ${label[category]} · ${firstLine(message)}`,
      text: lines.join("\n"),
      reply_to: replyTo,
      attachments: files.length ? files : undefined,
    }),
  });
  if (!response.ok) {
    console.error("resend", response.status, await response.text());
    return { status: 502, body: { error: "delivery failed" } };
  }
  return { status: 200, body: { ok: true } };
}

function firstLine(text: string): string {
  const line = text.split("\n")[0].trim();
  return line.length > 60 ? line.slice(0, 57) + "…" : line;
}
