#!/usr/bin/env bash
# Runs on an EAS macOS worker after an issue was REPLICATED (a bug) or
# CONFIRMED (a missing capability) on an Expo Simulator: clones the base
# branch, lets an agent write a minimal Swift change, compiles it with
# xcodebuild (the gate; the Expo repo's is tsc + lint), pushes
# expo-bot/issue-N, opens a PR that closes the issue, comments the PR link
# on the issue, and dispatches expo-bot-verify on the PR.
# The replication report comes from the evidence site's evidence.json,
# because this job runs on a different worker than the replication.
# Requires: ISSUE_NUMBER, BASE_BRANCH, GITHUB_TOKEN, EVIDENCE_URL,
#           VERDICT_LINE, the agent runner's credentials
# Optional: AUTO_VERIFY (default true; "false" skips the verify dispatch),
#           EXPO_TOKEN_SIMULATOR (the token that dispatches the verify run),
#           GH_REPO (owner/repo; default: package.json "repository")
set -euo pipefail

ORIG_DIR=$(pwd)
# shellcheck disable=SC1091
. "$ORIG_DIR/scripts/agent/comment-lib.sh"
BOT=$(bot_handle)
GH_REPO=$(repo_slug)
export GH_REPO
FIX_DIR=/tmp/fix-repo
FIX_BRANCH="${BOT#@}/issue-${ISSUE_NUMBER}"
rm -rf "$FIX_DIR" /tmp/fix-summary.md

require_env GITHUB_TOKEN "add a GitHub token with issues, contents, and pull-request write access in the production EAS environment."
use_simulator_token
use_agent_token

# A run that dies before commenting would leave the issue without the
# outcome of the fix step.
COMMENT_POSTED=""
cleanup() {
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    node "$ORIG_DIR/scripts/agent/gh.mjs" comment "$ISSUE_NUMBER" "## 🤖 Agent fix

⚠️ **The fix step errored before it could open a PR** — see the \"Fix on a macOS worker\" job of the expo-bot-issue run on EAS. A human needs to pick this up.

_Posted by the expo-bot-issue EAS workflow._" || true
  fi
}
trap cleanup EXIT

# Issue context and the replication report (the evidence site holds it).
node "$ORIG_DIR/scripts/agent/gh.mjs" get-issue "$ISSUE_NUMBER" > /tmp/issue-info.json
ISSUE_TITLE=$(json_file_field /tmp/issue-info.json title)
curl -fsSL "${EVIDENCE_URL%/}/evidence.json" > /tmp/evidence.json
{
  printf '%s\n\n' "$VERDICT_LINE"
  json_file_field /tmp/evidence.json report
} > /tmp/issue-verdict.md
# Replication screenshots, inline, so the PR shows the bug it fixes.
THUMBS=$(node -e "
  const e = JSON.parse(require('fs').readFileSync('/tmp/evidence.json', 'utf8'));
  const base = process.argv[1].replace(/\/\$/, '');
  const files = (e.images ?? []).map(i => typeof i === 'string' ? i : (i.file ?? i.name ?? i.src ?? '')).filter(Boolean).slice(0, 4);
  console.log(files.map(f => '<a href=\"' + base + '/' + f + '\"><img src=\"' + base + '/' + f + '\" width=\"150\" /></a>').join(' '));
" "$EVIDENCE_URL")

# The workflow checkout has no pushable git remote, so work in a real clone.
git clone --depth 1 --branch "$BASE_BRANCH" \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/${GH_REPO}.git" "$FIX_DIR"

cp "$ORIG_DIR/.eas/expo-bot-fix-prompt.md" /tmp/fix-prompt.md
printf '\nThe issue under fix is #%s on %s.\n' "$ISSUE_NUMBER" "$GH_REPO" >> /tmp/fix-prompt.md

echo "Running the fix agent..."
cd "$FIX_DIR"
# The summary file is the contract; the agent's exit code is not.
bash "$ORIG_DIR/scripts/agent/run-agent.sh" run --prompt-file /tmp/fix-prompt.md \
  --profile fix --max-turns 80 --timeout 15m

no_fix_comment() {
  node "$ORIG_DIR/scripts/agent/gh.mjs" comment "$ISSUE_NUMBER" "## 🤖 Agent fix

**Verdict:** $(verdict_badge "$VERDICT_LINE")

- ⚠️ **No PR opened** — $1 A human needs to pick this up.
- 🖼️ **Evidence** — ${EVIDENCE_URL}

_Posted by the expo-bot-issue EAS workflow._"
  COMMENT_POSTED=1
}

if [ -z "$(git status --porcelain)" ]; then
  REASON=""
  if [ -s /tmp/fix-summary.md ]; then
    REASON=$(head -n 1 /tmp/fix-summary.md | sed -E 's/^No fix:[[:space:]]*//')
  fi
  [ -n "$REASON" ] || REASON="the fix agent errored or timed out; see the workflow logs."
  no_fix_comment "$REASON"
  set_output pr_url "none"
  set_output verify_run_url "none"
  exit 0
fi

# Hard gate: never push Swift that does not compile. xcodebuild runs here
# on the macOS worker; the simulator build is also what expo-bot-verify
# will install.
if ! npm run build:simulator; then
  no_fix_comment "the agent's change did not compile (xcodebuild failed); the compiler output is in the workflow logs."
  set_output pr_url "none"
  set_output verify_run_url "none"
  exit 1
fi

SUMMARY_LINE=$(head -n 1 /tmp/fix-summary.md 2>/dev/null || true)
[ -n "$SUMMARY_LINE" ] || SUMMARY_LINE="Fix the behavior reported in issue #${ISSUE_NUMBER}"
DETAILS=$(tail -n +2 /tmp/fix-summary.md 2>/dev/null | sed '/./,$!d' || true)

# The github-actions[bot] noreply address: commits show the bot avatar and
# the address does not deliver mail.
git config user.name "${BOT#@}"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$FIX_BRANCH"
git add -A
git commit -m "${BOT#@}: ${SUMMARY_LINE}" \
  -m "Fixes #${ISSUE_NUMBER}. Replicated on an Expo Simulator, then fixed and compiled on an EAS macOS worker, via an ${BOT} issue comment."
# The branch is bot-owned: force push so re-triaging the issue replaces it.
git push --force origin "$FIX_BRANCH"

if [[ "$VERDICT_LINE" == CONFIRMED* ]]; then
  KIND_WORD="implementation"; DID_WORD="confirmed the capability is missing"
else
  KIND_WORD="fix"; DID_WORD="replicated the report"
fi

# The agent writes three "### " sections. "What changed" stays visible;
# the why and the file list fold away.
CHANGED=$(printf '%s\n' "$DETAILS" | awk '/^### What changed/{f=1} /^### / && !/^### What changed/{f=0} f')
if [ -n "$CHANGED" ]; then
  REST=$(printf '%s\n' "$DETAILS" | awk '/^### What changed/{f=1; next} /^### /{f=0} !f' | sed '/./,$!d')
  WRITEUP="${CHANGED}

<details>
<summary>What was wrong, files touched</summary>

${REST}

</details>"
else
  WRITEUP="$DETAILS"
fi

if [ "${AUTO_VERIFY:-true}" != "false" ]; then
  NEXT_LINE="**Posted below as they complete:** code review · agent verification on a second Expo Simulator · the EAS Build to install."
else
  NEXT_LINE="**Not verified yet:** comment \`${BOT}\` on this PR for a code review and an Expo Simulator check."
fi

PR_BODY="## 🤖 Automated ${KIND_WORD} for #${ISSUE_NUMBER}

**Issue:** #${ISSUE_NUMBER} ${ISSUE_TITLE}
**Replication verdict:** $(verdict_badge "$VERDICT_LINE")
**Evidence:** [screenshots](${EVIDENCE_URL}) — an agent ${DID_WORD} on an Expo Simulator; an agent wrote the ${KIND_WORD} on an EAS macOS worker; xcodebuild passes

${THUMBS}

${WRITEUP}

${NEXT_LINE}

Closes #${ISSUE_NUMBER}. _Opened by the expo-bot-issue EAS workflow._"

PR_JSON=$(node "$ORIG_DIR/scripts/agent/gh.mjs" create-pr \
  "${SUMMARY_LINE} (#${ISSUE_NUMBER})" "$FIX_BRANCH" "$BASE_BRANCH" "$PR_BODY")
PR_URL=$(node -e "console.log(JSON.parse(process.argv[1]).url)" "$PR_JSON")
PR_NUMBER=$(node -e "console.log(JSON.parse(process.argv[1]).number)" "$PR_JSON")
echo "Opened ${KIND_WORD} PR: $PR_URL"

VERIFY_RUN_URL=""
if [ "${AUTO_VERIFY:-true}" != "false" ]; then
  # Dispatch from this clone, not the workflow checkout: workflow:run
  # uploads the current tree, and expo-bot-verify must see the PR's code.
  # A dispatch failure is reported, not fatal: the PR still exists and a
  # human can comment on it.
  echo "Dispatching expo-bot-verify on PR #$PR_NUMBER..."
  VERIFY_INSTRUCTION=$(printf "This PR was opened by ${BOT} for issue #%s (%s). Verify that behavior specifically: %s" \
    "$ISSUE_NUMBER" "$ISSUE_TITLE" "$VERDICT_LINE")
  VERIFY_OUT=$(eas workflow:run .eas/workflows/expo-bot-verify.yml \
    --input "pr_number=${PR_NUMBER}" \
    --input "instruction=${VERIFY_INSTRUCTION}" \
    --non-interactive 2>&1 | tee /dev/stderr) || true
  VERIFY_RUN_URL=$(printf '%s' "$VERIFY_OUT" | grep -oE 'https://expo\.dev[^[:space:]]*' | head -n 1 || true)
fi
cd "$ORIG_DIR"

VERIFY_LINE=""
if [ -n "$VERIFY_RUN_URL" ]; then
  VERIFY_LINE="
- 🧪 **Verifying** — code review + a second Expo Simulator; results land on the PR ([run](${VERIFY_RUN_URL}))"
else
  VERIFY_LINE="
- ⚠️ **Not verified** — comment \`${BOT}\` on the PR to review and check it on an Expo Simulator"
fi
PR_WORD="Fix"; [ "$KIND_WORD" = "implementation" ] && PR_WORD="Implementation"

node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent fix

**Verdict:** $(verdict_badge "$VERDICT_LINE")

- 🔧 **${PR_WORD} PR** — ${PR_URL} (compiled with xcodebuild on an EAS macOS worker)${VERIFY_LINE}
- 🖼️ **Evidence** — ${EVIDENCE_URL}

_Posted by the expo-bot-issue EAS workflow._"
COMMENT_POSTED=1

set_output pr_url "$PR_URL"
set_output verify_run_url "${VERIFY_RUN_URL:-none}"
