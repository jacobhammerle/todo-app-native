#!/usr/bin/env bash
# An agent reviews the PR diff and posts a review comment on the PR.
# The workflow is dispatched from a comment, so there is no pull_request
# context and the checkout may lack git metadata, so the diff comes from the
# GitHub API instead of git.
# Requires: PR_NUMBER, GITHUB_TOKEN,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: GH_REPO (owner/repo; default: package.json "repository")
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh

require_env GITHUB_TOKEN "add a GitHub token with pull-request write access as a secret env var in the production EAS environment."
use_agent_token

# A run that dies before commenting would leave the PR silent.
COMMENT_POSTED=""
cleanup() {
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Automated code review

⚠️ **Review errored before it could complete** — see the expo-bot-verify run logs on EAS.

_Posted by the expo-bot-verify EAS workflow._" || true
  fi
}
trap cleanup EXIT

node scripts/agent/gh.mjs get-pr "$PR_NUMBER" > /tmp/pr-info.json
node scripts/agent/gh.mjs get-pr-diff "$PR_NUMBER" > /tmp/pr.diff

cap_diff /tmp/pr.diff

PROMPT=$(cat <<'EOF'
Review this pull request diff for a native SwiftUI to-do demo app
(iOS only; the project is in ios/SimpleTodo/, built by EAS Build and run
on Expo Simulators). The diff is in /tmp/pr.diff and the PR title and
body are in /tmp/pr-info.json. You may read the project source (current
working directory) for context.

Write a concise code review in GitHub Markdown to /tmp/review.md, in
exactly this shape (fill in the angle-bracket parts, keep everything
else verbatim; lines 1-3 are shown, the rest is folded away):

**Verdict:** ✅ LGTM

**Summary** — <one line: what the change does and whether it is safe>

1. 🎯 **Correctness** — <does the change do what the PR says? Name the
   edge cases you checked>
2. 🐛 **Bugs and risks** — <real problems found, most severe first,
   or "None found."; skip style nits. A Swift file added without an
   entry in ios/SimpleTodo.xcodeproj, or an accessibility identifier the
   scripts target (task-title-input, add-task, clear-history, preset-*)
   renamed or removed, is a real problem>

Use "**Verdict:** ⚠️ Needs changes" instead when you find a real
problem. Keep the whole review under 200 words.
EOF
)

# The review file is the contract; the agent's exit code is not.
printf '%s\n' "$PROMPT" > /tmp/review-prompt.md
bash scripts/agent/run-agent.sh run --prompt-file /tmp/review-prompt.md \
  --profile review --max-turns 40 --timeout 10m

if [ ! -s /tmp/review.md ]; then
  echo "**Verdict:** ⚠️ Review errored: the reviewer produced no output. See the workflow logs." > /tmp/review.md
fi

# Verdict and summary stay visible; the numbered notes fold away.
REVIEW_HEAD=$(head -n 3 /tmp/review.md)
REVIEW_NOTES=$(tail -n +4 /tmp/review.md | sed '/./,$!d')
NOTES_BLOCK=""
if [ -n "$REVIEW_NOTES" ]; then
  NOTES_BLOCK="
<details>
<summary>Review notes</summary>

${REVIEW_NOTES}

</details>
"
fi
node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Automated code review

${REVIEW_HEAD}
${NOTES_BLOCK}
_Posted by the expo-bot-verify EAS workflow._"
COMMENT_POSTED=1
