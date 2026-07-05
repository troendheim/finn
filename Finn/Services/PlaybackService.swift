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

        // Determine play method (pass requested indices so transcode URLs
        // get the correct SubtitleStreamIndex / AudioStreamIndex — the server
        // may return a transcodingURL with stale defaults)
        let (url, playMethod) = try buildStreamURL(
            mediaSource: mediaSource,
            serverURL: jellyfinService.serverURL,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )

        return StreamInfo(
            url: url,
            playMethod: playMethod,
            mediaSource: mediaSource,
            playSessionID: playSessionID,
            accessToken: jellyfinService.client?.accessToken
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

    /// Check if a subtitle stream requires a playback restart to switch to.
    /// External subtitles need a restart so the server generates a new HLS manifest
    /// with the correct subtitle embedded. Burn-in subtitles also need a restart.
    static func requiresRestart(stream: MediaStream) -> Bool {
        return requiresBurnIn(stream: stream) || stream.isExternal == true
    }

    // MARK: - Private

    private func buildStreamURL(
        mediaSource: MediaSourceInfo,
        serverURL: URL?,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) throws -> (URL, PlayMethod) {
        guard let serverURL else { throw FinnError.notConnected }
        guard let mediaSourceID = mediaSource.id else { throw FinnError.noMediaSource }
        let escapedMediaSourceID = mediaSourceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mediaSourceID

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
            components.path += "/Videos/\(escapedMediaSourceID)/stream"
            components.queryItems = [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
                URLQueryItem(name: "api_key", value: jellyfinService.client?.accessToken),
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
            components.path += "/Videos/\(escapedMediaSourceID)/stream"
            components.queryItems = [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSource.id),
                URLQueryItem(name: "api_key", value: jellyfinService.client?.accessToken),
            ]
            if let url = components.url {
                return (url, .directStream)
            }
        }

        // Fall back to transcode
        if mediaSource.isSupportsTranscoding == true,
           let transcodePath = mediaSource.transcodingURL {
            // transcodingURL is a path with query string (e.g. /videos/.../master.m3u8?params=...)
            // The server may return stale SubtitleStreamIndex / AudioStreamIndex values in
            // this URL (it often ignores the indices we sent in the POST body). Patch them
            // to match what the caller actually requested.
            let patchedPath = Self.patchTranscodeQueryParams(
                transcodePath,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )
            if let url = URL(string: patchedPath, relativeTo: serverURL)?.absoluteURL {
                return (url, .transcode)
            }
        }

        throw FinnError.noMediaSource
    }

    /// Replace `SubtitleStreamIndex` and `AudioStreamIndex` query parameters in a
    /// server-provided transcode URL path.  When `subtitleStreamIndex` is `nil` the
    /// parameter is removed entirely (disables subtitles).  When `audioStreamIndex`
    /// is `nil` the existing value is left as-is (server default).
    private static func patchTranscodeQueryParams(
        _ path: String,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?
    ) -> String {
        // Split into path and query parts
        guard let questionMark = path.firstIndex(of: "?") else { return path }
        let basePath = String(path[path.startIndex..<questionMark])
        let queryString = String(path[path.index(after: questionMark)...])

        // Parse existing query items, filtering out the ones we'll replace
        var items = queryString
            .split(separator: "&", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { item in
                let key = item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if key == "SubtitleStreamIndex" { return false }
                if key == "AudioStreamIndex" && audioStreamIndex != nil { return false }
                // When disabling subtitles, also remove SubtitleMethod so the
                // server doesn't burn in a default subtitle track
                if key == "SubtitleMethod" && subtitleStreamIndex == nil { return false }
                return true
            }

        // Add the requested values
        if let subIdx = subtitleStreamIndex {
            items.append("SubtitleStreamIndex=\(subIdx)")
        }
        if let audioIdx = audioStreamIndex {
            items.append("AudioStreamIndex=\(audioIdx)")
        }

        let result = basePath + "?" + items.joined(separator: "&")
        #if DEBUG
        print("[SUBS] patchTranscodeQueryParams: sub=\(String(describing: subtitleStreamIndex)) audio=\(String(describing: audioStreamIndex))")
        print("[SUBS]   patched URL=\(result)")
        #endif
        return result
    }
}

// MARK: - StreamInfo

struct StreamInfo {
    let url: URL
    let playMethod: PlayMethod
    let mediaSource: MediaSourceInfo
    let playSessionID: String?
    let accessToken: String?
}
