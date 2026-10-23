#!/usr/bin/env bash
# Boots an Expo Simulator with the EAS Build of the base branch, lets an
# agent try to replicate the reported issue (screenshots into evidence/),
# deploys the evidence to EAS Hosting, and comments the verdict on the
# issue. The fix itself is a separate workflow job on an EAS macOS worker
# (scripts/agent/fix-issue.sh), gated on the "fix" output here:
#   REPLICATED     -> fix=true  (a bug to fix)
#   CONFIRMED      -> fix=true  (a feature request: capability absent)
#   NOT-REPLICATED -> fix=false (the reasoning is on the issue)
# Requires: BUILD_ID, ISSUE_NUMBER, GITHUB_TOKEN,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: GH_REPO (owner/repo; default: package.json "repository")
#           INSTRUCTION (guidance from the @expo-bot comment)
#           BUILD_STATUS (upstream build job status)
#           EXPO_TOKEN_SIMULATOR, DEVICE (default iPhone 17)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh
BOT=$(bot_handle)
APP_ID=$(app_id)
EVIDENCE_DIR="evidence"
DEVICE="${DEVICE:-iPhone 17}"

use_simulator_token
require_env GITHUB_TOKEN "add a GitHub token with issues, contents, and pull-request write access in the production EAS environment."
use_agent_token

# The session bills until stopped, and a run that dies before commenting
# would leave the issue silent; the trap covers both.
COMMENT_POSTED=""
cleanup() {
  code=$?
  eas simulator:stop --non-interactive >/dev/null 2>&1 || true
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    if [ -s /tmp/issue-verdict.md ]; then
      node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** $(verdict_badge "$(normalize_verdict "$(head -n 1 /tmp/issue-verdict.md)" INCONCLUSIVE)")

⚠️ **A later step failed after the verdict** — the full report is in the expo-bot-issue run logs on EAS.

_Posted by the expo-bot-issue EAS workflow._" || true
    elif [ "${BUILD_STATUS:-}" = "failure" ]; then
      node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

🚫 **The iOS Simulator build of the base branch failed**, so nothing was replicated. The compiler output is in the build job of the expo-bot-issue run on EAS.

_Posted by the expo-bot-issue EAS workflow._" || true
    else
      node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

⚠️ **Triage errored before a verdict** — see the expo-bot-issue run logs on EAS, then comment \`${BOT}\` here to retry.

_Posted by the expo-bot-issue EAS workflow._" || true
    fi
  fi
}
trap cleanup EXIT

require_build "simulator build to validate against"

mkdir -p "$EVIDENCE_DIR"

# Issue context for the replication prompt and the session name.
node scripts/agent/gh.mjs get-issue "$ISSUE_NUMBER" > /tmp/issue-info.json
ISSUE_TITLE=$(json_file_field /tmp/issue-info.json title)

echo "Replicating issue #$ISSUE_NUMBER against EAS Build $BUILD_ID"

SESSION_NAME_FULL=$(printf 'Issue #%s expo-bot: %s' "$ISSUE_NUMBER" "$ISSUE_TITLE")
start_session --platform ios --type argent --device "$DEVICE" \
  --build-id "$BUILD_ID" --tag expo-bot \
  --max-duration-minutes 30 --name "${SESSION_NAME_FULL:0:50}" > /tmp/issue-start.json
wait_for_session

load_argent_session
argent_device
sleep 3

# Deterministic floor beneath the AI replicator: the Tasks screen is on screen.
wait_for_home "Add a task"

# The replication prompt lives in the repo (YAML has a 16 kB server limit).
cp .eas/expo-bot-issue-prompt.md /tmp/issue-prompt.md
printf '\nThe issue under triage is #%s: "%s".\n' "$ISSUE_NUMBER" "$ISSUE_TITLE" >> /tmp/issue-prompt.md
printf '\nThe device udid for every argent command is: %s\n' "$UDID" >> /tmp/issue-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/issue-prompt.md
if [ -n "${INSTRUCTION:-}" ]; then
  printf "\nGuidance for this run (from the ${BOT} comment): %s\n" "$INSTRUCTION" >> /tmp/issue-prompt.md
fi

echo "Running the replication agent..."
rm -f /tmp/issue-verdict.md
bash scripts/agent/run-agent.sh run --prompt-file /tmp/issue-prompt.md \
  --profile simulator --max-turns 120 --timeout 20m

if [ ! -s /tmp/issue-verdict.md ]; then
  echo "INCONCLUSIVE: the replicator produced no verdict (agent error, timeout, or runaway)." > /tmp/issue-verdict.md
fi
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/issue-verdict.md)" INCONCLUSIVE)
echo "================ VERDICT ================"
cat /tmp/issue-verdict.md
echo "========================================="

RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "Issue #${ISSUE_NUMBER}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/issue-verdict.md \
  --agent "${BOT#@}" --lane "Issue #${ISSUE_NUMBER}" --build-id "$BUILD_ID" \
  --deploy-alias "issue-${ISSUE_NUMBER}-evidence" --json)
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"

VERDICT_SHOWN=$(verdict_badge "$VERDICT_LINE")
THUMBS=$(evidence_thumbs "$EVIDENCE_DIR" "$EVIDENCE_URL")
REPORT=$(tail -n +2 /tmp/issue-verdict.md)

FIX=false
NEXT_LINE=""
if [[ "$VERDICT_LINE" == REPLICATED* || "$VERDICT_LINE" == CONFIRMED* ]]; then
  FIX=true
  NEXT_LINE="
- 🔧 **Next** — a fix agent on an EAS macOS worker is writing the change, compiling it with xcodebuild, and opening a PR; the link lands here"
  FOOTER="_Posted by the expo-bot-issue EAS workflow._"
else
  FOOTER="_Posted by the expo-bot-issue EAS workflow. Missed something? Comment \`${BOT} <hint>\` to retry._"
fi

node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** ${VERDICT_SHOWN}

- 🖼️ **Evidence** — ${EVIDENCE_URL}${NEXT_LINE}

${THUMBS}

<details>
<summary>Full report</summary>

${REPORT}

</details>

${FOOTER}"
COMMENT_POSTED=1

set_output evidence_url "$EVIDENCE_URL"
set_output verdict "$VERDICT_LINE"
set_output verdict_shown "$VERDICT_SHOWN"
set_output fix "$FIX"
