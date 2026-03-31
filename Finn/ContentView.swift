import SwiftUI

struct ContentView: View {
    @State private var jellyfinService = JellyfinService()
    @State private var navigationPath = NavigationPath()
    @State private var homeViewModel: HomeViewModel?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            rootView
                .task { await jellyfinService.validateSession() }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .movieDetail(let itemID):
                        MovieDetailView(
                            viewModel: MovieDetailViewModel(
                                itemID: itemID,
                                jellyfinService: jellyfinService
                            ),
                            imageService: jellyfinService.imageService,
                            navigationPath: $navigationPath
                        )
                    case .seriesDetail(let itemID):
                        SeriesDetailView(
                            viewModel: SeriesDetailViewModel(
                                itemID: itemID,
                                jellyfinService: jellyfinService
                            ),
                            imageService: jellyfinService.imageService,
                            navigationPath: $navigationPath
                        )
                    case .player(let itemID):
                        PlayerView(
                            viewModel: PlayerViewModel(
                                itemID: itemID,
                                jellyfinService: jellyfinService
                            )
                        )
                    case .search:
                        SearchView(
                            viewModel: SearchViewModel(
                                jellyfinService: jellyfinService
                            ),
                            imageService: jellyfinService.imageService,
                            navigationPath: $navigationPath
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if jellyfinService.isAuthenticated {
            HomeView(
                viewModel: {
                    if homeViewModel == nil {
                        homeViewModel = HomeViewModel(jellyfinService: jellyfinService)
                    }
                    return homeViewModel!
                }(),
                imageService: jellyfinService.imageService,
                navigationPath: $navigationPath
            )
        } else if jellyfinService.serverURL != nil {
            LoginView(
                viewModel: LoginViewModel(jellyfinService: jellyfinService),
                imageService: jellyfinService.imageService
            )
        } else {
            ServerConnectView(
                viewModel: ServerConnectViewModel(jellyfinService: jellyfinService)
            )
        }
    }
}
