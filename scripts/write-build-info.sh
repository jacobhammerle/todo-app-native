#!/bin/sh
# Xcode run-script phase (see ios/project.yml). Stamps build provenance into
# the Info.plist of the built bundle so the app can show it on the Admin tab:
#
#   BuildSource      "eas" on EAS Build, "local" for a plain xcodebuild
#   EASBuildID       EAS_BUILD_ID, set by EAS Build during the job
#   EASBuildProfile  EAS_BUILD_PROFILE, the eas.json profile
#   GitCommit        EAS_BUILD_GIT_COMMIT_HASH, or `git rev-parse HEAD` locally
#   BuiltAt          UTC timestamp
#
# Nothing here touches the source Info.plist; only the copy inside the .app.
set -eu

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ]; then
  echo "write-build-info: no Info.plist at $PLIST" >&2
  exit 1
fi

set_key() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"
}

if [ -n "${EAS_BUILD_ID:-}" ]; then
  source="eas"
else
  source="local"
fi

commit="${EAS_BUILD_GIT_COMMIT_HASH:-}"
if [ -z "$commit" ]; then
  commit=$(git -C "${SRCROOT}" rev-parse --verify --quiet HEAD 2>/dev/null || true)
fi

set_key BuildSource "$source"
set_key EASBuildID "${EAS_BUILD_ID:-}"
set_key EASBuildProfile "${EAS_BUILD_PROFILE:-}"
set_key GitCommit "$commit"
set_key BuiltAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "write-build-info: source=$source commit=${commit:-none} build=${EAS_BUILD_ID:-none}"
