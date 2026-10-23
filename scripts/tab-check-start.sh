#!/usr/bin/env bash
# Start the pre-demo EAS simulator session for /tab-check and keep it ready.
#
# Usage: scripts/tab-check-start.sh ["Session name"] [BUILD_ID] [flags]
#
# Flags (any order, before or after the positionals):
#   --android | --ios          platform shorthand          (default: --ios)
#   -p, --platform <ios|android>
#   --type <agent-device|argent|appium|web-preview-only>   (default: agent-device)
#                              ('serve-sim' is accepted as the old name)
#   --device <name>            simulator device / AVD profile to boot
#
#   bash scripts/tab-check-start.sh "Live demo for Acme"
#   bash scripts/tab-check-start.sh "Live demo for Acme" --android
#   bash scripts/tab-check-start.sh "Argent demo" --type argent
#
#   1. Starts a session with the newest finished `simulator` build for that
#      platform (or BUILD_ID), so the app is already installed.
#   2. Records the platform/type pair so the other tab-check scripts target the
#      same session without repeating the flags.
#   3. Runs scripts/tab-check-preflight.sh, which checks the app and starts the
#      keepalive that stops the daemon from idling out.
#
# Only 'agent-device' sessions can be driven by tab-check-run.sh. The other
# types start and connect; drive them with their own tooling.
# Pass TAB_CHECK_MAX_MINUTES to bound the session (default: none, EAS default).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="" TYPE="" DEVICE="" NAME="" BUILD="" POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --android) PLATFORM=android ;;
    --ios) PLATFORM=ios ;;
    -p|--platform) shift; PLATFORM=${1:-} ;;
    --type) shift; TYPE=${1:-} ;;
    --device) shift; DEVICE=${1:-} ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) POS+=("$1") ;;
  esac
  shift
done
NAME="Tab check demo"
BUILD=""
if [ ${#POS[@]} -ge 1 ]; then NAME="${POS[0]}"; fi
if [ ${#POS[@]} -ge 2 ]; then BUILD="${POS[1]}"; fi

# Export before sourcing the lib so they win over the recorded pair.
[ -n "$PLATFORM" ] && export TAB_CHECK_PLATFORM="$PLATFORM"
[ -n "$TYPE" ] && export TAB_CHECK_TYPE="$TYPE"
# A fresh start defines the pair; ignore what a previous run recorded.
export TAB_CHECK_PLATFORM="${TAB_CHECK_PLATFORM:-ios}"
export TAB_CHECK_TYPE="${TAB_CHECK_TYPE:-agent-device}"
. scripts/tab-check-lib.sh

valid_platform "$TAB_CHECK_PLATFORM" || { echo "--platform must be ios or android, got '$TAB_CHECK_PLATFORM'." >&2; exit 2; }
valid_type "$TAB_CHECK_TYPE" || { echo "--type must be agent-device, argent, appium or web-preview-only, got '$TAB_CHECK_TYPE'." >&2; exit 2; }

echo "platform: $TAB_CHECK_PLATFORM"
echo "type:     $TAB_CHECK_TYPE"

if [ -z "$BUILD" ]; then
  # Not `read < <(...)`: process substitution hides the helper's exit code.
  PICK=$(newest_build "$TAB_CHECK_PLATFORM") || PICK=""
  [ -n "$PICK" ] || { echo "No finished $TAB_CHECK_PLATFORM $TAB_CHECK_BUILD_PROFILE build with an installable artifact found. Run: eas build --platform ios --profile simulator" >&2; exit 2; }
  BUILD=${PICK%% *}
fi
echo "build:    $BUILD"

# Record the pair before starting, so a failed start still leaves the later
# scripts pointing at the platform/type the operator asked for.
save_session_conf

ARGS=(--platform "$TAB_CHECK_PLATFORM" --type "$TAB_CHECK_TYPE" --non-interactive --name "$NAME" --build-id "$BUILD" --json)
[ -n "$DEVICE" ] && ARGS+=(--device "$DEVICE")
[ -n "${TAB_CHECK_MAX_MINUTES:-}" ] && ARGS+=(--max-duration-minutes "$TAB_CHECK_MAX_MINUTES")
J=$(eas simulator:start "${ARGS[@]}" 2>/dev/null) || { echo "simulator:start failed" >&2; exit 1; }
ID=$(field "$J" id)
echo "session:  $ID  \"$NAME\""

PREVIEW=$(preview_url "$J")
if [ -n "$PREVIEW" ]; then
  echo "preview:  $PREVIEW"
elif [ "$TAB_CHECK_PLATFORM" = android ]; then
  echo "preview:  (none - Android sessions have no web preview)"
else
  echo "preview:  (none)"
fi

bash scripts/tab-check-preflight.sh "$ID"
