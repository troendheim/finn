import SwiftUI
import JellyfinAPI

struct ContentRow<Card: View>: View {
    let title: String
    let items: [BaseItemDto]
    let onSelect: (BaseItemDto) -> Void
    @ViewBuilder let cardBuilder: (BaseItemDto) -> Card

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.leading, 60)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(items, id: \.id) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                cardBuilder(item)
                            }
                            .tvCardButton()
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
        }
    }
}

// MARK: - Platform Button Style

extension View {
    /// Applies `.buttonStyle(.card)` on tvOS for proper focus-driven lift/shadow,
    /// and `.buttonStyle(.plain)` on macOS where `.card` is unavailable.
    func tvCardButton() -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        self.buttonStyle(.plain)
        #endif
    }
}
