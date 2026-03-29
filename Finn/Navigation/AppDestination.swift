import Foundation

enum AppDestination: Hashable {
    case movieDetail(itemID: String)
    case seriesDetail(itemID: String)
    case player(itemID: String)
    case search
}
