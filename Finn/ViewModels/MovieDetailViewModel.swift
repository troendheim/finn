import Foundation
import JellyfinAPI

@MainActor
@Observable
final class MovieDetailViewModel {
    var item: BaseItemDto?
    var isLoading = false
    var error: String?
    var isFavorite = false
    var actionError: String?

    let itemID: String
    private let jellyfinService: JellyfinService

    init(itemID: String, jellyfinService: JellyfinService) {
        self.itemID = itemID
        self.jellyfinService = jellyfinService
    }

    func loadDetail() async {
        isLoading = true
        error = nil
        do {
            let loaded = try await jellyfinService.getItem(id: itemID)
            item = loaded
            isFavorite = loaded.userData?.isFavorite == true
        } catch {
            self.error = "Failed to load movie details"
        }
        isLoading = false
    }

    func toggleFavorite() async {
        guard let item else { return }
        guard let id = item.id else { return }
        do {
            if isFavorite {
                try await jellyfinService.unmarkFavorite(itemID: id)
            } else {
                try await jellyfinService.markFavorite(itemID: id)
            }
            isFavorite.toggle()
        } catch {
            actionError = "Failed to update favorite"
        }
    }

    /// Button label: "Play" or "Resume · Xh Xm left"
    var playButtonTitle: String {
        guard let item, item.hasProgress else { return "Play" }
        let remaining = TimeFormatting.remaining(
            totalTicks: item.runTimeTicks,
            positionTicks: item.userData?.playbackPositionTicks
        )
        return "Resume · \(remaining)"
    }

    /// Metadata line: "2024 · 2h 15m · PG-13"
    var metadataLine: String {
        var parts: [String] = []
        if let year = item?.yearDisplay { parts.append(year) }
        if let runtime = item?.runtimeDisplay { parts.append(runtime) }
        if let rating = item?.officialRating { parts.append(rating) }
        return parts.joined(separator: " · ")
    }

    /// Community rating as string
    var ratingDisplay: String? {
        guard let rating = item?.communityRating else { return nil }
        return String(format: "%.1f", rating)
    }
}
