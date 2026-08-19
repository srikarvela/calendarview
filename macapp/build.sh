#!/usr/bin/env bash
#
# Builds CalendarView.app (Universal: Apple Silicon + Intel) and CalendarView.dmg.
# Needs only the Xcode Command Line Tools — no Xcode, no signing certificate.
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="CalendarView"
BUNDLE_ID="com.calendarview.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUM="${BUILD_NUM:-1}"
MIN_MACOS="11.0"

BUILD="build"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling universal binary (arm64 + x86_64)"
clang -fobjc-arc -O2 \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min="$MIN_MACOS" \
  -framework AppKit -framework WebKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/main.m

echo "==> Rendering icon"
clang -fobjc-arc -framework AppKit -o "$BUILD/makeicon" Tools/makeicon.m
"$BUILD/makeicon" "$BUILD/icon-1024.png" >/dev/null

ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$BUILD/icon-1024.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD_NUM</string>
    <key>LSMinimumSystemVersion</key>    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>CalendarView</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature ok"

echo "==> Building DMG"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$DMG"

rm -rf "$STAGE" "$ICONSET" "$BUILD/makeicon" "$BUILD/icon-1024.png"

echo
echo "Built:"
echo "  $(pwd)/$APP"
echo "  $(pwd)/$DMG  ($(du -h "$DMG" | cut -f1))"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/  architectures: /'
