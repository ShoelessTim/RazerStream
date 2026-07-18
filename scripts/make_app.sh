#!/bin/zsh
# Assembles RazerStream.app from the SPM build.
# Usage: scripts/make_app.sh [debug|release]
set -e

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/RazerStream.app"

if [ -d "/Applications/Xcode-beta.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

echo "Building ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG" 2>&1 | tail -1

echo "Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/$CONFIG/RazerStreamApp" "$APP/Contents/MacOS/RazerStream"

# App icon; generated once, reused until deleted
ICONSET="$ROOT/dist/AppIcon.iconset"
ICNS="$ROOT/dist/AppIcon.icns"
if [ ! -f "$ICNS" ]; then
    echo "Rendering app icon…"
    swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Bundled icon packs; fetched once by scripts/fetch_icon_packs.sh
if [ -d "$ROOT/dist/IconPacks" ]; then
    cp -R "$ROOT/dist/IconPacks" "$APP/Contents/Resources/IconPacks"
fi

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>RazerStream</string>
    <key>CFBundleIdentifier</key>          <string>org.community.razerstream</string>
    <key>CFBundleName</key>                <string>RazerStream</string>
    <key>CFBundleDisplayName</key>         <string>RazerStream</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>1.4.4</string>
    <key>CFBundleVersion</key>             <string>11</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Community project — MIT</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>  <string>org.community.razerstream.profile</string>
            <key>UTTypeDescription</key> <string>RazerStream Profile</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>razerstream</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>  <string>org.community.razerstream.tile</string>
            <key>UTTypeDescription</key> <string>RazerStream Tile (internal drag payload)</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Signing identity preference:
#  1. Developer ID Application; distributable and notarizable, stable grant
#  2. Apple Development or the local self-signed cert; stable grant, dev only
#  3. ad hoc; grant resets every build
ENTITLEMENTS="$ROOT/scripts/RazerStream.entitlements"
DEVID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
DEVCERT=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/RazerStream Dev|Apple Development/ {print $2; exit}')

if [ -n "$DEVID" ]; then
    echo "Signing with Developer ID (hardened runtime): $DEVID"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEVID" "$APP"
elif [ -n "$DEVCERT" ]; then
    echo "Signing with: $DEVCERT"
    codesign --force --sign "$DEVCERT" "$APP"
else
    echo "Signing ad hoc; Accessibility will need a re-grant after each update"
    codesign --force --sign - "$APP"
fi

echo "Done: $APP"

# Pass "install" to update /Applications
if [ "$2" = "install" ] || [ "$3" = "install" ]; then
    echo "Installing to /Applications…"
    rm -rf "/Applications/RazerStream.app"
    cp -R "$APP" "/Applications/RazerStream.app"
    echo "Installed: /Applications/RazerStream.app"
fi

# Pass "notarize" to notarize, staple, and zip for distribution. Requires a
# Developer ID signature and stored credentials under the profile name below.
if [ "$2" = "notarize" ] || [ "$3" = "notarize" ]; then
    if [ -z "$DEVID" ]; then
        echo "Cannot notarize; no Developer ID Application certificate found."
        exit 1
    fi
    NOTARY_PROFILE="razerstream-notary"
    ZIP="$ROOT/dist/RazerStream.zip"
    echo "Zipping for notarization…"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Submitting to Apple notary service (this can take a few minutes)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "Stapling ticket…"
    xcrun stapler staple "$APP"
    # Re-zip the stapled app for release upload
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarized and stapled: $ZIP"
fi
