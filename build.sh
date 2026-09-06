#!/bin/bash
# Builds Setlist.app. No Xcode required -- Command Line Tools are enough.
#
#   ./build.sh            build into the source directory
#   ./build.sh --install  build, then install to /Applications for Launchpad
#
# This calls swiftc directly rather than using Swift Package Manager, because
# SwiftPM is broken on this machine (mismatched Command Line Tools versions).
# The app has no third-party dependencies, so nothing is lost by doing so.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Setlist"
BUNDLE="$APP_NAME.app"
INSTALL_DIR="/Applications"

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
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "build/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc signature: enough to run locally on Apple Silicon, no developer account.
codesign --force --sign - "$BUNDLE"

echo "Built $(pwd)/$BUNDLE"

if [ "${1:-}" = "--install" ]; then
    # Quit a running copy first; macOS will not replace a bundle in use cleanly.
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1

    rm -rf "${INSTALL_DIR:?}/$BUNDLE"
    cp -R "$BUNDLE" "$INSTALL_DIR/"

    # Tell LaunchServices about it so it shows up in Launchpad and Spotlight
    # without waiting for a rescan.
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$INSTALL_DIR/$BUNDLE" || true

    echo "Installed $INSTALL_DIR/$BUNDLE"
fi
