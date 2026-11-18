#!/bin/bash
# Checks club numbers: SKCC's member list, the SKCC number check, numbers
# from your log, and your own club fields (tools/clubs-check/main.swift).
# No internet. Give it a copy of SKCC's file to check reading that too:
#   bash tools/check-clubs.sh [skccdata.txt]
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Uploads/*.swift Sources/Activity/*.swift tools/clubs-check/main.swift -o "$WORK/check"
"$WORK/check" "$@"
