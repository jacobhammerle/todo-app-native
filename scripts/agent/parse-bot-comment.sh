#!/usr/bin/env bash
# Parses a bot mention comment into GITHUB_OUTPUT lines:
#   handle=<the mention, e.g. @expo-bot>
#   mode=<full|change|review|preview|issue|none>
#   instruction=<text after the keyword>
# The mention is "botHandle" in package.json (BOT_HANDLE overrides it).
# Only the first line of the comment counts.
#
# On a pull request (target "pr"):
#   @bot <instruction>          mode=full    apply the change, then review + verify
#   @bot change <instruction>   mode=change  apply the change only (instruction required)
#   @bot review [instruction]   mode=review  review + verify only
#   @bot preview [args]         mode=preview args parsed later by parse-preview-args.sh
#   @bot                        mode=review  a bare mention
# On an issue (target "issue"): mode=issue, and everything after the
# mention is guidance for the replication agent.
#
# The mention must be a whole word at the start of the comment: followed by
# whitespace or the end of the line. Any other comment ("@expo-bottle x", or
# a comment not meant for the bot) prints mode=none and exits 0, so the
# bridge can skip it quietly.
#
# Usage: parse-bot-comment.sh "<comment body>" <pr|issue>
set -euo pipefail

BODY="${1:-}"
TARGET="${2:?second argument must be pr or issue}"
BOT="${BOT_HANDLE:-$(node -p "require('./package.json').botHandle || '@expo-bot'")}"
echo "handle=$BOT"

FIRST_LINE=$(printf '%s' "$BODY" | head -n 1 | tr -d '\r')
# Literal match on the handle, then a whole-word boundary.
case "$FIRST_LINE" in
  "$BOT"|"$BOT "*|"$BOT	"*) ;;
  *) echo "mode=none"; echo "instruction="; exit 0 ;;
esac
FIRST_LINE=$(printf '%s' "${FIRST_LINE#"$BOT"}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

if [ "$TARGET" = "issue" ]; then
  MODE=issue
  INSTRUCTION="$FIRST_LINE"
else
  MODE=full
  INSTRUCTION="$FIRST_LINE"
  # The first word may be a mode keyword; the rest is the instruction.
  read -r KEYWORD REST <<< "$FIRST_LINE" || true
  case "$KEYWORD" in
    review|change|preview)
      MODE=$KEYWORD
      INSTRUCTION="${REST:-}"
      ;;
  esac
  if [ "$MODE" = "change" ] && [ -z "$INSTRUCTION" ]; then
    echo "change mode needs an instruction after the keyword." >&2
    exit 1
  fi
  if [ "$MODE" = "full" ] && [ -z "$INSTRUCTION" ]; then
    MODE=review
  fi
fi

echo "mode=$MODE"
echo "instruction=$INSTRUCTION"
