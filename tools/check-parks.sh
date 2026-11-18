#!/bin/bash
# Checks POTA's park list and park search with a small sample list, in a
# throwaway folder (the app's own list is never touched). Give it POTA's
# real list (all_parks_ext.csv) to also time building and searching it:
#   bash tools/check-parks.sh ~/Downloads/all_parks_ext.csv
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/Lookup/*.swift \
  Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift Sources/Radio/*.swift Sources/Spots/*.swift Sources/LogTable/*.swift Sources/EditContact/*.swift \
  tools/park-check/main.swift -o "$WORK/check"
"$WORK/check" "$WORK" "$@"
