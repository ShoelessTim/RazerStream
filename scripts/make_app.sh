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
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Community project — MIT</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC (Accessibility) can track a stable identity
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
