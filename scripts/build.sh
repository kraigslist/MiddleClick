#!/bin/sh
# The app is ad-hoc signed, so macOS treats every rebuild as a new app:
# remove MiddleClick from System Settings > Privacy & Security > Accessibility
# and add the new build again after each rebuild.
set -eu
cd "$(dirname "$0")/.."

SRC=MiddleClick
ASSETS=$SRC/Images.xcassets
APP=build/MiddleClick.app
ICONSET=build/AppIcon.iconset

setting() {
  sed -n "s/.*[[:space:]]$1 = \(.*\);/\1/p" MiddleClick.xcodeproj/project.pbxproj | head -1
}
VERSION=$(setting MARKETING_VERSION)
BUILD_NUMBER=$(setting CURRENT_PROJECT_VERSION)
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)
MIN_MACOS=$(setting MACOSX_DEPLOYMENT_TARGET)

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

echo "Linting..."
scripts/lint.sh "$SRC"

echo "Compiling MiddleClick $VERSION..."
clang -Os -flto -fno-objc-arc -fobjc-weak \
  -arch arm64 -arch x86_64 -mmacosx-version-min="$MIN_MACOS" \
  "$SRC"/*.m "$SRC"/*.c -o "$APP/Contents/MacOS/MiddleClick" \
  -framework Cocoa -framework ApplicationServices -framework IOKit \
  -F/System/Library/PrivateFrameworks -framework MultitouchSupport \
  -Wl,-dead_strip
strip -x "$APP/Contents/MacOS/MiddleClick"

sed -e 's/${EXECUTABLE_NAME}/MiddleClick/' \
    -e 's/${PRODUCT_NAME}/MiddleClick/' \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    "$SRC/Info.plist" > "$APP/Contents/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"

# Asset catalogs need Xcode's actool, so the icons are copied as plain files instead.
cp "$ASSETS/StatusIcon.imageset/mouse32x32.png" "$APP/Contents/Resources/StatusIcon.png"
cp "$ASSETS/StatusIcon.imageset/mouse-1.png" "$APP/Contents/Resources/StatusIcon@2x.png"
cp "$ASSETS/AppIcon.appiconset/mouse16x16.png" "$ICONSET/icon_16x16.png"
cp "$ASSETS/AppIcon.appiconset/mouse@2x.png" "$ICONSET/icon_16x16@2x.png"
cp "$ASSETS/AppIcon.appiconset/mouse32x32.png" "$ICONSET/icon_32x32.png"
cp "$ASSETS/AppIcon.appiconset/mouse-1.png" "$ICONSET/icon_32x32@2x.png"
cp "$ASSETS/AppIcon.appiconset/mouse128x128.png" "$ICONSET/icon_128x128.png"
cp "$ASSETS/AppIcon.appiconset/mouse.png" "$ICONSET/icon_128x128@2x.png"
cp "$ASSETS/AppIcon.appiconset/mouse256x256.png" "$ICONSET/icon_256x256.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - --options runtime \
  --entitlements "$SRC/MiddleClick.entitlements" "$APP"

echo "Built $APP"
