import SwiftUI

struct ContentView: View {
    @State private var jellyfinService = JellyfinService()
    @State private var navigationPath = NavigationPath()
    @State private var homeViewModel: HomeViewModel?
    @State private var loginViewModel: LoginViewModel?
    @State private var serverConnectViewModel: ServerConnectViewModel?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            rootView
                .task { await jellyfinService.validateSession() }
                .onChange(of: jellyfinService.isAuthenticated) { _, isAuthenticated in
                    if !isAuthenticated {
                        homeViewModel = nil
                    }
                }
                .onChange(of: jellyfinService.serverURL) { _, serverURL in
                    if serverURL == nil {
                        loginViewModel = nil
                        homeViewModel = nil
                    }
                }
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
                viewModel: cachedModel(&homeViewModel) {
                    HomeViewModel(jellyfinService: jellyfinService)
                },
                imageService: jellyfinService.imageService,
                navigationPath: $navigationPath
            )
        } else if jellyfinService.serverURL != nil {
            LoginView(
                viewModel: cachedModel(&loginViewModel) {
                    LoginViewModel(jellyfinService: jellyfinService)
                },
                imageService: jellyfinService.imageService
            )
        } else {
            ServerConnectView(
                viewModel: cachedModel(&serverConnectViewModel) {
                    ServerConnectViewModel(jellyfinService: jellyfinService)
                }
            )
        }
    }

    /// Return an existing cached model or create and cache a new one.
    private func cachedModel<T>(_ storage: inout T?, create: () -> T) -> T {
        if let existing = storage { return existing }
        let model = create()
        storage = model
        return model
    }
}
