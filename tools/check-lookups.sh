#!/bin/bash
# Checks the callsign lookup code with sample replies (no account needed).
# Add --live to also ask callook.info about W1AW over the internet.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/BandPlan/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift \
  tools/lookup-check/main.swift -o "$WORK/check"
"$WORK/check" "$@"
