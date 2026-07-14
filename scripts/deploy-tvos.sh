#!/bin/bash
set -euo pipefail

# Deploy Finn to an Apple TV on the local network.
# Requires pymobiledevice3 (pip install pymobiledevice3).
#
# Usage:
#   ./scripts/deploy-tvos.sh                        # auto-discover, release build
#   ./scripts/deploy-tvos.sh --device <UDID>        # specific device
#   ./scripts/deploy-tvos.sh --debug                # debug build
#   ./scripts/deploy-tvos.sh --pair                 # pair with Apple TV first

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Finn"
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"
BUILD_CONFIG="release"
DEVICE_ID=""
ACTION="deploy"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) BUILD_CONFIG="debug"; shift ;;
        --release) BUILD_CONFIG="release"; shift ;;
        --device) DEVICE_ID="$2"; shift 2 ;;
        --pair) ACTION="pair"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -d "$APP_DIR" ] && [ "$ACTION" = "deploy" ]; then
    echo "ERROR: App bundle not found at $APP_DIR"
    echo "Run ./scripts/build-tvos.sh && ./scripts/package-tvos.sh first."
    exit 1
fi

# Ensure pymobiledevice3 is available
ensure_pymd3() {
    if ! python3 -c "import pymobiledevice3" 2>/dev/null; then
        echo "Installing pymobiledevice3..."
        pip3 install --user --quiet pymobiledevice3 2>&1
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

echo "=== Finn tvOS Deployment ==="

if [ "$ACTION" = "pair" ]; then
    ensure_pymd3
    echo "Scanning for Apple TV on the network (5s)..."
    DEVICES=$(python3 -m pymobiledevice3 bonjour discover --timeout 5 2>&1 || true)
    echo "$DEVICES"
    echo ""
    if [ -z "$DEVICE_ID" ]; then
        echo "Specify the device UDID with --device <UDID> to pair."
        echo "Example: ./scripts/deploy-tvos.sh --pair --device 00008120-0012345678901234"
    else
        echo "Pairing with $DEVICE_ID..."
        python3 -m pymobiledevice3 lockdown pair --udid "$DEVICE_ID"
        echo "Follow the on-screen prompt on your Apple TV."
    fi
    exit 0
fi

# --- Deploy ---
ensure_pymd3
export PATH="$HOME/.local/bin:$PATH"

if [ -z "$DEVICE_ID" ]; then
    echo "Discovering Apple TVs on the network..."
    DEVICE_LIST=$(python3 -m pymobiledevice3 bonjour discover --timeout 5 2>&1 || true)
    echo "$DEVICE_LIST"
    echo ""

    if echo "$DEVICE_LIST" | grep -q "Identifier"; then
        DEVICE_ID=$(echo "$DEVICE_LIST" | grep -oP 'Identifier:\s*\K\S+' | head -1)
        echo "Using first discovered device: $DEVICE_ID"
    else
        echo "No Apple TV found. Make sure:"
        echo "  1. The Apple TV is on the same network"
        echo "  2. Settings > Remotes and Devices > Remote App and Devices is enabled"
        echo "  3. You've paired this machine (./scripts/deploy-tvos.sh --pair --device <UDID>)"
        echo ""
        echo "To specify a device: --device <UDID>"
        exit 1
    fi
fi

echo ""
echo "Deploying $APP_NAME.app to $DEVICE_ID..."

python3 -m pymobiledevice3 developer dvt install \
    "$APP_DIR" \
    --udid "$DEVICE_ID" \
    2>&1

echo ""
echo "=== Deployment complete ==="
echo "$APP_NAME should now appear on your Apple TV home screen."
