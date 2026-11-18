#!/bin/bash
# bundle-rigctld.sh
#
# Copies hamlib's rigctld (the program that talks to the radio) and the
# two libraries it needs into Solid Copy.app, so Solid Copy can start it
# itself. Xcode runs this while building (see project.yml); you don't
# run it by hand.
#
# Why bundle it? Solid Copy is sandboxed: it can only reach what it has
# asked macOS for, and it can't see Homebrew's /opt/homebrew at all. A
# program inside the app can be started by it, and inherits its
# permissions (including the serial ports, for the radio).
#
# Where it comes from: Homebrew's hamlib (brew install hamlib). After
# `brew upgrade hamlib`, rebuild Solid Copy to bundle the new version.
#
# What it does:
#   1. Copies rigctld to Contents/Helpers, and libhamlib and libusb to
#      Contents/Frameworks.
#   2. Points each at the bundled copies instead of /opt/homebrew
#      (install_name_tool changes the paths written inside them).
#   3. Signs each with your certificate. rigctld is signed with
#      rigctld.entitlements, which says "run inside Solid Copy's sandbox".
#   4. Copies hamlib's licence and a note on where its source is, which
#      its licence (the GPL) asks for when it's given to others.

set -euo pipefail

BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
HAMLIB="$BREW/opt/hamlib"
LIBUSB="$BREW/opt/libusb"
if [ ! -x "$HAMLIB/bin/rigctld" ]; then
    echo "error: rigctld not found. Install hamlib with: brew install hamlib" >&2
    exit 1
fi

CONTENTS="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
HELPERS="$CONTENTS/Helpers"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$HELPERS" "$FRAMEWORKS" "$RESOURCES"

# 1. Copy. (Homebrew's files are read-only; the copies needn't be.)
install -m 755 "$HAMLIB/bin/rigctld" "$HELPERS/rigctld"
install -m 644 "$HAMLIB/lib/libhamlib.4.dylib" "$FRAMEWORKS/libhamlib.4.dylib"
install -m 644 "$LIBUSB/lib/libusb-1.0.0.dylib" "$FRAMEWORKS/libusb-1.0.0.dylib"

# 2. Repoint. "@rpath" means "look in the places this program lists",
# and rigctld lists ../Frameworks.
change() {  # change <file> <library name>: any /opt/homebrew path to it
    local old
    old=$(otool -L "$1" | awk -v name="$2" '$1 ~ name { print $1 }' | grep -v '^@' || true)
    for path in $old; do install_name_tool -change "$path" "@rpath/$2" "$1" 2>/dev/null; done
}
install_name_tool -id "@rpath/libhamlib.4.dylib" "$FRAMEWORKS/libhamlib.4.dylib" 2>/dev/null
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$FRAMEWORKS/libusb-1.0.0.dylib" 2>/dev/null
change "$FRAMEWORKS/libhamlib.4.dylib" libusb-1.0.0.dylib
change "$HELPERS/rigctld" libhamlib.4.dylib
change "$HELPERS/rigctld" libusb-1.0.0.dylib
install_name_tool -add_rpath "@executable_path/../Frameworks" "$HELPERS/rigctld" 2>/dev/null || true

# Nothing may still point into Homebrew, or the app would only work on a
# Mac that has it.
if otool -L "$HELPERS/rigctld" "$FRAMEWORKS"/*.dylib | grep -q "$BREW"; then
    echo "error: a bundled file still points into $BREW:" >&2
    otool -L "$HELPERS/rigctld" "$FRAMEWORKS"/*.dylib >&2
    exit 1
fi

# 3. Sign: libraries first, then the program that uses them. Xcode signs
# the app itself afterwards. ("-" signs without a certificate, for
# builds that aren't signed.)
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
# Apple's notary service needs a secure timestamp on every signed file
# (release.sh); development builds don't need one.
if [ "$IDENTITY" = "-" ]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
for library in "$FRAMEWORKS"/*.dylib; do
    codesign --force --sign "$IDENTITY" --options runtime $TIMESTAMP "$library"
done
codesign --force --sign "$IDENTITY" --options runtime $TIMESTAMP \
    --entitlements "$SRCROOT/macOS/rigctld.entitlements" "$HELPERS/rigctld"

# 4. Licence.
install -m 644 "$HAMLIB/COPYING" "$RESOURCES/Hamlib-COPYING.txt"
# (The bundled copy only runs when Solid Copy starts it, so ask Homebrew's.)
VERSION=$("$HAMLIB/bin/rigctld" --version 2>/dev/null | head -1 || true)
cat > "$RESOURCES/Hamlib-NOTICE.txt" <<EOF
Solid Copy includes rigctld and libhamlib from Hamlib ($VERSION), and
libusb, unchanged. Hamlib's rigctld is licensed under the GNU General
Public License and libhamlib and libusb under the GNU Lesser General
Public License; see Hamlib-COPYING.txt. Their source code is available
from https://github.com/Hamlib/Hamlib and https://github.com/libusb/libusb.
EOF
