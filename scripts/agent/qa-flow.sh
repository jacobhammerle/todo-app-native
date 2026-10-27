#!/usr/bin/env bash
# Runs one QA swarm lane: boots its own Expo Simulator with the native
# build preinstalled and launched (--build-id), lets a coding agent
# execute the flow in .eas/qa-flows/<FLOW>.md through argent, deploys the
# screenshot evidence to EAS Hosting at alias qa-ios-<FLOW>-evidence,
# emits timing metrics, and exits with the verdict (PASS -> 0, else 1) so
# the lane's job status mirrors the QA result.
# Requires: BUILD_ID, FLOW (tasks | add | done | admin), node_modules
#           (eas-simulator-evidence), the agent runner's credentials
# Optional: BUILD_STATUS (upstream job status), DEVICE (default iPhone 17)
#
# Run one lane from a laptop:
#   BUILD_ID=<id> FLOW=tasks bash scripts/agent/qa-flow.sh
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/qa-lib.sh

APP_ID=$(app_id)
EVIDENCE_DIR="evidence"
DEVICE="${DEVICE:-iPhone 17}"
: "${FLOW:?FLOW env is required (tasks | add | done | admin)}"
FLOW_FILE=".eas/qa-flows/${FLOW}.md"
[ -f "$FLOW_FILE" ] || { echo "Unknown flow: ${FLOW}"; exit 1; }
LANE="ios-${FLOW}"
LANE_LABEL="iOS · ${FLOW}"

# Wall clock for the metrics line. T0 is lane start; the session bills
# from simulator:start until simulator:stop.
T0=$(date +%s)
use_simulator_token
bash scripts/agent/run-agent.sh check

if [ "${BUILD_STATUS:-}" = "failure" ]; then
  echo "Upstream build failed; no binary to test."
  exit 1
fi
if [ -z "${BUILD_ID:-}" ]; then
  echo "BUILD_ID is empty; no binary to test."
  exit 1
fi

# The session bills until stopped; stop it on every exit path. Each lane
# runs on its own worker, so the dotenv default targets this lane only.
cleanup() {
  eas simulator:stop --non-interactive >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The evidence folder is uploaded as the lane's artifact even when the lane
# fails, and an empty folder fails the upload step. On a laptop a previous
# lane's screenshots and site would otherwise end up on this lane's page.
mkdir -p "$EVIDENCE_DIR"
find "${EVIDENCE_DIR:?}" -mindepth 1 -maxdepth 1 \( -name '*.png' -o -name '*.mp4' -o -name '*.mov' -o -name '*.txt' -o -name site -o -name session \) -exec rm -rf {} +
printf 'lane=%s\nbuild=%s\n' "$LANE" "$BUILD_ID" > "$EVIDENCE_DIR/lane.txt"

echo "QA lane '${LANE}' against build $BUILD_ID"

# --build-id installs and launches the binary before the session is ready.
# --tag groups the lanes on the expo.dev Simulator sessions page.
T_START=$(date +%s)
start_session --platform ios --type argent --device "$DEVICE" \
  --build-id "$BUILD_ID" --tag qa-swarm \
  --max-duration-minutes 30 --name "QA swarm: ${LANE_LABEL}" > /tmp/qa-start.json
wait_for_session
T_LIVE=$(date +%s)
echo "Session live after $(fmt_dur $((T_LIVE - T_START)))"

load_argent_session
argent_device
sleep 3

# Deterministic floor beneath the AI tester: the Tasks screen is on screen.
wait_for_home "Add a task"

# Prompts live in the repo (YAML has a 16 kB server limit).
cp .eas/qa-swarm-prompt.md /tmp/qa-prompt.md
printf '\nThe device udid for every argent command is: %s\n' "$UDID" >> /tmp/qa-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/qa-prompt.md
printf '\n--- The flow this lane must execute ---\n\n' >> /tmp/qa-prompt.md
cat "$FLOW_FILE" >> /tmp/qa-prompt.md

# argent.sh appends every `argent run <tool>` name here; the metrics line
# counts device commands and taps from it.
export ARGENT_CALL_LOG=/tmp/qa-argent-calls.log
rm -f "$ARGENT_CALL_LOG"

echo "Running QA agent for lane '${LANE}'..."
rm -f /tmp/qa-verdict.md
bash scripts/agent/run-agent.sh run --prompt-file /tmp/qa-prompt.md \
  --profile simulator --max-turns 50 --timeout 10m
T_VERDICT=$(date +%s)

if [ ! -s /tmp/qa-verdict.md ]; then
  echo "FAIL: QA agent produced no verdict (agent error, timeout, or runaway)." > /tmp/qa-verdict.md
fi
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/qa-verdict.md)")
echo "================ VERDICT (${LANE}) ================"
cat /tmp/qa-verdict.md
echo "==================================================="

T_STOP=$(date +%s)
TOTAL=$((T_VERDICT - T0))
BOOT=$((T_LIVE - T_START))
FLOW_S=$((T_VERDICT - T_LIVE))
CMDS=0; TAPS=0
if [ -f "$ARGENT_CALL_LOG" ]; then
  CMDS=$(wc -l < "$ARGENT_CALL_LOG" | tr -d ' ')
  TAPS=$(grep -c '^gesture-tap$' "$ARGENT_CALL_LOG" || true)
fi
SIM_MIN=$(awk "BEGIN { printf \"%.1f\", ($T_STOP - $T_START) / 60 }")
METRICS="⏱ $(fmt_dur "$TOTAL") lane (boot $(fmt_dur "$BOOT"), agent $(fmt_dur "$FLOW_S")) · ${CMDS} device commands, ${TAPS} taps · ${SIM_MIN} simulator-min"
echo "Metrics: $METRICS"

# The evidence site, by eas-simulator-evidence: the session's own
# artifacts (cpu/mem, the action timeline, the recording) plus the
# screenshots and the agent's report, deployed to EAS Hosting under a
# per-lane alias. --stop stops the session first; it bills until then.
RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "QA swarm · ${LANE_LABEL}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/qa-verdict.md \
  --agent "qa-swarm" --lane "$LANE_LABEL" --build-id "$BUILD_ID" \
  --extra "metrics=${METRICS}" \
  --deploy-alias "qa-${LANE}-evidence" --json)
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"
THUMBS=$(evidence_tool thumbs "$EVIDENCE_DIR" "$EVIDENCE_URL" --max 2 | tr -d '\n')

set_output verdict "$VERDICT_LINE"
set_output evidence_url "$EVIDENCE_URL"
set_output metrics "$METRICS"
set_output seconds "$TOTAL"
set_output sim_minutes "$SIM_MIN"
set_output thumbs "$THUMBS"

# The lane's job status is the QA result.
case "$VERDICT_LINE" in
  PASS:*) exit 0 ;;
  *) exit 1 ;;
esac
