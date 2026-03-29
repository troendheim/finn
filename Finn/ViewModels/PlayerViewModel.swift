import Foundation
import AVFoundation
import JellyfinAPI

@MainActor
@Observable
final class PlayerViewModel {
    // MARK: - State

    var isPlaying = false
    var currentTime: Double = 0 // seconds
    var duration: Double = 0 // seconds
    var isControlsVisible = true
    var isLoading = true
    var error: String?
    var title = ""
    var showResumeToast = false
    var resumeTimeDisplay = ""

    // Audio/subtitle state
    var audioStreams: [MediaStream] = []
    var subtitleStreams: [MediaStream] = []
    var selectedAudioIndex: Int?
    var selectedSubtitleIndex: Int? // nil means off
    var isPickerVisible = false
    var currentAudioLabel = ""
    var currentSubtitleLabel = ""

    // Next episode
    var nextEpisode: BaseItemDto?
    var showNextEpisodeOverlay = false
    var nextEpisodeCountdown = 10

    // MARK: - AVPlayer

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var progressTimer: Task<Void, Never>?

    // MARK: - Playback info

    let itemID: String
    private var streamInfo: StreamInfo?
    private var item: BaseItemDto?
    private let jellyfinService: JellyfinService
    private let playbackService: PlaybackService
    private var countdownTask: Task<Void, Never>?

    init(itemID: String, jellyfinService: JellyfinService) {
        self.itemID = itemID
        self.jellyfinService = jellyfinService
        self.playbackService = PlaybackService(jellyfinService: jellyfinService)
    }

    // MARK: - Lifecycle

    func onAppear() async {
        do {
            // Load item detail for title and next episode info
            item = try await jellyfinService.getItem(id: itemID)
            updateTitle()

            // Load next episode if this is a series episode
            if item?.type == .episode, let seriesID = item?.seriesID, let seasonID = item?.seasonID {
                await loadNextEpisode(seriesID: seriesID, seasonID: seasonID)
            }

            // Get stream info
            let info = try await playbackService.getStreamInfo(itemID: itemID)
            streamInfo = info

            // Setup audio/subtitle tracks
            audioStreams = PlaybackService.audioStreams(from: info.mediaSource)
            subtitleStreams = PlaybackService.subtitleStreams(from: info.mediaSource)
            selectedAudioIndex = info.mediaSource.defaultAudioStreamIndex
            selectedSubtitleIndex = info.mediaSource.defaultSubtitleStreamIndex
            updateTrackLabels()

            // Apply preferred audio language
            applyPreferredAudioLanguage()

            // Create player
            let playerItem = AVPlayerItem(url: info.url)
            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer

            // Resume position
            let resumePosition = item?.userData?.playbackPositionTicks ?? 0
            if resumePosition > 0 {
                let seconds = TimeFormatting.ticksToSeconds(resumePosition)
                await avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                resumeTimeDisplay = TimeFormatting.playerTime(seconds: seconds)
                showResumeToast = true
                // Hide toast after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showResumeToast = false
                }
            }

            // Start playback
            avPlayer.play()
            isPlaying = true
            isLoading = false

            // Setup time observer
            setupTimeObserver(avPlayer)

            // Report playback start
            await playbackService.reportStart(
                itemID: itemID,
                mediaSourceID: info.mediaSource.id,
                playSessionID: info.playSessionID,
                positionTicks: resumePosition > 0 ? resumePosition : 0,
                playMethod: info.playMethod
            )

            // Start progress reporting timer
            startProgressReporting()

        } catch {
            self.error = "Failed to start playback"
            isLoading = false
        }
    }

    func onDisappear() async {
        // Report stopped
        let ticks = secondsToTicks(currentTime)
        await playbackService.reportStopped(
            itemID: itemID,
            mediaSourceID: streamInfo?.mediaSource.id,
            playSessionID: streamInfo?.playSessionID,
            positionTicks: ticks
        )

        // Cleanup
        progressTimer?.cancel()
        countdownTask?.cancel()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }

    // MARK: - Transport Controls

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            reportCurrentProgress(isPaused: true)
        } else {
            player.play()
            isPlaying = true
            reportCurrentProgress(isPaused: false)
        }
    }

    func skipForward(seconds: Double = 10) {
        guard let player else { return }
        let target = min(currentTime + seconds, duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func skipBackward(seconds: Double = 10) {
        guard let player else { return }
        let target = max(currentTime - seconds, 0)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let target = duration * fraction
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func toggleControls() {
        isControlsVisible.toggle()
    }

    // MARK: - Audio/Subtitle Selection

    func selectAudio(index: Int) {
        selectedAudioIndex = index
        updateTrackLabels()

        // Remember language preference
        if let stream = audioStreams.first(where: { $0.index == index }) {
            jellyfinService.preferredAudioLanguage = stream.language
        }

        // Report progress with new audio selection
        reportCurrentProgress(isPaused: !isPlaying)
    }

    func selectSubtitle(index: Int?) {
        selectedSubtitleIndex = index
        updateTrackLabels()

        // Handle subtitle display on AVPlayer
        if let player, let currentItem = player.currentItem {
            if let index {
                // Find the matching AVMediaSelectionOption
                let subtitleStream = subtitleStreams.first { $0.index == index }
                if let subtitleStream, PlaybackService.requiresBurnIn(stream: subtitleStream) {
                    // ASS/SSA — would need transcode. For now just report to server.
                    // A full implementation would restart with transcode URL including subtitle burn-in.
                }
                // For external subtitles (SRT/VTT), AVPlayer handles them if they're in the manifest
            }
            // For embedded subtitles, use AVMediaSelectionGroup
            if let group = currentItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                if let index {
                    // Try to find matching option by language
                    let targetLang = subtitleStreams.first { $0.index == index }?.language
                    let option = group.options.first { option in
                        option.locale?.languageCode == targetLang
                    }
                    currentItem.select(option, in: group)
                } else {
                    // Subtitles off
                    currentItem.select(nil, in: group)
                }
            }
        }

        reportCurrentProgress(isPaused: !isPlaying)
    }

    func togglePicker() {
        isPickerVisible.toggle()
    }

    // MARK: - Next Episode

    func playNextEpisode() {
        countdownTask?.cancel()
        guard let next = nextEpisode, next.id != nil else { return }
        // The view should handle navigation to the next episode
        // This is signaled by setting a published property
        showNextEpisodeOverlay = false
    }

    func cancelNextEpisode() {
        countdownTask?.cancel()
        showNextEpisodeOverlay = false
    }

    // MARK: - Private

    private func setupTimeObserver(_ player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                if let dur = player.currentItem?.duration, dur.isNumeric {
                    self.duration = dur.seconds
                }
                // Check for near-end (next episode countdown)
                self.checkNearEnd()
            }
        }
    }

    private func startProgressReporting() {
        progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                reportCurrentProgress(isPaused: !isPlaying)
            }
        }
    }

    private func reportCurrentProgress(isPaused: Bool) {
        guard let streamInfo else { return }
        let ticks = secondsToTicks(currentTime)
        Task {
            await playbackService.reportProgress(
                itemID: itemID,
                mediaSourceID: streamInfo.mediaSource.id,
                playSessionID: streamInfo.playSessionID,
                positionTicks: ticks,
                isPaused: isPaused,
                playMethod: streamInfo.playMethod,
                audioStreamIndex: selectedAudioIndex,
                subtitleStreamIndex: selectedSubtitleIndex
            )
        }
    }

    private func secondsToTicks(_ seconds: Double) -> Int {
        Int(seconds * 10_000_000)
    }

    private func updateTitle() {
        guard let item else { return }
        if item.type == .episode {
            title = "\(item.seriesName ?? "") · \(item.episodeLabel ?? "") · \(item.name ?? "")"
        } else {
            title = item.name ?? ""
        }
    }

    private func updateTrackLabels() {
        if let idx = selectedAudioIndex,
           let stream = audioStreams.first(where: { $0.index == idx }) {
            currentAudioLabel = stream.displayTitle ?? stream.language ?? "Audio"
        } else {
            currentAudioLabel = "Default"
        }

        if let idx = selectedSubtitleIndex,
           let stream = subtitleStreams.first(where: { $0.index == idx }) {
            currentSubtitleLabel = stream.displayTitle ?? stream.language ?? "Subtitle"
        } else {
            currentSubtitleLabel = "Off"
        }
    }

    private func applyPreferredAudioLanguage() {
        guard let preferred = jellyfinService.preferredAudioLanguage else { return }
        if let match = audioStreams.first(where: { $0.language == preferred }) {
            selectedAudioIndex = match.index
            updateTrackLabels()
        }
    }

    private func loadNextEpisode(seriesID: String, seasonID: String) async {
        do {
            let episodes = try await jellyfinService.getEpisodes(
                seriesID: seriesID,
                seasonID: seasonID
            )
            // Find current episode index and get next
            if let currentIndex = episodes.firstIndex(where: { $0.id == itemID }),
               currentIndex + 1 < episodes.count {
                nextEpisode = episodes[currentIndex + 1]
            }
        } catch {}
    }

    private func checkNearEnd() {
        guard duration > 0, nextEpisode != nil, !showNextEpisodeOverlay else { return }
        let remaining = duration - currentTime
        if remaining <= 10 && remaining > 0 {
            showNextEpisodeOverlay = true
            startNextEpisodeCountdown()
        }
    }

    private func startNextEpisodeCountdown() {
        nextEpisodeCountdown = Int(duration - currentTime)
        countdownTask = Task {
            while nextEpisodeCountdown > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                nextEpisodeCountdown -= 1
            }
            guard !Task.isCancelled else { return }
            // Auto-play next
            playNextEpisode()
        }
    }
}
