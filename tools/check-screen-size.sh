#!/bin/bash
# Checks that every window and sheet fits a small, zoomed screen (1024 by 640).
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/Keyer/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/BandPlan/*.swift Sources/Rotor/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Radio/*.swift Sources/Spots/*.swift Sources/Lookup/*.swift Sources/LogEntry/*.swift Sources/Awards/*.swift Sources/Conditions/*.swift \
  tools/screen-size-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data"
