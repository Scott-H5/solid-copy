#!/bin/bash
# Checks importing and exporting against a real log file in the SQL format
# (only read, never changed). Give its path, or set SOLID_COPY_SQL_LOG in
# tools/checks.local (see below).
#   bash tools/check-import-export.sh [path to a .sql log]
#
# tools/checks.local, if it's there, is read first. It's your own file,
# never committed (.gitignore), for paths on your Mac, such as:
#   SOLID_COPY_SQL_LOG="$HOME/Documents/My Log.sql"
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tools/checks.local ] && . tools/checks.local
SOURCE="${1:-${SOLID_COPY_SQL_LOG:-}}"
if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
  echo "Give the path to a log file in the SQL format: bash tools/check-import-export.sh <file.sql>" >&2
  echo "(or set SOLID_COPY_SQL_LOG in tools/checks.local)." >&2
  exit 1
fi
export SOLID_COPY_AUTHOR_LOG="${SOLID_COPY_AUTHOR_LOG:-0}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Import/*.swift Sources/Export/*.swift \
  tools/import-export-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$SOURCE" "$WORK/data"
