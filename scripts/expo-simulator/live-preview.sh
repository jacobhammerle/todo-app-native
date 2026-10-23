#!/usr/bin/env bash
# Boots an Expo Simulator running the native app and prints the browser
# preview link, so anyone can drive the app without Xcode. The session
# stays up until it hits the duration. Same sources as smoke-test.sh:
#   --build-id <id> | --archive-url <url> | --app <path>
# Options: --minutes <n> (default 30), --device <name> (default iPhone 17)
# When PR_NUMBER, GH_REPO (owner/repo) and GITHUB_TOKEN are set, the link
# is also posted as a PR comment.
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
. scripts/expo-simulator/lib.sh

BUILD_ID="" ARCHIVE_URL="" APP_PATH="" DEVICE="iPhone 17" MINUTES="30"
while [ $# -gt 0 ]; do
  case "$1" in
    --build-id) BUILD_ID="$2"; shift 2 ;;
    --archive-url) ARCHIVE_URL="$2"; shift 2 ;;
    --app) APP_PATH="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --minutes) MINUTES="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$BUILD_ID$ARCHIVE_URL$APP_PATH" ]; then
  echo "Pass one of --build-id, --archive-url, --app." >&2
  exit 2
fi

APP_ID=$(app_id)
use_simulator_token
# owner/repo for the PR comment: GH_REPO when set, else package.json "repository".
GH_REPO="${GH_REPO:-$(node -p "String(require('./package.json').repository || '').replace(/^github:/, '')")}"

NAME="Native live preview"
[ -n "${PR_NUMBER:-}" ] && NAME="PR #${PR_NUMBER} native preview"
START_ARGS=(--platform ios --type agent-device --device "$DEVICE" --max-duration-minutes "$MINUTES" --name "$NAME")
[ -n "$BUILD_ID" ] && START_ARGS+=(--build-id "$BUILD_ID")
[ -n "$ARCHIVE_URL" ] && START_ARGS+=(--application-archive-url "$ARCHIVE_URL")

echo "Starting a $MINUTES-minute $DEVICE session..."
START_JSON=$(start_session "${START_ARGS[@]}")
SESSION_ID=$(printf '%s' "$START_JSON" | json_field id)
wait_for_session "$SESSION_ID"
PREVIEW_URL=$(eas simulator:get --id "$SESSION_ID" --json --non-interactive | json_field remoteConfig.webPreviewUrl)

if [ -n "$APP_PATH" ]; then
  ad install "$APP_ID" "$APP_PATH" --platform ios
  ad open "$APP_ID" --platform ios --timeout 120000
fi

echo
echo "🌐 Live preview ($DEVICE): $PREVIEW_URL"
echo "   Stops by itself after $MINUTES minutes; stop early with:"
echo "   npx eas-cli@${EAS_CLI_VERSION} simulator:stop --id $SESSION_ID"
set_output preview_url "$PREVIEW_URL"
set_output session_id "$SESSION_ID"

if [ -n "${PR_NUMBER:-}" ] && [ -n "${GH_REPO:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
  BODY=$(printf '## 📱 Live preview\n\n**[Open the %s in your browser](%s)**\n\nThis PR'"'"'s native app is installed and running on an Expo Simulator. The session stops by itself after %s minutes; stop it early with `eas simulator:stop --id %s`.\n\n_Posted by the pr-live-preview EAS workflow._' "$DEVICE" "$PREVIEW_URL" "$MINUTES" "$SESSION_ID")
  node -e '
    const [repo, pr, body] = process.argv.slice(1);
    fetch(`https://api.github.com/repos/${repo}/issues/${pr}/comments`, {
      method: "POST",
      headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: "application/vnd.github+json" },
      body: JSON.stringify({ body }),
    }).then(async (r) => { if (!r.ok) { console.error(await r.text()); process.exit(1); } console.log("Commented on PR #" + pr); });
  ' "$GH_REPO" "$PR_NUMBER" "$BODY"
fi
