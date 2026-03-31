import SwiftUI
import JellyfinAPI

/// 16:9 landscape card for Continue Watching and Next Up rows
struct LandscapeCard: View {
    let item: BaseItemDto
    let imageService: ImageService?

    private let cardWidth: CGFloat = 500
    private let cardHeight: CGFloat = 281 // 16:9

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background image — try thumb, backdrop, then primary with series fallback
            if let url = imageService?.landscapeURL(item: item, maxWidth: Int(cardWidth)) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                }
            } else {
                Rectangle().fill(.gray.opacity(0.2))
            }

            // Text overlay — full-width Liquid Glass bar at bottom
            VStack(spacing: 0) {
                HStack {
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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Progress bar inside the glass bar so it renders on top
                if item.playbackProgress > 0 {
                    Rectangle()
                        .fill(.red)
                        .frame(height: 4)
                        .frame(width: cardWidth * item.playbackProgress, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .liquidGlass(in: 0)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
