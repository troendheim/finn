import Foundation
import JellyfinAPI
import SwiftUI

enum AppDestination: Hashable {
    case movieDetail(itemID: String)
    case seriesDetail(itemID: String)
    case collection(itemID: String)
    case player(itemID: String)
    case search
}

/// Shared detail navigation used by Home, Library, and Search views.
/// Routes an item to its appropriate destination based on its type.
@MainActor
func navigateToDetail(_ item: BaseItemDto, navigationPath: Binding<NavigationPath>) {
    guard let id = item.id else { return }
    switch item.type {
    case .movie:
        navigationPath.wrappedValue.append(AppDestination.movieDetail(itemID: id))
    case .series:
        navigationPath.wrappedValue.append(AppDestination.seriesDetail(itemID: id))
    case .boxSet:
        navigationPath.wrappedValue.append(AppDestination.collection(itemID: id))
    case .episode:
        // Episodes in Continue Watching / Next Up go straight to the player
        navigationPath.wrappedValue.append(AppDestination.player(itemID: id))
    default:
        break
    }
}
