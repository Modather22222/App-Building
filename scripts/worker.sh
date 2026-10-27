#!/usr/bin/env bash
# App Factory — worker pipeline. One shell per project build:
#   1. read the projects row from Supabase
#   2. opencode generates the Flutter sources into a clean dir
#   3. push as a private repo af-<slug>-<id>
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
: "${FACTORY_GH_PAT:?}" "${REPO_OWNER:?}" "${MODEL:?}"

# The CLI requires provider-prefixed model refs ("opencode/<id>"); bare ids
# fail opencode's resolution with a cryptic server-side UnknownError.
case "$MODEL" in
  opencode/*) ;;
  *) MODEL="opencode/${MODEL}" ;;
esac

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

sb_patch() { # best-effort; must never break the pipeline itself
  curl -sS -m 20 -X PATCH \
    "${SUPABASE_URL}/rest/v1/projects?id=eq.${PROJECT_ID}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "content-type: application/json" \
    -H "Prefer: return=minimal" \
    -d "$1" > /dev/null || true
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

with_retry() { # with_retry <label> <cmd...> — bursty POST endpoints trip GitHub's
               # secondary rate limits; backoff 15/30/60/120/240 clears them.
  local label="$1"; shift
  local delays=(15 30 60 120 240)
  local attempt=0
  for d in 0 "${delays[@]}"; do
    if [[ $attempt -gt 0 ]]; then
      echo "  retrying ${label} in ${d}s (attempt $((attempt + 1)))"
      sleep "$d"
    fi
    if "$@"; then return 0; fi
    attempt=$((attempt + 1))
  done
  return 1
}

# --- 1. project row ----------------------------------------------------------------
ROW=$(curl -sS -m 20 "${SUPABASE_URL}/rest/v1/projects?id=eq.${PROJECT_ID}&select=id,name,prompt,summary,status" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" | jq -c '.[0] // empty')

if [[ -z "$ROW" ]]; then
  echo "Project row vanished (deleted mid-flight) — nothing to do."
  exit 0
fi

APP_NAME=$(jq -r '.name' <<< "$ROW")
USER_PROMPT=$(jq -r '.prompt' <<< "$ROW")
PLAN_SUMMARY=$(jq -r '.summary' <<< "$ROW")

SLUG=$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
if [[ ! "$SLUG" =~ ^[a-z0-9-]+$ ]] || [[ -z "$SLUG" ]]; then SLUG=flutter-app; fi
DART_NAME=$(printf '%s' "$SLUG" | sed -E 's/-+/_/g')
if [[ "$DART_NAME" =~ ^[0-9] ]]; then DART_NAME="app${DART_NAME}"; fi
SHORT_ID=$(printf '%s' "$PROJECT_ID" | tail -c 8 | tr '_' '-')
REPO_NAME="af-${SLUG}-${SHORT_ID}"

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
OPENCODE_API_KEY="${OPENCODE_API_KEY:?OPENCODE_API_KEY secret missing on factory repo}" \
  opencode run --model "$MODEL" "$(cat request.md)" > /tmp/opencode-agent.log 2>&1 ||
  { tail -n 60 /tmp/opencode-agent.log; fail "codegen step failed (see log above)"; }

if [[ ! -f pubspec.yaml ]] || [[ ! -f lib/main.dart ]]; then
  printf '%s\n' "--- files produced ---"
  find . -type f | head -40 | sed 's/^/  /'
  fail "codegen incomplete — pubspec.yaml or lib/main.dart missing"
fi

# --- 2b. smoke-test gate + self-repair ------------------------------------------
# Private repo build minutes are precious: verify the generated code compiles
# and passes its own smoke test HERE (free public minutes), feeding failures
# back to the model for up to 2 repair passes.

flutter pub get > /dev/null 2>&1 || true
REPAIRS=0
while :; do
  # The ERR trap inherits into command substitutions (even under set +e) —
  # around this EXPECTED-to-fail probe it must be disarmed or the trap's
  # fail() kills the run before any repair pass can happen.
  trap - ERR
  set +e
  TEST_LOG=$(flutter test 2>&1)
  TEST_STATUS=$?
  set -e
  trap 'fail "worker step failed at line $LINENO (see this run log)"' ERR
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

# --- 3. wiring + repo push ------------------------------------------------------------
mark pushing
patch_state pushing

mkdir -p .github/workflows
sed -e "s/__SLUG__/${SLUG}/g" -e "s/__DART__/${DART_NAME}/g" \
  "$FACTORY_DIR/templates/app/build.yml" > .github/workflows/build.yml
if grep -q "__SLUG__\|__DART__" .github/workflows/build.yml; then
  fail "template placeholder leak — slug substitution failed"
fi

rm -f request.md repair.md /tmp/opencode-agent.log 2> /dev/null || true
git init -q -b main
git config user.name "App Factory worker"
git config user.email "workers@users.noreply.github.com"
git add -A
git commit -qm "Initial generated app (via App Factory)"
export GH_TOKEN="$FACTORY_GH_PAT"
gh auth setup-git > /dev/null 2>&1 || true
if gh repo view "${REPO_OWNER}/${REPO_NAME}" > /dev/null 2>&1; then
  # Retry of the same project: repo already exists — reuse and overwrite it.
  git remote add origin "https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
  with_retry "push" git push -q --force -u origin main
else
  with_retry "repo create" gh repo create "${REPO_OWNER}/${REPO_NAME}" \
    --public --source . --remote origin --push > /dev/null
fi

stage_end pushing
mark queued
sb_patch "$(jq -nc --arg r "${REPO_OWNER}/${REPO_NAME}" --argjson st "$(markers_json)" \
  '{status:"queued", repo:$r, stage_times:$st}')"

# --- 4. dispatch build + poll -----------------------------------------------------------
with_retry "build dispatch" gh workflow run build.yml -R "${REPO_OWNER}/${REPO_NAME}" --ref main
sleep 20

BUILDING_MARKED=0
FINAL_CONCLUSION=""
FINAL_RUN_ID=""
for _ in $(seq 1 80); do # 80 * 20s ≈ 27 min ceiling
  RUN_JSON=$(gh run list -R "${REPO_OWNER}/${REPO_NAME}" --workflow build.yml --limit 1 \
    --json status,conclusion,databaseId 2>/dev/null | jq -c '.[0] // empty') || true
  STATUS=$(jq -r '.status // ""' <<< "${RUN_JSON:-}")
  CONCLUSION=$(jq -r '.conclusion // ""' <<< "${RUN_JSON:-}")
  RUN_ID=$(jq -r '.databaseId // ""' <<< "${RUN_JSON:-}")
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
  fail "build runner timed out (~27 min) — repo: ${REPO_OWNER}/${REPO_NAME}"
fi
if [[ "$FINAL_CONCLUSION" != "success" ]]; then
  fail "APK build failed — see https://github.com/${REPO_OWNER}/${REPO_NAME}/actions/runs/${FINAL_RUN_ID:-unknown}"
fi

# --- 5. asset url + ready ----------------------------------------------------------------
APK_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/latest-build/app-release.apk"
ASSET_OK=0
for _ in $(seq 1 6); do
  ASSET=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/releases" \
    --jq '[.[] | select(.tag_name=="latest-build") | .assets[] | select(.name=="app-release.apk")] | length > 0' \
    2>/dev/null) || true
  if [[ "$ASSET" == "true" ]]; then ASSET_OK=1; break; fi
  sleep 10
done
if [[ "$ASSET_OK" -ne 1 ]]; then
  fail "APK build succeeded but the release asset is missing (unexpected)"
fi

stage_end building
sb_patch "$(jq -nc --arg u "$APK_URL" --argjson st "$(markers_json)" \
  '{status:"ready", apk_url:$u, error:null, stage_times:$st}')"
echo "Shipped ${REPO_OWNER}/${REPO_NAME} → ${APK_URL}"
