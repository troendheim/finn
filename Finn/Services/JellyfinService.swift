import Foundation
import JellyfinAPI
import Get

@MainActor
@Observable
final class JellyfinService {
    // MARK: - Client Constants

    private static let clientName = "Finn"
    private static let clientVersion = "1.0.0"
    #if os(tvOS)
    private static let deviceName = "Apple TV"
    #elseif os(macOS)
    private static let deviceName = "Mac"
    #endif

    // MARK: - State

    private(set) var client: JellyfinClient?
    private(set) var currentUserID: String?
    private(set) var isAuthenticated = false
    private(set) var currentUserName: String?

    private(set) var serverURL: URL? {
        didSet { _imageService = serverURL.map { ImageService(serverURL: $0) } }
    }

    private var _imageService: ImageService?
    var imageService: ImageService? { _imageService }

    // MARK: - Persistence Keys

    private enum Keys {
        static let serverURL = "finn.serverURL"
        static let userID = "finn.userID"
        static let userName = "finn.userName"
        static let accessToken = "finn.accessToken"
        static let preferredAudioLanguage = "finn.preferredAudioLanguage"
        static let preferredSubtitleLanguage = "finn.preferredSubtitleLanguage"
    }

    // MARK: - Init

    init() {
        restoreSession()
    }

    // MARK: - Server Connection

    /// Validate and connect to a Jellyfin server
    func connectToServer(url: URL) async throws {
        let config = JellyfinClient.Configuration(
            url: url,
            client: Self.clientName,
            deviceName: Self.deviceName,
            deviceID: deviceID(),
            version: Self.clientVersion
        )
        let newClient = JellyfinClient(configuration: config)

        // Validate by fetching public system info (works even when public user display is disabled)
        let _ = try await newClient.send(Paths.getPublicSystemInfo).value

        self.client = newClient
        self.serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Keys.serverURL)
    }

    /// Get list of public users for login screen
    func getPublicUsers() async throws -> [UserDto] {
        guard let client else { throw FinnError.notConnected }
        return try await client.send(Paths.getPublicUsers).value
    }

    // MARK: - Authentication

    /// Sign in with username and password
    func signIn(username: String, password: String) async throws {
        guard let client else { throw FinnError.notConnected }
        let result = try await client.signIn(username: username, password: password)

        guard let userID = result.user?.id else {
            throw FinnError.noUserID
        }
        guard let token = result.accessToken else {
            throw FinnError.noAccessToken
        }

        self.currentUserID = userID
        self.isAuthenticated = true
        self.currentUserName = result.user?.name

        // Persist
        UserDefaults.standard.set(userID, forKey: Keys.userID)
        if let name = result.user?.name {
            UserDefaults.standard.set(name, forKey: Keys.userName)
        }
        KeychainHelper.save(key: Keys.accessToken, value: token)
    }

    /// Sign out and clear saved credentials
    func signOut() async {
        try? await client?.signOut()
        self.currentUserID = nil
        self.currentUserName = nil
        self.isAuthenticated = false
        KeychainHelper.delete(key: Keys.accessToken)
        UserDefaults.standard.removeObject(forKey: Keys.userID)
        UserDefaults.standard.removeObject(forKey: Keys.userName)
    }

    /// Disconnect from the server entirely, clearing all saved state.
    /// After this call `serverURL` is nil, which causes ContentView
    /// to present the server-connect screen.
    func disconnect() async {
        await signOut()
        self.client = nil
        self.serverURL = nil
        UserDefaults.standard.removeObject(forKey: Keys.serverURL)
    }

    // MARK: - Library Queries

    /// Continue Watching — partially watched items
    func getResumeItems() async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetResumeItemsParameters(
            userID: currentUserID,
            limit: 20,
            fields: [.overview, .mediaSources, .mediaStreams],
            mediaTypes: [.video],
            enableUserData: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop, .thumb]
        )
        let result = try await client.send(Paths.getResumeItems(parameters: params)).value
        return result.items ?? []
    }

    /// Next Up — next unwatched episode for in-progress series
    func getNextUp() async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetNextUpParameters(
            userID: currentUserID,
            limit: 20,
            fields: [.overview, .mediaSources, .mediaStreams],
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop, .thumb],
            enableUserData: true
        )
        let result = try await client.send(Paths.getNextUp(parameters: params)).value
        return result.items ?? []
    }

    /// Next Up for a specific series — cross-season next episode
    func getNextUp(seriesID: String) async throws -> BaseItemDto? {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetNextUpParameters(
            userID: currentUserID,
            limit: 1,
            fields: [.overview, .mediaSources, .mediaStreams],
            seriesID: seriesID,
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop, .thumb],
            enableUserData: true,
            enableRewatching: false
        )
        let result = try await client.send(Paths.getNextUp(parameters: params)).value
        return result.items?.first
    }

    /// Recently Added — newest content
    func getLatestMedia() async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetLatestMediaParameters(
            userID: currentUserID,
            fields: [.overview],
            includeItemTypes: [.movie, .series],
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop],
            enableUserData: true,
            limit: 20
        )
        return try await client.send(Paths.getLatestMedia(parameters: params)).value
    }

    /// Get genre list
    func getGenres() async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetGenresParameters(
            includeItemTypes: [.movie, .series],
            userID: currentUserID
        )
        let result = try await client.send(Paths.getGenres(parameters: params)).value
        return result.items ?? []
    }

    /// Items for a specific genre
    func getItemsByGenre(genreID: String) async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetItemsParameters(
            userID: currentUserID,
            limit: 20,
            isRecursive: true,
            fields: [.overview],
            includeItemTypes: [.movie, .series],
            sortBy: [.random],
            enableUserData: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop],
            genreIDs: [genreID],
            enableImages: true
        )
        let result = try await client.send(Paths.getItems(parameters: params)).value
        return result.items ?? []
    }

    /// Single item detail
    func getItem(id: String) async throws -> BaseItemDto {
        guard let client else { throw FinnError.notConnected }
        return try await client.send(
            Paths.getItem(itemID: id, userID: currentUserID)
        ).value
    }

    /// Seasons for a series
    func getSeasons(seriesID: String) async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetSeasonsParameters(
            userID: currentUserID,
            fields: [.overview],
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary],
            enableUserData: true
        )
        let result = try await client.send(
            Paths.getSeasons(seriesID: seriesID, parameters: params)
        ).value
        return result.items ?? []
    }

    /// Episodes for a season
    func getEpisodes(seriesID: String, seasonID: String) async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetEpisodesParameters(
            userID: currentUserID,
            fields: [.overview, .mediaSources, .mediaStreams],
            seasonID: seasonID,
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .backdrop, .thumb],
            enableUserData: true
        )
        let result = try await client.send(
            Paths.getEpisodes(seriesID: seriesID, parameters: params)
        ).value
        return result.items ?? []
    }

    /// Search
    func search(query: String) async throws -> [BaseItemDto] {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetItemsParameters(
            userID: currentUserID,
            limit: 30,
            isRecursive: true,
            searchTerm: query,
            fields: [.overview],
            includeItemTypes: [.movie, .series],
            enableUserData: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary],
            enableImages: true
        )
        let result = try await client.send(Paths.getItems(parameters: params)).value
        return result.items ?? []
    }

    // MARK: - Favorites

    func markFavorite(itemID: String) async throws {
        guard let client else { throw FinnError.notConnected }
        let _ = try await client.send(
            Paths.markFavoriteItem(itemID: itemID, userID: currentUserID)
        ).value
    }

    func unmarkFavorite(itemID: String) async throws {
        guard let client else { throw FinnError.notConnected }
        let _ = try await client.send(
            Paths.unmarkFavoriteItem(itemID: itemID, userID: currentUserID)
        ).value
    }

    // MARK: - Played Status

    /// Mark an item as fully played/watched
    func markPlayed(itemID: String) async throws {
        guard let client else { throw FinnError.notConnected }
        let _ = try await client.send(
            Paths.markPlayedItem(itemID: itemID, userID: currentUserID)
        ).value
    }

    /// Mark an item as unplayed/unwatched
    func markUnplayed(itemID: String) async throws {
        guard let client else { throw FinnError.notConnected }
        let _ = try await client.send(
            Paths.markUnplayedItem(itemID: itemID, userID: currentUserID)
        ).value
    }

    // MARK: - Playback Info

    func getPlaybackInfo(
        itemID: String,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async throws -> PlaybackInfoResponse {
        guard let client else { throw FinnError.notConnected }

        // Build a device profile so the server knows what Apple TV / AVPlayer can handle.
        // Without this, the server can't determine direct play compatibility or produce
        // a correct transcoding URL.
        let deviceProfile = DeviceProfile(
            directPlayProfiles: [
                // Containers and codecs AVPlayer supports natively
                DirectPlayProfile(
                    audioCodec: "aac,ac3,eac3,flac,alac",
                    container: "mp4,m4v,mov",
                    type: .video,
                    videoCodec: "h264,hevc,mpeg4"
                ),
                DirectPlayProfile(
                    audioCodec: "aac,ac3,eac3,flac,alac,mp3",
                    container: "mp4,m4v,mov",
                    type: .audio
                ),
            ],
            maxStreamingBitrate: 120_000_000,
            subtitleProfiles: [
                // Text-based formats: embed in HLS manifest as WebVTT
                // The server converts SRT/VTT to WebVTT segments in the m3u8
                SubtitleProfile(format: "vtt", method: .embed),
                SubtitleProfile(format: "srt", method: .embed),
                SubtitleProfile(format: "subrip", method: .embed),
                // Image/styled formats: burn into video via server transcode
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode),
                SubtitleProfile(format: "sub", method: .encode),
                SubtitleProfile(format: "pgs", method: .encode),
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    audioCodec: "aac,ac3,eac3",
                    isBreakOnNonKeyFrames: true,
                    container: "mp4",
                    context: .streaming,
                    protocol: .hls,
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                TranscodingProfile(
                    audioCodec: "aac",
                    container: "mp4",
                    context: .streaming,
                    protocol: .http,
                    type: .audio
                ),
            ]
        )

        let body = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: true,
            audioStreamIndex: audioStreamIndex,
            isAutoOpenLiveStream: true,
            deviceProfile: deviceProfile,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            maxStreamingBitrate: 120_000_000,
            subtitleStreamIndex: subtitleStreamIndex,
            userID: currentUserID
        )

        return try await client.send(
            Paths.getPostedPlaybackInfo(itemID: itemID, body)
        ).value
    }

    // MARK: - Progress Reporting

    func reportPlaybackStart(info: PlaybackStartInfo) async throws {
        guard let client else { throw FinnError.notConnected }
        try await client.send(Paths.reportPlaybackStart(info))
    }

    func reportPlaybackProgress(info: PlaybackProgressInfo) async throws {
        guard let client else { throw FinnError.notConnected }
        try await client.send(Paths.reportPlaybackProgress(info))
    }

    func reportPlaybackStopped(info: PlaybackStopInfo) async throws {
        guard let client else { throw FinnError.notConnected }
        try await client.send(Paths.reportPlaybackStopped(info))
    }

    // MARK: - Audio Preference

    var preferredAudioLanguage: String? {
        get { UserDefaults.standard.string(forKey: Keys.preferredAudioLanguage) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.preferredAudioLanguage) }
    }

    // MARK: - Subtitle Preference

    var preferredSubtitleLanguage: String? {
        get { UserDefaults.standard.string(forKey: Keys.preferredSubtitleLanguage) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.preferredSubtitleLanguage) }
    }

    // MARK: - Private

    private func restoreSession() {
        guard
            let urlString = UserDefaults.standard.string(forKey: Keys.serverURL),
            let url = URL(string: urlString),
            let token = KeychainHelper.load(key: Keys.accessToken),
            let userID = UserDefaults.standard.string(forKey: Keys.userID)
        else { return }

        let config = JellyfinClient.Configuration(
            url: url,
            accessToken: token,
            client: Self.clientName,
            deviceName: Self.deviceName,
            deviceID: deviceID(),
            version: Self.clientVersion
        )
        self.client = JellyfinClient(configuration: config)
        self.serverURL = url
        self.currentUserID = userID
        self.isAuthenticated = true
        self.currentUserName = UserDefaults.standard.string(forKey: Keys.userName)
    }

    /// Validates the restored session by fetching the current user.
    /// If the token is expired or revoked, signs out so the user sees
    /// the login screen instead of empty/broken content.
    func validateSession() async {
        guard isAuthenticated, client != nil else { return }
        do {
            let _ = try await client?.send(Paths.getCurrentUser).value
        } catch {
            await signOut()
        }
    }

    private func deviceID() -> String {
        let key = "finn.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}

// MARK: - Errors

enum FinnError: LocalizedError {
    case notConnected
    case noUserID
    case noAccessToken
    case noMediaSource
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to server"
        case .noUserID: "No user ID in authentication response"
        case .noAccessToken: "No access token in authentication response"
        case .noMediaSource: "No compatible media source found"
        case .playbackFailed(let reason): "Playback failed: \(reason)"
        }
    }
}
