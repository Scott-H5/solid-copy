#!/bin/bash
# Checks operating profiles with a throwaway log and this check's own
# settings (the app's settings are never touched).
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Radio/*.swift Sources/Spots/*.swift \
  tools/profiles-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data"
