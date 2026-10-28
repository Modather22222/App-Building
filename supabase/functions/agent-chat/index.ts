// App Building — agent-chat edge function.
//
// Real planning conversation for the chat screen. The app POSTs the visible
// history (including the message just sent); the function calls the LLM and
// parses an optional trailing PLAN line into the build-action payload the UI
// already knows how to render.
//
// Secret (Supabase function secrets): OPENCODE_ZEN_KEY
// Optional: FACTORY_CHAT_MODEL (bare zen model id, e.g. deepseek-v4.1-flash-free)
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ZEN_URL = "https://opencode.ai/zen/v1/chat/completions";
const DEFAULT_MODEL = "deepseek-v4.1-flash-free";

const SYSTEM = `You are the App Building agent inside a mobile app that builds Flutter apps.
Rules:
- Chat briefly, warm, practical. Ask at most ONE clarifying question per turn.
- As soon as the request is concrete enough (main screens + features clear), end your reply with a final line EXACTLY in this format:
PLAN: <short app name> | <one-sentence description of the app to build>
- Propose the plan promptly; don't drag out clarification for simple requests.
- Keep replies under 120 words. Never include code in chat.
- Generated apps run on Flutter stable 3.47, Material 3, work offline, use only pub.dev packages, no binary assets (icons/emoji only).
- Refuse (reply WITHOUT a PLAN line) if the app's primary purpose is surveillance or spying on people, tracking someone without their consent, harassment, stalking, malware, phishing or credential theft — briefly explain why and, when obvious, suggest a legitimate alternative.`;

// Phase 6 H-P5 — content gate (layer 2). The SYSTEM prompt refuses malicious
// requests, but prompts can be steered; every emitted plan is screened
// against high-signal abuse patterns. A hit strips the plan (no build
// button) and lands in the audit trail, which survives account deletion.
const ABUSE_PATTERNS = [
  /\bkey\s?log(ger|ging)?\b/i,
  /\bkeystroke/i,
  /\bspy(ing|ware)?\b/i,
  /\b(stealth|covert|hidden)\s+(app|cam(era)?|mic(rophone)?|recorder|monitor(ing)?|track(er|ing)?)\b/i,
  /\b(track|monitor)(ing)?\s+(someone|people|my (partner|spouse|wife|husband|girlfriend|boyfriend|ex)|employees?)\b/i,
  /\b(harass\w*|bull(y|ying|ied)|dox\w*|stalk\w*)\b/i,
  /\b(phish(ing)?|credential harvesting?)\b/i,
  /\b(password|otp|pin)\s?(steal(ing)?|grab(ber)?|crack(ing)?|bypass)\b/i,
  /\b(malware|ransomware|virus|trojan|botnet|ddos|rootkit)\b/i,
  /\b(sms|text|call|whatsapp)\s+(intercept(ion)?|sniff(ing)?|forward(ing)?)\b/i,
  /\bintercept(ion|s|ed)?\b/i,
  /\bsteal(ing)?\s+(passwords?|credentials?|otp|pins?)\b/i,
  /\bforward(ing)?\s+(incoming\s+)?(sms|texts?|messages?|calls?)\b/i,
  /\bhidden\s+(camera|photos?|recording|record)\b/i,
];

const REFUSAL_REPLY =
  "I can't help build that one — it looks designed to monitor, harass, or " +
  "harm someone, which App Building doesn't do. If you meant something " +
  "legitimate, describe the app from its user's point of view and I'll scope it.";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

type Turn = { role: "user" | "assistant"; content: string };

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  let payload: { history?: unknown };
  try {
    payload = (await req.json()) as { history?: unknown };
  } catch (_) {
    payload = {};
  }

  const turns: Turn[] = Array.isArray(payload.history)
    ? (payload.history as unknown[])
        .slice(-20)
        .map((t) => {
          const turn = t as { role?: unknown; content?: unknown };
          return {
            role: turn.role === "assistant" ? "assistant" as const : "user" as const,
            content: String(turn.content ?? "").slice(0, 4000),
          };
        })
        .filter((t) => t.content.trim().length > 0)
    : [];

  if (turns.length === 0) {
    return json({ error: "history must contain at least one turn" }, 400);
  }

  // Phase 5 — abuse guard: per-user chat rate limit (dashboard-tunable via
  // factory_settings['rate_chat_hour'], default 40/hour). The count happens
  // before any LLM spend.
  {
    const { error: rateErr } = await admin.rpc("assert_rate_ok", {
      p_user: userData.user.id,
      p_action: "chat",
    });
    if (rateErr) {
      return json({ error: rateErr.message }, 429);
    }
  }

  const key = Deno.env.get("OPENCODE_ZEN_KEY");
  if (!key) {
    return json(
      { error: "Chat agent is not configured yet (missing OPENCODE_ZEN_KEY)" },
      503,
    );
  }

  // Model resolution order: DB factory_settings.model → env FACTORY_CHAT_MODEL
  // → DEFAULT_MODEL. The DB stores one bare id shared with codegen; the raw
  // REST API needs it unprefixed, so strip a provider prefix if present.
  let model = Deno.env.get("FACTORY_CHAT_MODEL") || DEFAULT_MODEL;
  {
    const { data: settings } = await admin
      .from("factory_settings")
      .select("key, value");
    const dbModel = (settings ?? []).find((s) => s.key === "model")?.value;
    if (dbModel && dbModel.trim()) {
      model = dbModel.trim().replace(/^opencode\//, "");
    }
  }

  const body = {
    model: model, // the RESOLVED id (DB → env → default). The old inline
    // re-resolution ignored the DB and pinned chat to the drained free
    // model — 429 on every turn once the free pool emptied.
    messages: [{ role: "system", content: SYSTEM }, ...turns],
    max_tokens: 700,
    temperature: 0.4,
  };

  let llm: {
    choices?: Array<{ message?: { content?: string } }>;
  };
  try {
    const r = await fetch(ZEN_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60000),
    });
    if (!r.ok) {
      const detail = (await r.text().catch(() => "")).slice(0, 300);
      return json({ error: `Agent model error (${r.status})`, detail }, 502);
    }
    llm = (await r.json()) as typeof llm;
  } catch (_) {
    return json({ error: "Agent model unreachable" }, 504);
  }

  const text = llm?.choices?.[0]?.message?.content ?? "";
  if (!text.trim()) {
    return json({ error: "Empty agent reply" }, 502);
  }

  // Pull the last PLAN: line out of the reply, if the model proposed one.
  let plan: { app_name: string; summary: string } | null = null;
  const lines = text.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const m = lines[i].match(/^PLAN:\s*(.+?)\s*\|\s*(.+?)\s*$/);
    if (m) {
      plan = { app_name: m[1].slice(0, 60), summary: m[2].slice(0, 200) };
      lines.splice(i, 1);
      break;
    }
  }
  const reply = lines.join("\n").trim();

  // Phase 6 H-P5 — screen + audit every emitted plan. The audit write is
  // best-effort: it must never break the chat.
  if (plan) {
    const lastUser = [...turns].reverse().find((t) => t.role === "user")?.content ?? "";
    const screened = `${plan.app_name} ${plan.summary} ${lastUser}`;
    const hit = ABUSE_PATTERNS.find((p) => p.test(screened)) ?? null;
    try {
      await admin.from("plan_audit").insert({
        user_id: userData.user.id,
        app_name: plan.app_name,
        summary: plan.summary,
        prompt_snippet: lastUser.slice(0, 500),
        decision: hit ? "blocked" : "allowed",
        reason: hit ? hit.source : null,
      });
    } catch (_) { /* audit is best-effort */ }
    if (hit) {
      return json({ reply: REFUSAL_REPLY, plan: null });
    }
  }

  return json({ reply, plan });
});
