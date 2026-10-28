# App Building — Master TODO

Working copy lives in `D:\projects\app_building` (package `com.appy.app_building`).
Update checklists as work completes. Scope decisions are pinned in `DESIGN.md`.

---

## Phase 0 — Product & Architecture (done)

- [x] Concept locked: AI chat agent (Flutter app) that scopes, generates, builds and delivers MVP Flutter apps
- [x] Infrastructure decision: GitHub-only MVP (repos + Actions runners), queue UX shown to users
- [x] Cost model locked: ~15 min clean build ($0.09), ~7.5 min cached edit ($0.045), 3,000 free Pro minutes ≈ 33 users
- [x] Pricing plans designed: Starter $19 / Pro $49 / Scale $129 + $9 refill packs (build+edit token gates)
- [x] Guardrails decided: GitHub spending cap, `timeout-minutes: 20`, backend polls Actions API for queue state

## Phase 1 — Flutter chat app MVP (this repo) — IN PROGRESS

### Design system
- [x] Mode: Crafted Utility (clean + trustworthy, no flash)
- [x] Tokens: indigo brand, semantic build-status colors, 4/8pt spacing, Material 3
- [x] Light + dark themes (semantic dark override, not inverted)
- [x] Thumb-zone rules: composer bottom-sticky, CTAs in bottom third, 44pt+ targets
- [x] Skeleton/empty/error state rules documented

### App shell & navigation
- [x] `flutter create .` — org `com.appy`, project `app_building`, Android + iOS
- [x] Riverpod (no codegen) + go_router (StatefulShellRoute) + shared_preferences
- [x] Router redirects: onboarding → auth → tabs
- [x] Bottom tabs: Chats / Apps / Profile (M3 NavigationBar, state preserved per tab)

### Screens
- [x] Onboarding (2 pages, skip visible, value-first)
- [x] Auth (sign in / sign up / guest — mock, pluggable for Phase 2 backend)
- [x] Chats list (FAB "New chat", empty state with ghost preview)
- [x] Chat screen (streaming agent replies, typing dots, copy on long-press, suggestion chips)
- [x] Chat → build handoff: "Build this app" action creates a project and opens its pipeline
- [x] Apps list (status pills, indeterminate progress, long-press actions incl. dev failure simulation + delete)
- [x] Project detail (status header, build-pipeline timeline card, repository/build info, sticky bottom CTA)
- [x] Profile (plan card with usage meters, appearance setting w/ live theme switch, sign out)

### State & mock pipeline
- [x] Chats/messages Riverpod providers (streaming updates, plan attach, action-used)
- [x] Projects provider with staged pipeline simulation: generate → push → queue → build → ready (+ fail/retry/remove)
- [x] MockChatService streaming chunks + plan emission (real OpenCode pipeline replaces this in Phase 3)

### App quality
- [x] `flutter analyze` clean (0 issues)
- [x] Unit test for theme semantics passing
- [x] Real device smoke test on Android (user-verified, locally built APK of a70f107 — all flows work)
  - Launch white-screen incident (resolved): Flutter's Gradle plugin force-enables R8 minification for
    release builds; shared_preferences_android ships no consumer-rules.pro, so R8 renamed plugin methods
    that pigeon's dispatcher resolves reflectively → NoSuchMethodError on the first
    `SharedPreferences.getInstance()` in main() → app never reached first frame. Verified via
    dex-string analysis of the CI APK (legacy plugin class stripped) + logcat. Fix: `isMinifyEnabled =
    false` in release buildType + defensive try/catch fallback around prefs init (in-memory degrade).
    Re-enable shrinking only with proper -keep rules during Phase 5 hardening.
  - NOTE: local builds and CI builds are both debug-signed but with DIFFERENT keystore keys — installing
    the release APK over the locally built one will fail with "App not installed" unless the local one
    is uninstalled first (expected, not a bug).
- [ ] App icon + splash assets (default Flutter icon in place; replace before any public build)
- [ ] Accessibility pass: Dynamic Type 135%, screen-reader labels, contrast check on status pills

## Phase 2 — Backend & real persistence

- [x] Choose backend (lean pick: Supabase — auth + Postgres + storage) — project ref `loeaiuktjmhxeoxpyqjl`,
      wired into `opencode.json` (remote MCP); publishable key in GitHub secret `SUPABASE_ANON_KEY`
- [x] Swap mock auth for **email + password** (user decision: no guest mode) — `AuthState` now driven by
      Supabase sessions (`onAuthStateChange`), sign-up detects email-confirmation requirement
- [x] Database schema slice 1: profiles (+ auto-create trigger in private schema), chats, messages — RLS
      owner-only; billing columns locked (table-level revoke, then `GRANT UPDATE (display_name)`),
      bootstrap `rls_auto_enable()` revoked from PUBLIC; corrective migration `phase2_security_lockdown`
- [x] Persist chats server-side (user turns + final assistant turns mirrored; streaming/plan/live state
      stays local) — bootstraps from DB with in-memory degrade; projects/build rows land in the next slice
      with the pipeline (Phase 3/4). **Device-verified 2026-10-25: signup → chat → uninstall + reinstall →
      history restored**
- [ ] Billing: Stripe subscriptions (Starter/Pro/Scale) + refill packs; enforce via token counters
- [ ] Plan enforcement: app slots, clean-build tokens, edit tokens (runners documented in Phase 0)

## Phase 3 — Codegen pipeline (OpenCode agent)

- [x] Projects schema slice (`phase3_projects` migration + RLS all-own) — TEXT id, worker-owned
      repo/apk_url/error columns, `stage_times` jsonb feeding the timeline
- [x] Cloud codegen runner: `factory-worker.yml` + `scripts/worker.sh` — opencode headless generates
      sources only; `templates/app/build.yml` scaffolds Android (flutter create) + baked known-good
      fixes; public repo `af-<slug>-<id>` per app; poll loop flips statuses; ERR-trap → failed+error
- [x] `request-build` edge function deployed (verify_jwt on; ownership/ready checks e2e-verified)
- [~] Live pipeline verification — all 4 secrets set; chain exercised: codegen + repo creation +
      dispatch + poll + failure reporting all proven (2 jq bugs + a dropped `>` in the manifest sed
      fixed); generated-repo builds hit GitHub's billing gate → **all repos public now** (factory
      repo was briefly private and every workflow startup-failed until reverted); waiting on the
      first fully green run
- [x] Spec refinement loop (slice: agent proposes plan → user confirms) — real agent chat delivers
      this behavior now; edit-token tracking lands with billing
- [x] Plan/token meters server-side — DB trigger quota (free 3 / pro 30 per month, friendly
      refusal) + real profile card; owner bumped to `pro` for dev comfort
- [x] Queue watchdog: pg_cron sweep every 10 min auto-fails rows stalled > 30 min
      (`phase3_reliability_pack`, factory-stalled-sweep cron job) + `updated_at` trigger
- [x] Real agent chat — `agent-chat` edge function + `AgentChatService` through the ReplyChunk
      contract; **live-verified 2026-10-26**: two-turn real conversation, plan proposal + parse ✓
      (3.7–5.3 s latency), backend-less mock fallback intact
- [x] Model economics resolved: free pool is account-level (drained) → paid `glm-5.3-flash`
      default on the funded key; error surfacing fixed (raw HttpClient — real reasons in chat)
- [ ] True SSE streaming for chat replies (replace the wait-then-type feel)
- [x] Persist plan proposals (name/summary) on the message row — cards survive reinstall
- [x] Stress-proven: 12 parallel builds 12/12 shipped → **monorepo** build repo
      (`app-building-outputs`, per-app folder + per-app release tag) replaced per-app repos
- [x] Multi-account build pool (`factory_accounts` + atomic LRU claim + worker self-seed):
      **20-build soak: 20/20 shipped** — final distribution Modather22222 10 · modatherclacher 5 ·
      hesab59hesba 5; first-ever builds on the two fresh accounts worked end-to-end
      (empty-repo first push, first dispatch, first releases). Failure mechanisms found and
      permanently fixed along the way:
      - rebase conflict on shared build.yml (per-app __DART__ baked in) → build.yml now
        content-identical, per-app identity travels as dispatch inputs (app_dir + dart_name;
        dart_name keeps applicationId = com.appbuilding.<dart> unique per app)
      - agent produced an incomplete project, no retry → one fresh codegen retry added
      - zombie run (in_progress 2h+, GitHub never enforced the 60-min timeout) + uncapped
        flutter-test probe hang → probe wrapped in `timeout 900`, timeout ≠ code failure
        (fails honestly: "infrastructure stall, not code"); zombie run cancelled manually
- [x] Account health + DB-managed factory account (verified live 2026-10-27):
      PAT pre-flight (identity + repo/workflow scopes) at claim; broken rows auto-quarantined
      (active=false + last_error) with re-claim — bad PAT detected in 1s, build shipped green
      on a healthy account; factory bootstrap owned by the `factory_settings` pair
      (`factory_owner`, `none` kill value + `factory_pat` in the service-only table); legacy
      GH secret auto-promoted into the pair on first build → dashboard is the single
      management surface for add/replace/rotate/disable

- [x] Identity pass — "App Factory" → "App Building" everywhere visible (shipped 2026-10-28):
  - agent says App Building: agent-chat v9 deployed (SYSTEM "You are the App Building agent…");
    seeded greeting + all "factory" copy reworded ("build service/_report_/built yet" etc.)
  - MaterialApp title → App Building (task-switcher name), auth headline, About snackbar
  - 3× app-factory-outputs repos RENAMED to app-building-outputs via GitHub API (all 3 accounts,
    +descriptions); old URLs redirect (verified 301→200) so existing APK links/cards keep working
  - worker.sh BUILD_REPO constant → app-building-outputs; commit author "App Building worker";
    workflow name "App Building worker"; release notes "generated by App Building"
  - generated apps: --org com.appbuilding ⇒ future installs are com.appbuilding.<name>
    (apps installed before this change keep com.appfactory.<name> — reinstall replaces)
  - legacy tidy: 12 old af-* repos on Modather22222 renamed ab-* (redirects); 3 stored chat
    rows updated from "I'm App Factory" → "I'm App Building"
  - internals intentionally UNCHANGED: FACTORY_* secrets/env, DB objects (factory_*,
    claim_factory_account), af- release tags, package com.appy.app_building

- [~] Chat + build-kick hardening pass (shipped 35091a4 + 8d93269, device verification pending):
  - bootstrap MERGES local turns instead of clobbering — opening a thread and sending
    before the fetch landed used to wipe the new turns (they "disappeared", then
    "reordered" back once their own insert landed + a later restore ran)
  - stable restore ordering: created_at ties no longer flap (id tiebreak)
  - assistant replies: one quiet persistence retry before degrading to memory-only
  - project-store failures surface the server's verbatim reason (no more generic-only
    "could not reach the factory" masks)
  - quota refusals are DURABLE failed rows (trigger records status=failed + refused=true +
    friendly error instead of raising) — verified live: over-limit insert returns 201 with
    the refusal recorded; refused attempts don't consume quota; meter excludes them; retry
    clears the flag
  - owner plan bumped pro→scale for dev comfort (today's 40 test rows exhausted the pro quota —
    the original "apps didn't go at all" blocker)

## Phase 4 — GitHub Actions build & delivery

- [x] Workflow: ubuntu-latest, Flutter 3.47.7 (pinned), Gradle cache, `timeout-minutes: 20`, analyze + test gates — first run patched green in 8m36s (build succeeded)
- [x] Delivery: rolling **`latest-build` release asset** per run (`--clobber` overwrite). Artifact-upload route was abandoned: the shared 500 MB personal storage quota is full (scan showed 0 MB of Actions caches/artifacts across all 86 repos → suspected old GitHub Packages containers; gh token lacks `read:packages` to confirm). Release storage is separate and effectively unlimited.
- [x] Trigger via `repository_dispatch` from backend — **verified live 2026-10-27**:
      request-build v13+ fires `build-requested` with client_payload {project_id, model};
      API e2e green (sign-in → 202 → run with event=repository_dispatch → row ready in ~6 min).
      Statuses map to app states via the DB rows (row-status polling won over runs-API polling
      during Phase 3 — the worker authors the truth)
- [x] Queue UX: real `dispatched` state — the row sits `dispatched` between a successful
      dispatch and the worker's first stage patch (GitHub-side queue wait), shown as the
      existing "Queued — Waiting for build runner" chip. Bug fixed en route: the
      `projects_status_check` constraint (fixed enum) bounced 'dispatched' writes silently
      (supabase-js resolves REST errors without throwing) — constraint now includes it
- [x] Download screen: per-app install link (the row's `apk_url` → its own release tag on the
      build repo) + real build info — worker captures `build_info {run_id, run_number, size_bytes}`
      at ready (verified live: "Build #20 · 43.1 MB"); footer wording fixed for monorepo mode.
      Poll bug fixed en route: `gh run list` field is `number`, not `runNumber` — an invalid
      field makes gh reject EVERY poll cycle, and `2>/dev/null` hid the reason for the whole
      27-min window; poll stderr is now visible in worker logs

## Phase 5 — Hardening & launch prep (map locked 2026-10-28)

Work order: each slice = implement → verify live → commit → next.

- [x] Slice 1 — Retry idempotency guard (shipped, e2e-proven):
      request-build v15 — 'generating' disambiguated by `dispatched_at` (set at claim,
      cleared by the app's resetForRetry); in-flight rows (dispatched/pushing/queued/
      building, or generating+stamp) return 200 already-in-flight without dispatching;
      the claim is an ATOMIC conditional update (generating-without-stamp or failed) so
      concurrent double-calls yield exactly ONE dispatch. Live proof: sequential
      double-tap 202 → 200 already; true concurrent race → exactly one 202; both probe
      runs cancelled pre-push (no pollution); probe cleaned up.
- [x] Slice 2 — Fail-fast error classification in worker `with_retry` (shipped, synth-proven):
      permanent errors (couldn't find remote ref, repository not found, bad credentials,
      terminal prompts disabled, workflow-scope refusal, permission denied, resource not
      accessible) return after ONE attempt instead of burning the 7m45s ladder; transient
      errors (rate limits, network) keep it; exhaustion now PRINTS the real stderr tail
      (never swallowed). 10/10 synthetic tests pass against the verbatim extracted function.
- [x] Slice 3 — Scoped dispatch token (code shipped + verified; activation = one owner step):
      request-build v16 prefers `FACTORY_DISPATCH_TOKEN` (fine-grained PAT,
      Actions:write only, repo-scoped to Modather22222/App-Building) and falls back to
      FACTORY_GH_PAT; fallback dispatch e2e re-verified live (202 + run cancelled
      pre-push). OWNER ACTIVATION RECIPE: GitHub → Settings → Developer settings →
      Fine-grained personal access tokens → Generate: repository access = Only select
      repositories → App-Building; permissions = Actions: Read and write → copy value
      into Supabase dashboard → Edge Functions → request-build → secrets as
      `FACTORY_DISPATCH_TOKEN`. Then FACTORY_GH_PAT can be dropped from the function
      secrets entirely.
- [x] Slice 4 — R8 re-enable with keep rules (shipped; device-verify pending):
      generated apps: templates/app/build.yml scaffold now wires minify + writes
      proguard-rules.pro (idempotent python edit) — keeps io.flutter.** (kills the
      pigeon reflective-dispatch white-screen family) + @Keep rules + `-dontwarn
      com.google.android.play.core.**` (engine references Play Core split-install
      classes absent from direct-APK builds — Flutter's own missing_rules.txt says
      the same); factory app: isMinifyEnabled=true + same rules — local release
      build GREEN (54.2MB universal, R8 engaged: the pre-fix build failed exactly
      at the R8 task). Owner: install a fresh CI build to device-verify launch.
- [x] Slice 5 — CI hygiene: actions/checkout v4→v5 in BOTH workflows (kills the Node20
      deprecation warnings), setup-java v5 + flutter-action v2 already current.
      NOTE: ubuntu-latest → 26.04 migration — check on the next GitHub runner-image
      announcement; nothing pinned to 24 that breaks.
- [x] Slice 6 — Abuse guards (shipped + verified):
      `assert_rate_ok(p_user, p_action)` — chat 40 msgs/hour, builds 6/hour, both
      tunable via factory_settings (rate_chat_hour / rate_build_hour) from the
      dashboard; daily-build ceiling (25+) writes private.factory_alerts rows
      (service-context only — authenticated RPC callers can't fabricate alerts).
      Hooked into agent-chat v11 + request-build v17 (after the idempotent paths,
      before LLM/runner spend; build-refusal marks the row failed for retry).
      Verified: below-limit pass, at-limit raise (friendly text), alert row at 25/day.
      En route: POSTGRES function must live in PUBLIC schema for supabase-js rpc
      (private is invisible to PostgREST) + service-role guard for alert writes.
- [x] Chat hotfix riding slice 6 — agent-chat v11: the request body re-resolved
      `FACTORY_CHAT_MODEL || DEFAULT_MODEL` inline, IGNORING the DB-resolved model —
      chat was pinned to the drained free model (429 every turn, silently broken for
      everyone once the free pool emptied). Now uses the resolved id; live-verified
      200 with a real plan proposal via paid glm-5.3-flash.
- [x] Slice 7 — Failure taxonomy (shipped; patterns prove out on the next real failure):
      on a failed build run the worker pulls the failed steps' log tail
      (gh run view --log-failed, last 200 lines) and translates: pub.dev network
      hiccup / dart compile failure / Gradle step failure / rate limiter / cancelled
      run → plain-language error on the row (run link preserved in the message tail).
- [x] Slice 8 — Telemetry funnel (shipped + verified):
      signup → first chat → first plan → first build derived SERVER-SIDE from
      existing rows (no client events); the device-only stage (download tap) logs
      funnel_events (insert-only RLS: own rows in, forged user_id rejected 403,
      select revoked, FK cascade keeps counts honest) + `funnel_view` (30-day
      windows, service-role only) — verified live: insert 201, view counts correct.
      Read the funnel: `select * from funnel_view` in the dashboard SQL editor.
- [ ] Slice 9 — Distribution & trust: direct-APK now / Play Store decision doc,
      PRIVACY.md + terms summary + link in profile screen, beta recruitment kit.

## Known gaps in the current MVP build (by design)

| Gap | Reason | Lands in |
|---|---|---|
| Sign-in is local-only | No backend yet | Phase 2 |
| Pipeline is simulated with timers | No OpenCode + Actions wiring yet | Phase 3/4 |
| APK download link is a placeholder | No artifact storage yet | Phase 4 |
| Usage meters show demo data | Token metering needs DB + billing | Phase 2 |
| Default Flutter app icon/splash | Brand assets not decided yet | Phase 5 |
