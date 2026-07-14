#!/bin/bash
set -euo pipefail

# Package the built Finn binary into a tvOS .app bundle.
# Usage: ./scripts/package-tvos.sh [--release|--debug]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRIPLE="arm64-apple-tvos"
BUILD_CONFIG="release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) BUILD_CONFIG="debug"; shift ;;
        --release) BUILD_CONFIG="release"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

BUILD_BIN="$PROJECT_DIR/.build/$TRIPLE/$BUILD_CONFIG/Finn"
APP_NAME="Finn"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.finn-holger.app}"
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"

if [ ! -f "$BUILD_BIN" ]; then
    echo "ERROR: Binary not found at $BUILD_BIN"
    echo "Run ./scripts/build-tvos.sh first."
    exit 1
fi

echo "=== Packaging $APP_NAME.app ==="

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# Standard tvOS .app bundle structure
cat > "$APP_DIR/Info.plist" << INFOEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UILaunchScreen</key>
    <dict/>
    <key>DTPlatformName</key>
    <string>appletvos</string>
    <key>DTPlatformVersion</key>
    <string>17.0</string>
    <key>DTSDKName</key>
    <string>appletvos17.0</string>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>3</integer>
    </array>
</dict>
</plist>
INFOEOF

cp "$BUILD_BIN" "$APP_DIR/$APP_NAME"
chmod +x "$APP_DIR/$APP_NAME"

# Merge project Info.plist if it exists
if [ -f "$PROJECT_DIR/Finn/Info.plist" ]; then
    echo "Note: Project has an Info.plist; merging values may need manual review."
fi

echo ""
echo "=== Package created ==="
echo "App bundle: $APP_DIR"
ls -la "$APP_DIR/$APP_NAME"
echo ""
echo "To deploy: ./scripts/deploy-tvos.sh"
