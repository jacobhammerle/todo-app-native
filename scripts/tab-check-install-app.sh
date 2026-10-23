#!/usr/bin/env bash
# Install the newest finished EAS simulator build into the simulator session in
# .env.eas-simulator. Used by scripts/tab-check-run.sh only when the app is not
# installed on the session (a session started without --build-id).
#
# iOS artifacts are a .tar.gz holding a .app directory; Android artifacts are a
# .apk. Both are downloaded locally and uploaded with `agent-device install`.
# `install-from-source <expo.dev url>` was tried first and fails inside the EAS
# VM with "App source network request failed" (observed 2026-08-26), so the
# upload path is used.
#
# Usage: scripts/tab-check-install-app.sh [BUILD_ID]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/tab-check-lib.sh
require_type agent-device "Installing the app from these scripts" || exit 1
load_session_env

if [ -n "${1:-}" ]; then
  BUILD_JSON=$(eas build:view "$1" --json 2>/dev/null)
  URL=$(field "$BUILD_JSON" artifacts.applicationArchiveUrl)
  ID=$1
else
  PICK=$(newest_build "$TAB_CHECK_PLATFORM") || PICK=""
  [ -n "$PICK" ] || { echo "No finished $TAB_CHECK_PLATFORM build with an artifact found." >&2; exit 2; }
  ID=${PICK%% *}
  URL=${PICK#* }
fi

WORK="${TMPDIR:-/tmp}/tab-check-build-$ID"
mkdir -p "$WORK"

if [ "$TAB_CHECK_PLATFORM" = android ]; then
  APP="$WORK/app.apk"
  if [ ! -f "$APP" ]; then
    echo "Downloading build $ID ..."
    curl -sS -m 600 -L -o "$APP" "$URL"
  fi
else
  if [ -z "$(find "$WORK" -maxdepth 1 -name '*.app' 2>/dev/null)" ]; then
    echo "Downloading build $ID ..."
    curl -sS -m 600 -L -o "$WORK/app.tar.gz" "$URL"
    tar -xzf "$WORK/app.tar.gz" -C "$WORK"
  fi
  APP=$(find "$WORK" -maxdepth 1 -name '*.app' | head -1)
  [ -n "$APP" ] || { echo "No .app found in the artifact." >&2; exit 2; }
fi

echo "Installing $TAB_CHECK_APP_ID from build $ID ($APP)"
agent_device install "$TAB_CHECK_APP_ID" "$APP"
