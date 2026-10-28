#!/usr/bin/env bash
# App Building — worker pipeline. One shell per project build:
#   1. read the projects row from Supabase
#   2. opencode generates the Flutter sources into a clean dir
#   3. claim a GitHub account from the pool → wire into its app-building-outputs monorepo
#   4. dispatch the generated repo's build.yml, poll until the APK lands
#   5. update the row (ready + apk_url, or failed + where to look)
#
# Every fatal path goes through fail(), which best-effort writes
# status=failed to Supabase before exiting non-zero.

set -euo pipefail
set -o errtrace

FACTORY_DIR="$(pwd)" # repo checkout root; used for templates below

# --- required environment ------------------------------------------------------
: "${SUPABASE_URL:?}" "${SUPABASE_SERVICE_ROLE_KEY:?}" "${PROJECT_ID:?}"
: "${REPO_OWNER:?}" "${MODEL:?}"

# Phase 6 B1 — the project id is client-generated and flows into file paths,
# git refs, release tags AND workflow-dispatch inputs. Anything outside this
# charset (shell metacharacters, slashes, dots for traversal) must die here,
# before it touches a single command. Same rule as the DB CHECK constraint
# (projects_id_format) and the edge function's early rejection.
if [[ ! "$PROJECT_ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  echo "::error::refusing to run: PROJECT_ID fails ^[A-Za-z0-9_-]{1,64}$"
  exit 1
fi

# The CLI requires provider-prefixed model refs ("opencode/<id>"); bare ids
# fail opencode's resolution with a cryptic server-side UnknownError.
case "$MODEL" in
  opencode/*) ;;
  *) MODEL="opencode/${MODEL}" ;;
esac

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Phase 6 B2 — generated code is UNTRUSTED: `flutter test` compiles and
# executes agent-authored Dart, and one planted line reading
# Platform.environment would exfiltrate whatever is in scope. Factory
# secrets therefore never enter the probe's environment (pub.dev needs no
# credentials). Array form so it composes with `timeout`.
UNTRUSTED_ENV=(env -u SUPABASE_SERVICE_ROLE_KEY -u OPENCODE_API_KEY -u GH_TOKEN -u FACTORY_GH_PAT)

sb_patch() { # best-effort; must never break the pipeline itself
  curl -sS -m 20 -X PATCH \
    "${SUPABASE_URL}/rest/v1/projects?id=eq.${PROJECT_ID}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -H "Prefer: return=minimal" \
    -d "$1" > /dev/null || true
}

sb_rpc() { # fire-and-forget service-key RPC call
  curl -sS -m 20 -X POST \
    "${SUPABASE_URL}/rest/v1/rpc/$1" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" -d "$2" > /dev/null || true
}

sb_patch_acct() { # best-effort write to a factory_accounts row (quarantine etc.)
  curl -sS -m 20 -X PATCH \
    "${SUPABASE_URL}/rest/v1/factory_accounts?id=eq.$1" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -H "Prefer: return=minimal" \
    -d "$2" > /dev/null || true
}

validate_pat() { # validate_pat <pat> → "ok" | "TRANSIENT: …" | a definitive reason.
                 # Definitive verdicts (expired/revoked, missing scopes) quarantine
                 # the row; TRANSIENT ones (network blips, GitHub 5xx) only skip
                 # the account for this run — quarantining on a hiccup
                 # permanently shrank the pool (audit H-P1). Identity + OAuth
                 # scopes via GitHub REST. Fine-grained PATs return no scopes
                 # header and cannot create repos → rejected.
  local HEADERS CODE SCOPES
  HEADERS=$(curl -sS -m 20 -D - -o /dev/null \
    -H "Authorization: Bearer $1" -H "Accept: application/vnd.github+json" \
    https://api.github.com/user 2>/dev/null) || { echo "TRANSIENT: identity check request failed"; return 0; }
  CODE=$(printf '%s\n' "$HEADERS" | head -n1 | awk '{print $2}')
  if [[ "$CODE" != "200" ]]; then
    case "$CODE" in
      401|403)
        echo "PAT rejected by GitHub (HTTP ${CODE:-unknown}) — expired, wrong, or revoked" ;;
      *)
        echo "TRANSIENT: GitHub identity check returned HTTP ${CODE:-unknown}" ;;
    esac
    return 0
  fi
  SCOPES=$(printf '%s\n' "$HEADERS" | grep -i '^x-oauth-scopes:' | cut -d':' -f2- | sed 's/^ //' | tr -d '\r')
  if ! printf '%s\n' "$SCOPES" | grep -qw repo; then
    echo "PAT lacks 'repo' scope (scopes: ${SCOPES:-none — fine-grained token?})"
    return 0
  fi
  if ! printf '%s\n' "$SCOPES" | grep -qw workflow; then
    echo "PAT lacks 'workflow' scope (scopes: $SCOPES)"
    return 0
  fi
  echo "ok"
}

sb_settings_put() { # idempotent settings seed — user edits always win
  curl -sS -m 20 -X POST \
    "${SUPABASE_URL}/rest/v1/factory_settings?on_conflict=key" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -H "Prefer: return=minimal,resolution=ignore-duplicates" \
    -d "$(jq -nc --arg k "$1" --arg v "$2" '{key:$k, value:$v}')" > /dev/null || true
}

claim_account() { # atomic LRU claim from the multi-account pool
  curl -sS -m 20 -X POST \
    "${SUPABASE_URL}/rest/v1/rpc/claim_factory_account" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" -d '{}'
}

fail() {
  sb_patch "$(jq -nc --arg e "$1" '{status:"failed", error:$e}')"
  echo "::error::$1"
  exit 1
}

# --- stage markers ---------------------------------------------------------------
declare -A MARKERS

mark() { MARKERS["$1"]="$(now)"; }                      # stage started
stage_end() { MARKERS["${1}_done"]="$(now)"; }          # stage completed

markers_json() {
  # Keys are fixed enum names, values are ISO timestamps from date(1) —
  # plain printf assembly is deterministic; jq framing bugs twice bit us.
  local out="{" first=1
  for k in "${!MARKERS[@]}"; do
    [[ $first -eq 1 ]] || out+=","
    out+="\"${k}\":\"${MARKERS[$k]}\""
    first=0
  done
  echo "${out}}"
}

patch_state() { # patch_state <status> — writes status + all stage markers
  sb_patch "$(jq -nc --arg s "$1" --argjson st "$(markers_json)" '{status:$s, stage_times:$st}')"
}

trap 'fail "worker step failed at line $LINENO (see this run log)"' ERR

# Phase 7 — heartbeat: long stages (smoke/repair loop, build poll) can legally
# run 45+ minutes without a stage transition, but the watchdog sweep auto-fails
# rows whose updated_at goes stale (>30 min). A background toucher refreshes
# updated_at every 5 minutes for the worker's whole lifetime, so the sweep only
# ever kills rows whose worker is actually gone. Dies with the process.
( while :; do
    sleep 300
    curl -sS -m 20 -X PATCH \
      "${SUPABASE_URL}/rest/v1/projects?id=eq.${PROJECT_ID}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "content-type: application/json" \
      -H "Prefer: return=minimal" \
      -d "{\"updated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /dev/null 2>&1 || true
  done ) &

with_retry() { # with_retry <label> <cmd...> — bursty POST endpoints trip GitHub's
               # secondary rate limits; backoff 15/30/60/120/240 clears them.
  local label="$1"; shift
  local delays=(15 30 60 120 240)
  local attempt=0
  local log
  log="$(mktemp)"
  for d in 0 "${delays[@]}"; do
    if [[ $attempt -gt 0 ]]; then
      echo "  retrying ${label} in ${d}s (attempt $((attempt + 1)))"
      sleep "$d"
    fi
    if "$@" 2>>"$log"; then
      rm -f "$log"
      return 0
    fi
    # Phase 5 — fail-fast classification: ~8 min of backoff on a failure that
    # can never succeed (dead ref, revoked/under-scoped PAT, vanished repo)
    # wastes runner minutes and buries the cause. Structural errors return
    # immediately; everything else (rate limits, network) keeps the ladder.
    if tail -c 4000 "$log" 2>/dev/null | grep -qiE \
      "couldn.?t find remote ref|repository not found|authentication failed|bad credentials|terminal prompts disabled|refusing to allow .*token to create or update workflow|permission to .* denied|resource not accessible"; then
      echo "::error::${label}: permanent failure — not retryable:"
      tail -n 5 "$log" 2>/dev/null || true
      rm -f "$log"
      return 1
    fi
    attempt=$((attempt + 1))
  done
  # All attempts exhausted — surface the real reason before bailing
  # (stderr must never vanish into /dev/null; that once hid a poll bug
  # for a whole 27-min window).
  echo "::error::${label}: exhausted ${#delays[@]} retries; last stderr:"
  tail -n 8 "$log" 2>/dev/null || true
  rm -f "$log"
  return 1
}

# --- 1. project row ----------------------------------------------------------------
# Phase 7 — the read is status-checked: a Supabase blip used to look exactly
# like "row vanished" (silent exit 0, green run, stuck row). Transport errors
# now fail the run honestly; only a genuine empty result means deleted.
ROW_HTTP=$(curl -sS -m 20 -o /tmp/row.json -w '%{http_code}' \
  "${SUPABASE_URL}/rest/v1/projects?id=eq.${PROJECT_ID}&select=id,name,prompt,summary,status" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}") || ROW_HTTP="000"
if [[ "$ROW_HTTP" != "200" ]]; then
  fail "could not read the project row (HTTP ${ROW_HTTP}) — retry the build"
fi
ROW=$(jq -c '.[0] // empty' /tmp/row.json)

if [[ -z "$ROW" ]]; then
  echo "Project row vanished (deleted mid-flight) — nothing to do."
  exit 0
fi

APP_NAME=$(jq -r '.name' <<< "$ROW")
USER_PROMPT=$(jq -r '.prompt' <<< "$ROW")
PLAN_SUMMARY=$(jq -r '.summary' <<< "$ROW")

# Phase 6 H-P5 — content gate, last line of defense: the chat agent applies
# this screen too, but the worker is where the build actually happens. A hit
# refuses the build and logs the refusal to the audit trail.
ABUSE_RE='key ?log(ger|ging)?|keystroke|spy(ing|ware)?|(stealth|covert|hidden) +(app|cam(era)?|mic(rophone)?|recorder|monitor(ing)?|track(er|ing)?)|(track|monitor)(ing)? +(someone|people|my +(partner|spouse|wife|husband|girlfriend|boyfriend|ex)|employees?)|harass|bull(y|ying|ied)|dox|stalk|phish(ing)?|credential harvesting?|(password|otp|pin) ?(steal(ing)?|grab(ber)?|crack(ing)?|bypass)|steal(ing)? +(passwords?|credentials?|otp|pins?)|malware|ransomware|trojan|botnet|ddos|rootkit|(sms|text|call|whatsapp) +(intercept(ion)?|sniff(ing)?|forward(ing)?)|intercept(ion|s|ed)?|forward(ing)? +(incoming +)?(sms|texts?|messages?|calls?)'
if printf '%s\n%s' "$USER_PROMPT" "$PLAN_SUMMARY" | grep -qiE "$ABUSE_RE"; then
  curl -sS -m 20 -X POST "${SUPABASE_URL}/rest/v1/plan_audit" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -d "$(jq -nc --arg p "${PROJECT_ID}" --arg n "$APP_NAME" --arg s "$PLAN_SUMMARY" --arg u "${USER_PROMPT:0:500}" \
      '{project_id:$p, app_name:$n, summary:$s, prompt_snippet:$u, decision:"blocked", reason:"worker content gate"}')" > /dev/null || true
  fail "this request violates the App Building content policy — the build was refused"
fi

SLUG=$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
if [[ ! "$SLUG" =~ ^[a-z0-9-]+$ ]] || [[ -z "$SLUG" ]]; then SLUG=flutter-app; fi
DART_NAME=$(printf '%s' "$SLUG" | sed -E 's/-+/_/g')
if [[ "$DART_NAME" =~ ^[0-9] ]]; then DART_NAME="app${DART_NAME}"; fi
SHORT_ID=$(printf '%s' "$PROJECT_ID" | tail -c 8 | tr '_' '-')
# Monorepo: ONE build repo for every generated app — per-app folders under
# apps/ and per-app release tags. Sidesteps GitHub's repo-creation burst
# limiter entirely and keeps the user's account clean.
APP_DIR="apps/${PROJECT_ID}"
RELEASE_TAG="af-${PROJECT_ID}"

# --- 2. codegen with opencode -------------------------------------------------------
mark generating
patch_state generating

npm install -g opencode-ai@latest > /dev/null 2>&1
opencode --version

WORK="$(mktemp -d)"
jq -Rn --rawfile tmpl templates/app/codegen-instructions.md \
  --arg dart "$DART_NAME" \
  --arg name "$APP_NAME" \
  --arg prompt "$USER_PROMPT" \
  --arg sum "$PLAN_SUMMARY" \
  '$tmpl | gsub("\\{\\{DART\\}\\}"; $dart) | gsub("\\{\\{NAME\\}\\}"; $name)
       | gsub("\\{\\{REQUEST\\}\\}"; $prompt) | gsub("\\{\\{SUMMARY\\}\\}"; $sum)' \
  > "$WORK/request.md"

cd "$WORK"
run_codegen() {
  OPENCODE_API_KEY="${OPENCODE_API_KEY:?OPENCODE_API_KEY secret missing on factory repo}" \
    opencode run --model "$MODEL" "$(cat request.md)" > /tmp/opencode-agent.log 2>&1
}
if ! run_codegen; then
  tail -n 60 /tmp/opencode-agent.log
  fail "codegen step failed (see log above)"
fi

if [[ ! -f pubspec.yaml ]] || [[ ! -f lib/main.dart ]]; then
  # The agent occasionally produces nothing usable. One fresh roll before
  # giving up — a hung/incomplete first attempt is a roll of the dice, not a
  # verdict on the prompt.
  echo "codegen produced an incomplete project — one fresh retry"
  find . -mindepth 1 -maxdepth 1 ! -name request.md -exec rm -rf {} +
  if ! run_codegen; then
    tail -n 60 /tmp/opencode-agent.log
    fail "codegen retry failed (see log above)"
  fi
  if [[ ! -f pubspec.yaml ]] || [[ ! -f lib/main.dart ]]; then
    printf '%s\n' "--- files produced ---"
    find . -type f | head -40 | sed 's/^/  /'
    fail "codegen incomplete after fresh retry — pubspec.yaml or lib/main.dart missing"
  fi
fi

# Phase 6 B2 — dependency supply-chain gate: the template allows pub.dev
# hosted packages only. git/path sources and dependency_overrides can pull
# arbitrary code from anywhere; reject before a single line executes.
if grep -qE '^[[:space:]]*(git|path|hosted):' pubspec.yaml; then
  fail "pubspec declares a non-pub.dev dependency source (git/path/hosted) — not allowed"
fi
if grep -qE '^dependency_overrides:' pubspec.yaml; then
  fail "pubspec declares dependency_overrides — not allowed"
fi

# --- 2b. smoke-test gate + self-repair ------------------------------------------
# Private repo build minutes are precious: verify the generated code compiles
# and passes its own smoke test HERE (free public minutes), feeding failures
# back to the model for up to 2 repair passes.

"${UNTRUSTED_ENV[@]}" flutter pub get > /dev/null 2>&1 || true
REPAIRS=0
while :; do
  # The ERR trap inherits into command substitutions (even under set +e) —
  # around this EXPECTED-to-fail probe it must be disarmed or the trap's
  # fail() kills the run before any repair pass can happen.
  trap - ERR
  set +e
  # 15-min cap: a hung probe (network/pub stall) is infrastructure, not code —
  # without this the worker waits until GitHub's 60-min job kill, the row goes
  # stale, and only the watchdog sweep explains it (Unit Quiz, 2026-10-27).
  TEST_LOG=$(timeout 900 "${UNTRUSTED_ENV[@]}" flutter test 2>&1)
  TEST_STATUS=$?
  set -e
  trap 'fail "worker step failed at line $LINENO (see this run log)"' ERR
  if [[ "$TEST_STATUS" -eq 124 ]]; then
    printf '%s\n' "$TEST_LOG" | tail -n 30
    fail "smoke probe hung >15 min (infrastructure stall, not code) — retry the build"
  fi
  if [[ "$TEST_STATUS" -eq 0 ]]; then
    if [[ "$REPAIRS" -gt 0 ]]; then
      echo "Repair pass $REPAIRS made the smoke test pass."
    fi
    break
  fi
  if [[ "$REPAIRS" -ge 2 ]]; then
    echo "::group::last smoke-test failure (tail)"
    printf '%s\n' "$TEST_LOG" | tail -n 80
    echo "::endgroup::"
    fail "generated code failed its smoke test after $REPAIRS repair passes"
  fi
  REPAIRS=$((REPAIRS + 1))
  echo "::group::repair pass $REPAIRS"
  jq -Rn --rawfile tmpl "$FACTORY_DIR/templates/app/repair-instructions.md" \
    --arg failures "$TEST_LOG" \
    '$tmpl | gsub("\\{\\{FAILURES\\}\\}"; $failures)' > repair.md
  printf 'repair prompt: %s bytes\n' "$(wc -c < repair.md)"
  OPENCODE_API_KEY="${OPENCODE_API_KEY:?OPENCODE_API_KEY secret missing on factory repo}" \
    opencode run --model "$MODEL" "$(cat repair.md)" >> /tmp/opencode-agent.log 2>&1 ||
    { tail -n 40 /tmp/opencode-agent.log; fail "repair pass $REPAIRS failed"; }
  echo "::endgroup::"
done

stage_end generating

# --- 3. wire into the build monorepo ---------------------------------------------------
mark pushing
patch_state pushing

# --- account pool -----------------------------------------------------------------------
# Bootstrap — which account does the factory manage? Fully DB-driven:
#   factory_settings['factory_owner']        = GitHub username, or 'none' to disable
#   factory_settings['factory_pat_secret_id'] = vault secret id holding that PAT
# The PAT lives ENCRYPTED in supabase_vault (Phase 6) — the settings pair and
# the accounts table never hold plaintext. Every run ensures the pair's row
# exists (resurrect if deleted, never overwrite).
SETTINGS=$(curl -sS -m 20 \
  "${SUPABASE_URL}/rest/v1/factory_settings?key=in.(\"factory_owner\",\"factory_pat_secret_id\")&select=key,value" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
OWNER_SETTING=$(jq -r '.[] | select(.key == "factory_owner") | .value // empty' <<<"$SETTINGS")
SECRET_ID_SETTING=$(jq -r '.[] | select(.key == "factory_pat_secret_id") | .value // empty' <<<"$SETTINGS")
if [[ "$OWNER_SETTING" == "none" ]]; then
  echo "factory-managed account disabled (factory_settings.factory_owner = none)"
elif [[ -n "$OWNER_SETTING" && -n "$SECRET_ID_SETTING" ]]; then
  sb_rpc ensure_factory_account "$(jq -nc \
    --arg o "$OWNER_SETTING" --arg sid "$SECRET_ID_SETTING" '{p_owner:$o, p_pat_secret_id:$sid}')"
fi

# Claim the least-recently-used account, then pre-flight its PAT. Definitive
# verdicts (expired/revoked token, missing repo/workflow scope, fine-grained
# token) quarantine the row — active=false + last_error — and the next
# account is claimed: a bad paste costs seconds, not a build. TRANSIENT
# verdicts (GitHub blips) only skip the account for this run. Each
# definitive validation shrinks the pool, so the loop terminates in
# FACTORY_NO_ACCOUNTS at worst; the attempt bound covers transient-only
# pools (a skipped row stays LRU-recent, so the next claim rotates rows).
# PostgREST RPC returns an ARRAY envelope; paths handle both array/object.
POOL_ATTEMPTS=0
while :; do
  POOL_ATTEMPTS=$((POOL_ATTEMPTS + 1))
  if [[ "$POOL_ATTEMPTS" -gt 6 ]]; then
    fail "GitHub account pool: no usable account after ${POOL_ATTEMPTS} claims (exhausted or unreachable) — retry the build"
  fi
  ACCT=$(claim_account) || ACCT=""
  OWNER=$(jq -r '(.[0].owner // .owner) // empty' <<<"$ACCT" 2>/dev/null || echo "")
  if [[ -z "$OWNER" ]]; then
    MSG=$(jq -r '(.[0].message // .message) // "empty claim response"' <<<"$ACCT" 2>/dev/null) || \
      MSG="account claim request failed"
    [[ -z "$MSG" || "$MSG" == "null" ]] && MSG="account claim request failed"
    fail "GitHub account pool: ${MSG}"
  fi
  CLAIM_PAT=$(jq -r '(.[0].pat // .pat)' <<<"$ACCT")
  CLAIM_ID=$(jq -r '(.[0].id // .id)' <<<"$ACCT")
  VERDICT=$(validate_pat "$CLAIM_PAT")
  if [[ "$VERDICT" == "ok" ]]; then
    sb_patch_acct "$CLAIM_ID" '{"last_error":null}'
    echo "Build account: ${OWNER} (pool row ${CLAIM_ID}) — PAT ok"
    break
  fi
  if [[ "$VERDICT" == TRANSIENT:* ]]; then
    echo "skipping ${OWNER} for this run: ${VERDICT}"
    continue
  fi
  sb_patch_acct "$CLAIM_ID" "$(jq -nc --arg e "$VERDICT" '{active:false, last_error:$e}')"
  echo "quarantined ${OWNER}: ${VERDICT}"
  # Phase 7 — quarantine is operator-visible immediately (alert consumer
  # dispatches it to the configured webhook within 10 minutes).
  curl -sS -m 20 -X POST "${SUPABASE_URL}/rest/v1/factory_alerts" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -d "$(jq -nc --arg d "account ${OWNER} quarantined: ${VERDICT}" '{kind:"account_quarantined", detail:$d}')" > /dev/null || true
done
BUILD_REPO="${OWNER}/app-building-outputs"
export GH_TOKEN="$CLAIM_PAT"

rm -f request.md repair.md /tmp/opencode-agent.log 2> /dev/null || true
gh auth setup-git > /dev/null 2>&1 || true

# Clone (full depth — the monorepo is MBs of small sources; --depth 1 breaks
# rebase merge-base computation the moment origin/main advances) the build
# monorepo, creating it on first ever use.
if ! gh repo view "$BUILD_REPO" > /dev/null 2>&1; then
  with_retry "monorepo create" gh repo create "$BUILD_REPO" --public > /dev/null
  sleep 5
fi
MONO="$(mktemp -d)"
with_retry "monorepo clone" git clone -q "https://github.com/${BUILD_REPO}.git" "$MONO"
mkdir -p "${MONO}/apps"

# Fresh generated tree into its app folder (retry overwrites cleanly).
# Phase 6 B2 — enforce the codegen file allowlist MECHANICALLY: the agent is
# told to write only pubspec.yaml + lib/ + test/ + README.md, but the monorepo
# build executes whatever exists in the copied tree. Everything else (stray
# gradle files, scripts, request.md, .dart_tool) is deleted here — the build
# must never see unreviewed executable surface. pubspec.lock is kept: it pins
# the resolved dependency set for a reproducible build.
find "$WORK" -mindepth 1 -maxdepth 1 \
  ! -name 'pubspec.yaml' ! -name 'pubspec.lock' ! -name 'lib' ! -name 'test' ! -name 'README.md' \
  -exec rm -rf {} +
MONO_APP="${MONO}/${APP_DIR}"
rm -rf "$MONO_APP"
mkdir -p "$MONO_APP"
cp -a "$WORK"/. "$MONO_APP"/
# The app's build workflow: one copy lives at the monorepo root; refresh it
# on every push so template updates propagate with any app.
# One IDENTICAL build.yml for every app — per-app identity travels ONLY as
# dispatch inputs (app_dir, dart_name). Identical content means parallel
# pushes never conflict on this shared file (baked __DART__ per app caused
# rebase conflicts under bursts — Recipe Card, 2026-10-27).
mkdir -p "${MONO}/.github/workflows"
cp "$FACTORY_DIR/templates/app/build.yml" "${MONO}/.github/workflows/build.yml"

# Push races under parallel workers → see mono_push above.
mono_push() {
  # Parallel workers push to the same monorepo: pushes race into non-fast-forward
  # rejections. Fetch ALL refs (an empty repo has no remote main to name —
  # "couldn't find remote ref main" — and only the first push creates it),
  # rebase only when a remote main exists, then push.
  git fetch -q origin || return 1
  if git show-ref --verify -q refs/remotes/origin/main; then
    if ! git rebase -q origin/main; then
      git rebase --abort 2> /dev/null || true
      return 1
    fi
  fi
  git push -q origin main
}

cd "$MONO"
git config user.name "App Building worker"
git config user.email "workers@users.noreply.github.com"
git add -A
git commit -qm "App Building: ${APP_NAME} (${PROJECT_ID})"
with_retry "monorepo push" mono_push
HEAD_SHA=$(git rev-parse HEAD)

stage_end pushing
mark queued
sb_patch "$(jq -nc --arg r "$BUILD_REPO" --argjson st "$(markers_json)" \
  '{status:"queued", repo:$r, stage_times:$st}')"

# --- 4. dispatch build + poll (matched by our push SHA) -----------------------------------
with_retry "build dispatch" gh workflow run build.yml -R "$BUILD_REPO" --ref main \
  -f "app_dir=${APP_DIR}" -f "dart_name=${DART_NAME}"
sleep 20

BUILDING_MARKED=0
FINAL_CONCLUSION=""
FINAL_RUN_ID=""
POLL_ERRORS=0
for _ in $(seq 1 80); do # 80 * 20s ≈ 27 min ceiling
  # Phase 7 — poll by head_sha SERVER-SIDE (the old --limit 40 + client filter
  # dropped our run off page 1 under burst), with a per-call timeout, and
  # consecutive API failures classified instead of silently looping to the
  # 27-min timeout.
  RUN_JSON=$(timeout 60 gh api "repos/${BUILD_REPO}/actions/runs?head_sha=${HEAD_SHA}&per_page=5" \
    --jq '[.workflow_runs[0]] | map({status, conclusion, databaseId: .id, number: .run_number})[0] // empty' 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    # API failure — distinct from "run not registered yet" (which is normal
    # right after dispatch and must not burn the error budget).
    POLL_ERRORS=$((POLL_ERRORS + 1))
    if [[ "$POLL_ERRORS" -ge 5 ]]; then
      fail "build polling is failing against the GitHub API (${POLL_ERRORS} consecutive errors) — retry the build"
    fi
    sleep 20
    continue
  fi
  POLL_ERRORS=0
  if [[ -z "$RUN_JSON" || "$RUN_JSON" == "null" ]]; then
    sleep 20
    continue
  fi
  POLL_ERRORS=0
  STATUS=$(jq -r '.status // ""' <<< "${RUN_JSON:-}")
  CONCLUSION=$(jq -r '.conclusion // ""' <<< "${RUN_JSON:-}")
  RUN_ID=$(jq -r '.databaseId // ""' <<< "${RUN_JSON:-}")
  RUN_NUMBER=$(jq -r '.number // ""' <<< "${RUN_JSON:-}")
  if [[ "$STATUS" == "in_progress" && "$BUILDING_MARKED" -eq 0 ]]; then
    BUILDING_MARKED=1
    mark building
    patch_state building
  fi
  if [[ "$STATUS" == "completed" ]]; then
    FINAL_CONCLUSION="$CONCLUSION"
    FINAL_RUN_ID="$RUN_ID"
    break
  fi
  sleep 20
done

if [[ -z "$FINAL_CONCLUSION" ]]; then
  fail "build runner timed out (~27 min) — repo: ${BUILD_REPO}"
fi
if [[ "$FINAL_CONCLUSION" != "success" ]]; then
  # Phase 5 — failure taxonomy: read the failed job's log tail and translate
  # the machine error into a plain-language reason on the card. The raw tail
  # stays in the run log; the row keeps the friendly version + run link.
  TAXONOMY_TAIL=""
  if [[ -n "${FINAL_RUN_ID:-}" ]]; then
    TAXONOMY_TAIL=$(gh run view "$FINAL_RUN_ID" -R "$BUILD_REPO" --log-failed 2>/dev/null | tail -n 200 || true)
  fi
  FRIENDLY="The APK build failed on the runner — see https://github.com/${BUILD_REPO}/actions/runs/${FINAL_RUN_ID:-unknown}"
  if [[ -n "$TAXONOMY_TAIL" ]]; then
    if grep -qiE "failed host lookup|couldn.?t resolve pub\.dev|network is unreachable|connection (reset|refused)|early EOF" <<<"$TAXONOMY_TAIL"; then
      FRIENDLY="The build couldn't reach pub.dev (network hiccup on the runner) — retry; it usually clears."
    elif grep -qiE "compilation (failed|error)|compiler message|error: .+\.dart" <<<"$TAXONOMY_TAIL"; then
      FRIENDLY="The generated code didn't compile — retry to regenerate; the factory retries the agent once."
    elif grep -qiE "FAILURE: Build failed with an exception|Gradle task assembleRelease" <<<"$TAXONOMY_TAIL"; then
      FRIENDLY="The Android build step failed (Gradle) — retry; if it repeats the generated app needs a fix."
    elif grep -qiE "you have exceeded|rate limit|secondary rate" <<<"$TAXONOMY_TAIL"; then
      FRIENDLY="The build hit GitHub's rate limiter — retry in a few minutes."
    elif grep -qiE "run was cancelled|cancellation requested" <<<"$TAXONOMY_TAIL"; then
      FRIENDLY="The build run was cancelled (timeout or manual stop)."
    fi
  fi
  fail "${FRIENDLY}"
fi

# --- 5. asset url + ready ----------------------------------------------------------------
APK_URL="https://github.com/${BUILD_REPO}/releases/download/${RELEASE_TAG}/app-release.apk"
APK_SIZE=""
for _ in $(seq 1 6); do
  APK_SIZE=$(gh api "repos/${BUILD_REPO}/releases" \
    --jq "[.[] | select(.tag_name==\"${RELEASE_TAG}\") | .assets[] | select(.name==\"app-release.apk\")][0].size // empty" \
    2>/dev/null) || APK_SIZE=""
  if [[ -n "$APK_SIZE" ]]; then ASSET_OK=1; break; fi
  sleep 10
done
if [[ "$ASSET_OK" -ne 1 ]]; then
  fail "APK build succeeded but the release asset is missing (unexpected)"
fi

BUILD_INFO=$(jq -nc \
  --arg rid "${FINAL_RUN_ID:-}" \
  --arg rn "${RUN_NUMBER:-}" \
  --arg sz "${APK_SIZE:-}" \
  '{run_id:(if $rid=="" then null else $rid end),
    run_number:(if $rn=="" then null else ($rn|tonumber) end),
    size_bytes:(if $sz=="" then null else ($sz|tonumber) end)}')

stage_end building
sb_patch "$(jq -nc --arg u "$APK_URL" --argjson bi "$BUILD_INFO" --argjson st "$(markers_json)" \
  '{status:"ready", apk_url:$u, error:null, stage_times:$st, build_info:$bi}')"
echo "Shipped ${APP_NAME} → ${APK_URL}"
