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
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Community project — MIT</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC (Accessibility) can track a stable identity
codesign --force --deep --sign - "$APP"

echo "Done: $APP"

# Pass "install" as the second argument to update /Applications
if [ "$2" = "install" ]; then
    echo "Installing to /Applications…"
    rm -rf "/Applications/RazerStream.app"
    cp -R "$APP" "/Applications/RazerStream.app"
    echo "Installed: /Applications/RazerStream.app"
fi
