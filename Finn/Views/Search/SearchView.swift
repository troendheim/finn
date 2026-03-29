import SwiftUI
import JellyfinAPI

struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let imageService: ImageService?
    @Binding var navigationPath: NavigationPath

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search movies and series...", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.query) {
                        viewModel.onQueryChanged()
                    }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 60)
            .padding(.top, 30)

            // Results
            if viewModel.isSearching {
                ProgressView()
                    .padding(.top, 60)
                Spacer()
            } else if viewModel.results.isEmpty && viewModel.hasSearched {
                Text("No results found")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.results, id: \.id) { item in
                            Button {
                                navigateToDetail(item)
                            } label: {
                                searchResultRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ item: BaseItemDto) -> some View {
        HStack(spacing: 20) {
            // Poster thumbnail
            if let id = item.id, let url = imageService?.posterURL(itemID: id, maxWidth: 80) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Title with type badge
                HStack(spacing: 10) {
                    Text(item.name ?? "")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    typeBadge(item)
                }

                // Year and runtime/season count
                metadataText(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Brief description
                if let overview = item.overview {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func typeBadge(_ item: BaseItemDto) -> some View {
        let label = item.type == .series ? "Series" : "Movie"
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func metadataText(_ item: BaseItemDto) -> Text {
        var parts: [String] = []
        if let year = item.yearDisplay { parts.append(year) }
        if item.type == .series {
            if let count = item.childCount {
                parts.append("\(count) Season\(count == 1 ? "" : "s")")
            }
        } else {
            if let runtime = item.runtimeDisplay { parts.append(runtime) }
        }
        return Text(parts.joined(separator: " · "))
    }

    private func navigateToDetail(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        switch item.type {
        case .movie:
            navigationPath.append(AppDestination.movieDetail(itemID: id))
        case .series:
            navigationPath.append(AppDestination.seriesDetail(itemID: id))
        default:
            break
        }
    }
}
