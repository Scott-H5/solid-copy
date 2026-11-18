#!/bin/bash
# release.sh
#
# Makes the download: a Release build of Solid Copy, signed with your
# Developer ID, sent to Apple to be notarized (checked for malware, so
# people can open it without warnings), then packed as a zip with a
# checksum in build/release/. It doesn't upload anything; you publish the
# zip yourself, on GitHub.
#
# Before the first run, once:
#   1. A "Developer ID Application" certificate in your keychain, from
#      developer.apple.com (Certificates, Identifiers & Profiles). Check
#      with:  security find-identity -v -p codesigning
#   2. Notary credentials stored under a name. Run this and enter your
#      Apple ID, team ID and an app-specific password when asked:
#        xcrun notarytool store-credentials solid-copy-notary
#
# Then run it, from this folder:
#   bash release.sh
set -euo pipefail
cd "$(dirname "$0")"

TEAM="$(tr -d '[:space:]' < team.txt 2>/dev/null || true)"
[ -n "$TEAM" ] || { echo "Put your Apple Developer team ID in team.txt first." >&2; exit 1; }

PROFILE="${NOTARY_PROFILE:-solid-copy-notary}"

IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application certificate in your keychain. See the notes at the top of release.sh." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No notary credentials named \"$PROFILE\". See the notes at the top of release.sh." >&2
  exit 1
fi

# A clean Release build, signed by hand with the Developer ID (the
# project's own settings are for development builds).
xcodegen generate --quiet
OUT="build/release"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -quiet \
  -project SolidCopy.xcodeproj -scheme SolidCopy -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$OUT/derived" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

APP="$OUT/Solid Copy.app"
ditto "$OUT/derived/Build/Products/Release/SolidCopy.app" "$APP"

# Check the signature before sending anything to Apple.
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ZIP="$OUT/Solid-Copy-$VERSION-$BUILD.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# Notarize. Apple's answer is printed; "Accepted" is the one that counts.
echo "Sending to Apple to notarize (this can take a few minutes)..."
RESULT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 || true)"
echo "$RESULT"
if ! grep -q "status: Accepted" <<<"$RESULT"; then
  echo "Apple didn't accept the app. Read the log for the reasons, with the id shown above:" >&2
  echo "  xcrun notarytool log <id> --keychain-profile $PROFILE" >&2
  exit 1
fi

# Attach the notary ticket to the app, so it opens offline, then pack again.
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"

echo
echo "Ready to publish:"
echo "  $(pwd)/$ZIP"
echo "  $(pwd)/$ZIP.sha256"
