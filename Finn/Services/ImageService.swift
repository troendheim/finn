import Foundation
import JellyfinAPI

final class ImageService {
    private let serverURL: URL

    init(serverURL: URL) {
        self.serverURL = serverURL
    }

    /// Build URL for an item's primary (poster) image
    func posterURL(itemID: String, maxWidth: Int = 400) -> URL? {
        imageURL(itemID: itemID, imageType: "Primary", maxWidth: maxWidth)
    }

    /// Build URL for an item's backdrop image
    func backdropURL(itemID: String, maxWidth: Int = 1920) -> URL? {
        imageURL(itemID: itemID, imageType: "Backdrop", maxWidth: maxWidth)
    }

    /// Build URL for an item's backdrop at a specific index
    func backdropURL(itemID: String, index: Int, maxWidth: Int = 1920) -> URL? {
        serverURL
            .appendingPathComponent("Items/\(itemID)/Images/Backdrop/\(index)")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "quality", value: "90")
            ])
    }

    /// Build URL for an episode/series thumbnail
    func thumbURL(itemID: String, maxWidth: Int = 600) -> URL? {
        imageURL(itemID: itemID, imageType: "Thumb", maxWidth: maxWidth)
    }

    /// Best landscape image for an item — tries Thumb, then Backdrop, then parent images.
    /// For episodes, falls back to parent (season/series) Thumb and Backdrop.
    func landscapeURL(item: BaseItemDto, maxWidth: Int = 600) -> URL? {
        guard let id = item.id else { return nil }
        let tags = item.imageTags ?? [:]

        // 1. Thumb on the item itself (episode screenshot)
        if tags["Thumb"] != nil {
            return thumbURL(itemID: id, maxWidth: maxWidth)
        }

        // 2. Backdrop on the item itself
        if let backdropTags = item.backdropImageTags, !backdropTags.isEmpty {
            return backdropURL(itemID: id, maxWidth: maxWidth)
        }

        // 3. Parent Thumb (season or series thumb) — most common for episodes
        if let parentThumbID = item.parentThumbItemID, item.parentThumbImageTag != nil {
            return thumbURL(itemID: parentThumbID, maxWidth: maxWidth)
        }

        // 4. Series Thumb (via seriesId)
        if item.type == .episode, let seriesID = item.seriesID, item.seriesThumbImageTag != nil {
            return thumbURL(itemID: seriesID, maxWidth: maxWidth)
        }

        // 5. Parent Backdrop (season or series backdrop)
        if let parentBackdropID = item.parentBackdropItemID,
           let parentBackdropTags = item.parentBackdropImageTags, !parentBackdropTags.isEmpty {
            return backdropURL(itemID: parentBackdropID, maxWidth: maxWidth)
        }

        // 6. Series Backdrop (via seriesId)
        if item.type == .episode, let seriesID = item.seriesID {
            return backdropURL(itemID: seriesID, maxWidth: maxWidth)
        }

        // 7. Primary image as last resort (portrait, but better than nothing)
        if tags["Primary"] != nil {
            return posterURL(itemID: id, maxWidth: maxWidth)
        }

        return nil
    }

    // MARK: - Private

    private func imageURL(itemID: String, imageType: String, maxWidth: Int, quality: Int = 90) -> URL? {
        serverURL
            .appendingPathComponent("Items/\(itemID)/Images/\(imageType)")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "quality", value: String(quality))
            ])
    }
}
