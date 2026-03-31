import SwiftUI

struct TransportControls: View {
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void
    var onHoldForward: (() -> Void)? = nil
    var onHoldBackward: (() -> Void)? = nil
    var onHoldRelease: (() -> Void)? = nil
    var seekPreviewTime: Double? = nil
    var onSeekPreviewUpdate: ((Double) -> Void)? = nil
    var onSeekCommit: (() -> Void)? = nil

    @State private var isHoldingBackward = false
    @State private var isHoldingForward = false
    @FocusState private var focusedButton: TransportButton?

    private enum TransportButton: Hashable {
        case skipBack, playPause, skipForward
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private var seekPreviewProgress: Double? {
        guard let seekPreviewTime, duration > 0 else { return nil }
        return seekPreviewTime / duration
    }

    var body: some View {
        VStack(spacing: 20) {
            // Interactive scrubber
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.4))
                        .frame(height: 8)

                    // Filled portion (current playback position)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red)
                        .frame(width: geo.size.width * progress, height: 8)

                    // Seek preview highlight (between current and preview positions)
                    if let previewProg = seekPreviewProgress {
                        let start = min(progress, previewProg)
                        let end = max(progress, previewProg)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow.opacity(0.5))
                            .frame(width: geo.size.width * (end - start), height: 8)
                            .offset(x: geo.size.width * start)
                    }

                    // Current playhead
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .frame(width: 18, height: 18)
                        .offset(x: geo.size.width * progress - 9)

                    // Seek preview playhead
                    if let previewProg = seekPreviewProgress {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 22, height: 22)
                            .offset(x: geo.size.width * previewProg - 11)

                        // Time label above preview playhead
                        Text(TimeFormatting.playerTime(seconds: seekPreviewTime ?? 0))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .liquidGlass(in: 6)
                            .offset(x: geo.size.width * previewProg - 30, y: -30)
                    }
                }
                #if os(macOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(value.location.x / geo.size.width, 1.0))
                            onSeekPreviewUpdate?(duration * fraction - (seekPreviewTime ?? currentTime))
                        }
                        .onEnded { _ in
                            onSeekCommit?()
                        }
                )
                #endif
            }
            .frame(height: 18)

            // Transport buttons
            HStack(spacing: 60) {
                // Skip backward (tap: -10s, hold: continuous rewind)
                Button {
                    onSkipBackward()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 36))
                }
                .glassButtonStyle()
                .focused($focusedButton, equals: .skipBack)
                .scaleEffect(focusedButton == .skipBack ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: focusedButton)
                .accessibilityLabel("Skip backward 10 seconds")
                .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                    if pressing {
                        isHoldingBackward = true
                        onHoldBackward?()
                    } else if isHoldingBackward {
                        isHoldingBackward = false
                        onHoldRelease?()
                    }
                }, perform: {
                    // Long press recognized — scrub is already running via pressing callback
                })

                // Play/Pause
                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .glassButtonStyle()
                .focused($focusedButton, equals: .playPause)
                .scaleEffect(focusedButton == .playPause ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: focusedButton)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                // Skip forward (tap: +10s, hold: continuous fast-forward)
                Button {
                    onSkipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 36))
                }
                .glassButtonStyle()
                .focused($focusedButton, equals: .skipForward)
                .scaleEffect(focusedButton == .skipForward ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: focusedButton)
                .accessibilityLabel("Skip forward 10 seconds")
                .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                    if pressing {
                        isHoldingForward = true
                        onHoldForward?()
                    } else if isHoldingForward {
                        isHoldingForward = false
                        onHoldRelease?()
                    }
                }, perform: {
                    // Long press recognized — scrub is already running via pressing callback
                })
            }
            .liquidGlassContainer(spacing: 16)
        }
        .padding(24)
        .liquidGlass(in: 20)
    }
}
