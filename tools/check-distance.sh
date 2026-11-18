#!/bin/bash
# Checks distance and bearing between grids (Sources/Model/GreatCircle.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift tools/distance-check/main.swift -o "$WORK/check"
"$WORK/check"
