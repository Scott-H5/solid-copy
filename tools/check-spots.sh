#!/bin/bash
# Checks spots with spots of its own and a throwaway log (the app's log
# and settings are never touched). Add --live to fetch POTA's real spots.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift tools/spots-check/main.swift -o "$WORK/check"
"$WORK/check" "$WORK" "$@"
