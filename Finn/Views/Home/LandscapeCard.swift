import SwiftUI
import JellyfinAPI

/// 16:9 landscape card for Continue Watching and Next Up rows
struct LandscapeCard: View {
    let item: BaseItemDto
    let imageService: ImageService?

    private let cardWidth: CGFloat = 440
    private let cardHeight: CGFloat = 248 // 16:9

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image
            if let id = item.id, let url = imageService?.backdropURL(itemID: id, maxWidth: Int(cardWidth)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                }
            } else {
                Rectangle().fill(.gray.opacity(0.2))
            }

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Text overlay
            VStack(alignment: .leading, spacing: 4) {
                if let episodeLabel = item.episodeLabel {
                    Text(episodeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.seriesName ?? item.name ?? "")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if item.hasProgress, let total = item.runTimeTicks, let pos = item.userData?.playbackPositionTicks {
                    Text(TimeFormatting.remaining(totalTicks: total, positionTicks: pos))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            // Progress bar at bottom
            if item.playbackProgress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.red)
                            .frame(width: geo.size.width * item.playbackProgress, height: 3)
                    }
                    .frame(height: 3)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
