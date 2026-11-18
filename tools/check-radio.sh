#!/bin/bash
# Checks the radio connection with hamlib's Dummy radio, in Homebrew's
# rigctld on spare ports (4600 to 4602). Needs: brew install hamlib.
# The app's settings and any real radio are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
# Any rigctld the check started (all listen on port 4600) goes at the end.
trap 'pkill -f "rigctld -m .* -t 4600" 2>/dev/null || true; rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift tools/radio-check/main.swift -o "$WORK/check"
"$WORK/check" "$WORK"
