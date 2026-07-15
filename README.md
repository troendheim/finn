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

You can build and deploy to an Apple TV entirely from Linux — **no Mac required**. The tvOS SDK is extracted via a free GitHub Actions workflow and downloaded to your machine.

### Prerequisites

- **Podman** (pre-installed on Fedora) or Docker
- **Python 3** with `pymobiledevice3` (auto-installed by deploy script)
- **Apple TV** on the same local network
- **GitHub CLI** (`gh`) — for downloading the tvOS SDK artifact (one-time setup)

### Quick Start

```bash
# 1. One-time: Get the tvOS SDK (no Mac needed!)
#    Go to: https://github.com/troendheim/finn/actions/workflows/extract-tvos-sdk.yml
#    Click "Run workflow", wait ~2 minutes, then:
./scripts/extract-tvos-sdk.sh --download
tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk

# 2. Build for tvOS
./scripts/build-tvos.sh

# 3. Package into .app bundle
./scripts/package-tvos.sh

# 4. Pair with Apple TV (first time only)
./scripts/deploy-tvos.sh --pair --device <AppleTV-UDID>

# 5. Deploy to Apple TV
./scripts/deploy-tvos.sh
```

> If you *do* have a Mac with Xcode, you can skip GitHub Actions. Just run `./scripts/extract-tvos-sdk.sh` on the Mac and transfer the resulting `.tar.gz` to this machine.

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

**Build fails with SDK errors**: Make sure the SDK was properly extracted. The path `~/tvos-sdk/AppleTVOS.sdk` must exist.

**"Cannot find type 'ObservableObject'"**: This means you're building for Linux native instead of tvOS. The build script MUST use `--triple arm64-apple-tvos` with the SDK.
