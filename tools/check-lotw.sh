#!/bin/bash
# Checks LoTW sync's rules (LoTW.swift) without the internet or TQSL:
# what's uploaded, TQSL's results, LoTW's replies, and matching.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  tools/lotw-check/main.swift -o "$WORK/check"
"$WORK/check"
