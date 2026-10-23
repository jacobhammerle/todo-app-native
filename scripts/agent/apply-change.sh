#!/usr/bin/env bash
# Runs on an EAS macOS worker: applies the reviewer's @expo-bot instruction
# to the PR branch. An agent edits the Swift code in a fresh clone, the
# change must compile with xcodebuild (the gate; the Expo repo's is tsc +
# lint), and the result is committed and pushed to the PR head. Posts a
# summary comment on the PR either way, and with VERIFY=true dispatches
# expo-bot-verify on the PR from the clone.
# Requires: PR_NUMBER, INSTRUCTION, GITHUB_TOKEN,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: VERIFY (default false), EXPO_TOKEN_SIMULATOR (dispatches the
#           verify run), GH_REPO (owner/repo; default: package.json "repository")
set -euo pipefail

ORIG_DIR=$(pwd)
# shellcheck disable=SC1091
. "$ORIG_DIR/scripts/agent/comment-lib.sh"
BOT=$(bot_handle)
GH_REPO=$(repo_slug)
export GH_REPO
WORK_DIR=/tmp/change-repo
SUMMARY_FILE=/tmp/expo-bot-change-summary.md
rm -rf "$WORK_DIR" "$SUMMARY_FILE"

require_env GITHUB_TOKEN "add a GitHub token with contents and pull-request write access in the production EAS environment."
use_simulator_token
use_agent_token

COMMENT_POSTED=""
cleanup() {
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    node "$ORIG_DIR/scripts/agent/gh.mjs" comment "$PR_NUMBER" "## 🤖 Agent iteration

**Requested:** _${INSTRUCTION}_

⚠️ **The change step errored before it could commit** — see the expo-bot-change run logs on EAS, then comment \`${BOT} change ${INSTRUCTION}\` to retry.

_Posted by the expo-bot-change EAS workflow._" || true
  fi
}
trap cleanup EXIT

node "$ORIG_DIR/scripts/agent/gh.mjs" get-pr "$PR_NUMBER" > /tmp/pr-info.json
PR_BRANCH=$(json_file_field /tmp/pr-info.json branch)
PR_HEAD_REPO=$(json_file_field /tmp/pr-info.json headRepo)
PR_STATE=$(json_file_field /tmp/pr-info.json state)
# The bridge refuses forks and closed PRs; this is the same gate for a
# manual `eas workflow:run`.
if [ "$PR_HEAD_REPO" != "$GH_REPO" ] || [ "$PR_STATE" != "open" ]; then
  echo "PR #$PR_NUMBER is from '$PR_HEAD_REPO' and is $PR_STATE; only open PRs from $GH_REPO are changed."
  exit 1
fi

# The workflow checkout has no pushable git remote, so work in a real clone.
git clone --depth 1 --branch "$PR_BRANCH" \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/${GH_REPO}.git" "$WORK_DIR"

cp "$ORIG_DIR/.eas/expo-bot-change-prompt.md" /tmp/change-prompt.md
printf "\nThe requested change (from the ${BOT} comment on PR #%s): %s\n" \
  "$PR_NUMBER" "$INSTRUCTION" >> /tmp/change-prompt.md

echo "Running the change agent..."
cd "$WORK_DIR"
# The summary file is the contract; the agent's exit code is not.
bash "$ORIG_DIR/scripts/agent/run-agent.sh" run --prompt-file /tmp/change-prompt.md \
  --profile fix --max-turns 60 --timeout 15m

if [ -z "$(git status --porcelain)" ]; then
  REASON=$(cat "$SUMMARY_FILE" 2>/dev/null || echo "The agent gave no reason (error or timeout).")
  node "$ORIG_DIR/scripts/agent/gh.mjs" comment "$PR_NUMBER" "## 🤖 Agent iteration

**Requested:** _${INSTRUCTION}_

⚠️ **No change made** — ${REASON}

_Posted by the expo-bot-change EAS workflow._"
  COMMENT_POSTED=1
  set_output commit "none"
  exit 1
fi

# Hard gate: never push Swift that does not compile.
if ! npm run build:simulator; then
  node "$ORIG_DIR/scripts/agent/gh.mjs" comment "$PR_NUMBER" "## 🤖 Agent iteration

**Requested:** _${INSTRUCTION}_

⚠️ **No change pushed** — the agent's edit did not compile (xcodebuild failed); the compiler output is in the expo-bot-change run logs on EAS.

_Posted by the expo-bot-change EAS workflow._"
  COMMENT_POSTED=1
  set_output commit "none"
  exit 1
fi

SUMMARY_LINE=$(head -n 1 "$SUMMARY_FILE" 2>/dev/null || true)
[ -n "$SUMMARY_LINE" ] || SUMMARY_LINE="$INSTRUCTION"

git config user.name "${BOT#@}"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -m "${BOT#@}: ${SUMMARY_LINE}" \
  -m "Requested via an ${BOT} comment on PR #${PR_NUMBER}; compiled with xcodebuild on an EAS macOS worker."
git push origin "HEAD:${PR_BRANCH}"
COMMIT_SHA=$(git rev-parse --short HEAD)

VERIFY_RUN_URL=""
if [ "${VERIFY:-false}" = "true" ]; then
  # Dispatch from this clone so expo-bot-verify sees the pushed code.
  VERIFY_OUT=$(eas workflow:run .eas/workflows/expo-bot-verify.yml \
    --input "pr_number=${PR_NUMBER}" \
    --input "instruction=${INSTRUCTION}" \
    --non-interactive 2>&1 | tee /dev/stderr) || true
  VERIFY_RUN_URL=$(printf '%s' "$VERIFY_OUT" | grep -oE 'https://expo\.dev[^[:space:]]*' | head -n 1 || true)
fi
cd "$ORIG_DIR"

DETAILS=$(tail -n +2 "$SUMMARY_FILE" 2>/dev/null || true)
VERIFY_LINE=""
if [ -n "$VERIFY_RUN_URL" ]; then
  VERIFY_LINE="
- 🧪 **Verifying** — code review + an Expo Simulator check follow ([run](${VERIFY_RUN_URL}))"
elif [ "${VERIFY:-false}" = "true" ]; then
  VERIFY_LINE="
- ⚠️ **Not verified** — the verify dispatch failed; comment \`${BOT} review\` to run it"
fi

node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent iteration

**Requested:** _${INSTRUCTION}_

✅ **Applied** — ${SUMMARY_LINE} (\`${COMMIT_SHA}\`, xcodebuild passed)${VERIFY_LINE}

${DETAILS}

_Posted by the expo-bot-change EAS workflow._"
COMMENT_POSTED=1

set_output commit "$COMMIT_SHA"
set_output verify_run_url "${VERIFY_RUN_URL:-none}"
