import SwiftUI
import AVKit
import JellyfinAPI

struct PlayerView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Video layer
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.toggleControls()
                    }
            } else {
                Color.black.ignoresSafeArea()
            }

            // Loading state
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
            }

            // Error state
            if let error = viewModel.error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                    Text(error)
                        .font(.title3)
                }
            }

            // Controls overlay
            if viewModel.isControlsVisible && !viewModel.isLoading {
                controlsOverlay
            }

            // Resume toast
            if viewModel.showResumeToast {
                VStack {
                    Spacer()
                    Text("Resuming from \(viewModel.resumeTimeDisplay)")
                        .font(.callout)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 80)
                }
                .transition(.opacity)
            }

            // Audio/subtitle picker
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
            }

            // Next episode overlay
            if viewModel.showNextEpisodeOverlay, let next = viewModel.nextEpisode {
                nextEpisodeOverlay(next)
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            Task { await viewModel.onDisappear() }
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            if direction == .down {
                viewModel.togglePicker()
            }
        }
        #else
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height > 50 {
                        viewModel.togglePicker()
                    }
                }
        )
        #endif
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
                        Text("Swipe down for audio & subtitles")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    Spacer()
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
                    onSkipForward: { viewModel.skipForward() },
                    onSkipBackward: { viewModel.skipBackward() },
                    onHoldForward: { viewModel.startContinuousScrub(forward: true) },
                    onHoldBackward: { viewModel.startContinuousScrub(forward: false) },
                    onHoldRelease: { viewModel.stopContinuousScrub() }
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
                        .tint(.red)

                        Button("Cancel") {
                            viewModel.cancelNextEpisode()
                        }
                    }
                }
                .padding(30)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(40)
            }
        }
    }
}
