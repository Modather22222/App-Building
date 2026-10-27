# BACKEND.md — Phase 2 (Supabase)

Status: **phase 2 slice 1 shipped + device-verified; phase 3 slice 1 (real build pipeline) wired**.
Project ref: `loeaiuktjmhxeoxpyqjl` (remote MCP in `opencode.json`).

## Goals

Replace the mock layer with real persistence while keeping the app's shape intact:

- Mock auth → Supabase auth, **email + password only** (decision: no guest/anonymous mode; the
  onboarding flow ends at a sign-up/sign-in form instead of guest sign-in)
- Mock chat (`MockChatService`) → real chat/message rows (agent replies stay mock-generated until Phase 3)
- Simulated pipeline (`projects_providers.dart`) → projects/builds rows with real status timeline **(later slice)**
- Plan meters → server-derived token accounting (authoritative, not client-filtered) **(later slice)**

## Schema (v1)

All tables in `public`, RLS **ON** on every table, keyed by `auth.uid()`.

### profiles
| column | type | notes |
|---|---|---|
| id | uuid PK | = `auth.users.id`, `on delete cascade` |
| display_name | text | UI nickname |
| plan | text default 'free' | `free` / `starter` / `pro` / `scale` — app metadata, NOT user_metadata (user-editable) |
| tokens_month | int default 0 | consumed this billing period |
| tokens_limit | int default 50 | per plan (free) |
| created_at | timestamptz default now() |

Trigger: on new `auth.users` row → insert profile (security definer function in private schema).

### chats
| column | type | notes |
|---|---|---|
| id | **text PK** | client-generated (`chat-…` id) — lets `create()` stay synchronous and keeps ids stable across local/degraded fallback |
| user_id | uuid FK profiles(id) |
| title | text | first prompt truncated |
| created_at / updated_at | timestamptz default now() |

### messages
| column | type | notes |
|---|---|---|
| id | **text PK** | client-generated (`u-…` / `a-…`) |
| chat_id | text FK chats(id) on delete cascade |
| role | text | `user` / `assistant` / `system` |
| content | text |
| created_at | timestamptz default now() |

Server side (applied via MCP): projects + **builds** (per pipeline run: stage timeline, gh run id, asset
size) land in the NEXT slice alongside the real pipeline (Phase 3/4), so the v1 migration stays minimal.

### Auth notes
- Email + password only (user decision). Supabase may require email confirmation per project setting —
  the sign-up flow detects `session == null` and instructs the user to confirm then sign in.
- Publishable key (`sb_publishable_…`) shipped via `--dart-define=SUPABASE_ANON_KEY` (CI reads the GitHub
  secret SUPABASE_ANON_KEY; local dev passes it on the command line). Without it the app runs backend-less.
- verified E2E via REST (2026-10-24): signup→profile trigger, password sign-in, chat+message inserts,
  RLS blocks foreign-user writes (403), anonymous reads return 0 rows, fake tokens → 401.

## Policies

- Every table: `authenticated` users get SELECT/INSERT/UPDATE (and DELETE for chats+projects) strictly
  where `user_id = auth.uid()`.
- `anon` role: zero policies → anonymous REST reads return 200 with **0 rows** (e2e-verified).

# Phase 3 slice 1 — the real build pipeline

## Flow

```
"Build this app" (chat)
  → projectsProvider.create()  : projects row (status generating, stage_times seeded)
  → edge function request-build: JWT-verified, row-ownership check, dispatches factory-worker.yml
  → GitHub Actions worker      : opencode codegen → public repo af-<slug>-<id> → dispatch build.yml → poll
  → worker flips row status    : generating → pushing → queued → building → ready + apk_url
  → app polls (12 s)           : timeline + Apps tab update; Download APK / Repo buttons go live
```

## projects table (migration `phase3_projects`)

| column | type | notes |
|---|---|---|
| id | **text PK** | client-generated (`proj-…`, app owns insert) |
| user_id | uuid FK profiles(id) | owner; RLS all-own |
| name / prompt / summary | text | plan chunk + verbatim chat request |
| status | text | generating/pushing/queued/building/ready/failed (check) |
| repo / apk_url / error | text | **worker-owned** (service role writes; app freezes them) |
| stage_times | jsonb | `{stage: iso, stage_done: iso……}` — app folds into timeline markers |
| created_at / updated_at | timestamptz | |

RLS: `projects_all_own` (authenticated). Anonymous reads → 200 with 0 rows (e2e-verified).

## Worker (`scripts/worker.sh` + `.github/workflows/factory-worker.yml`)

- One bash shell per build: ERR-trap writes `status=failed + error` back to Supabase on any fatal step.
- Model: `opencode/glm-5.3-flash-free` by default (workflow_dispatch `model` input / `FACTORY_MODEL`
  function secret override).
- Generated repos contain ONLY agent-written sources (pubspec, lib/, test, README); the copied
  `templates/app/build.yml` runs `flutter create --platforms android --org com.appfactory` to
  scaffold gradle/manifest, then applies the known-good fixes (INTERNET permission, minify off for
  the R8/shared_preferences incident) — the agent never writes gradle.
- **Smoke-test gate + self-repair (in the worker, free public minutes)**: generated code must pass
  `flutter test` BEFORE pushing to the app repo; on failure the worker feeds the test output back
  to the agent for up to 2 repair passes. Default model `opencode/deepseek-v4.1-flash-free`
  (glm-5.3-flash-free shipped syntax slips); the model is a dispatch input / `FACTORY_MODEL` secret.
- **ALL repos public** (2026-10-26 decision): private-repo Actions hit GitHub's billing gate on the
  free plan ("job was not started — payments failed or spending limit") even with minutes available;
  public repos are unlimited and free. The factory repo was also briefly flipped private and every
  workflow startup-failed until reverted — public is the operating baseline now.

## request-build edge function ( deployed, verify_jwt: on )

JWT → auth.getUser → project ownership → (ready short-circuits) → GH dispatch.
Needs a function secret **FACTORY_GH_PAT** until then callers get 503 "factory is not configured yet".

## Factory repo secrets (GitHub)

- `FACTORY_GH_PAT` — set 2026-10-25 (classic repo+workflow scopes)
- `SUPABASE_SERVICE_ROLE_KEY` — **pending user** (dashboard → Settings → API → service_role)
- `OPENCODE_API_KEY` — **pending user** (opencode account key)

## E2E results (2026-10-25, all cleaned afterwards)

password grant 200 · projects insert 201 · owner PATCH 204 · forged user_id insert **403** ·
anon reads **0 rows** · edge fn: ready-short-circuit 200 ok/ready · fake JWT **401** gateway ·
unknown project **404** · unconfigured factory **503** with clean message.

# Phase 3 slice 4 — stress test findings + monorepo build repo

## Stress test (2026-10-27): 12 parallel builds on one account

- **Codegen parallelizes perfectly** — 12 opencode agent sessions completed simultaneously,
  no auth races, all produced complete projects.
- **Wall #1 — repo-creation burst limiter**: `gh repo create` (GraphQL createRepository) refused
  with "You have created too many repositories, too quickly" ×8; backoff (15/30/60/120/240s)
  didn't clear it — the window outlives the backoff and parallel retries keep the counter hot.
- **Wall #2 — build-dispatch burst**: same family, refused ×2.
- **Architecture response — the build MONOREPO** (commit fbde491): one repo
  `app-factory-outputs`, each app = `apps/<project-id>/` + per-app release tag `af-<project-id>`.
  - Zero repo creation at build time (one repo, created once) → the limiter is gone by design.
  - Worker clones (depth 1), replaces its app folder, pushes; the build workflow (one copy at the
    repo root, refreshed on every push) is dispatched with `app_dir`; polls match OUR push's
    commit SHA (unambiguous under parallel dispatches).
  - APK lands at `releases/download/af-<project-id>/app-release.apk` — per-app rolling releases.
- Wave 3 (7 failed projects, staggered 90s, monorepo pipeline) → verifying.

# Phase 3 slice 3 — real plan meters + server-enforced quota

- **Enforcement = DB trigger** (`phase3_project_quota` → `private.enforce_project_quota()`):
  BEFORE INSERT on projects, counts the user's projects in the current calendar month vs the plan
  map (free 3 / starter 10 / pro 30 / scale 100), refuses with a friendly RAISE that travels
  verbatim through PostgREST (`400 P0001 "Monthly limit reached — …"`). Service-role contexts
  bypass (uid null). Retry-friendly by design: quota is consumed at CREATION, dispatch has no gate.
- **App**: `ProfileRepository` + `profileProvider` (watches authProvider, re-fetches on sign-in);
  profile screen shows real plan + `Projects / month` meter derived from the watched projects list
  (calendar month) — demo Starter/$19 card removed.
- **Flow**: `create()` inserts first; on `ProjectLimitReached` the project renders as failed with
  the verbatim limit message and no dispatch; on offline degrade → failed with retry hint.
  `retry()` re-inserts (duplicate-key 23505 tolerated), resets worker columns, re-dispatches.
- Owner account bumped to plan=pro while billing lands (2026-10-26).
- E2E verified: 4th insert as free user → 400 + message; delete-one-and-retry semantics correct;
  all test rows cleaned.

# Phase 3 slice 2 — real agent chat (agent-chat edge function)

The planning conversation is now a real LLM; "Build this app" appears when the
MODEL decides the request is concrete enough (not canned).

```
chat screen _send()
  → history built from visible turns (greeting + streaming placeholder excluded)
  → SupabaseConfig.enabled ? AgentChatService : MockChatService   (backend-less fallback kept)
  → edge fn agent-chat: JWT → getUser → history sanitize (≤20 turns, 4k chars)
      → zen chat completions (default glm-5.3-flash paid, 60 s timeout)
      → parses trailing "PLAN: <name> | <summary>" line → {reply, plan}
  → app replays through the SAME ReplyChunk contract (TextChunk + optional PlanChunk)
```

- Function: `supabase/functions/agent-chat/index.ts` (verify_jwt on). Secret: **OPENCODE_ZEN_KEY**
  (dashboard function secrets — same place as FACTORY_GH_PAT). Optional override: FACTORY_CHAT_MODEL
  (bare zen id — the zen REST API takes bare ids; the opencode CLI takes `opencode/<id>`).

### Model economics (2026-10-26 discovery)

- OpenCode zen **free models are gated by an account-level free-usage pool** — drained, and EVERY
  key on the account returns `429 FreeUsageLimitError` (new keys under the same account share it;
  a Go subscription does NOT apply to raw REST calls — those need credit balance, `402` otherwise).
- Operating default is therefore the **paid `glm-5.3-flash`** ($0.15/1M in, $0.50/1M out — chat turn
  ≈ $0.0002, full app codegen ≈ $0.05–0.15), funded by credits on the key's account.
  - GH secret `OPENCODE_API_KEY` + Supabase secret `OPENCODE_ZEN_KEY` = the funded key.
  - Factory default `opencode/glm-5.3-flash` (commit 7d05424); chat default `glm-5.3-flash` (fn v6).
- Free keys remain valid fallbacks once a new allowance cycle starts; the app surfaces quota errors
  verbatim in chat now (raw HttpClient instead of functions.invoke, which flattens non-200 to a
  generic throw).
- Streaming feel comes from the existing streaming bubble; true SSE is a later upgrade.
- Plan proposals are in-memory only (DB stores reply text; plan re-proposal after reinstall is
  acceptable for this slice).
- Path e2e-verified (2026-10-26): valid JWT → 503 clean "not configured" (key pending),
  fake token → 401, empty history → 400. Live LLM test pending OPENCODE_ZEN_KEY.
- Data API exposure check after creation per skill note (`GRANT` if Data API didn't pick tables up).

## Client wiring

- `supabase_flutter` >= 2.x added to `pubspec.yaml`; `Supabase.initialize` in `main()`.
- `auth_repository.dart`: `signInGuest()` → `signInAnonymous()`; `signInEmail/password`, signOut,
  auth-state stream feeding go_router redirect.
- `chat_repository.dart` + `projects_repository.dart`: same method signatures the mock providers expose →
  Riverpod providers swap by config flag, app UI untouched.
- Offline/degrade: chats stay cached in `shared_preferences` rows keyed by user (relaunch after fix
  delivers persistence; the white-screen fallback path remains).

## Sequencing (with MCP after restart)

1. `list_tables`/inspect → confirm fresh project state
2. Apply SQL via `execute_sql` iteration (NOT apply_migration until stable)
3. Run advisors → fix issues → `supabase db pull` full migration when green
4. Flutter side: package + init + repos + provider swap
5. E2E: guest sign-in creates on-device account, chats persist across installs
