#!/bin/sh
# Build the Mac App Store version of neatly: sandboxed, no self-update, no background service (it opens at login
# through the system's Login Items instead). Runs on the maintainer's Mac (the signing keys never leave it).
#
# Usage: scripts/make-appstore.sh <build number> [--upload]
#   build number: must go up with every upload (1, 2, 3…); the version is the same as the GitHub release.
# Needs in the environment: NOTARY_KEY_ID, NOTARY_ISSUER (App Store Connect API key, also used for notarizing),
#   and the key file at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8 for --upload.
#   APPSTORE_PROFILE: path to the "Mac App Store Connect" provisioning profile for dev.neatly.app.
set -eu
build="$1"; upload="${2:-}"
cd "$(dirname "$0")/.."
: "${APPSTORE_PROFILE:?set APPSTORE_PROFILE}"
team=$(security cms -D -i "$APPSTORE_PROFILE" | plutil -extract TeamIdentifier.0 raw -)
app_id="dev.neatly.app"
app_sign="3rd Party Mac Developer Application"
pkg_sign="3rd Party Mac Developer Installer"

swift build -c release --product neatly --arch arm64 -Xswiftc -DAPPSTORE --build-path .build-appstore
bin="$(swift build -c release --product neatly --arch arm64 -Xswiftc -DAPPSTORE --build-path .build-appstore --show-bin-path)/neatly"
version=$("$bin" --version | awk '{print $2}')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p dist

# 1. The app bundle, built the way the installer builds it (Info.plist, icon, Finder service).
NEATLY_APP_DIR="$work" "$bin" app-bundle >/dev/null
app="$work/neatly.app"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Delete :NeatlyBundleFormat" "$plist"
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" "$plist"

# 2. The App Store wants the icon in an asset catalog too.
iconutil -c iconset "$app/Contents/Resources/AppIcon.icns" -o "$work/AppIcon.iconset"
cat="$work/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$cat"
cp "$work/AppIcon.iconset/"*.png "$cat/"
python3 - "$cat" <<'EOF'
import json, os, re, sys
d = sys.argv[1]; images = []
for f in sorted(os.listdir(d)):
    m = re.match(r"icon_(\d+)x\d+(@2x)?\.png", f)
    if m: images.append({"idiom": "mac", "size": f"{m.group(1)}x{m.group(1)}", "scale": "2x" if m.group(2) else "1x", "filename": f})
json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, open(os.path.join(d, "Contents.json"), "w"))
json.dump({"info": {"version": 1, "author": "xcode"}}, open(os.path.join(os.path.dirname(d), "Contents.json"), "w"))
EOF
xcrun actool --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$work/partial.plist" "$work/Assets.xcassets" >/dev/null

# 3. Sandbox permissions: files you choose (your home folder, once), Downloads, and the network for lookups.
cat > "$work/neatly.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  <key>com.apple.security.files.bookmarks.app-scope</key><true/>
  <key>com.apple.security.files.downloads.read-write</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.application-identifier</key><string>$team.$app_id</string>
  <key>com.apple.developer.team-identifier</key><string>$team</string>
</dict></plist>
EOF
cp "$APPSTORE_PROFILE" "$app/Contents/embedded.provisionprofile"
xattr -cr "$app"
codesign --force --sign "$app_sign" --entitlements "$work/neatly.entitlements" "$app"
codesign --verify --strict --verbose=2 "$app"

# 4. The installer package App Store Connect accepts.
pkg="dist/neatly-appstore-$version-$build.pkg"
productbuild --component "$app" /Applications --sign "$pkg_sign" "$pkg" >/dev/null
echo "$pkg is ready (version $version, build $build)"

if [ "$upload" = "--upload" ]; then
    : "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER:?}"
    xcrun altool --validate-app -f "$pkg" -t macos --apiKey "$NOTARY_KEY_ID" --apiIssuer "$NOTARY_ISSUER"
    xcrun altool --upload-app -f "$pkg" -t macos --apiKey "$NOTARY_KEY_ID" --apiIssuer "$NOTARY_ISSUER"
fi
