#!/bin/bash
# Checks separate logs and that a test log never uploads
# (tools/logs-check/main.swift). No internet, nothing of yours touched.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/BandPlan/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Uploads/*.swift Sources/Activity/*.swift tools/logs-check/main.swift -o "$WORK/check"
"$WORK/check"
