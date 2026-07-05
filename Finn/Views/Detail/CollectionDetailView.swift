import SwiftUI
import JellyfinAPI

struct CollectionDetailView: View {
    @Bindable var viewModel: CollectionDetailViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath
    @State private var isOverviewExpanded = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 240), spacing: 40)
    ]

    var body: some View {
        ScrollView(.vertical) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 200)
            } else if let item = viewModel.item {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection(item)

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
                        .padding(.horizontal, 60)
                        .padding(.top, 24)
                    }

                    if !viewModel.displayItems.isEmpty {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(viewModel.displayItems, id: \.id) { item in
                                Button {
                                    navigateToDetail(item, navigationPath: $navigationPath)
                                } label: {
                                    PosterCard(item: item, imageService: imageService)
                                }
                                .tvCardButton()
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 40)
                        .padding(.bottom, 40)
                    }
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
    }

    @ViewBuilder
    private func headerSection(_ item: BaseItemDto) -> some View {
        ZStack(alignment: .bottomLeading) {
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

            VStack(alignment: .leading, spacing: 12) {
                Text(item.name ?? "")
                    .font(.title)
                    .fontWeight(.bold)

                if let genres = item.genres, !genres.isEmpty {
                    Text(genres.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("\(viewModel.items.count) items")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
    }
}
