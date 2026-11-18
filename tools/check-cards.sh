#!/bin/bash
# Checks scanned QSL cards (QSLCards.swift) with cards and a log of its own,
# then, if they're there, against the author's real card folder and MacLoggerDX
# log, both only read: the cards are copied into a throwaway folder.
#   bash tools/check-cards.sh [card folder] [MacLoggerDX.sql]
set -euo pipefail
cd "$(dirname "$0")/.."
CARDS="${1:-$HOME/Downloads/QSL Cards}"
MLDX="${2:-$HOME/Documents/Amateur Radio/MLDX_Logs/MacLoggerDX.sql}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Import/*.swift Sources/Accessibility/*.swift \
  Sources/LogTable/*.swift Sources/EditContact/*.swift Sources/Settings/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Radio/*.swift \
  Sources/Spots/*.swift Sources/Lookup/*.swift tools/cards-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data" "$CARDS" "$MLDX"
