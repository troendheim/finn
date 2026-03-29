import SwiftUI
import JellyfinAPI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Header with search button
                HStack {
                    Text("Finn")
                        .font(.system(size: 48, weight: .bold))

                    Spacer()

                    Button {
                        navigationPath.append(AppDestination.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)

                if viewModel.isLoading && viewModel.continueWatching.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else {
                    // Continue Watching
                    ContentRow(
                        title: "Continue Watching",
                        items: viewModel.continueWatching,
                        onSelect: { navigateToDetail($0) }
                    ) { item in
                        LandscapeCard(item: item, imageService: imageService)
                    }

                    // Next Up
                    ContentRow(
                        title: "Next Up",
                        items: viewModel.nextUp,
                        onSelect: { navigateToDetail($0) }
                    ) { item in
                        LandscapeCard(item: item, imageService: imageService)
                    }

                    // Recently Added
                    ContentRow(
                        title: "Recently Added",
                        items: viewModel.latestMedia,
                        onSelect: { navigateToDetail($0) }
                    ) { item in
                        PosterCard(item: item, imageService: imageService)
                    }

                    // Genre rows
                    ForEach(viewModel.genreRows, id: \.genre.id) { row in
                        ContentRow(
                            title: row.genre.name ?? "Genre",
                            items: row.items,
                            onSelect: { navigateToDetail($0) }
                        ) { item in
                            PosterCard(item: item, imageService: imageService)
                        }
                    }
                }

                if let error = viewModel.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.bottom, 40)
        }
        .task {
            await viewModel.loadAll()
        }
        .refreshable {
            await viewModel.refresh()
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
            // For episodes in Continue Watching / Next Up, navigate to the series
            if let seriesID = item.seriesID {
                navigationPath.append(AppDestination.seriesDetail(itemID: seriesID))
            }
        default:
            break
        }
    }
}
