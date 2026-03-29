import Foundation
import JellyfinAPI

final class ImageService {
    private let serverURL: URL

    init(serverURL: URL) {
        self.serverURL = serverURL
    }

    /// Build URL for an item's primary (poster) image
    func posterURL(itemID: String, maxWidth: Int = 400) -> URL? {
        serverURL
            .appendingPathComponent("Items/\(itemID)/Images/Primary")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "quality", value: "90")
            ])
    }

    /// Build URL for an item's backdrop image
    func backdropURL(itemID: String, maxWidth: Int = 1920) -> URL? {
        serverURL
            .appendingPathComponent("Items/\(itemID)/Images/Backdrop")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "quality", value: "90")
            ])
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
        serverURL
            .appendingPathComponent("Items/\(itemID)/Images/Primary")
            .appending(queryItems: [
                URLQueryItem(name: "maxWidth", value: String(maxWidth)),
                URLQueryItem(name: "quality", value: "80")
            ])
    }
}
