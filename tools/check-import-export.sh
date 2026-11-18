#!/bin/bash
# Checks importing and exporting against a real MacLoggerDX log (only read,
# never changed). With no path, uses
# ~/Documents/Amateur Radio/MLDX_Logs/MacLoggerDX.sql.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-$HOME/Documents/Amateur Radio/MLDX_Logs/MacLoggerDX.sql}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Import/*.swift Sources/Export/*.swift \
  tools/import-export-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$SOURCE" "$WORK/data"
