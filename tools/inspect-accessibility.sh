#!/bin/bash
# Prints what VoiceOver can see in Solid Copy right now (or in another app:
# pass its bundle ID). Open the thing you want to inspect first, such as a
# shortcut menu, then run this. Read-only.
#
#   bash tools/inspect-accessibility.sh
#   bash tools/inspect-accessibility.sh com.apple.finder
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 tools/inspect-accessibility/main.swift -o "$WORK/inspect"
"$WORK/inspect" "${1:-io.github.scott-h5.solidcopy}"
