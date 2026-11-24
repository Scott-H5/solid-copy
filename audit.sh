#!/bin/bash
# Runs Apple's automatic accessibility audit on each of Solid Copy's screens
# and prints what it finds (see UITests/AccessibilityAuditTests.swift).
#
#   bash audit.sh
#
# Solid Copy opens and moves through its screens by itself, taking over
# the screen while it runs: 53 minutes on 2026-11-24, then 40 once the
# test read each flagged element once per screen. It now remembers each
# element across screens too (not yet timed). The first time, macOS asks
# to let the test runner control the computer (Privacy & Security >
# Accessibility); turn that off again afterwards.
#
# Only the findings are printed, one "AUDIT:" line each, then a summary.
# The full log is build/audit.log; screenshots of each screen are in
# build/audit-screenshots.
set -euo pipefail
cd "$(dirname "$0")"

TEAM="$(tr -d '[:space:]' < team.txt 2>/dev/null || true)"
[ -n "$TEAM" ] || { echo "Put your Apple Developer team ID in team.txt first." >&2; exit 1; }

# Solid Copy open already (the copy in /Applications) would run beside
# the audit's own copy, and both would open the same radio's port. So it's
# quit first; reopen it afterwards.
osascript -e 'tell application id "io.github.scott-h5.solidcopy" to quit' 2>/dev/null || true

xcodegen generate --quiet
mkdir -p build
LOG="build/audit.log"

# The run "fails" when the audit finds problems, so its exit status is
# ignored; the summary below says what happened.
xcodebuild -project SolidCopy.xcodeproj -scheme SolidCopy \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/tests \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" test > "$LOG" 2>&1 || true

SHOTS="build/audit-screenshots"
rm -rf "$SHOTS"; mkdir -p "$SHOTS"
RESULT="$(ls -td build/tests/Logs/Test/*.xcresult 2>/dev/null | head -1)"
if [ -n "$RESULT" ]; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS" >/dev/null 2>&1 || true
fi

grep -E '^AUDIT: ' "$LOG" | awk '!seen[$0]++' || true
grep -E '^AUDIT SUMMARY|Executed [0-9]+ test|error:|\*\* TEST' "$LOG" | awk '!seen[$0]++' || true
echo "Full log: $(pwd)/$LOG"
echo "Screenshots: $(pwd)/$SHOTS"
