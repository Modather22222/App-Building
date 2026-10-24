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
- [~] Real device smoke test on Android (release APK from `latest-build` release)
  - First installable attempt hit a **launch white screen**: Flutter's Gradle plugin force-enables R8
    minification for release builds; shared_preferences_android ships no consumer-rules.pro, so R8
    renamed plugin methods that pigeon's dispatcher resolves reflectively → NoSuchMethodError on the
    first `SharedPreferences.getInstance()` in main() → app never reached first frame. Verified by
    dex-string analysis of the CI APK (legacy plugin class stripped) + logcat. Fix: `isMinifyEnabled =
    false` in release buildType + defensive try/catch fallback around prefs init (in-memory degrade).
    Re-enable shrinking only with proper -keep rules during Phase 5 hardening.
- [ ] App icon + splash assets (default Flutter icon in place; replace before any public build)
- [ ] Accessibility pass: Dynamic Type 135%, screen-reader labels, contrast check on status pills

## Phase 2 — Backend & real persistence

- [ ] Choose backend (lean pick: Supabase — auth + Postgres + storage)
- [ ] Swap mock auth for real email/OTP auth; keep guest mode dev-only
- [ ] Database schema: users, chats, messages, projects, build_runs, token_ledger (build/edit credits), queue_state
- [ ] Persist chats/projects server-side; merge local session
- [ ] Billing: Stripe subscriptions (Starter/Pro/Scale) + refill packs; enforce via token counters
- [ ] Plan enforcement: app slots, clean-build tokens, edit tokens (runners documented in Phase 0)

## Phase 3 — Codegen pipeline (OpenCode agent)

- [ ] Per-build repo creation via GitHub API (naming: `af-<user>-<slug>-<id>`)
- [ ] OpenCode headless run with product prompt templates → full Flutter project files
- [ ] Spec refinement loop in chat (agent proposes plan → user confirms → edits tracked as edit Tokens)
- [ ] Push code to repo; commit generated code (no repo-long-lived secrets)
- [ ] Structured progress events → backend → app (replace the simulation timers)
- [ ] Artifact conventions: APK path + versioning known to the CI workflow

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
