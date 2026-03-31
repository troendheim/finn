import Foundation
import JellyfinAPI

@MainActor
@Observable
final class HomeViewModel {
    // MARK: - State

    var continueWatching: [BaseItemDto] = []
    var nextUp: [BaseItemDto] = []
    var latestMedia: [BaseItemDto] = []
    var genreRows: [(genre: BaseItemDto, items: [BaseItemDto])] = []
    var isLoading = false
    var isLoadingGenres = false
    private(set) var hasLoaded = false
    var error: String?

    let jellyfinService: JellyfinService

    /// Timestamp of the last successful full load. Used by `refresh()` to avoid
    /// re-fetching all sections when data is still fresh.
    private var lastLoadTime: Date?

    /// Minimum interval (seconds) between automatic refreshes triggered by
    /// navigation back. Pull-to-refresh always forces a full reload.
    private let refreshInterval: TimeInterval = 30

    /// Display-friendly server URL for the settings overlay.
    var serverURLDisplay: String {
        jellyfinService.serverURL?.absoluteString ?? "Unknown"
    }

    /// Display-friendly current user identifier.
    var currentUserDisplay: String {
        jellyfinService.currentUserName ?? jellyfinService.currentUserID ?? "Unknown"
    }

    /// Whether every content section is empty (and we're not still loading).
    /// Only evaluates to `true` after the first load has completed so the
    /// empty-library message never flashes before data has been fetched.
    var isLibraryEmpty: Bool {
        hasLoaded
            && !isLoading
            && !isLoadingGenres
            && continueWatching.isEmpty
            && nextUp.isEmpty
            && latestMedia.isEmpty
            && genreRows.isEmpty
    }

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    // MARK: - Account Actions

    func signOut() async {
        await jellyfinService.signOut()
    }

    func disconnect() async {
        await jellyfinService.disconnect()
    }

    // MARK: - Loading

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        // Load main rows concurrently with individual error handling
        async let resumeResult: [BaseItemDto] = loadSection { try await jellyfinService.getResumeItems() }
        async let nextUpResult: [BaseItemDto] = loadSection { try await jellyfinService.getNextUp() }
        async let latestResult: [BaseItemDto] = loadSection { try await jellyfinService.getLatestMedia() }

        let results = await (resumeResult, nextUpResult, latestResult)
        continueWatching = results.0
        nextUp = results.1
        latestMedia = results.2

        // Main content is ready — stop showing the spinner
        isLoading = false

        // Load genre rows in the background (they'll appear as they arrive)
        isLoadingGenres = true
        await loadGenreRows()
        isLoadingGenres = false
        hasLoaded = true
        lastLoadTime = Date()
    }

    /// Refresh data when returning from navigation. Only re-fetches the
    /// time-sensitive rows (Continue Watching, Next Up) if data was loaded
    /// recently. Forces a full reload when data is stale.
    func refresh() async {
        if let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < refreshInterval {
            // Data is fresh — only refresh playback-sensitive rows
            await refreshPlaybackRows()
        } else {
            await loadAll()
        }
    }

    /// Force a full reload (used by pull-to-refresh).
    func forceRefresh() async {
        lastLoadTime = nil
        await loadAll()
    }

    /// Lightweight refresh that only re-fetches rows affected by playback
    /// (Continue Watching and Next Up). Genre rows and Recently Added are
    /// left untouched since they rarely change mid-session.
    private func refreshPlaybackRows() async {
        async let resumeResult: [BaseItemDto] = loadSection { try await jellyfinService.getResumeItems() }
        async let nextUpResult: [BaseItemDto] = loadSection { try await jellyfinService.getNextUp() }

        let results = await (resumeResult, nextUpResult)
        continueWatching = results.0
        nextUp = results.1
    }

    // MARK: - Private

    /// Load a section, returning empty array on failure instead of throwing.
    private func loadSection(_ fetch: () async throws -> [BaseItemDto]) async -> [BaseItemDto] {
        do {
            return try await fetch()
        } catch {
            return []
        }
    }

    private func loadGenreRows() async {
        do {
            let genres = try await jellyfinService.getGenres()
            // Take up to 5 genres for the home screen
            let selected = Array(genres.prefix(5))

            // Fetch all genre rows concurrently instead of sequentially
            let rows: [(genre: BaseItemDto, items: [BaseItemDto])] = await withTaskGroup(
                of: (Int, BaseItemDto, [BaseItemDto])?.self
            ) { group in
                for (index, genre) in selected.enumerated() {
                    guard let genreID = genre.id else { continue }
                    group.addTask { [jellyfinService] in
                        do {
                            let items = try await jellyfinService.getItemsByGenre(genreID: genreID)
                            return items.isEmpty ? nil : (index, genre, items)
                        } catch {
                            return nil
                        }
                    }
                }

                var results: [(index: Int, genre: BaseItemDto, items: [BaseItemDto])] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                // Sort by original index to preserve stable genre ordering
                return results.sorted(by: { $0.index < $1.index })
                    .map { (genre: $0.genre, items: $0.items) }
            }

            genreRows = rows
        } catch {
            // Genre rows are non-critical, don't set top-level error
        }
    }
}
