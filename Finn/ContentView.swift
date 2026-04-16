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
                        MovieDetailDestination(
                            itemID: itemID,
                            jellyfinService: jellyfinService,
                            navigationPath: $navigationPath
                        )
                    case .seriesDetail(let itemID):
                        SeriesDetailDestination(
                            itemID: itemID,
                            jellyfinService: jellyfinService,
                            navigationPath: $navigationPath
                        )
                    case .player(let itemID):
                        PlayerDestination(
                            itemID: itemID,
                            jellyfinService: jellyfinService
                        )
                    case .search:
                        SearchDestination(
                            jellyfinService: jellyfinService,
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
                viewModel: homeViewModel ?? makeHomeViewModel(),
                imageService: jellyfinService.imageService,
                navigationPath: $navigationPath
            )
            .onAppear { ensureHomeViewModel() }
        } else if jellyfinService.serverURL != nil {
            LoginView(
                viewModel: loginViewModel ?? makeLoginViewModel(),
                imageService: jellyfinService.imageService
            )
            .onAppear { ensureLoginViewModel() }
        } else {
            ServerConnectView(
                viewModel: serverConnectViewModel ?? makeServerConnectViewModel()
            )
            .onAppear { ensureServerConnectViewModel() }
        }
    }

    // Create models without mutating @State during body; onAppear caches them.
    private func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(jellyfinService: jellyfinService)
    }
    private func ensureHomeViewModel() {
        if homeViewModel == nil { homeViewModel = HomeViewModel(jellyfinService: jellyfinService) }
    }
    private func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(jellyfinService: jellyfinService)
    }
    private func ensureLoginViewModel() {
        if loginViewModel == nil { loginViewModel = LoginViewModel(jellyfinService: jellyfinService) }
    }
    private func makeServerConnectViewModel() -> ServerConnectViewModel {
        ServerConnectViewModel(jellyfinService: jellyfinService)
    }
    private func ensureServerConnectViewModel() {
        if serverConnectViewModel == nil { serverConnectViewModel = ServerConnectViewModel(jellyfinService: jellyfinService) }
    }
}

// MARK: - Destination Wrappers
// Each wraps the real view and owns its ViewModel via @State so it
// survives navigationDestination closure re-evaluations.

struct MovieDetailDestination: View {
    let itemID: String
    let jellyfinService: JellyfinService
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: MovieDetailViewModel?

    var body: some View {
        if let viewModel {
            MovieDetailView(viewModel: viewModel, imageService: jellyfinService.imageService, navigationPath: $navigationPath)
        } else {
            ProgressView().onAppear {
                viewModel = MovieDetailViewModel(itemID: itemID, jellyfinService: jellyfinService)
            }
        }
    }
}

struct SeriesDetailDestination: View {
    let itemID: String
    let jellyfinService: JellyfinService
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: SeriesDetailViewModel?

    var body: some View {
        if let viewModel {
            SeriesDetailView(viewModel: viewModel, imageService: jellyfinService.imageService, navigationPath: $navigationPath)
        } else {
            ProgressView().onAppear {
                viewModel = SeriesDetailViewModel(itemID: itemID, jellyfinService: jellyfinService)
            }
        }
    }
}

struct PlayerDestination: View {
    let itemID: String
    let jellyfinService: JellyfinService
    @State private var viewModel: PlayerViewModel?

    var body: some View {
        if let viewModel {
            PlayerView(viewModel: viewModel)
        } else {
            ProgressView().onAppear {
                viewModel = PlayerViewModel(itemID: itemID, jellyfinService: jellyfinService)
            }
        }
    }
}

struct SearchDestination: View {
    let jellyfinService: JellyfinService
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: SearchViewModel?

    var body: some View {
        if let viewModel {
            SearchView(viewModel: viewModel, imageService: jellyfinService.imageService, navigationPath: $navigationPath)
        } else {
            ProgressView().onAppear {
                viewModel = SearchViewModel(jellyfinService: jellyfinService)
            }
        }
    }
}
