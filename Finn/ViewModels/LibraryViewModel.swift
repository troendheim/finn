import Foundation
import JellyfinAPI

/// View model backing the Series and Movies overview tabs. Parameterised by
/// the Jellyfin item type(s) it should fetch and the desired sort order so it
/// can be reused for future filter/sort extensions.
@MainActor
@Observable
final class LibraryViewModel {
    // MARK: - State

    var items: [BaseItemDto] = [] {
        didSet { displayItems = items.filter { $0.id != nil } }
    }

    /// Items guaranteed to have an `id`, suitable for `ForEach(id: \.id)`.
    /// Pre-filtered once on assignment so the grid body doesn't allocate a
    /// filtered copy on every view update.
    private(set) var displayItems: [BaseItemDto] = []

    var isLoading = false
    private(set) var hasLoaded = false
    var error: String?

    let jellyfinService: JellyfinService

    /// True once the first load has completed and the result set is empty.
    /// Lets the view render a proper empty state instead of a spinner.
    var isEmpty: Bool {
        hasLoaded && !isLoading && items.isEmpty
    }

    private let includeItemTypes: [BaseItemKind]
    private let sortBy: [ItemSortBy]
    private let sortOrder: [JellyfinAPI.SortOrder]

    init(
        jellyfinService: JellyfinService,
        includeItemTypes: [BaseItemKind],
        sortBy: [ItemSortBy] = [.dateCreated],
        sortOrder: [JellyfinAPI.SortOrder] = [.descending]
    ) {
        self.jellyfinService = jellyfinService
        self.includeItemTypes = includeItemTypes
        self.sortBy = sortBy
        self.sortOrder = sortOrder
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            items = try await jellyfinService.getLibraryItems(
                includeItemTypes: includeItemTypes,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-fetch the listing, ignoring any in-flight load.
    func refresh() async {
        hasLoaded = false
        isLoading = false
        await load()
    }
}