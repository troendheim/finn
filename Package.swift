// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Finn",
    platforms: [
        .tvOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Finn",
            dependencies: [
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")
            ],
            path: "Finn"
        )
    ]
)
