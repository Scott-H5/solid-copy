#!/bin/bash
# Checks the callsign lookup code with sample replies (no account needed).
# Add --live to also ask callook.info about W1AW over the internet.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Lookup/LookupResult.swift Sources/Lookup/QRZClient.swift \
  Sources/Lookup/CallookClient.swift Sources/Lookup/CallsignLookup.swift Sources/Model/*.swift \
  Sources/Settings/Settings.swift Sources/Settings/Keychain.swift Sources/Radio/RadioSettings.swift Sources/Accessibility/Speaker.swift Sources/Accessibility/Tone.swift \
  tools/lookup-check/main.swift -o "$WORK/check"
"$WORK/check" "$@"
