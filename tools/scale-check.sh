#!/bin/bash
# How Solid Copy copes with a very big log. Pass the number of made-up
# contacts (default 100000). Uses a throwaway log, deleted afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A tiny shim so the check can use the log table's search text without
# building the whole table.
cat > "$WORK/shim.swift" <<'SWIFT'
func LogTableViewController_searchableText(_ qso: QSO) -> String {
    var text = [qso.call, qso.utcDateText] + qso.fields.values
    if let stateName = USStates.name(for: qso["state"]) { text.append(stateName) }
    return text.joined(separator: " ").lowercased()
}
SWIFT
xcrun swiftc Sources/Activity/*.swift -O -swift-version 5 Sources/Model/*.swift Sources/Lookup/LookupResult.swift \
  "$WORK/shim.swift" tools/scale-check/main.swift -o "$WORK/check"
mkdir "$WORK/data"
"$WORK/check" "${1:-100000}" "$WORK/data"
