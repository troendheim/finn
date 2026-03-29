import Foundation
import JellyfinAPI
import Get

@MainActor
@Observable
final class JellyfinService {
    // MARK: - State

    private(set) var client: JellyfinClient?
    private(set) var serverURL: URL?
    private(set) var currentUserID: String?
    private(set) var isAuthenticated = false

    var imageService: ImageService? {
        guard let serverURL else { return nil }
        return ImageService(serverURL: serverURL)
    }

    // MARK: - Persistence Keys

    private enum Keys {
        static let serverURL = "finn.serverURL"
        static let userID = "finn.userID"
        static let accessToken = "finn.accessToken"
        static let preferredAudioLanguage = "finn.preferredAudioLanguage"
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
            client: "Finn",
            deviceName: "Apple TV",
            deviceID: deviceID(),
            version: "1.0.0"
        )
        let newClient = JellyfinClient(configuration: config)

        // Validate by fetching public users
        let _ = try await newClient.send(Paths.getPublicUsers).value

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

        // Persist
        UserDefaults.standard.set(userID, forKey: Keys.userID)
        KeychainHelper.save(key: Keys.accessToken, value: token)
    }

    /// Sign out and clear saved credentials
    func signOut() async {
        try? await client?.signOut()
        self.currentUserID = nil
        self.isAuthenticated = false
        KeychainHelper.delete(key: Keys.accessToken)
        UserDefaults.standard.removeObject(forKey: Keys.userID)
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

    // MARK: - Playback Info

    func getPlaybackInfo(itemID: String) async throws -> PlaybackInfoResponse {
        guard let client else { throw FinnError.notConnected }
        let params = Paths.GetPostedPlaybackInfoParameters(
            userID: currentUserID,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true
        )
        return try await client.send(
            Paths.getPostedPlaybackInfo(itemID: itemID, parameters: params)
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
            client: "Finn",
            deviceName: "Apple TV",
            deviceID: deviceID(),
            version: "1.0.0"
        )
        self.client = JellyfinClient(configuration: config)
        self.serverURL = url
        self.currentUserID = userID
        self.isAuthenticated = true
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
