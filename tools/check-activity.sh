#!/bin/bash
# Checks Window > Activity's list (Sources/Activity): what's running, what's
# done, newest first, and the limit. No internet, nothing from your Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Activity/Activity.swift tools/activity-check/main.swift -o "$WORK/check"
"$WORK/check"
