#!/usr/bin/env bash
# Runs the native app on an Expo Simulator and checks the core flow:
# add a task, complete it, open Done, open Admin. Screenshots and a report
# land in the output folder. The exit code is the verdict.
#
# Where the app comes from (exactly one):
#   --build-id <id>      an EAS Build: the session installs and launches it
#   --archive-url <url>  any HTTPS URL to a .tar.gz of the .app (the EAS
#                        Build artifact URL works; so does your own storage)
#   --app <path>         a local SimpleTodo.app: a blank session is started
#                        and agent-device uploads the bundle
# Options:
#   --device <name>      iOS Simulator device (default iPhone 17)
#   --out <dir>          output folder (default artifacts)
#   --keep               leave the session running for the browser preview
#
# Usage:
#   bash scripts/expo-simulator/smoke-test.sh --app build/SimpleTodo.app
#   bash scripts/expo-simulator/smoke-test.sh --build-id <id>
# Needs: an eas-cli login (or EXPO_TOKEN / EXPO_TOKEN_SIMULATOR), node, npx.
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
. scripts/expo-simulator/lib.sh

BUILD_ID="" ARCHIVE_URL="" APP_PATH="" DEVICE="iPhone 17" OUT="artifacts" KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build-id) BUILD_ID="$2"; shift 2 ;;
    --archive-url) ARCHIVE_URL="$2"; shift 2 ;;
    --app) APP_PATH="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
SOURCES=0
[ -n "$BUILD_ID" ] && SOURCES=$((SOURCES + 1))
[ -n "$ARCHIVE_URL" ] && SOURCES=$((SOURCES + 1))
[ -n "$APP_PATH" ] && SOURCES=$((SOURCES + 1))
if [ "$SOURCES" -ne 1 ]; then
  echo "Pass exactly one of --build-id, --archive-url, --app." >&2
  exit 2
fi

APP_ID=$(app_id)
TASK="Verified on an Expo Simulator"
mkdir -p "${OUT:?}"
find "${OUT:?}" -maxdepth 1 -type f \( -name '*.png' -o -name '*.txt' -o -name '*.md' -o -name '*.log' \) -delete
use_simulator_token

STARTED=$(date +%s)
SESSION_ID=""
PREVIEW_URL=""
VERDICT="FAIL: the run stopped before the first check"
STEP="start"

write_report() {
  local source
  if [ -n "$BUILD_ID" ]; then source="EAS Build \`$BUILD_ID\` (\`--build-id\`)"
  elif [ -n "$ARCHIVE_URL" ]; then source="archive URL (\`--application-archive-url\`)"
  else source="local bundle \`$APP_PATH\` uploaded with agent-device \`install\`"; fi
  {
    echo "# Smoke test on an Expo Simulator"
    echo
    echo "**Verdict:** $VERDICT"
    echo
    echo "- App: \`$APP_ID\` from $source"
    echo "- Device: $DEVICE (iOS Simulator in the cloud)"
    echo "- Session: \`${SESSION_ID:-none}\`${PREVIEW_URL:+ · [browser preview]($PREVIEW_URL)}"
    echo "- Duration: $(fmt_dur $(( $(date +%s) - STARTED )))"
    echo
    echo "## Steps"
    cat "$OUT/steps.log" 2>/dev/null || true
    echo
    echo "## Screenshots"
    for f in "$OUT"/*.png; do
      [ -f "$f" ] && echo "- $(basename "$f")"
    done
  } > "$OUT/report.md"
  echo "$VERDICT" > "$OUT/verdict.txt"
}

# Every exit path stops the session (it bills until stopped) unless --keep,
# and writes the report with whatever verdict was reached.
cleanup() {
  code=$?
  if [ -n "$SESSION_ID" ] && [ -z "$KEEP" ]; then
    eas simulator:stop --id "$SESSION_ID" --non-interactive >/dev/null 2>&1 || true
    printf '# managed by eas-cli\n' > .env.eas-simulator
  fi
  if [ "$code" -ne 0 ] && [[ "$VERDICT" != FAIL* ]]; then
    VERDICT="FAIL: step '$STEP' failed (exit $code)"
  elif [ "$code" -ne 0 ]; then
    VERDICT="FAIL: step '$STEP' failed (exit $code)"
  fi
  write_report
  echo "================ VERDICT ================"
  echo "$VERDICT"
  echo "========================================="
  set_output verdict "$VERDICT"
  set_output session_id "${SESSION_ID:-none}"
  set_output device "$DEVICE"
}
trap cleanup EXIT

step() {
  STEP="$1"
  echo "→ $1"
  printf -- '- %s\n' "$1" >> "$OUT/steps.log"
}
: > "$OUT/steps.log"

# 1. Session. With --build-id or --archive-url the app is installed and
#    launched before the session is ready; with --app the device boots blank.
step "Start an Expo Simulator session ($DEVICE)"
START_ARGS=(--platform ios --type agent-device --device "$DEVICE" --max-duration-minutes 30 --name "Native smoke test")
[ -n "$BUILD_ID" ] && START_ARGS+=(--build-id "$BUILD_ID")
[ -n "$ARCHIVE_URL" ] && START_ARGS+=(--application-archive-url "$ARCHIVE_URL")
START_JSON=$(start_session "${START_ARGS[@]}")
SESSION_ID=$(printf '%s' "$START_JSON" | json_field id)
echo "Session $SESSION_ID created; waiting for it to come alive..."
wait_for_session "$SESSION_ID"
PREVIEW_URL=$(eas simulator:get --id "$SESSION_ID" --json --non-interactive | json_field remoteConfig.webPreviewUrl || true)
echo "Session ready after $(fmt_dur $(( $(date +%s) - STARTED )))${PREVIEW_URL:+; preview: $PREVIEW_URL}"

# 2. Install (local bundle only) and open the app.
if [ -n "$APP_PATH" ]; then
  step "Upload and install $APP_PATH"
  ad install "$APP_ID" "$APP_PATH" --platform ios
fi
step "Open $APP_ID"
ad open "$APP_ID" --platform ios --timeout 120000

# 3. Drive the app through its accessibility tree.
step "Wait for the Tasks screen"
ad wait text "Add a task" 60000
ad screenshot "$OUT/01-tasks.png"

step "Add the task \"$TASK\""
ad fill 'id="task-title-input"' "$TASK"
ad press 'id="add-task"'
ad wait text "$TASK" 30000
ad screenshot "$OUT/02-task-added.png"

step "Complete the task"
# The default preset has 3 open and 4 done tasks; after adding one and
# completing it the summary reads "3 tasks to do" and "5 of 8 tasks done".
ad press "label=\"$TASK\""
ad wait text "5 of 8 tasks done" 30000
ad screenshot "$OUT/03-task-completed.png"

step "Open the Done tab"
ad press 'label="Done"'
ad wait text "Clear history" 30000
ad wait text "$TASK" 30000
ad screenshot "$OUT/04-done.png"

step "Open the Admin tab"
ad press 'label="Admin"'
ad wait text "Build provenance" 30000
ad screenshot "$OUT/05-admin.png"
ad snapshot > "$OUT/05-admin-snapshot.txt" 2>&1 || true

step "Close the app"
ad close || true

VERDICT="PASS: added, completed, and found \"$TASK\" on Done; Admin shows the build provenance"
