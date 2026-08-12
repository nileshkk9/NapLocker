#!/usr/bin/env bash
# Build NapLocker from source and install it to /Applications.
# Requires Xcode (not just the Command Line Tools) — an app bundle can't be
# produced without it.
#
#   curl -fsSL https://raw.githubusercontent.com/nileshkk9/NapLocker/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/nileshkk9/NapLocker.git"
APP_NAME="NapLocker"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: Xcode is required to build $APP_NAME from source." >&2
    echo "Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Cloning $APP_NAME..."
git clone --depth 1 "$REPO_URL" "$WORKDIR/$APP_NAME"

echo "Building (Release)..."
xcodebuild -project "$WORKDIR/$APP_NAME/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration Release -derivedDataPath "$WORKDIR/build" clean build

BUILT_APP="$WORKDIR/build/Build/Products/Release/$APP_NAME.app"

if [ -d "/Applications/$APP_NAME.app" ]; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
fi

echo "Installing to /Applications..."
cp -R "$BUILT_APP" /Applications/
touch "/Applications/$APP_NAME.app"

echo "Launching $APP_NAME..."
open "/Applications/$APP_NAME.app"

echo "Done — $APP_NAME is installed at /Applications/$APP_NAME.app"
