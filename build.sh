#!/bin/bash
# Builds Setlist.app. No Xcode required -- Command Line Tools are enough.
#
# This calls swiftc directly rather than using Swift Package Manager, because
# SwiftPM is broken on this machine (mismatched Command Line Tools versions).
# The app has no third-party dependencies, so nothing is lost by doing so.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Setlist"
BUNDLE="$APP_NAME.app"

mkdir -p build
swiftc \
    -parse-as-library \
    -O \
    -target arm64-apple-macosx14.0 \
    -o "build/$APP_NAME" \
    Sources/Setlist/*.swift

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp "build/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc signature: enough to run locally on Apple Silicon, no developer account.
codesign --force --sign - "$BUNDLE"

echo "Built $(pwd)/$BUNDLE"
