#!/bin/sh
# Builds Soroban.app. Pass --install to copy it into ~/Applications.
set -e
cd "$(dirname "$0")"

VERSION=$(tr -d '[:space:]' < VERSION)
# Build number: commit count, so it increases with every commit.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release
APP=build/Soroban.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Soroban "$APP/Contents/MacOS/"
rm -rf build/AppIcon.iconset
swift scripts/make-icon.swift assets/icon.svg build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Soroban</string>
    <key>CFBundleIdentifier</key><string>io.github.soroban</string>
    <key>CFBundleExecutable</key><string>Soroban</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP (version $VERSION, build $BUILD)"

if [ "$1" = "--install" ]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Soroban.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Soroban.app"
fi
