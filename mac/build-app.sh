#!/bin/bash
# Build a double-clickable, ad-hoc-signed Lensfix.app from the Swift package.
# Requires the Xcode Command Line Tools (swift, codesign, iconutil) — NOT full Xcode.
#
#   ./build-app.sh            # builds mac/dist/Lensfix.app
#   open dist/Lensfix.app     # launch it
#
# For distribution to other people (Developer ID signing + notarization),
# see the "Sharing the app" section in README.md.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Lensfix"
BUNDLE_ID="com.kleinmatic.lensfix"
VERSION="1.0"
BUILD="1"
MIN_MACOS="13.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building release binary..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Generating icon..."
ICON_KEY=""
if swift AppIcon/make-icon.swift "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
    ICON_KEY="
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    echo "    (icon generation skipped — app will use the default icon)"
fi

echo "==> Writing Info.plist..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Lensfix — EXIF lens tagging for vintage lenses.</string>$ICON_KEY
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc code-signing..."
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo ""
echo "Done: $APP"
echo "Launch with:  open \"$APP\"   (or double-click it in Finder)"
