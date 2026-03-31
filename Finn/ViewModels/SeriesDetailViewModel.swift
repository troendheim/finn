import Foundation
import JellyfinAPI

@MainActor
@Observable
final class SeriesDetailViewModel {
    var item: BaseItemDto?
    var seasons: [BaseItemDto] = []
    var episodes: [BaseItemDto] = []
    var selectedSeason: BaseItemDto?
    var isLoading = false
    var isLoadingEpisodes = false
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
            async let itemTask = jellyfinService.getItem(id: itemID)
            async let seasonsTask = jellyfinService.getSeasons(seriesID: itemID)

            let (loaded, loadedSeasons) = try await (itemTask, seasonsTask)
            item = loaded
            isFavorite = loaded.userData?.isFavorite == true
            seasons = loadedSeasons

            // Select first season and load its episodes
            if let first = loadedSeasons.first {
                await selectSeason(first)
            }
        } catch {
            self.error = "Failed to load series details"
        }
        isLoading = false
    }

    func selectSeason(_ season: BaseItemDto) async {
        selectedSeason = season
        guard let seasonID = season.id else { return }

        isLoadingEpisodes = true
        do {
            episodes = try await jellyfinService.getEpisodes(
                seriesID: itemID,
                seasonID: seasonID
            )
        } catch {
            episodes = []
        }
        isLoadingEpisodes = false
    }

    func toggleFavorite() async {
        guard let id = item?.id else { return }
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

    /// Toggle the played/watched status of an episode
    func togglePlayed(episode: BaseItemDto) async {
        guard let episodeID = episode.id else { return }
        do {
            if episode.isWatched {
                try await jellyfinService.markUnplayed(itemID: episodeID)
            } else {
                try await jellyfinService.markPlayed(itemID: episodeID)
            }
            // Update local state by finding and replacing the episode
            if let index = episodes.firstIndex(where: { $0.id == episodeID }) {
                // Reload the episode to get fresh userData
                let updated = try await jellyfinService.getItem(id: episodeID)
                episodes[index] = updated
            }
        } catch {
            actionError = "Failed to update watch status"
        }
    }

    /// The episode the user should continue/start watching
    var continueEpisode: BaseItemDto? {
        // Find first episode with progress, or first unwatched
        if let inProgress = episodes.first(where: { $0.hasProgress }) {
            return inProgress
        }
        return episodes.first(where: { !$0.isWatched })
    }

    /// Play button title
    var playButtonTitle: String {
        guard let ep = continueEpisode else { return "Play" }
        if ep.hasProgress {
            let remaining = TimeFormatting.remaining(
                totalTicks: ep.runTimeTicks,
                positionTicks: ep.userData?.playbackPositionTicks
            )
            return "Continue \u{00B7} \(ep.episodeDisplayTitle ?? "") \u{00B7} \(remaining)"
        }
        return "Play \(ep.episodeLabel ?? "")"
    }

    /// The item ID to play
    var playItemID: String? {
        continueEpisode?.id
    }

    /// Metadata line
    var metadataLine: String {
        var parts: [String] = []
        if let year = item?.yearDisplay { parts.append(year) }
        let count = seasons.count
        if count > 0 {
            parts.append("\(count) Season\(count == 1 ? "" : "s")")
        }
        if let rating = item?.officialRating { parts.append(rating) }
        return parts.joined(separator: " \u{00B7} ")
    }
}
