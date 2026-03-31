import SwiftUI
import AVKit
import AVFoundation
import JellyfinAPI

/// Renders only the video layer without any system playback controls.
/// This avoids the duplicate progress bar that SwiftUI's `VideoPlayer` adds.
#if os(tvOS)
private struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PlayerUIView)?.playerLayer.player = player
    }

    private class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
#elseif os(macOS)
private struct AVPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PlayerNSView)?.playerLayer.player = player
    }

    private class PlayerNSView: NSView {
        override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
#endif

struct PlayerView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Player content layer — handles remote move/exit commands
            #if os(tvOS)
            playerContent
                .focusable(!viewModel.isControlsVisible && !viewModel.isPickerVisible)
                .onMoveCommand { direction in
                    if direction == .down {
                        viewModel.isPickerVisible = true
                    } else if direction == .left || direction == .right {
                        if viewModel.isControlsVisible {
                            let increment = viewModel.duration * 0.02
                            let delta = direction == .right ? increment : -increment
                            viewModel.updateSeekPreview(delta: delta)
                        } else {
                            if direction == .right {
                                viewModel.skipForward()
                            } else {
                                viewModel.skipBackward()
                            }
                            viewModel.showControlsIfHidden()
                            viewModel.resetControlsTimer()
                        }
                    } else {
                        viewModel.showControlsIfHidden()
                        viewModel.resetControlsTimer()
                    }
                }
            #else
            playerContent
            #endif

            // Audio/subtitle picker — separate from onMoveCommand so
            // the tvOS focus engine can navigate between columns freely.
            if viewModel.isPickerVisible {
                AudioSubtitlePicker(
                    audioStreams: viewModel.audioStreams,
                    subtitleStreams: viewModel.subtitleStreams,
                    selectedAudioIndex: viewModel.selectedAudioIndex,
                    selectedSubtitleIndex: viewModel.selectedSubtitleIndex,
                    onSelectAudio: { viewModel.selectAudio(index: $0) },
                    onSelectSubtitle: { viewModel.selectSubtitle(index: $0) },
                    onDismiss: { viewModel.isPickerVisible = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPickerVisible)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isControlsVisible)
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            Task { await viewModel.onDisappear() }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            if viewModel.isSeekPreviewing {
                viewModel.commitSeek()
            } else {
                viewModel.togglePlayPause()
            }
            viewModel.showControlsIfHidden()
        }
        .onExitCommand {
            if viewModel.isSeekPreviewing {
                viewModel.cancelSeekPreview()
            } else if viewModel.isPickerVisible {
                viewModel.isPickerVisible = false
            } else if viewModel.isControlsVisible {
                viewModel.isControlsVisible = false
            } else {
                dismiss()
            }
        }
        #else
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height > 50 && !viewModel.isPickerVisible {
                        viewModel.isPickerVisible = true
                    }
                }
        )
        .onKeyPress(.escape) {
            if viewModel.isSeekPreviewing {
                viewModel.cancelSeekPreview()
            } else if viewModel.isPickerVisible {
                viewModel.isPickerVisible = false
            } else if viewModel.isControlsVisible {
                viewModel.isControlsVisible = false
            } else {
                dismiss()
            }
            return .handled
        }
        .onKeyPress(.space) {
            if viewModel.isSeekPreviewing {
                viewModel.commitSeek()
            } else {
                viewModel.togglePlayPause()
            }
            viewModel.showControlsIfHidden()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.skipBackward()
            viewModel.showControlsIfHidden()
            viewModel.resetControlsTimer()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.skipForward()
            viewModel.showControlsIfHidden()
            viewModel.resetControlsTimer()
            return .handled
        }
        #endif
    }

    // MARK: - Player Content

    /// All player layers except the audio/subtitle picker.
    /// Separated so that `.onMoveCommand` only applies here and doesn't
    /// intercept directional input meant for the picker's focus engine.
    private var playerContent: some View {
        ZStack {
            // Video layer
            if let player = viewModel.player {
                AVPlayerLayerView(player: player)
                    .ignoresSafeArea()
                    #if os(macOS)
                    .onTapGesture {
                        viewModel.toggleControls()
                    }
                    #endif
            } else {
                Color.black.ignoresSafeArea()
            }

            // Subtitle overlay
            if !viewModel.subtitleText.isEmpty {
                VStack {
                    Spacer()
                    Text(viewModel.subtitleText)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.75))
                        )
                        .padding(.bottom, viewModel.isControlsVisible ? 160 : 60)
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.15), value: viewModel.subtitleText)
            }

            // Error state takes priority over buffering/loading
            if let error = viewModel.error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text(error)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    HStack(spacing: 20) {
                        Button("Retry") {
                            viewModel.retryPlayback()
                        }
                        .glassButtonStyle(prominent: true)
                        Button("Dismiss") {
                            dismiss()
                        }
                        .glassButtonStyle()
                    }
                }
            } else if viewModel.isLoading || viewModel.isBuffering {
                // Loading / buffering indicator (only when no error)
                ProgressView()
                    .scaleEffect(2)
            }

            // Controls overlay
            if viewModel.isControlsVisible && !viewModel.isLoading {
                controlsOverlay
                    .transition(.opacity)
                    #if os(tvOS)
                    .onMoveCommand { direction in
                        if direction == .down {
                            viewModel.isControlsVisible = false
                            viewModel.isPickerVisible = true
                        }
                    }
                    #endif
            }

            // Resume toast
            if viewModel.showResumeToast {
                VStack {
                    Spacer()
                    Text("Resuming from \(viewModel.resumeTimeDisplay)")
                        .font(.callout)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .liquidGlass(in: 10)
                        .padding(.bottom, 80)
                }
                .transition(.opacity)
            }

            // Next episode overlay
            if viewModel.showNextEpisodeOverlay, let next = viewModel.nextEpisode {
                nextEpisodeOverlay(next)
            }

            // Playback complete overlay
            if viewModel.isPlaybackComplete {
                playbackCompleteOverlay
            }
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack {
                // Top bar: title + time + track info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("\(viewModel.currentAudioLabel) \u{00B7} Subtitles: \(viewModel.currentSubtitleLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    #if os(tvOS)
                    Button {
                        viewModel.isControlsVisible = false
                        viewModel.isPickerVisible = true
                    } label: {
                        Image(systemName: "captions.bubble")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    #endif
                    VStack(alignment: .trailing) {
                        Text("\(TimeFormatting.playerTime(seconds: viewModel.currentTime)) / \(TimeFormatting.playerTime(seconds: viewModel.duration))")
                            .font(.callout)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                Spacer()

                // Transport controls
                TransportControls(
                    currentTime: viewModel.currentTime,
                    duration: viewModel.duration,
                    isPlaying: viewModel.isPlaying,
                    onPlayPause: { viewModel.togglePlayPause() },
                    onSkipForward: {
                        viewModel.skipForward()
                        viewModel.resetControlsTimer()
                    },
                    onSkipBackward: {
                        viewModel.skipBackward()
                        viewModel.resetControlsTimer()
                    },
                    onHoldForward: { viewModel.startContinuousScrub(forward: true) },
                    onHoldBackward: { viewModel.startContinuousScrub(forward: false) },
                    onHoldRelease: {
                        viewModel.stopContinuousScrub()
                        viewModel.resetControlsTimer()
                    },
                    seekPreviewTime: viewModel.seekPreviewTime,
                    onSeekPreviewUpdate: { delta in
                        viewModel.updateSeekPreview(delta: delta)
                    },
                    onSeekCommit: {
                        viewModel.commitSeek()
                    }
                )
                .padding(.horizontal, 120)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Next Episode Overlay

    @ViewBuilder
    private func nextEpisodeOverlay(_ next: BaseItemDto) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Next Episode in \(viewModel.nextEpisodeCountdown)s")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(next.episodeDisplayTitle ?? next.name ?? "Next Episode")
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        Button("Play Now") {
                            viewModel.playNextEpisode()
                        }
                        .glassButtonStyle(prominent: true)

                        Button("Cancel") {
                            viewModel.cancelNextEpisode()
                        }
                        .glassButtonStyle()
                    }
                }
                .padding(30)
                .liquidGlass(in: 16)
                .padding(40)
            }
        }
    }

    // MARK: - Playback Complete Overlay

    private var playbackCompleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Playback Complete")
                    .font(.title3)
                    .fontWeight(.semibold)
                Button("Done") {
                    dismiss()
                }
                .glassButtonStyle(prominent: true)
            }
        }
    }
}
