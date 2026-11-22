#!/bin/bash
# Checks scanned QSL cards (QSLCards.swift) with cards and a log of its own,
# then, if they're there, against the author's real card folder and SQL log file,
# both only read: the cards are copied into a throwaway folder.
#   bash tools/check-cards.sh [card folder] [log file.sql]
# With no log file, it uses SOLID_COPY_SQL_LOG from tools/checks.local
# (see check-import-export.sh), or skips the real-cards checks.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tools/checks.local ] && . tools/checks.local
CARDS="${1:-$HOME/Downloads/QSL Cards}"
# A path that can't exist when there's no log, so those checks are skipped.
LOG="${2:-${SOLID_COPY_SQL_LOG:-/dev/null/no-log}}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Import/*.swift Sources/Accessibility/*.swift \
  Sources/LogTable/*.swift Sources/EditContact/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/BandPlan/*.swift Sources/Rotor/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Keyer/*.swift Sources/Radio/*.swift \
  Sources/Spots/*.swift Sources/Lookup/*.swift tools/cards-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data" "$CARDS" "$LOG"
