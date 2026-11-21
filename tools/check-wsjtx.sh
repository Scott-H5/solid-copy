#!/bin/bash
# Checks reading WSJT-X's UDP messages (Sources/WSJTX) with made-up
# messages: no WSJT-X needed.
#   bash tools/check-wsjtx.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Activity/*.swift Sources/Model/*.swift Sources/Radio/RadioReading.swift \
  Sources/WSJTX/WSJTXMessage.swift Sources/WSJTX/WSJTXListener.swift Sources/WSJTX/DecodeLine.swift \
  Sources/WSJTX/WSJTXLogging.swift Sources/Import/*.swift Sources/Export/*.swift \
  tools/wsjtx-check/main.swift -o "$WORK/check"
"$WORK/check"
