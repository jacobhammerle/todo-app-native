#!/usr/bin/env bash
# Posts one bridge comment on the PR or issue, in the shape every
# bot post shares:
#   ## <heading>
#   <body>
#   _<note> Posted by the <bot> bridge for @<actor>._
#
# Usage: bot-comment.sh "<heading>" "<body markdown>" ["<note>"]
# Requires: ISSUE_NUMBER (PR or issue number), ACTOR (comment author),
#           GH_TOKEN and GH_REPO for the gh CLI.
# DRY_RUN=1 prints the comment instead of posting it.
set -euo pipefail

HEADING="${1:?heading}"
BODY="${2:?body}"
NOTE="${3:-}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ACTOR:?ACTOR is required}"

FOOTER="Posted by the ${BOT_HANDLE:-$(node -p "require('./package.json').botHandle || '@expo-bot'")} bridge for @${ACTOR}."
if [ -n "$NOTE" ]; then
  FOOTER="${NOTE} ${FOOTER}"
fi

BODY_FILE=$(mktemp)
printf '## %s\n\n%s\n\n_%s_\n' "$HEADING" "$BODY" "$FOOTER" > "$BODY_FILE"

if [ "${DRY_RUN:-}" = "1" ]; then
  echo "--- comment on #${ISSUE_NUMBER} (dry run) ---"
  cat "$BODY_FILE"
  echo "--- end comment ---"
else
  gh issue comment "$ISSUE_NUMBER" --body-file "$BODY_FILE"
fi
rm -f "$BODY_FILE"
