#!/bin/bash
# Compiles and runs tools/log-database-check/main.swift against a temporary
# log file, then deletes it. Your real log is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 \
  Sources/Model/Database.swift Sources/Model/LogDatabase.swift Sources/Model/QSO.swift Sources/Model/LogField.swift Sources/Model/Callsign.swift \
  tools/log-database-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "$WORK/data"
