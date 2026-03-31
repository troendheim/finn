import SwiftUI
import JellyfinAPI

struct MovieDetailView: View {
    @Bindable var viewModel: MovieDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath
    @State private var isOverviewExpanded = false

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 200)
            } else if let item = viewModel.item {
                ZStack(alignment: .topLeading) {
                    // Backdrop
                    backdropImage(item)

                    // Content overlay
                    HStack(alignment: .top, spacing: 60) {
                        // Left: main info
                        VStack(alignment: .leading, spacing: 20) {
                            Spacer().frame(height: 300)

                            Text(item.name ?? "")
                                .font(.title)
                                .fontWeight(.bold)

                            Text(viewModel.metadataLine)
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            if let rating = viewModel.ratingDisplay {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                    Text(rating)
                                        .font(.title3)
                                }
                            }

                            if let genres = item.genres, !genres.isEmpty {
                                Text(genres.joined(separator: ", "))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            // Action buttons
                            HStack(spacing: 20) {
                                Button {
                                    navigationPath.append(AppDestination.player(itemID: viewModel.itemID))
                                } label: {
                                    HStack {
                                        Image(systemName: item.hasProgress ? "play.circle.fill" : "play.fill")
                                        Text(viewModel.playButtonTitle)
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 12)
                                }
                                .tint(.red)

                                Button {
                                    Task { await viewModel.toggleFavorite() }
                                } label: {
                                    Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                        .font(.title3)
                                }
                                .accessibilityLabel(viewModel.isFavorite ? "Remove from favorites" : "Add to favorites")
                            }

                            // Progress bar for resume
                            if item.hasProgress {
                                ProgressView(value: item.playbackProgress)
                                    .tint(.red)
                                    .frame(maxWidth: 300)
                            }

                            if let overview = item.overview {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(overview)
                                        .font(.body)
                                        .lineLimit(isOverviewExpanded ? nil : 4)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: 700, alignment: .leading)

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isOverviewExpanded.toggle()
                                        }
                                    } label: {
                                        Text(isOverviewExpanded ? "Show Less" : "Show More")
                                            .font(.callout)
                                            .foregroundStyle(.red)
                                    }
                                    #if os(tvOS)
                                    .buttonStyle(.plain)
                                    #endif
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right sidebar: credits and tracks
                        VStack(alignment: .leading, spacing: 20) {
                            Spacer().frame(height: 320)

                            if let director = item.directorNames {
                                InfoSection(title: "Director", value: director)
                            }

                            if !item.castNames.isEmpty {
                                InfoSection(title: "Cast", value: item.castNames.joined(separator: ", "))
                            }

                            if !item.audioLanguages.isEmpty {
                                InfoSection(title: "Audio", value: item.audioLanguages.joined(separator: ", "))
                            }

                            if !item.subtitleLanguages.isEmpty {
                                InfoSection(title: "Subtitles", value: item.subtitleLanguages.joined(separator: ", "))
                            }
                        }
                        .frame(width: 350)
                    }
                    .padding(.horizontal, 60)
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
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { viewModel.actionError = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut, value: viewModel.actionError)
    }

    @ViewBuilder
    private func backdropImage(_ item: BaseItemDto) -> some View {
        if let id = item.id, let url = imageService?.backdropURL(itemID: id) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
                    .frame(height: 600)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } placeholder: {
                Rectangle().fill(.black).frame(height: 600)
            }
        }
    }
}

// MARK: - InfoSection

struct InfoSection: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .lineLimit(3)
        }
    }
}
