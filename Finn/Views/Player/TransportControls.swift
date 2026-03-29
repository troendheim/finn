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

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var body: some View {
        VStack(spacing: 20) {
            // Scrubber bar (read-only progress indicator)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.3))
                        .frame(height: 6)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.red)
                        .frame(width: geo.size.width * progress, height: 6)

                    // Playhead
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * progress - 8)
                }
            }
            .frame(height: 16)

            // Transport icons
            HStack(spacing: 60) {
                // Skip backward (tap: -10s, hold: continuous rewind)
                Button {
                    onSkipBackward()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, _) = value {
                                onHoldBackward?()
                            }
                        }
                        .onEnded { _ in
                            onHoldRelease?()
                        }
                )

                // Play/Pause
                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                // Skip forward (tap: +10s, hold: continuous fast-forward)
                Button {
                    onSkipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, _) = value {
                                onHoldForward?()
                            }
                        }
                        .onEnded { _ in
                            onHoldRelease?()
                        }
                )
            }
        }
    }
}
