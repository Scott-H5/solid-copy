#!/bin/bash
# Checks band conditions (Speech > Say Band Conditions) with N0NBH's XML
# kept in the check, and a pretend fetch. Add --live to read the real one.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Conditions/*.swift Sources/Model/*.swift Sources/Accessibility/*.swift \
  Sources/Activity/*.swift Sources/Settings/*.swift Sources/Lookup/*.swift Sources/Radio/*.swift Sources/Keyer/*.swift \
  Sources/LogTable/*.swift Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Spots/*.swift \
  Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Uploads/*.swift \
  tools/conditions-check/main.swift -o "$WORK/check" 2>&1 | grep -E "error" || true
"$WORK/check" "$@"
