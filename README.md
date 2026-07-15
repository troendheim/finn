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

The build runs on a free **GitHub Actions macOS runner** — no Mac, no Xcode, no Apple developer account needed. Linux just downloads the built `.app` and deploys it to the Apple TV.

### Prerequisites

- **GitHub CLI** (`gh`) — for downloading builds. Already installed on Fedora: `sudo dnf install gh && gh auth login`
- **Python 3** with `pymobiledevice3` — for deployment (auto-installed by deploy script)
- **Apple TV** on the same local network

### Quick Start

```bash
# 1. Trigger a build on GitHub Actions (or push code to main)
#    Go to: https://github.com/troendheim/finn/actions/workflows/build-tvos.yml
#    Click "Run workflow", wait ~3 minutes

# 2. Download the built .app
./scripts/build-tvos.sh --download

# 3. Pair with Apple TV (first time only)
./scripts/deploy-tvos.sh --pair --device <AppleTV-UDID>

# 4. Deploy to Apple TV
./scripts/deploy-tvos.sh
```

### How it works

- **Build**: GitHub Actions macOS runner builds the project using Xcode's native toolchain (`swift build --triple arm64-apple-tvos`). The resulting `.app` bundle is uploaded as an artifact.
- **Download**: `./scripts/build-tvos.sh --download` fetches the latest successful build artifact.
- **Deploy**: `pymobiledevice3` discovers the Apple TV via mDNS and installs the app wirelessly.

### Local build (experimental)

If you prefer to build locally on Linux, you'll need the tvOS SDK:

```bash
./scripts/extract-tvos-sdk.sh --download   # get the SDK
tar -xzf tvos-sdk-appletvos.tar.gz -C ~/tvos-sdk
./scripts/build-tvos.sh                     # local cross-compile (requires Podman)
```

> **Note**: Local Linux cross-compilation is experimental. The Linux Swift compiler has version mismatches with SDK modules. Use `--download` for reliable builds.

### Configuration

| Env var | Default | Description |
|---|---|---|
| `CONTAINER_CMD` | `podman` | Container runtime (podman/docker) |
| `SDK_PATH` | `~/tvos-sdk` | Path to extracted tvOS SDK (local builds) |

### Pairing the Apple TV

Before deploying, the Apple TV must be paired with this machine:

1. On Apple TV: Settings → Remotes and Devices → Remote App and Devices
2. Keep this screen open
3. Run: `./scripts/deploy-tvos.sh --pair --device <UDID>`
4. Enter the PIN shown on the Apple TV when prompted

To find the UDID, run `./scripts/deploy-tvos.sh --pair` which scans the network for devices.

### Troubleshooting

**"Apple TV not found"**: Ensure the Apple TV is awake, on the same network, and the Remote App and Devices screen is open.

**"No successful build found"**: Trigger a build at https://github.com/troendheim/finn/actions/workflows/build-tvos.yml
