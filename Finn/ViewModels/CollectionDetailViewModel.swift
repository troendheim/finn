import Foundation
import JellyfinAPI

@MainActor
@Observable
final class CollectionDetailViewModel {
    var item: BaseItemDto?
    var items: [BaseItemDto] = []
    var displayItems: [BaseItemDto] = []
    var isLoading = false
    var error: String?

    let itemID: String
    private let jellyfinService: JellyfinService

    init(itemID: String, jellyfinService: JellyfinService) {
        self.itemID = itemID
        self.jellyfinService = jellyfinService
    }

    func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            async let itemTask = jellyfinService.getItem(id: itemID)
            async let childrenTask = jellyfinService.getLibraryItems(
                parentID: itemID,
                sortBy: [.sortName],
                sortOrder: [.ascending],
                limit: 500,
                isRecursive: false
            )

            let (loaded, children) = try await (itemTask, childrenTask)
            item = loaded
            items = children
            displayItems = children.filter { $0.id != nil }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
