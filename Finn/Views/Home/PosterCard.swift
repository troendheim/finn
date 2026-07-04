import SwiftUI
import JellyfinAPI

/// 2:3 portrait poster card for Recently Added and genre rows
struct PosterCard: View {
    let item: BaseItemDto
    let imageService: ImageService?

    private let cardWidth: CGFloat = 220
    private let cardHeight: CGFloat = 330 // 2:3

    var body: some View {
        ZStack(alignment: .bottom) {
            // Poster image
            if let id = item.id, let url = imageService?.posterURL(itemID: id, maxWidth: Int(cardWidth)) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                }
            } else {
                Rectangle().fill(.gray.opacity(0.2))
            }

            // Text overlay — bottom scrim gradient
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if item.type == .series {
                        Text("Series")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.name ?? "")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(item.name ?? "Unknown")
    }
}
