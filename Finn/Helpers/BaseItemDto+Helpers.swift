import Foundation
import JellyfinAPI

extension BaseItemDto {
    /// Whether this item has been fully watched
    var isWatched: Bool {
        userData?.isPlayed == true
    }

    /// Playback progress as 0.0-1.0 (clamped)
    var playbackProgress: Double {
        min(max((userData?.playedPercentage ?? 0) / 100.0, 0), 1)
    }

    /// Whether there is resume progress
    var hasProgress: Bool {
        (userData?.playbackPositionTicks ?? 0) > 0
    }

    /// Display string for episode: "S3 E5"
    var episodeLabel: String? {
        guard let season = parentIndexNumber, let episode = indexNumber else { return nil }
        return "S\(season) E\(episode)"
    }

    /// Combined episode label with title: "S3 E5 - Episode Title"
    var episodeDisplayTitle: String? {
        guard let label = episodeLabel else { return nil }
        if let title = name {
            return "\(label) \u{00B7} \(title)"
        }
        return label
    }

    /// Runtime as readable string
    var runtimeDisplay: String? {
        guard let ticks = runTimeTicks else { return nil }
        return TimeFormatting.shortDuration(ticks: ticks)
    }

    /// Year as string
    var yearDisplay: String? {
        guard let year = productionYear else { return nil }
        return String(year)
    }

    /// People filtered by role
    func people(ofKind kind: PersonKind) -> [BaseItemPerson] {
        (people ?? []).filter { $0.type == kind }
    }

    /// Director names joined
    var directorNames: String? {
        let directors = people(ofKind: .director)
        guard !directors.isEmpty else { return nil }
        return directors.compactMap(\.name).joined(separator: ", ")
    }

    /// Cast names (first 10)
    var castNames: [String] {
        Array(people(ofKind: .actor).compactMap(\.name).prefix(10))
    }

    /// Available audio language names from media streams
    var audioLanguages: [String] {
        (mediaStreams ?? [])
            .filter { $0.type == .audio }
            .compactMap { $0.displayTitle ?? $0.language }
    }

    /// Available subtitle language names from media streams
    var subtitleLanguages: [String] {
        (mediaStreams ?? [])
            .filter { $0.type == .subtitle }
            .compactMap { $0.displayTitle ?? $0.language }
    }
}
