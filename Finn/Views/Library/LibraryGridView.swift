import SwiftUI
import JellyfinAPI

/// Flat, scrollable grid of `PosterCard`s used for the Series and Movies
/// overview tabs. Mirrors the layout used by `SearchView` so visual style
/// stays consistent across the app. Built to be extensible with filters
/// later — the underlying `LibraryViewModel` is sortable and paginated.
struct LibraryGridView: View {
    @Bindable var viewModel: LibraryViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 240), spacing: 40)
    ]

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            } else if viewModel.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Nothing here yet")
                        .font(.title3)
                    Text("Add some media to your Jellyfin server to get started")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                ScrollView {
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
                    .padding(.top, 30)
                    .padding(.bottom, 40)
                }
                .focusSection()
            }

            if let error = viewModel.error {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .task { await viewModel.load() }
    }
}