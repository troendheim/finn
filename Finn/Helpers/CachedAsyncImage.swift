import SwiftUI

#if os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#else
import UIKit
private typealias PlatformImage = UIImage
#endif

/// A drop-in replacement for `AsyncImage` that caches downloaded images in memory.
///
/// SwiftUI's built-in `AsyncImage` has no caching -- every time the view is
/// recreated (e.g. scrolling off-screen and back) the image is re-downloaded.
/// `CachedAsyncImage` uses a shared `NSCache` so images are fetched once and
/// served from memory on subsequent appearances.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                content(makeSwiftUIImage(image))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }

        // Check memory cache first
        if let cached = ImageCacheStore.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Decode on a background thread so scrolling doesn't block the
            // main run loop — UIImage(data:) is surprisingly expensive.
            let downloaded = try await Task.detached(priority: .userInitiated) {
                PlatformImage(data: data)
            }.value
            guard let downloaded else { return }
            ImageCacheStore.shared.setImage(downloaded, for: url)
            // Only update if we're still showing the same URL
            if !Task.isCancelled {
                self.image = downloaded
            }
        } catch {
            // Silently fail -- placeholder remains visible
        }
    }

    private func makeSwiftUIImage(_ platformImage: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: platformImage)
        #else
        Image(uiImage: platformImage)
        #endif
    }
}

// MARK: - Convenience initialiser matching AsyncImage API

extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { Color.clear }
    }
}

// MARK: - Shared in-memory image cache

private final class ImageCacheStore: @unchecked Sendable {
    static let shared = ImageCacheStore()

    private let cache = NSCache<NSURL, PlatformImage>()

    private init() {
        // Allow up to ~600 images in memory — a full library page plus
        // the visible rows so scrolling back doesn't re-fetch.
        cache.countLimit = 600
    }

    func image(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: PlatformImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
