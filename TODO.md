# App Factory — Master TODO

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
- [ ] Queue watchdog: rows stuck in generating > 30 min get flagged/dead-lettered
- [x] Real agent chat — `agent-chat` edge function + `AgentChatService` through the ReplyChunk
      contract; **live-verified 2026-10-26**: two-turn real conversation, plan proposal + parse ✓
      (3.7–5.3 s latency), backend-less mock fallback intact
- [x] Model economics resolved: free pool is account-level (drained) → paid `glm-5.3-flash`
      default on the funded key; error surfacing fixed (raw HttpClient — real reasons in chat)
- [ ] True SSE streaming for chat replies (replace the wait-then-type feel)
- [ ] Persist plan proposals (name/summary) on the message row so they survive reinstall

## Phase 4 — GitHub Actions build & delivery

- [x] Workflow: ubuntu-latest, Flutter 3.47.7 (pinned), Gradle cache, `timeout-minutes: 20`, analyze + test gates — first run patched green in 8m36s (build succeeded)
- [x] Delivery: rolling **`latest-build` release asset** per run (`--clobber` overwrite). Artifact-upload route was abandoned: the shared 500 MB personal storage quota is full (scan showed 0 MB of Actions caches/artifacts across all 86 repos → suspected old GitHub Packages containers; gh token lacks `read:packages` to confirm). Release storage is separate and effectively unlimited.
- [ ] Trigger via `repository_dispatch` from backend; poll `runs` API; map statuses to app states
- [ ] Queue UX: pre-existing queue banner (done in mock) now fed by real Automation concurrency data
- [ ] Download screen: direct install link to `releases/download/latest-build/app-release.apk` + build id/size info

## Phase 5 — Hardening & launch prep

- [ ] Secrets: scoped GitHub token per operation (repo create/dispatch/artifact) — no broad PAT in app
- [ ] Abuse guards: rate limits per user, spam detection on chat, spending-limit alerts
- [ ] Failure taxonomy: maps CI errors → plain-language chat replies for users
- [ ] Telemetry: activation funnel (onboard → first chat → first build → first download)
- [ ] Play Store / direct-APK distribution decision; privacy policy + terms
- [ ] Beta: 10–20 Flutter devs, collect feedback on plan sizes and agent quality

## Known gaps in the current MVP build (by design)

| Gap | Reason | Lands in |
|---|---|---|
| Sign-in is local-only | No backend yet | Phase 2 |
| Pipeline is simulated with timers | No OpenCode + Actions wiring yet | Phase 3/4 |
| APK download link is a placeholder | No artifact storage yet | Phase 4 |
| Usage meters show demo data | Token metering needs DB + billing | Phase 2 |
| Default Flutter app icon/splash | Brand assets not decided yet | Phase 5 |
