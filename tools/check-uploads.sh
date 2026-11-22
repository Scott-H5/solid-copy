#!/bin/bash
# Checks QRZ Logbook uploads and automatic uploads (Sources/Uploads) with a
# pretend QRZ: no internet, nothing from your Keychain or settings.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Rotor/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Uploads/*.swift Sources/Activity/*.swift tools/uploads-check/main.swift -o "$WORK/check"
"$WORK/check"
