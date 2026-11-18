#!/bin/bash
# Checks CW messages and what's sent to the WinKeyer (tools/cw-check). No
# keyer needed; nothing is sent.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/Keyer/*.swift \
  Sources/Settings/*.swift Sources/Lookup/*.swift Sources/Radio/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Spots/*.swift Sources/LoTW/*.swift \
  Sources/Export/*.swift Sources/Import/*.swift Sources/Uploads/*.swift Sources/Activity/*.swift tools/cw-check/main.swift -o "$WORK/check"
"$WORK/check"
