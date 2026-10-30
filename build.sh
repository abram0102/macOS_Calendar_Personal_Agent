#!/bin/bash
# Build CalendarDesk.app with plain swiftc (no Xcode project required).
# Usage: ./build.sh           build only, into ./build/CalendarDesk.app
#        ./build.sh install  build, install into ~/Applications, then launch
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="CalendarDesk"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "-> Compiling Swift sources"
swiftc \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  -O -whole-module-optimization \
  -framework AppKit -framework SwiftUI -framework EventKit \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>CalendarDesk</string>
    <key>CFBundleDisplayName</key>          <string>CalendarDesk</string>
    <key>CFBundleExecutable</key>           <string>CalendarDesk</string>
    <key>CFBundleIdentifier</key>           <string>com.abram.calendardesk</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>   <string>1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>15.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSCalendarsUsageDescription</key>
    <string>读取你的日程，显示在桌面窗口里（只读，不会修改日历）。</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>读取你的日程，显示在桌面窗口里（只读，不会修改日历）。</string>
</dict>
</plist>
PLIST

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "-> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "OK  Built: $APP"

if [[ "${1:-}" == "install" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST/$APP_NAME.app"
  cp -R "$APP" "$DEST/"
  echo "OK  Installed to $DEST/$APP_NAME.app"
  open "$DEST/$APP_NAME.app"
  echo "OK  Launched (look for the calendar icon in the menu bar)"
fi
