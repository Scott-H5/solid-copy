#!/bin/bash
# Checks the rigctl server (RigctlServer.swift) with hamlib's own rigctl
# and a pretend radio: no radio needed, nothing sent to one.
#   bash tools/check-rigctl.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Activity/*.swift Sources/Model/*.swift Sources/Radio/RadioReading.swift \
  Sources/Radio/RigctlServer.swift tools/rigctl-check/main.swift -o "$WORK/check"
"$WORK/check"
