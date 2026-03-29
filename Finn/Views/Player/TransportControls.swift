import SwiftUI

struct TransportControls: View {
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void
    let onSeek: (Double) -> Void
    var onHoldForward: (() -> Void)? = nil
    var onHoldBackward: (() -> Void)? = nil
    var onHoldRelease: (() -> Void)? = nil

    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isScrubbing ? scrubPosition : (currentTime / duration)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Scrubber bar
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
                // Skip backward with hold
                Button {
                    onSkipBackward()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in onHoldBackward?() }
                )

                // Play/Pause
                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                // Skip forward with hold
                Button {
                    onSkipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 36))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in onHoldForward?() }
                )
            }
        }
    }
}
