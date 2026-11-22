#!/bin/bash
# Builds Solid Copy.
#
#   bash build.sh            build only (into the build folder)
#   bash build.sh install    build, then quit Solid Copy if it's running
#                            and replace "/Applications/Solid Copy.app".
#                            It doesn't open it: open it yourself (Dock,
#                            Spotlight), so it comes up in front with its
#                            window, and never grabs focus while you're
#                            typing elsewhere. (Opened from a script in the
#                            background, it once came up with no window
#                            Command-Tab could reach, 15 November 2026.)
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Solid Copy"
BUILT="build/derived/Build/Products/Debug/SolidCopy.app"
INSTALLED="/Applications/$APP_NAME.app"

case "${1:-}" in
  ""|install) ;;
  *) echo "Usage: bash build.sh [install]" >&2; exit 2 ;;
esac

# Your Apple Developer team ID, kept out of git in team.txt.
TEAM="$(tr -d '[:space:]' < team.txt 2>/dev/null || true)"
if [ -z "$TEAM" ]; then
  echo "Put your Apple Developer team ID in team.txt first." >&2
  exit 1
fi

# Turn project.yml into SolidCopy.xcodeproj.
xcodegen generate --quiet

# Build. -quiet prints only warnings and errors.
# -allowProvisioningUpdates lets Xcode create the signing profile it needs.
xcodebuild -quiet \
  -project SolidCopy.xcodeproj -scheme SolidCopy -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/derived \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build

echo "Built: $(pwd)/$BUILT"

if [ "${1:-}" != "install" ]; then
  echo "To build and install:  bash build.sh install"
  exit 0
fi

# Ask a running copy to quit, the same as choosing Quit from its menu,
# and wait up to 5 seconds for it to close.
if pgrep -x SolidCopy >/dev/null; then
  osascript -e 'tell application id "io.github.scott-h5.solidcopy" to quit' || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x SolidCopy >/dev/null || break
    sleep 0.5
  done
  # Still running (a question on screen, say): don't replace it under it.
  if pgrep -x SolidCopy >/dev/null; then
    echo "Solid Copy didn't quit. Quit it, then run this again." >&2
    exit 1
  fi
fi

rm -rf "$INSTALLED"
cp -R "$BUILT" "$INSTALLED"

# Signed like the downloads (Developer ID), when you have that certificate
# for this team: the Keychain lets an app read what it saved only while
# its signature stays the same kind, so a copy built here and one
# downloaded would otherwise each ask for your password to read your
# logins. Without a Developer ID certificate (most people building from
# source), the build's own development signature is kept, as before.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n "s/.*\"\(Developer ID Application:[^\"]*($TEAM)\)\".*/\1/p" | head -1)"
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --options runtime --timestamp=none \
    --entitlements macOS/SolidCopy.entitlements --sign "$IDENTITY" "$INSTALLED"
  codesign --verify --deep --strict "$INSTALLED"
  echo "Signed with $IDENTITY."
fi
echo "Installed: $INSTALLED"

echo "Open Solid Copy when you're ready (Dock or Spotlight)."
