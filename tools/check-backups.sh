#!/bin/bash
# Checks copying backups to a second folder (Sources/Model/BackupCopy.swift)
# in a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/BackupCopy.swift tools/backups-check/main.swift -o "$WORK/check"
"$WORK/check"
