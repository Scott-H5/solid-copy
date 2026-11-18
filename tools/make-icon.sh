#!/bin/bash
# Draws the app icon (tools/make-icon/main.swift) into the asset catalog
# at macOS/Assets.xcassets/AppIcon.appiconset, with the Contents.json that
# tells Xcode which image is which size.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="macOS/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 tools/make-icon/main.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$SET"
# Each point size at 1x and 2x, from the matching pixel size.
python3 - "$SET" <<'PY'
import json, os, sys
folder = sys.argv[1]
entries = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = points * scale
        entries.append({"size": f"{points}x{points}", "idiom": "mac", "scale": f"{scale}x",
                        "filename": f"icon_{pixels}.png"})
with open(os.path.join(folder, "Contents.json"), "w") as f:
    json.dump({"images": entries, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
PY
echo "Icon drawn into $SET"
