#!/bin/bash
set -euo pipefail

# Script to run ON A MAC to extract the tvOS SDK for cross-compilation on Linux.
# Requires Xcode installed.

XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
SDK_NAME="${SDK_NAME:-appletvos}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/tvos-sdk-bundle}"

echo "=== Extracting tvOS SDK from Xcode ==="

SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
echo "SDK path: $SDK_PATH"

SWIFT_VERSION=$(xcrun --sdk "$SDK_NAME" swiftc --version | head -1)
echo "Swift version: $SWIFT_VERSION"

# Find the Xcode toolchain path
TOOLCHAIN_DIR=$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain
echo "Toolchain: $TOOLCHAIN_DIR"

PLATFORM_DIR=$(dirname "$SDK_PATH")
echo "Platform: $PLATFORM_DIR"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/sdk"
mkdir -p "$OUTPUT_DIR/swift-libs"

# Copy the SDK
echo "Copying SDK..."
cp -a "$SDK_PATH" "$OUTPUT_DIR/sdk/AppleTVOS.sdk"
cp -a "$PLATFORM_DIR" "$OUTPUT_DIR/sdk/AppleTVOS.platform"

# Copy tvOS Swift runtime libraries
echo "Copying Swift runtime libs..."
SWIFT_LIB_DIR="$TOOLCHAIN_DIR/usr/lib/swift/appletvos"
if [ -d "$SWIFT_LIB_DIR" ]; then
    cp -a "$SWIFT_LIB_DIR" "$OUTPUT_DIR/swift-libs/"
else
    echo "WARNING: Could not find Swift libs at $SWIFT_LIB_DIR"
fi

# Copy prebuilt Swift modules
SWIFT_MODULE_DIR="$TOOLCHAIN_DIR/usr/lib/swift/appletvos/prebuilt-modules"
if [ -d "$SWIFT_MODULE_DIR" ]; then
    cp -a "$SWIFT_MODULE_DIR" "$OUTPUT_DIR/swift-libs/"
fi

# Package it all up
ARCHIVE_NAME="tvos-sdk-$(echo "$SDK_NAME" | tr -d ' ').tar.gz"
echo "Creating archive: $ARCHIVE_NAME"
tar -czf "$ARCHIVE_NAME" -C "$OUTPUT_DIR" .

echo ""
echo "=== Done ==="
echo "SDK bundle created at: $PWD/$ARCHIVE_NAME"
echo ""
echo "Transfer this file to your Linux machine and run:"
echo "  tar -xzf $ARCHIVE_NAME -C ~/tvos-sdk"
echo "  ./scripts/build-tvos.sh"
