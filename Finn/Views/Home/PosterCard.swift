import SwiftUI
import JellyfinAPI

/// 2:3 portrait poster card for Recently Added and genre rows
struct PosterCard: View {
    let item: BaseItemDto
    let imageService: ImageService?

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 300 // 2:3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster image
            ZStack(alignment: .bottomLeading) {
                if let id = item.id, let url = imageService?.posterURL(itemID: id, maxWidth: Int(cardWidth)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.gray.opacity(0.2))
                    }
                } else {
                    Rectangle().fill(.gray.opacity(0.2))
                }

                // Type badge — only shown for series to distinguish from movies
                if item.type == .series {
                    Text("Series")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Title below
            Text(item.name ?? "")
                .font(.callout)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
}
