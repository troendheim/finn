import Foundation
import JellyfinAPI
import Combine

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var results: [BaseItemDto] = []
    var isSearching = false
    var hasSearched = false

    private let jellyfinService: JellyfinService
    private var searchTask: Task<Void, Never>?

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    func onQueryChanged() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            hasSearched = false
            return
        }

        searchTask = Task {
            // 300ms debounce
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true
            do {
                results = try await jellyfinService.search(query: trimmed)
            } catch {
                if !Task.isCancelled {
                    results = []
                }
            }
            guard !Task.isCancelled else { return }
            hasSearched = true
            isSearching = false
        }
    }
}
