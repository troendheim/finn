import AVFoundation
import Combine

/// Receives subtitle text from AVPlayerItemLegibleOutput and publishes it
/// for SwiftUI rendering on top of the video layer.
///
/// AVPlayerLayer (unlike AVPlayerViewController) does not render subtitles
/// on its own, so we capture legible output and draw it in a SwiftUI overlay.
final class SubtitleRenderer: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    /// The current subtitle text to display. Empty string means no subtitle visible.
    @Published var currentText: String = ""

    private let legibleOutput: AVPlayerItemLegibleOutput

    override init() {
        legibleOutput = AVPlayerItemLegibleOutput()
        super.init()
        legibleOutput.setDelegate(self, queue: .main)
        // Ensure we receive all strings, not just changes
        legibleOutput.advanceIntervalForDelegateInvocation = 0
        // Suppress AVPlayer's own rendering (it won't render on AVPlayerLayer anyway,
        // but this prevents any system-level subtitle drawing attempts)
        legibleOutput.suppressesPlayerRendering = true
    }

    /// The currently attached player item (weak to avoid retain cycles).
    private weak var attachedItem: AVPlayerItem?

    /// Attach to an AVPlayerItem to start receiving subtitle events.
    /// Auto-detaches from any previously attached item.
    func attach(to playerItem: AVPlayerItem) {
        if let previous = attachedItem, previous !== playerItem {
            previous.remove(legibleOutput)
        }
        playerItem.add(legibleOutput)
        attachedItem = playerItem
    }

    /// Detach from an AVPlayerItem.
    func detach(from playerItem: AVPlayerItem) {
        playerItem.remove(legibleOutput)
        if attachedItem === playerItem {
            attachedItem = nil
        }
    }

    // MARK: - AVPlayerItemLegibleOutputPushDelegate

    /// Called by AVFoundation when subtitle text changes (including becoming empty).
    nonisolated func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings
            .map { $0.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async { [weak self] in
            self?.currentText = text
        }
    }
}
