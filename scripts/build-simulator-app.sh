#!/usr/bin/env bash
# Builds the iOS Simulator app with xcodebuild and packs it the way Expo
# Simulators installs it from a URL: a .tar.gz with SimpleTodo.app at its
# root (a .zip does not install). Output:
#   build/SimpleTodo.app          the bundle (agent-device `install` uploads it)
#   build/SimpleTodo.app.tar.gz   the archive for --application-archive-url
# Optional: CONFIGURATION=Debug (default Release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED="build/DerivedData"
PRODUCTS="$DERIVED/Build/Products/${CONFIGURATION}-iphonesimulator"

echo "xcodebuild SimpleTodo ($CONFIGURATION, iphonesimulator)..."
xcodebuild \
  -project ios/SimpleTodo.xcodeproj \
  -scheme SimpleTodo \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet build

rm -rf build/SimpleTodo.app build/SimpleTodo.app.tar.gz
cp -R "$PRODUCTS/SimpleTodo.app" build/SimpleTodo.app
tar -czf build/SimpleTodo.app.tar.gz -C build SimpleTodo.app

echo "Built build/SimpleTodo.app"
echo "Archive build/SimpleTodo.app.tar.gz ($(du -h build/SimpleTodo.app.tar.gz | cut -f1))"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :BuildSource" -c "Print :GitCommit" build/SimpleTodo.app/Info.plist
