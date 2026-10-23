#!/usr/bin/env bash
# Parses the text after "@expo-bot preview" into the pr-live-preview
# workflow inputs. Prints two lines: duration=<minutes> and
# device=<iOS Simulator device name, or empty for the workflow default>.
# This app is iOS only, so there is no platform word.
#
#   @expo-bot preview                         30 min, default device
#   @expo-bot preview 45                      45 min
#   @expo-bot preview iPhone 17 Pro           device "iPhone 17 Pro"
#   @expo-bot preview 45 iPhone 17 Pro        both
#   @expo-bot preview iPhone 17 Pro for 45    both, natural order
#
# Rules, in order, per word:
#   - a bare number is the duration while no device word has been read yet;
#     "for N", "Nm", "Nmin", or "N minutes" is the duration anywhere
#     (so the 17 in "iPhone 17 Pro" stays part of the device name)
#   - filler words "ios", "on", "for", "device", "minute(s)", "min(s)" are dropped
#   - every other word joins the device name
#
# Usage: parse-preview-args.sh "<text after preview>"
# PREVIEW_DEFAULT_MINUTES overrides the 30-minute default duration.
set -euo pipefail

TEXT="${1:-}"
DEFAULT_DURATION="${PREVIEW_DEFAULT_MINUTES:-30}"

DURATION=""
DEVICE=""
EXPECT_DURATION=""

# Normalize quotes and commas so `preview "iPhone 17 Pro", 45` also works.
TEXT=$(printf '%s' "$TEXT" | tr '",\047' '   ')
# shellcheck disable=SC2206
WORDS=($TEXT)

for w in ${WORDS[@]+"${WORDS[@]}"}; do
  lower=$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')
  if [ -n "$EXPECT_DURATION" ] && [[ "$lower" =~ ^([0-9]+)(m|min|mins|minute|minutes)?$ ]]; then
    DURATION="${BASH_REMATCH[1]}"; EXPECT_DURATION=""; continue
  fi
  EXPECT_DURATION=""
  case "$lower" in
    for) EXPECT_DURATION=1; continue ;;
    ios|on|device|minute|minutes|min|mins) continue ;;
  esac
  if [[ "$lower" =~ ^([0-9]+)(m|min|mins|minute|minutes)$ ]]; then
    DURATION="${BASH_REMATCH[1]}"; continue
  fi
  if [[ "$lower" =~ ^[0-9]+$ ]] && [ -z "$DEVICE" ]; then
    DURATION="$lower"; continue
  fi
  DEVICE="${DEVICE:+$DEVICE }$w"
done

[ -n "$DURATION" ] || DURATION="$DEFAULT_DURATION"
# A zero-minute session is meaningless; treat it as the default.
[ "$DURATION" -gt 0 ] 2>/dev/null || DURATION="$DEFAULT_DURATION"

echo "duration=$DURATION"
echo "device=$DEVICE"
