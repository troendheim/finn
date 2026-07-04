import SwiftUI
import JellyfinAPI

enum HomeTab: String, CaseIterable, Hashable {
    case home
    case series
    case movies

    var label: String {
        switch self {
        case .home: "Home"
        case .series: "Series"
        case .movies: "Movies"
        }
    }
}

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath
    @State private var showSettings = false
    @State private var hasAppeared = false
    @State private var selectedTab: HomeTab = .home
    @State private var seriesLibraryViewModel: LibraryViewModel?
    @State private var moviesLibraryViewModel: LibraryViewModel?
    @Namespace private var contentNamespace

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                // Header with tabs and search/settings buttons
                HStack(spacing: 24) {
                    Text("Finn")
                        .font(.title)
                        .fontWeight(.bold)

                    Picker("Section", selection: $selectedTab) {
                        ForEach(HomeTab.allCases, id: \.self) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    Spacer()

                    HStack(spacing: 16) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title2)
                        }
                        .glassButtonStyle()
                        .accessibilityLabel("Settings")

                        Button {
                            navigationPath.append(AppDestination.search)
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                        }
                        .glassButtonStyle()
                        .accessibilityLabel("Search")
                    }
                    .liquidGlassContainer(spacing: 16)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .focusSection()

                switch selectedTab {
                case .home:
                    homeContent
                case .series:
                    if let vm = seriesLibraryViewModel {
                        LibraryGridView(
                            viewModel: vm,
                            imageService: imageService,
                            navigationPath: $navigationPath
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    }
                case .movies:
                    if let vm = moviesLibraryViewModel {
                        LibraryGridView(
                            viewModel: vm,
                            imageService: imageService,
                            navigationPath: $navigationPath
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    }
                }

                if selectedTab == .home, let error = viewModel.error {
                    VStack(spacing: 12) {
                        Text(error)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await viewModel.loadAll() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .padding(.bottom, 40)
        }
        .task {
            await viewModel.loadAll()
            hasAppeared = true
        }
        .onAppear {
            // Refresh data when returning from navigation (player, detail views)
            if hasAppeared {
                Task { await viewModel.refresh() }
            }
        }
        .refreshable {
            await viewModel.forceRefresh()
        }
        .focusScope(contentNamespace)
        .task(id: selectedTab) {
            // Create the library view model for the selected tab outside of
            // body evaluation so we never mutate @State during a view update.
            switch selectedTab {
            case .series where seriesLibraryViewModel == nil:
                seriesLibraryViewModel = LibraryViewModel(
                    jellyfinService: viewModel.jellyfinService,
                    includeItemTypes: [.series]
                )
            case .movies where moviesLibraryViewModel == nil:
                moviesLibraryViewModel = LibraryViewModel(
                    jellyfinService: viewModel.jellyfinService,
                    includeItemTypes: [.movie]
                )
            default:
                break
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsOverlay
        }
    }

    // MARK: - Home Tab Content

    @ViewBuilder
    private var homeContent: some View {
        if !viewModel.hasLoaded && viewModel.continueWatching.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
        } else {
            // Continue Watching
            ContentRow(
                title: "Continue Watching",
                items: viewModel.continueWatching,
                onSelect: { navigateToDetail($0, navigationPath: $navigationPath) }
            ) { item in
                LandscapeCard(item: item, imageService: imageService)
            }
            .prefersDefaultFocus(in: contentNamespace)

            // Next Up
            ContentRow(
                title: "Next Up",
                items: viewModel.nextUp,
                onSelect: { navigateToDetail($0, navigationPath: $navigationPath) }
            ) { item in
                LandscapeCard(item: item, imageService: imageService)
            }

            // Recently Added
            ContentRow(
                title: "Recently Added",
                items: viewModel.latestMedia,
                onSelect: { navigateToDetail($0, navigationPath: $navigationPath) }
            ) { item in
                PosterCard(item: item, imageService: imageService)
            }

            // Genre rows
            ForEach(viewModel.genreRows, id: \.genre.id) { row in
                ContentRow(
                    title: row.genre.name ?? "Genre",
                    items: row.items,
                    onSelect: { navigateToDetail($0, navigationPath: $navigationPath) }
                ) { item in
                    PosterCard(item: item, imageService: imageService)
                }
            }

            // Empty state
            if viewModel.isLibraryEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tv")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Your library is empty")
                        .font(.title3)
                    Text("Add some media to your Jellyfin server to get started")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            }
        }
    }

    // MARK: - Settings Overlay

    private var settingsOverlay: some View {
        VStack(spacing: 24) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.serverURLDisplay)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("User")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.currentUserDisplay)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(role: .destructive) {
                showSettings = false
                Task { await viewModel.signOut() }
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()

            Button(role: .destructive) {
                showSettings = false
                Task { await viewModel.disconnect() }
            } label: {
                Text("Switch Server")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()

            Button("Cancel", role: .cancel) {
                showSettings = false
            }
            .glassButtonStyle()
        }
        .padding(40)
    }
}
