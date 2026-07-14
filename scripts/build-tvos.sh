#!/bin/bash
set -euo pipefail

# Build Finn for tvOS on Linux using the official Swift Docker image.
# Requires Podman (or Docker) and the tvOS SDK extracted from a Mac.
#
# Usage:
#   ./scripts/build-tvos.sh                    # release build
#   ./scripts/build-tvos.sh --debug            # debug build
#   ./scripts/build-tvos.sh --sdk-path ~/tvos-sdk   # custom SDK path

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_PATH="${SDK_PATH:-$HOME/tvos-sdk}"
TRIPLE="arm64-apple-tvos"
CONTAINER_CMD="${CONTAINER_CMD:-podman}"
SWIFT_IMAGE="${SWIFT_IMAGE:-docker.io/swift:latest}"

# Parse args
BUILD_CONFIG="release"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) BUILD_CONFIG="debug"; shift ;;
        --release) BUILD_CONFIG="release"; shift ;;
        --sdk-path) SDK_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SDK="$SDK_PATH/sdk/AppleTVOS.sdk"
SWIFT_LIBS="$SDK_PATH/swift-libs"

if [ ! -d "$SDK" ]; then
    echo "ERROR: tvOS SDK not found at $SDK"
    echo ""
    echo "You need the tvOS SDK from a Mac with Xcode:"
    echo "  1. On a Mac: ./scripts/extract-tvos-sdk.sh"
    echo "  2. Transfer the .tar.gz to this Linux machine"
    echo "  3. Extract: tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk"
    echo ""
    echo "Or set SDK_PATH to point to your SDK directory."
    exit 1
fi

echo "=== Building Finn for tvOS ==="
echo "SDK: $SDK"
echo "Config: $BUILD_CONFIG"
echo "Container: $CONTAINER_CMD"

# Ensure the Swift image is available
if ! $CONTAINER_CMD image exists "$SWIFT_IMAGE" 2>/dev/null; then
    echo "Pulling Swift Docker image..."
    $CONTAINER_CMD pull "$SWIFT_IMAGE" 2>&1 | tail -3
fi

BUILD_FLAG=""
if [ "$BUILD_CONFIG" = "release" ]; then
    BUILD_FLAG="-c release"
fi

# Build inside the container
$CONTAINER_CMD run --rm \
    -v "$PROJECT_DIR:/app:Z" \
    -v "$SDK_PATH:/sdk:Z" \
    -w /app \
    "$SWIFT_IMAGE" \
    bash -c "
        set -euo pipefail
        SDK=/sdk/sdk/AppleTVOS.sdk
        SWIFT_LIBS=/sdk/swift-libs
        TRIPLE=$TRIPLE

        RESOURCE_FLAG=''
        if [ -d \"\$SWIFT_LIBS\" ]; then
            RESOURCE_FLAG='-Xswiftc -resource-dir -Xswiftc '\$SWIFT_LIBS
        fi

        echo 'Resolving dependencies...'
        swift package resolve

        echo ''
        echo 'Building for \$TRIPLE...'
        swift build \\
            $BUILD_FLAG \\
            --triple \"\$TRIPLE\" \\
            -Xswiftc -sdk -Xswiftc \"\$SDK\" \\
            -Xswiftc -target -Xswiftc \"\$TRIPLE\" \\
            -Xcc -isysroot -Xcc \"\$SDK\" \\
            -Xcc -target -Xcc \"\$TRIPLE\" \\
            \$RESOURCE_FLAG
    " 2>&1

BUILD_DIR_NAME="${BUILD_CONFIG}"
BUILD_BIN="$PROJECT_DIR/.build/$TRIPLE/$BUILD_DIR_NAME/Finn"

if [ -f "$BUILD_BIN" ]; then
    echo ""
    echo "=== Build successful ==="
    echo "Binary: $BUILD_BIN"
    echo ""
    echo "Next: ./scripts/package-tvos.sh [--$BUILD_CONFIG]"
else
    echo ""
    echo "=== Build completed with errors ==="
    echo "Check output above for details."
    exit 1
fi
