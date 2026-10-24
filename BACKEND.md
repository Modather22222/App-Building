# BACKEND.md — Phase 2 (Supabase)

Status: **design draft** — schema applied via Supabase MCP after auth link. Project ref:
`loeaiuktjmhxeoxpyqjl` (configured in `opencode.json` → remote MCP, features: docs, account, database,
debugging, development, functions, branching).

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
