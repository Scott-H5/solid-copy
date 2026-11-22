#!/bin/bash
# Checks award counting (Sources/Awards/Awards.swift) with a made-up log
# and country list: the app's log and settings are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/Awards/*.swift tools/awards-check/main.swift -o "$WORK/check"
"$WORK/check"
