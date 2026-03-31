import Foundation
import AVFoundation
import JellyfinAPI

@MainActor
@Observable
final class PlaybackService {
    private let jellyfinService: JellyfinService

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    // MARK: - Stream URL Construction

    /// Get the stream URL and media source for an item
    func getStreamInfo(
        itemID: String,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async throws -> StreamInfo {
        let response = try await jellyfinService.getPlaybackInfo(
            itemID: itemID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
        guard let mediaSource = response.mediaSources?.first else {
            throw FinnError.noMediaSource
        }

        let playSessionID = response.playSessionID

        // Determine play method
        let (url, playMethod) = try buildStreamURL(
            mediaSource: mediaSource,
            serverURL: jellyfinService.serverURL
        )

        return StreamInfo(
            url: url,
            playMethod: playMethod,
            mediaSource: mediaSource,
            playSessionID: playSessionID
        )
    }

    // MARK: - Progress Reporting

    func reportStart(
        itemID: String,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int?,
        playMethod: PlayMethod
    ) async {
        let info = PlaybackStartInfo(
            canSeek: true,
            isPaused: false,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: playMethod,
            playSessionID: playSessionID,
            positionTicks: positionTicks
        )
        try? await jellyfinService.reportPlaybackStart(info: info)
    }

    func reportProgress(
        itemID: String,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int,
        isPaused: Bool,
        playMethod: PlayMethod,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async {
        let info = PlaybackProgressInfo(
            audioStreamIndex: audioStreamIndex,
            canSeek: true,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: playMethod,
            playSessionID: playSessionID,
            positionTicks: positionTicks,
            subtitleStreamIndex: subtitleStreamIndex
        )
        try? await jellyfinService.reportPlaybackProgress(info: info)
    }

    func reportStopped(
        itemID: String,
        mediaSourceID: String?,
        playSessionID: String?,
        positionTicks: Int
    ) async {
        let info = PlaybackStopInfo(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: positionTicks
        )
        try? await jellyfinService.reportPlaybackStopped(info: info)
    }

    // MARK: - Audio/Subtitle Track Helpers

    /// Get audio streams from a media source
    static func audioStreams(from mediaSource: MediaSourceInfo) -> [MediaStream] {
        (mediaSource.mediaStreams ?? []).filter { $0.type == .audio }
    }

    /// Get subtitle streams from a media source
    static func subtitleStreams(from mediaSource: MediaSourceInfo) -> [MediaStream] {
        (mediaSource.mediaStreams ?? []).filter { $0.type == .subtitle }
    }

    /// Check if a subtitle format requires transcoding for burn-in
    static func requiresBurnIn(stream: MediaStream) -> Bool {
        guard let codec = stream.codec?.lowercased() else { return false }
        // ASS/SSA styled subtitles and PGS/DVD bitmap subtitles require burn-in via transcode
        // because AVPlayer cannot render these formats natively
        let burnInCodecs: Set<String> = ["ass", "ssa", "pgs", "pgssub", "dvdsub"]
        return burnInCodecs.contains(codec)
    }

    // MARK: - Private

    private func buildStreamURL(
        mediaSource: MediaSourceInfo,
        serverURL: URL?
    ) throws -> (URL, PlayMethod) {
        guard let serverURL else { throw FinnError.notConnected }
        guard let mediaSourceID = mediaSource.id else { throw FinnError.noMediaSource }

        // Check for direct play compatibility
        let containerFormats = Set(
            (mediaSource.container?.lowercased() ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )
        let avPlayerContainers: Set<String> = ["mp4", "m4v", "mov"]

        if mediaSource.isSupportsDirectPlay == true,
           !containerFormats.isDisjoint(with: avPlayerContainers) {
            // Build direct stream URL
            guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
                throw FinnError.noMediaSource
            }
            components.path += "/Videos/\(mediaSourceID)/stream"
            components.queryItems = [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
                URLQueryItem(name: "api_key", value: jellyfinService.client?.accessToken)
            ]
            if let url = components.url {
                return (url, .directPlay)
            }
        }

        // Fall back to direct stream (only for containers AVPlayer can handle)
        if mediaSource.isSupportsDirectStream == true,
           !containerFormats.isDisjoint(with: avPlayerContainers) {
            guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
                throw FinnError.noMediaSource
            }
            components.path += "/Videos/\(mediaSourceID)/stream"
            components.queryItems = [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
                URLQueryItem(name: "api_key", value: jellyfinService.client?.accessToken)
            ]
            if let url = components.url {
                return (url, .directStream)
            }
        }

        // Fall back to transcode
        if mediaSource.isSupportsTranscoding == true,
           let transcodePath = mediaSource.transcodingURL {
            // transcodingURL is a path with query string (e.g. /videos/.../master.m3u8?params=...)
            // Use URL(string:relativeTo:) to preserve query parameters correctly
            if let url = URL(string: transcodePath, relativeTo: serverURL)?.absoluteURL {
                return (url, .transcode)
            }
        }

        throw FinnError.noMediaSource
    }
}

// MARK: - StreamInfo

struct StreamInfo {
    let url: URL
    let playMethod: PlayMethod
    let mediaSource: MediaSourceInfo
    let playSessionID: String?
}
