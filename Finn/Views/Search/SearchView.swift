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
        VStack(spacing: 0) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search movies and series...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.query) {
                        viewModel.onQueryChanged()
                    }
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                        viewModel.results = []
                        viewModel.hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .liquidGlass(in: 12, isInteractive: true)
            .padding(.horizontal, 60)
            .padding(.top, 30)
            .focusSection()

            // Results
            if viewModel.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.results.isEmpty && viewModel.hasSearched {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No results found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Try a different search term")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if viewModel.results.isEmpty && !viewModel.hasSearched {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "tv")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Search your library")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Find movies and series")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(viewModel.results, id: \.id) { item in
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
                .focusSection()
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
