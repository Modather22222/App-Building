// App Factory — request-build edge function.
//
// The app calls this when the user confirms "Build this app" (or retries a
// failed project). It validates the caller's JWT, checks the project row
// belongs to them, enforces the plan's monthly build limit, then dispatches
// factory-worker.yml on the factory repo.
//
// Secrets (set in Supabase function secrets):
//   FACTORY_GH_PAT   — classic PAT with repo+workflow scope, for dispatching
//   FACTORY_MODEL    — optional override of the codegen model id
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

  const { data: project, error: projectErr } = await admin
    .from("projects")
    .select("id, user_id, status")
    .eq("id", projectId)
    .maybeSingle();
  if (projectErr) {
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

  // NOTE: plan quota is enforced at INSERT time by the DB trigger
  // private.enforce_project_quota() — unforgeable and retry-friendly.
  // This function only owns auth, ownership, and dispatch.

  const pat = Deno.env.get("FACTORY_GH_PAT");
  if (!pat) {
    await failRow(
      admin,
      projectId,
      "The factory is not configured yet (missing FACTORY_GH_PAT)",
    );
    return json(
      { error: "The factory is not configured yet (missing FACTORY_GH_PAT)" },
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

  // Phase 4: mark the dispatch-wait. The row sits 'dispatched' until the
  // worker job actually starts (GitHub queues it against the account's
  // concurrency ceiling); the worker's first stage patch flips it to
  // 'generating'. DB-true queue visibility for the app banner.
  await admin.from("projects").update({ status: "dispatched" }).eq("id", projectId);

  // 204 No Content on the GitHub side — the row flips through statuses as
  // the worker runs. The app contract stays 202.
  return json({ ok: true, model }, 202);
});
