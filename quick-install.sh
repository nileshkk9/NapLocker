#!/usr/bin/env bash
# Download the latest prebuilt NapLocker.app from GitHub Releases and install
# it to /Applications. No Xcode required.
#
#   curl -fsSL https://raw.githubusercontent.com/nileshkk9/NapLocker/main/quick-install.sh | bash
set -euo pipefail

APP_NAME="NapLocker"
ZIP_URL="https://github.com/nileshkk9/NapLocker/releases/latest/download/NapLocker.zip"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading latest $APP_NAME release..."
curl -fsSL "$ZIP_URL" -o "$WORKDIR/$APP_NAME.zip"

echo "Unzipping..."
ditto -x -k "$WORKDIR/$APP_NAME.zip" "$WORKDIR"

if [ -d "/Applications/$APP_NAME.app" ]; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
fi

echo "Installing to /Applications..."
cp -R "$WORKDIR/$APP_NAME.app" /Applications/

# NapLocker is ad-hoc signed (no paid Apple Developer ID, so it isn't
# notarized). A freshly downloaded copy carries a com.apple.quarantine
# attribute that makes Gatekeeper refuse to open it ("Apple cannot check it
# for malicious software"). Clearing that attribute here — right after
# install, before the first launch — is the standard workaround for
# distributing a signed-but-not-notarized app outside the App Store. It also
# means Gatekeeper's automated malware check never runs on this copy, so only
# do this for a source you trust.
xattr -cr "/Applications/$APP_NAME.app"
touch "/Applications/$APP_NAME.app"

echo "Launching $APP_NAME..."
open "/Applications/$APP_NAME.app"

echo "Done — $APP_NAME is installed at /Applications/$APP_NAME.app"
