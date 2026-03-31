# Finn

A Jellyfin client for Apple TV, built with SwiftUI.
Currently work in progress :-)

## What it does

- Connects to a Jellyfin server, browses libraries, searches content
- Plays movies and TV shows with full transport controls (scrub, seek, audio/subtitle switching)
- Continue Watching and Next Up rows with progress tracking
- Liquid Glass UI on tvOS 26+

## Building

Requires Xcode with tvOS 17+ SDK. Uses [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) as the only dependency.

```
xcodegen generate   # generates Finn.xcodeproj from project.yml
```

Then open in Xcode and run on an Apple TV or the simulator.
