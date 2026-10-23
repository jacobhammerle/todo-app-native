#!/usr/bin/env bash
# Boots an Expo Simulator with the EAS Build of this PR's native app,
# lets an agent verify the PR (screenshots into evidence/), deploys the
# evidence to EAS Hosting, comments the result on the PR, and emits step
# outputs.
# Requires: BUILD_ID, PR_NUMBER, GITHUB_TOKEN,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: GH_REPO (owner/repo; default: package.json "repository")
#           INSTRUCTION (reviewer guidance from the @expo-bot comment)
#           BUILD_STATUS (upstream build job status)
#           EXPO_TOKEN_SIMULATOR (personal access token; the worker's own
#           token is used otherwise), DEVICE (default iPhone 17)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh
BOT=$(bot_handle)
APP_ID=$(app_id)
EVIDENCE_DIR="evidence"
DEVICE="${DEVICE:-iPhone 17}"

use_simulator_token
require_env GITHUB_TOKEN "add a GitHub token with pull-request write access as a secret env var in the production EAS environment."
use_agent_token

# The session bills until stopped, and a run that dies before commenting
# would leave the PR silent; the trap covers both. It tells the truth: a
# reached verdict is reported as the verdict even when a later step
# (evidence deploy, comment) failed.
COMMENT_POSTED=""
cleanup() {
  code=$?
  eas simulator:stop --non-interactive >/dev/null 2>&1 || true
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    if [ -s /tmp/verify-verdict.md ]; then
      node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent verification

**Verdict:** $(verdict_badge "$(normalize_verdict "$(head -n 1 /tmp/verify-verdict.md)")")

⚠️ **A later step failed after the verdict** — the full report is in the expo-bot-verify run logs on EAS.

_Posted by the expo-bot-verify EAS workflow._" || true
    elif [ "${BUILD_STATUS:-}" = "failure" ]; then
      node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent verification

🚫 **The iOS Simulator build of this PR failed**, so nothing was verified. The compiler output is in the \"2. Build iOS Simulator app\" job of the expo-bot-verify run on EAS. Push a fix, then comment \`${BOT} review\` to retry.

_Posted by the expo-bot-verify EAS workflow._" || true
    else
      node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent verification

⚠️ **Verification errored before a verdict** — see the expo-bot-verify run logs on EAS, then comment \`${BOT} review\` to retry.

_Posted by the expo-bot-verify EAS workflow._" || true
    fi
  fi
}
trap cleanup EXIT

require_build "simulator build to verify against"

mkdir -p "$EVIDENCE_DIR"

# PR context for the verifier prompt and the session name.
node scripts/agent/gh.mjs get-pr "$PR_NUMBER" > /tmp/pr-info.json
PR_TITLE=$(json_file_field /tmp/pr-info.json title)
node scripts/agent/gh.mjs get-pr-diff "$PR_NUMBER" > /tmp/pr.diff
cap_diff /tmp/pr.diff

echo "Verifying EAS Build $BUILD_ID (this PR's native app)"

# Name the session so the dashboard reads like a history of verified PRs.
# --build-id installs and launches the binary before the session is ready.
SESSION_NAME_FULL=$(printf 'PR #%s expo-bot: %s' "$PR_NUMBER" "$PR_TITLE")
start_session --platform ios --type argent --device "$DEVICE" \
  --build-id "$BUILD_ID" --tag expo-bot \
  --max-duration-minutes 30 --name "${SESSION_NAME_FULL:0:50}" > /tmp/verify-start.json
wait_for_session

load_argent_session
argent_device
sleep 3

# Deterministic floor beneath the AI verifier: the Tasks screen is on screen.
wait_for_home "Add a task"

# The verifier prompt lives in the repo (YAML has a 16 kB server limit).
cp .eas/expo-bot-verify-prompt.md /tmp/verify-prompt.md
printf '\nThe PR under test is #%s: "%s".\n' "$PR_NUMBER" "$PR_TITLE" >> /tmp/verify-prompt.md
printf '\nThe device udid for every argent command is: %s\n' "$UDID" >> /tmp/verify-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/verify-prompt.md
if [ -n "${INSTRUCTION:-}" ]; then
  printf "\nReviewer guidance for this run (from the ${BOT} comment): %s\n" "$INSTRUCTION" >> /tmp/verify-prompt.md
fi

echo "Running the verifier agent..."
# The verdict file is the contract; the agent's exit code is not. The
# timeout is the hard backstop: a hung agent is killed, leaves no verdict,
# and the run fails closed.
rm -f /tmp/verify-verdict.md
bash scripts/agent/run-agent.sh run --prompt-file /tmp/verify-prompt.md \
  --profile simulator --max-turns 120 --timeout 20m

if [ ! -s /tmp/verify-verdict.md ]; then
  echo "FAIL: verifier produced no verdict file (agent error, timeout, or runaway)." > /tmp/verify-verdict.md
fi
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/verify-verdict.md)")
echo "================ VERDICT ================"
cat /tmp/verify-verdict.md
echo "========================================="

# The evidence site, by eas-simulator-evidence: the session's own
# artifacts plus the screenshots and the verifier's report, deployed to
# EAS Hosting under a per-PR alias. --stop stops the session first.
RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "PR #${PR_NUMBER}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/verify-verdict.md \
  --agent "${BOT#@}" --lane "PR #${PR_NUMBER}" --build-id "$BUILD_ID" \
  --deploy-alias "pr-${PR_NUMBER}-evidence" --json)
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"

# The Expo repo points reviewers at an update channel. There is no
# channel for a native app: the EAS Build is the thing to look at.
BUILD_LINE="- 🏗️ **Build** — [EAS Build \`${BUILD_ID:0:8}\`]($(expo_build_url "$BUILD_ID")): the iOS Simulator app compiled from this PR"

node scripts/agent/gh.mjs comment "$PR_NUMBER" "$(evidence_tool comment "$EVIDENCE_DIR" "$EVIDENCE_URL" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/verify-verdict.md \
  --title "Agent verification" \
  --line "$BUILD_LINE" \
  --agent "the expo-bot-verify EAS workflow")"
COMMENT_POSTED=1

set_output evidence_url "$EVIDENCE_URL"
set_output verdict "$VERDICT_LINE"
set_output verdict_shown "$(verdict_badge "$VERDICT_LINE")"
set_output build_url "$(expo_build_url "$BUILD_ID")"
