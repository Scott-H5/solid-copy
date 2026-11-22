#!/bin/bash
# Checks band plans, the US plan's privileges and the out-of-band
# warning (tools/bandplan-check), with a throwaway folder and a pretend
# radio. Nothing is tuned or keyed.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/BandPlan/*.swift Sources/Model/*.swift Sources/Accessibility/*.swift \
  Sources/Activity/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/Lookup/*.swift Sources/Radio/*.swift Sources/Keyer/*.swift \
  Sources/LogTable/*.swift Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Spots/*.swift \
  Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Uploads/*.swift \
  tools/bandplan-check/main.swift -o "$WORK/check" 2>&1 | grep -E "error" || true
"$WORK/check"
