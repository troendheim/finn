import SwiftUI
import JellyfinAPI

struct SeriesDetailView: View {
    @Bindable var viewModel: SeriesDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath
    @State private var errorDismissTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 200)
            } else if let item = viewModel.item {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with backdrop
                    headerSection(item)

                    // Season picker + episode list alongside sidebar
                    HStack(alignment: .top, spacing: 48) {
                        // Left: seasons + episodes
                        VStack(alignment: .leading, spacing: 32) {
                            seasonPicker
                            episodeList
                        }
                        .frame(maxWidth: .infinity)

                        // Right sidebar
                        sidebar(item)
                            .frame(width: 380)
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 48)
                    .padding(.bottom, 60)
                }
            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await viewModel.loadDetail() }
                    }
                }
                .padding(.top, 200)
            }
        }
        .task {
            await viewModel.loadDetail()
        }
        .overlay(alignment: .top) {
            if let errorMessage = viewModel.actionError {
                Text(errorMessage)
                    .font(.callout)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        errorDismissTask?.cancel()
                        errorDismissTask = Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { viewModel.actionError = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: viewModel.actionError)
        .onDisappear {
            errorDismissTask?.cancel()
            errorDismissTask = nil
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ item: BaseItemDto) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            if let id = item.id, let url = imageService?.backdropURL(itemID: id) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .frame(height: 500)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.2),
                                    .init(color: .black.opacity(0.6), location: 0.55),
                                    .init(color: .black.opacity(0.9), location: 0.8),
                                    .init(color: .black, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } placeholder: {
                    Rectangle().fill(.black).frame(height: 500)
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                Text(item.name ?? "")
                    .font(.title)
                    .fontWeight(.bold)

                Text(viewModel.metadataLine)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let genres = item.genres, !genres.isEmpty {
                    Text(genres.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                HStack(spacing: 20) {
                    Button {
                        if let epID = viewModel.playItemID {
                            navigationPath.append(AppDestination.player(itemID: epID))
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text(viewModel.playButtonTitle)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                    }
                    .glassButtonStyle(prominent: true)
                    .disabled(viewModel.playItemID == nil)

                    Button {
                        Task { await viewModel.toggleFavorite() }
                    } label: {
                        Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                    .glassButtonStyle()
                    .accessibilityLabel(viewModel.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
                .liquidGlassContainer(spacing: 16)
                .padding(.top, 4)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.seasons, id: \.id) { season in
                    let isSelected = viewModel.selectedSeason?.id == season.id
                    Button {
                        Task { await viewModel.selectSeason(season) }
                    } label: {
                        Text(season.name ?? "Season")
                            .font(.callout)
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .tvCardButton()
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Episode List

    private var episodeList: some View {
        VStack(spacing: 16) {
            if viewModel.isLoadingEpisodes {
                ProgressView()
                    .padding(.top, 40)
            } else {
                ForEach(viewModel.episodes.filter { $0.id != nil }, id: \.id) { episode in
                    Button {
                        if let id = episode.id {
                            navigationPath.append(AppDestination.player(itemID: id))
                        }
                    } label: {
                        episodeRow(episode)
                    }
                    .tvCardButton()
                }
            }
        }
    }

    @ViewBuilder
    private func episodeRow(_ episode: BaseItemDto) -> some View {
        HStack(spacing: 20) {
            // Left border indicator for current episode
            RoundedRectangle(cornerRadius: 2)
                .fill(episode.hasProgress ? Color.red : Color.clear)
                .frame(width: 4)

            // Thumbnail
            if let url = imageService?.landscapeURL(item: episode, maxWidth: 400) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.15))
                }
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if episode.playbackProgress > 0 {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(.white.opacity(0.2))
                                        .frame(height: 4)
                                    Rectangle()
                                        .fill(.red)
                                        .frame(width: geo.size.width * episode.playbackProgress, height: 4)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // Episode info
            VStack(alignment: .leading, spacing: 6) {
                Text("E\(episode.indexNumber ?? 0)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(episode.name ?? "")
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let runtime = episode.runtimeDisplay {
                    Text(runtime)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Watched indicator
            Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "eye.slash")
                .font(.body)
                .foregroundStyle(episode.isWatched ? .green : .clear)
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .opacity(episode.isWatched ? 0.5 : 1.0)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private func sidebar(_ item: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let overview = item.overview {
                sidebarSection(title: "About", value: overview, lineLimit: 6)
            }

            if let director = item.directorNames {
                sidebarSection(title: "Creator", value: director)
            }

            if !item.castNames.isEmpty {
                sidebarSection(title: "Cast", value: item.castNames.joined(separator: ", "), lineLimit: 4)
            }
        }
        .padding(24)
        .liquidGlass(in: 20)
    }

    @ViewBuilder
    private func sidebarSection(title: String, value: String, lineLimit: Int = 3) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.body)
                .lineLimit(lineLimit)
                .foregroundStyle(.primary.opacity(0.85))
        }
    }
}
