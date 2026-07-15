#!/bin/bash
set -euo pipefail

# Extract the tvOS SDK from Xcode.
# Can run on macOS (extracts locally) or Linux (downloads from GitHub Actions artifact).
#
# macOS usage:
#   ./scripts/extract-tvos-sdk.sh
#   # → produces tvos-sdk-appletvos.tar.gz
#
# Linux usage:
#   # First, run the GitHub Actions workflow "Extract tvOS SDK" in this repo.
#   # Then download the artifact:
#   ./scripts/extract-tvos-sdk.sh --download
#   # Or with a specific run ID:
#   ./scripts/extract-tvos-sdk.sh --download --run-id 1234567890
#
#   # Or if you already have the tar.gz:
#   tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="troendheim/finn"

download_from_actions() {
    local RUN_ID="${1:-latest}"
    local GH="${GH_CLI:-gh}"

    if ! command -v $GH &>/dev/null; then
        echo "ERROR: GitHub CLI 'gh' not found. Install it first:"
        echo "  sudo dnf install gh     # Fedora"
        echo "  gh auth login            # authenticate"
        echo ""
        echo "Alternatively, download the artifact manually from GitHub Actions:"
        echo "  https://github.com/$REPO/actions/workflows/extract-tvos-sdk.yml"
        exit 1
    fi

    echo "Downloading tvOS SDK artifact from GitHub Actions..."

    if [ "$RUN_ID" = "latest" ]; then
        echo "Finding latest successful run..."
        RUN_ID=$($GH run list --workflow extract-tvos-sdk.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
        if [ -z "$RUN_ID" ]; then
            echo "ERROR: No successful workflow run found."
            echo "Run the workflow first: https://github.com/$REPO/actions/workflows/extract-tvos-sdk.yml"
            exit 1
        fi
        echo "Using run ID: $RUN_ID"
    fi

    $GH run download "$RUN_ID" --name tvos-sdk-appletvos --dir "$PROJECT_DIR" 2>&1
    echo ""
    echo "Downloaded: $PROJECT_DIR/tvos-sdk-appletvos.tar.gz"
    echo ""
    echo "Extract it: tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk"
}

# --- macOS extraction (original path) ---
extract_on_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo "ERROR: This script must run on macOS to extract the SDK locally."
        echo "On Linux, use '--download' to get the SDK from GitHub Actions."
        exit 1
    fi

    XCODE_PATH="$(xcode-select -p 2>/dev/null || echo "")"
    if [ -z "$XCODE_PATH" ] || [ ! -d "$XCODE_PATH" ]; then
        echo "ERROR: Xcode not found. Install Xcode from the App Store."
        exit 1
    fi

    XCODE_PATH="${XCODE_PATH%/Contents/Developer}"     # strip trailing Developer
    SDK_PATH="$XCODE_PATH/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs"
    SWIFT_PATH="$XCODE_PATH/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/appletvos"

    SDK=$(find "$SDK_PATH" -name "*.sdk" -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
    if [ -z "$SDK" ]; then
        echo "ERROR: No tvOS SDK found in $SDK_PATH"
        exit 1
    fi

    echo "Found tvOS SDK: $(basename "$SDK")"

    mkdir -p "$PROJECT_DIR/sdk-package"
    cp -a "$SDK" "$PROJECT_DIR/sdk-package/"

    if [ -d "$SWIFT_PATH" ]; then
        mkdir -p "$PROJECT_DIR/sdk-package/swift-resources"
        cp -a "$SWIFT_PATH"/* "$PROJECT_DIR/sdk-package/swift-resources/"
        echo "Swift resources copied"
    fi

    tar -czf "$PROJECT_DIR/tvos-sdk-appletvos.tar.gz" -C "$PROJECT_DIR/sdk-package" .
    rm -rf "$PROJECT_DIR/sdk-package"
    echo ""
    echo "=== Done ==="
    echo "Package: $PROJECT_DIR/tvos-sdk-appletvos.tar.gz ($(du -sh "$PROJECT_DIR/tvos-sdk-appletvos.tar.gz" | cut -f1))"
    echo ""
    echo "Transfer this file to your Linux machine and extract:"
    echo "  tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk"
}

# --- Main ---
case "${1:-}" in
    --download)
        download_from_actions "${2:-latest}"
        ;;
    *)
        extract_on_macos
        ;;
esac
