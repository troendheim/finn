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
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 60)
                }
            }
        }
    }
}
