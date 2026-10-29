// App Building — request-build edge function.
//
// The app calls this when the user confirms "Build this app" (or retries a
// failed project). It validates the caller's JWT, checks the project row
// belongs to them, enforces the plan's monthly build limit, then dispatches
// factory-worker.yml on the factory repo.
//
// Secrets (set in Supabase function secrets):
//   FACTORY_DISPATCH_TOKEN — fine-grained PAT, Actions:write ONLY, repo-scoped
//     to the factory repo (Phase 5: the least-privilege dispatch token)
//   FACTORY_GH_PAT   — legacy classic PAT fallback (kept until rotation)
//   FACTORY_MODEL    — optional override of the codegen model id
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://esm.sh/@sentry/deno@10";

// Phase 7 — crash reporting, gated on the SENTRY_DSN function secret
// (unset = fully disabled).
const SENTRY_DSN = Deno.env.get("SENTRY_DSN");
if (SENTRY_DSN) {
  Sentry.init({ dsn: SENTRY_DSN, environment: "production" });
}

const FACTORY_REPO = "Modather22222/App-Building";
const WORKFLOW = "factory-worker.yml";
// CLI-format model ref (provider/model). Bare ids break opencode's model
// resolution with a cryptic server-side UnknownError — always prefix here.
const DEFAULT_MODEL = "opencode/glm-5.3-flash";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// Worker-owned columns get the truth even when the WORKER never runs —
// refusal paths (not configured, dispatch failure) write the failure back
// so no project row is ever left spinning.
async function failRow(
  admin: ReturnType<typeof createClient>,
  id: string,
  message: string,
): Promise<void> {
  await admin
    .from("projects")
    .update({ status: "failed", error: message })
    .eq("id", id);
}

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

  // verify_jwt is on at the gateway too; this resolves the user id.
  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  let projectId = "";
  try {
    const body = (await req.json()) as { project_id?: string };
    projectId = body.project_id ?? "";
  } catch (_) {
    /* fallthrough to the required check below */
  }
  if (!projectId) {
    return json({ error: "project_id is required" }, 400);
  }

  // Phase 6 B1 — same charset the worker and the DB CHECK enforce. The id
  // flows into file paths, release tags and workflow-dispatch inputs; reject
  // anything that could escape those contexts before any DB or GitHub work.
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(projectId)) {
    return json({ error: "invalid project_id" }, 400);
  }

  const { data: project, error: projectErr } = await admin
    .from("projects")
    .select("id, user_id, status, dispatched_at")
    .eq("id", projectId)
    .maybeSingle();
  if (projectErr) {
    if (SENTRY_DSN) Sentry.captureException(projectErr);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!project) {
    return json({ error: "Project not found" }, 404);
  }
  if (project.user_id !== userData.user.id) {
    return json({ error: "Not your project" }, 403);
  }
  if (project.status === "ready") {
    return json({ ok: true, already: "ready" }, 200);
  }

  // Phase 5 — idempotency guard. 'generating' is ambiguous (a fresh
  // pre-dispatch row vs the worker's first active stage), so the truth lives
  // in dispatched_at: set exactly when THIS function claims a row, cleared by
  // the app's resetForRetry. A row already in flight (dispatched, pushing,
  // queued, building — or generating with a dispatch stamp) must not
  // re-dispatch: that would race two identical worker runs.
  const inflight =
    ["dispatched", "pushing", "queued", "building"].includes(project.status) ||
    (project.status === "generating" && project.dispatched_at !== null);
  if (inflight) {
    return json({ ok: true, already: "in-flight" }, 200);
  }

  // Atomic claim: the conditional update IS the race lock. Two concurrent
  // callers for the same row can both pass the checks above; exactly one
  // claim (matching generating-without-stamp or failed) returns a row and
  // only that caller dispatches. The loser sees 0 rows and reports already.
  const { data: claimed, error: claimErr } = await admin
    .from("projects")
    .update({
      status: "dispatched",
      dispatched_at: new Date().toISOString(),
      error: null,
    })
    .or("and(status.eq.generating,dispatched_at.is.null),status.eq.failed")
    .eq("id", projectId)
    .select("id");
  if (claimErr) {
    if (SENTRY_DSN) Sentry.captureException(claimErr);
    return json({ error: "Claim failed" }, 500);
  }
  if (!claimed || claimed.length === 0) {
    return json({ ok: true, already: "in-flight" }, 200);
  }

  // Phase 5 — abuse guard: per-user build rate (factory_settings
  // ['rate_build_hour'], default 6/hour). Checked after the idempotent paths
  // so double-taps never get rate-bumped, before the LLM/runner spend.
  {
    const { error: rateErr } = await admin.rpc("assert_rate_ok", {
      p_user: userData.user.id,
      p_action: "build",
    });
    if (rateErr) {
      await failRow(admin, projectId, rateErr.message);
      return json({ error: rateErr.message }, 429);
    }
  }

  // NOTE: plan quota is enforced at INSERT time by the DB trigger
  // private.enforce_project_quota() — unforgeable and retry-friendly.
  // This function only owns auth, ownership, and dispatch.

  // Token order: FACTORY_DISPATCH_TOKEN (fine-grained PAT, Actions:write only,
  // repo-scoped to the factory repo — the least-privilege dispatch token this
  // function exists to hold) → FACTORY_GH_PAT (classic, broad) fallback so the
  // pipeline keeps running until the owner rotates. Phase 5: no BROAD PAT
  // required on the dispatch path anymore.
  const pat = Deno.env.get("FACTORY_DISPATCH_TOKEN") ||
    Deno.env.get("FACTORY_GH_PAT");
  if (!pat) {
    await failRow(
      admin,
      projectId,
      "The factory is not configured yet (missing FACTORY_DISPATCH_TOKEN)",
    );
    return json(
      { error: "The factory is not configured yet (missing FACTORY_DISPATCH_TOKEN)" },
      503,
    );
  }

  // Model resolution order: DB factory_settings.model → env FACTORY_MODEL →
  // DEFAULT_MODEL. Any format works — the worker normalizes bare to prefixed.
  let model = Deno.env.get("FACTORY_MODEL") || DEFAULT_MODEL;
  {
    const { data: settings } = await admin
      .from("factory_settings")
      .select("key, value");
    const dbModel = (settings ?? []).find((s) => s.key === "model")?.value;
    if (dbModel && dbModel.trim()) model = dbModel.trim();
  }

  // repository_dispatch — the Phase 4 integration point: the worker workflow
  // subscribes to `build-requested` and reads client_payload, so the backend
  // never needs to know workflow file names or input shapes.
  const dispatch = await fetch(
    `https://api.github.com/repos/${FACTORY_REPO}/dispatches`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${pat}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        event_type: "build-requested",
        client_payload: { project_id: projectId, model },
      }),
    },
  );

  if (!dispatch.ok) {
    const detail = await dispatch.text().catch(() => "");
    if (SENTRY_DSN) {
      Sentry.captureMessage(`Factory dispatch failed (${dispatch.status})`, {
        level: "error",
        extra: { detail, projectId },
      });
    }
    await failRow(
      admin,
      projectId,
      `Factory dispatch failed (${dispatch.status})`,
    );
    return json(
      { error: `Factory dispatch failed (${dispatch.status})`, detail },
      502,
    );
  }

  // The claim above already flipped the row to 'dispatched' atomically —
  // the old post-dispatch update is gone (it was the double-dispatch window).

  // 204 No Content on the GitHub side — the row flips through statuses as
  // the worker runs. The app contract stays 202.
  return json({ ok: true, model }, 202);
});
