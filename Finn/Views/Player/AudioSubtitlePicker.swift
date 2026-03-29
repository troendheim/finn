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

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Centered panel
            HStack(alignment: .top, spacing: 60) {
                // Audio column
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)

                    ForEach(audioStreams, id: \.index) { stream in
                        Button {
                            if let index = stream.index {
                                onSelectAudio(index)
                            }
                        } label: {
                            trackRow(
                                title: stream.displayTitle ?? stream.language ?? "Unknown",
                                detail: audioDetail(stream),
                                isSelected: stream.index == selectedAudioIndex
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 300, alignment: .leading)

                // Subtitle column
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subtitles")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)

                    // Off option
                    Button {
                        onSelectSubtitle(nil)
                    } label: {
                        trackRow(
                            title: "Off",
                            detail: nil,
                            isSelected: selectedSubtitleIndex == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(subtitleStreams, id: \.index) { stream in
                        Button {
                            onSelectSubtitle(stream.index)
                        } label: {
                            trackRow(
                                title: stream.displayTitle ?? stream.language ?? "Unknown",
                                detail: subtitleDetail(stream),
                                isSelected: stream.index == selectedSubtitleIndex
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 300, alignment: .leading)
            }
            .padding(50)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Track Row

    @ViewBuilder
    private func trackRow(title: String, detail: String?, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(isSelected ? .bold : .regular)
                if let detail {
                    Text(detail)
                        .font(.caption)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.red.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
        )
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
