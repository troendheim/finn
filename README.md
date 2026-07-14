# Finn

A Jellyfin client for Apple TV, built with SwiftUI.
Currently work in progress :-)

## What it does

- Connects to a Jellyfin server, browses libraries, searches content
- Plays movies and TV shows with full transport controls (scrub, seek, audio/subtitle switching)
- Continue Watching and Next Up rows with progress tracking
- Liquid Glass UI on tvOS 26+

## Building (macOS with Xcode)

Requires Xcode with tvOS 17+ SDK. Uses [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) as the only dependency.

```
xcodegen generate   # generates Finn.xcodeproj from project.yml
```

Then open in Xcode and run on an Apple TV or the simulator.

## Building & Deploying from Linux

You can build and deploy to an Apple TV directly from Linux — no Xcode or macOS needed for the build/deploy step. You **do** still need one-time access to a Mac with Xcode to extract the tvOS SDK.

### Prerequisites

- **Podman** (pre-installed on Fedora) or Docker
- **Python 3** with `pymobiledevice3` (auto-installed by deploy script)
- **Apple TV** on the same local network
- **tvOS SDK** — extracted once from a Mac (see below)

### Quick Start

```bash
# 1. One-time: Extract the tvOS SDK from a Mac
#    (run this on your Mac, then transfer the tar.gz to this Linux machine)
./scripts/extract-tvos-sdk.sh
#    → produces tvos-sdk-appletvos.tar.gz

# 2. On Linux: Extract the SDK
tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk

# 3. Build for tvOS
./scripts/build-tvos.sh

# 4. Package into .app bundle
./scripts/package-tvos.sh

# 5. Pair with Apple TV (first time only)
./scripts/deploy-tvos.sh --pair --device <AppleTV-UDID>

# 6. Deploy to Apple TV
./scripts/deploy-tvos.sh
```

### How it works

- **Build**: Uses the official `swift:latest` Docker image (via Podman) with the tvOS SDK mounted. The Swift compiler cross-compiles for `arm64-apple-tvos`.
- **Package**: Creates a standard tvOS `.app` bundle with `Info.plist`.
- **Deploy**: Uses `pymobiledevice3` to discover the Apple TV via Bonjour/mDNS and install the app wirelessly over the local network.

### Configuration

| Env var | Default | Description |
|---|---|---|
| `SDK_PATH` | `~/tvos-sdk` | Path to extracted tvOS SDK |
| `CONTAINER_CMD` | `podman` | Container runtime (podman/docker) |
| `SWIFT_IMAGE` | `docker.io/swift:latest` | Swift Docker image |

### Pairing the Apple TV

Before deploying, the Apple TV must be paired with this machine:

1. On Apple TV: Settings → Remotes and Devices → Remote App and Devices
2. Keep this screen open
3. Run: `./scripts/deploy-tvos.sh --pair --device <UDID>`
4. Enter the PIN shown on the Apple TV when prompted

To find the UDID, run `./scripts/deploy-tvos.sh --pair` which will scan the network for devices.

### Troubleshooting

**"Apple TV not found"**: Ensure the Apple TV is awake, on the same network, and the Remote App and Devices screen is open.

**Build fails with SDK errors**: Make sure the SDK was properly extracted. The path `~/tvos-sdk/sdk/AppleTVOS.sdk` must exist.

**"Cannot find type 'ObservableObject'"**: This means you're building for Linux native instead of tvOS. The build script MUST use `--triple arm64-apple-tvos` with the SDK.
