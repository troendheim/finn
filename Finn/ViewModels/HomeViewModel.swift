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
    var error: String?

    private let jellyfinService: JellyfinService

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    // MARK: - Loading

    func loadAll() async {
        isLoading = true
        error = nil

        // Load main rows concurrently
        async let resumeTask = jellyfinService.getResumeItems()
        async let nextUpTask = jellyfinService.getNextUp()
        async let latestTask = jellyfinService.getLatestMedia()

        do {
            let (resume, next, latest) = try await (resumeTask, nextUpTask, latestTask)
            continueWatching = resume
            nextUp = next
            latestMedia = latest
        } catch {
            self.error = "Failed to load library"
        }

        // Load genre rows (after main rows to avoid delaying them)
        await loadGenreRows()

        isLoading = false
    }

    func refresh() async {
        await loadAll()
    }

    // MARK: - Private

    private func loadGenreRows() async {
        do {
            let genres = try await jellyfinService.getGenres()
            // Take up to 5 genres for the home screen
            let selected = Array(genres.prefix(5))

            var rows: [(genre: BaseItemDto, items: [BaseItemDto])] = []
            for genre in selected {
                guard let genreID = genre.id else { continue }
                do {
                    let items = try await jellyfinService.getItemsByGenre(genreID: genreID)
                    if !items.isEmpty {
                        rows.append((genre: genre, items: items))
                    }
                } catch {
                    // Skip failed genre rows silently
                }
            }
            genreRows = rows
        } catch {
            // Genre rows are non-critical, don't set top-level error
        }
    }
}
