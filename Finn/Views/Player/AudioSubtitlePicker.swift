import SwiftUI
import JellyfinAPI

struct AudioSubtitlePicker: View {
    let audioStreams: [MediaStream]
    let subtitleStreams: [MediaStream]
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void
    let onDismiss: () -> Void

    /// Identifies each focusable item in the picker.
    private enum FocusItem: Hashable {
        case audio(Int)       // Jellyfin stream index
        case subtitleOff
        case subtitle(Int)    // Jellyfin stream index
    }

    @FocusState private var focusedItem: FocusItem?

    /// The item that should receive focus when the picker first appears.
    private var initialFocusItem: FocusItem {
        // Focus the currently-selected audio track (left column, top-ish)
        if let idx = selectedAudioIndex {
            return .audio(idx)
        }
        if let first = audioStreams.first?.index {
            return .audio(first)
        }
        return .subtitleOff
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // Panel slides up from bottom
            VStack {
                Spacer()

                HStack(alignment: .top, spacing: 60) {
                    // Audio column
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audio")
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(.bottom, 4)

                            ForEach(audioStreams, id: \.index) { stream in
                                TrackButton(
                                    title: stream.displayTitle ?? stream.language ?? "Unknown",
                                    detail: audioDetail(stream),
                                    isSelected: stream.index == selectedAudioIndex
                                ) {
                                    if let index = stream.index {
                                        onSelectAudio(index)
                                    }
                                }
                                .focused($focusedItem, equals: .audio(stream.index ?? -1))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(minWidth: 300, alignment: .leading)

                    // Subtitle column
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Subtitles")
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(.bottom, 4)

                            // Off option
                            TrackButton(
                                title: "Off",
                                detail: nil,
                                isSelected: selectedSubtitleIndex == nil
                            ) {
                                onSelectSubtitle(nil)
                            }
                            .focused($focusedItem, equals: .subtitleOff)

                            ForEach(subtitleStreams, id: \.index) { stream in
                                TrackButton(
                                    title: stream.displayTitle ?? stream.language ?? "Unknown",
                                    detail: subtitleDetail(stream),
                                    isSelected: stream.index == selectedSubtitleIndex
                                ) {
                                    onSelectSubtitle(stream.index)
                                }
                                .focused($focusedItem, equals: .subtitle(stream.index ?? -1))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(minWidth: 300, alignment: .leading)
                }
                .focusSection()
                .padding(50)
                .frame(maxHeight: 500)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
            }
            .transition(.move(edge: .bottom))
        }
        .onAppear {
            // Set initial focus so the user doesn't have to press up first
            focusedItem = initialFocusItem
        }
    }

    // MARK: - Detail Strings

    private func audioDetail(_ stream: MediaStream) -> String {
        var parts: [String] = []
        if let codec = stream.codec?.uppercased() { parts.append(codec) }
        if let layout = stream.channelLayout { parts.append(layout) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func subtitleDetail(_ stream: MediaStream) -> String? {
        var parts: [String] = []
        if let codec = stream.codec?.uppercased() { parts.append(codec) }
        if stream.isForced == true { parts.append("Forced") }
        if stream.isExternal == true { parts.append("External") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Track Button

/// A focusable button for track selection that works with tvOS focus navigation.
/// Uses .card style on tvOS so the focus engine handles highlight/navigation naturally.
private struct TrackButton: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(isSelected ? .bold : .regular)
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.red.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.red.opacity(0.4) : Color.clear, lineWidth: 2)
            )
        }
        .tvCardButton()
    }
}
