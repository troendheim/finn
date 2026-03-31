import SwiftUI
import JellyfinAPI

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath
    @State private var showSettings = false
    @State private var hasAppeared = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Header with search and settings buttons
                HStack {
                    Text("Finn")
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        navigationPath.append(AppDestination.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                    }
                    .accessibilityLabel("Search")
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

                if let error = viewModel.error {
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
            await viewModel.refresh()
        }
        .sheet(isPresented: $showSettings) {
            settingsOverlay
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

            Button(role: .destructive) {
                showSettings = false
                Task { await viewModel.disconnect() }
            } label: {
                Text("Switch Server")
                    .frame(maxWidth: .infinity)
            }

            Button("Cancel", role: .cancel) {
                showSettings = false
            }
        }
        .padding(40)
    }

    private func navigateToDetail(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        switch item.type {
        case .movie:
            navigationPath.append(AppDestination.movieDetail(itemID: id))
        case .series:
            navigationPath.append(AppDestination.seriesDetail(itemID: id))
        case .episode:
            // Episodes in Continue Watching / Next Up go straight to the player
            navigationPath.append(AppDestination.player(itemID: id))
        default:
            break
        }
    }
}
