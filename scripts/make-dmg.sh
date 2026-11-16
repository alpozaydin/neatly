#!/bin/sh
# Build neatly.dmg for people who don't use Terminal: a Developer ID–signed, notarized neatly.app with a
# shortcut to Applications. Runs on the maintainer's Mac (the signing key never leaves it).
#
# Usage: scripts/make-dmg.sh <version> [neatly binary]     (default binary: a fresh release build)
# Needs, in the environment:
#   NEATLY_SIGN_ID   e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_KEY       path to the App Store Connect API key (.p8)
#   NOTARY_KEY_ID, NOTARY_ISSUER
# Then: gh release upload v<version> dist/neatly.dmg
set -eu
v="$1"
cd "$(dirname "$0")/.."
: "${NEATLY_SIGN_ID:?set NEATLY_SIGN_ID}" "${NOTARY_KEY:?set NOTARY_KEY}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER:?}"
notary() { xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait; }

bin="${2:-}"
if [ -z "$bin" ]; then
    swift build -c release --product neatly --arch arm64
    bin="$(swift build -c release --product neatly --arch arm64 --show-bin-path)/neatly"
fi
"$bin" --version | grep -q " $v\$" || { echo "the binary is not version $v"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/app" "$work/dmg" dist

# 1. The app, built the same way the installer builds it, then signed for distribution.
NEATLY_APP_DIR="$work/app" "$bin" app-bundle >/dev/null
app="$work/app/neatly.app"
codesign --force --options runtime --timestamp --sign "$NEATLY_SIGN_ID" "$app"
codesign --verify --strict --verbose=2 "$app"

# 2. Notarize the app and attach the ticket, so it opens without a warning even offline.
ditto -c -k --keepParent "$app" "$work/neatly.zip"
notary "$work/neatly.zip"
xcrun stapler staple "$app"

# 3. The disk image: neatly.app next to a shortcut to Applications.
cp -R "$app" "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
rm -f dist/neatly.dmg
hdiutil create -volname "neatly" -srcfolder "$work/dmg" -fs APFS -format ULFO -ov dist/neatly.dmg >/dev/null
codesign --force --timestamp --sign "$NEATLY_SIGN_ID" dist/neatly.dmg
notary dist/neatly.dmg
xcrun stapler staple dist/neatly.dmg

spctl -a -t open --context context:primary-signature -v dist/neatly.dmg
echo "dist/neatly.dmg is ready: gh release upload v$v dist/neatly.dmg"
