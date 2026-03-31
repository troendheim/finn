import SwiftUI
import JellyfinAPI

struct SeriesDetailView: View {
    @Bindable var viewModel: SeriesDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

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
                    HStack(alignment: .top, spacing: 40) {
                        // Left: seasons + episodes
                        VStack(alignment: .leading, spacing: 24) {
                            seasonPicker
                            episodeList
                        }
                        .frame(maxWidth: .infinity)

                        // Right sidebar
                        sidebar(item)
                            .frame(width: 350)
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 30)
                }
            } else if let error = viewModel.error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.top, 200)
            }
        }
        .task {
            await viewModel.loadDetail()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ item: BaseItemDto) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            if let id = item.id, let url = imageService?.backdropURL(itemID: id) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .frame(height: 450)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8), .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } placeholder: {
                    Rectangle().fill(.black).frame(height: 450)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(item.name ?? "")
                    .font(.system(size: 48, weight: .bold))

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
                        HStack {
                            Image(systemName: "play.fill")
                            Text(viewModel.playButtonTitle)
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                    }
                    .tint(.red)
                    .disabled(viewModel.playItemID == nil)

                    Button {
                        Task { await viewModel.toggleFavorite() }
                    } label: {
                        Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(viewModel.seasons, id: \.id) { season in
                    Button {
                        Task { await viewModel.selectSeason(season) }
                    } label: {
                        VStack(spacing: 8) {
                            Text(season.name ?? "Season")
                                .font(.callout)
                                .fontWeight(viewModel.selectedSeason?.id == season.id ? .bold : .regular)

                            Rectangle()
                                .fill(viewModel.selectedSeason?.id == season.id ? Color.red : Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Episode List

    private var episodeList: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingEpisodes {
                ProgressView()
                    .padding(.top, 40)
            } else {
                ForEach(viewModel.episodes, id: \.id) { episode in
                    Button {
                        if let id = episode.id {
                            navigationPath.append(AppDestination.player(itemID: id))
                        }
                    } label: {
                        episodeRow(episode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func episodeRow(_ episode: BaseItemDto) -> some View {
        HStack(spacing: 16) {
            // Left border indicator for current episode
            RoundedRectangle(cornerRadius: 2)
                .fill(episode.hasProgress ? Color.red : Color.clear)
                .frame(width: 4, height: 80)

            // Thumbnail
            if let url = imageService?.landscapeURL(item: episode, maxWidth: 400) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if episode.playbackProgress > 0 {
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: geo.size.width * episode.playbackProgress, height: 3)
                            }
                            .frame(height: 3)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("E\(episode.indexNumber ?? 0)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(episode.name ?? "")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                if let runtime = episode.runtimeDisplay {
                    Text(runtime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Watch status
            if episode.isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(episode.isWatched ? 0.5 : 1.0)
        .padding(.vertical, 8)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private func sidebar(_ item: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let overview = item.overview {
                InfoSection(title: "About", value: overview)
            }

            if let director = item.directorNames {
                InfoSection(title: "Creator", value: director)
            }

            if !item.castNames.isEmpty {
                InfoSection(title: "Cast", value: item.castNames.joined(separator: ", "))
            }
        }
    }
}
