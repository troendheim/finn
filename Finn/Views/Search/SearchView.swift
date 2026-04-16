import SwiftUI
import JellyfinAPI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 240), spacing: 40)
    ]

    var body: some View {
        searchResults
            .searchable(text: $viewModel.query, prompt: "Movies and series")
            .autocorrectionDisabled()
            .onChange(of: viewModel.query) {
                viewModel.onQueryChanged()
            }
    }

    // MARK: - Results

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.results.isEmpty && viewModel.hasSearched {
            ContentUnavailableView(
                "No results found",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term")
            )
        } else if viewModel.results.isEmpty {
            ContentUnavailableView(
                "Search your library",
                systemImage: "tv",
                description: Text("Find movies and series")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(viewModel.results.filter { $0.id != nil }, id: \.id) { item in
                        Button {
                            navigateToDetail(item)
                        } label: {
                            PosterCard(item: item, imageService: imageService)
                        }
                        .tvCardButton()
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
        }
    }

    private func navigateToDetail(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        switch item.type {
        case .movie:
            navigationPath.append(AppDestination.movieDetail(itemID: id))
        case .series:
            navigationPath.append(AppDestination.seriesDetail(itemID: id))
        case .episode:
            navigationPath.append(AppDestination.player(itemID: id))
        default:
            break
        }
    }
}
