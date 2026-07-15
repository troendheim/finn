#!/bin/bash
set -euo pipefail

# Build or download Finn for tvOS.
#
# Modes:
#   --download    Download the pre-built .app from GitHub Actions (recommended)
#   (default)     Build locally using Podman + Docker Swift image + tvOS SDK
#
# Usage:
#   ./scripts/build-tvos.sh --download            # download release build
#   ./scripts/build-tvos.sh --download --debug    # download debug build (if available)
#   ./scripts/build-tvos.sh                       # local build

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="release"
MODE="local"
RUN_ID="${RUN_ID:-latest}"
REPO="troendheim/finn"
GH="${GH_CLI:-gh}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download) MODE="download"; shift ;;
        --local) MODE="local"; shift ;;
        --debug) BUILD_CONFIG="debug"; shift ;;
        --release) BUILD_CONFIG="release"; shift ;;
        --run-id) RUN_ID="$2"; shift 2 ;;
        --sdk-path) SDK_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================
# Download mode: get pre-built .app from GitHub Actions
# ============================================================
if [ "$MODE" = "download" ]; then
    ARTIFACT_NAME="finn-appletvos"

    if ! command -v $GH &>/dev/null; then
        echo "ERROR: GitHub CLI 'gh' not found. Install it first:"
        echo "  sudo dnf install gh     # Fedora"
        echo "  gh auth login            # authenticate"
        exit 1
    fi

    if [ "$RUN_ID" = "latest" ]; then
        echo "Finding latest successful build..."
        RUN_ID=$($GH run list --workflow build-tvos.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
        if [ -z "$RUN_ID" ]; then
            echo "ERROR: No successful build found."
            echo "Trigger a build: https://github.com/$REPO/actions/workflows/build-tvos.yml"
            exit 1
        fi
        echo "Using run ID: $RUN_ID"
    fi

    echo "Downloading $ARTIFACT_NAME from run $RUN_ID..."
    $GH run download "$RUN_ID" --name "$ARTIFACT_NAME" --dir /tmp/finn-download 2>&1

    mkdir -p "$PROJECT_DIR/build"
    tar -xzf /tmp/finn-download/finn-appletvos.tar.gz -C "$PROJECT_DIR/build/"
    rm -rf /tmp/finn-download

    echo ""
    echo "=== Download complete ==="
    echo "App: $PROJECT_DIR/build/Finn.app"
    echo ""
    echo "To deploy: ./scripts/deploy-tvos.sh"
    exit 0
fi

# ============================================================
# Local build mode: cross-compile on Linux with Podman
# ============================================================

SDK_PATH="${SDK_PATH:-$HOME/tvos-sdk}"
TRIPLE="arm64-apple-tvos"
CONTAINER_CMD="${CONTAINER_CMD:-podman}"
SWIFT_IMAGE="${SWIFT_IMAGE:-docker.io/swift:latest}"

SDK="$SDK_PATH/AppleTVOS.sdk"
SWIFT_RESOURCES="$SDK_PATH/swift-resources"

if [ ! -d "$SDK" ]; then
    echo "ERROR: tvOS SDK not found at $SDK"
    echo ""
    echo "To get the tvOS SDK (no Mac required):"
    echo "  1. Run: ./scripts/extract-tvos-sdk.sh --download"
    echo "  2. Or trigger: https://github.com/$REPO/actions/workflows/extract-tvos-sdk.yml"
    echo "  3. Extract: tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk"
    echo ""
    echo "Or skip local build entirely:"
    echo "  ./scripts/build-tvos.sh --download"
    exit 1
fi

echo "=== Building Finn for tvOS (local) ==="
echo "SDK: $SDK"
echo "Config: $BUILD_CONFIG"
echo "Container: $CONTAINER_CMD"
echo ""
echo "NOTE: Local cross-compilation on Linux is experimental."
echo "For reliable builds, use: ./scripts/build-tvos.sh --download"
echo ""

# Ensure the Swift image is available
if ! $CONTAINER_CMD image exists "$SWIFT_IMAGE" 2>/dev/null; then
    echo "Pulling Swift Docker image..."
    $CONTAINER_CMD pull "$SWIFT_IMAGE" 2>&1 | tail -3
fi

BUILD_FLAG=""
if [ "$BUILD_CONFIG" = "release" ]; then
    BUILD_FLAG="-c release"
fi

$CONTAINER_CMD run --rm \
    -v "$PROJECT_DIR:/app:Z" \
    -v "$SDK_PATH:/sdk:Z" \
    -w /app \
    "$SWIFT_IMAGE" \
    bash -c "
        set -euo pipefail
        SDK=/sdk/AppleTVOS.sdk
        SWIFT_RESOURCES=/sdk/swift-resources
        TRIPLE=$TRIPLE

        # Create Apple libtool compatibility wrapper
        cat > /usr/local/bin/libtool << 'LIBTOOLEOF'
#!/bin/bash
args=()
output=""
files=()
for a in \"\$@\"; do
  if [ \"\$a\" = \"-static\" ]; then continue; fi
  if [ \"\$a\" = \"-o\" ]; then output=\"__next__\"; continue; fi
  if [ \"\$output\" = \"__next__\" ]; then output=\"\$a\"; continue; fi
  files+=(\"\$a\")
done
if [ -n \"\$output\" ]; then
  ar crs \"\$output\" \"\${files[@]}\" 2>&1
else
  echo \"libtool wrapper: unknown mode\" >&2
  exit 1
fi
LIBTOOLEOF
        chmod +x /usr/local/bin/libtool

        RESOURCE_FLAG=''
        if [ -d \"\$SWIFT_RESOURCES\" ]; then
            RESOURCE_FLAG='-Xswiftc -resource-dir -Xswiftc '\$SWIFT_RESOURCES
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
    echo "Next: ./scripts/package-tvos.sh"
else
    echo ""
    echo "=== Local build failed ==="
    echo "For reliable builds, use: ./scripts/build-tvos.sh --download"
    exit 1
fi
