#!/bin/bash
# Checks the log table on its own, with a throwaway log.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Radio/*.swift Sources/Spots/*.swift Sources/Lookup/*.swift \
  tools/log-table-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data"
