#!/bin/bash
# Checks rotor control (Sources/Rotor) against a pretend rotctld: no rotor
# or hamlib needed. Add --live to try hamlib's dummy rotor too (rotctld -m
# 1, if rotctld is installed), on port 45534, stopped afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
ROTCTLD=""
trap 'rm -rf "$WORK"; [ -n "$ROTCTLD" ] && kill "$ROTCTLD" 2>/dev/null || true' EXIT
xcrun swiftc Sources/Activity/*.swift -swift-version 5 Sources/Model/*.swift Sources/Accessibility/*.swift Sources/LogTable/*.swift \
  Sources/EditContact/*.swift Sources/LogEntry/*.swift Sources/Keyer/*.swift Sources/Lookup/*.swift Sources/Settings/*.swift Sources/WSJTX/*.swift Sources/BandPlan/*.swift Sources/LoTW/*.swift Sources/Export/*.swift Sources/Import/*.swift \
  Sources/Radio/*.swift Sources/Spots/*.swift Sources/Rotor/*.swift tools/rotor-check/main.swift -o "$WORK/check"
if [ "${1:-}" = "--live" ] && command -v rotctld >/dev/null; then
  rotctld -m 1 -T 127.0.0.1 -t 45534 &
  ROTCTLD=$!
  sleep 1
  "$WORK/check" --live 45534
else
  "$WORK/check"
fi
