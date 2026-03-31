import Foundation
import AVFoundation
import Combine
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
    var subtitleText = "" // Current subtitle text for overlay rendering

    // Next episode
    var nextEpisode: BaseItemDto?
    var showNextEpisodeOverlay = false
    var nextEpisodeCountdown = 10

    // Playback completion
    var isPlaybackComplete = false

    // Burn-in subtitle state (requires transcode restart)
    var currentBurnInSubtitleIndex: Int?

    // Seek preview (interactive scrubber)
    var seekPreviewTime: Double?
    var isSeekPreviewing: Bool { seekPreviewTime != nil }
    private var seekCommitTask: Task<Void, Never>?

    // Buffering
    var isBuffering = false
    private var timeControlObservation: NSKeyValueObservation?

    // MARK: - AVPlayer

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var progressTimer: Task<Void, Never>?
    private var controlsHideTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var endObservation: NSObjectProtocol?
    private let subtitleRenderer = SubtitleRenderer()
    private var subtitleCancellable: AnyCancellable?

    // MARK: - Playback info

    private(set) var itemID: String
    private var streamInfo: StreamInfo?
    private var item: BaseItemDto?
    private let jellyfinService: JellyfinService
    private let playbackService: PlaybackService
    private var countdownTask: Task<Void, Never>?

    // MARK: - Continuous Scrub (hold to fast-forward/rewind)

    private var scrubTask: Task<Void, Never>?
    private var scrubSpeed: Double = 1.0

    init(itemID: String, jellyfinService: JellyfinService) {
        self.itemID = itemID
        self.jellyfinService = jellyfinService
        self.playbackService = PlaybackService(jellyfinService: jellyfinService)
    }

    // MARK: - Lifecycle

    func onAppear() async {
        // Configure audio session for media playback
        #if os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback may still work with default session
        }
        #endif

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
            applyPreferredSubtitleLanguage()

            // Create player
            let playerItem = AVPlayerItem(url: info.url)

            // Attach subtitle renderer to receive legible output
            subtitleRenderer.attach(to: playerItem)
            subtitleCancellable = subtitleRenderer.$currentText
                .receive(on: DispatchQueue.main)
                .sink { [weak self] text in
                    self?.subtitleText = text
                }

            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer

            // Observe player item status for errors
            statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if item.status == .failed {
                        self.error = item.error?.localizedDescription ?? "Playback failed"
                        self.isLoading = false
                    }
                }
            }

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

            // Observe playback end (register before play to avoid race with short content)
            endObservation = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackEnd()
                }
            }

            // Start playback
            avPlayer.play()
            isPlaying = true
            isLoading = false

            // Setup time observer
            setupTimeObserver(avPlayer)
            setupTimeControlObserver(avPlayer)

            // Select default subtitle if server specifies one
            if let defaultSubIndex = selectedSubtitleIndex {
                Task {
                    await selectLegibleOption(for: defaultSubIndex, on: playerItem)
                }
            }

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
            self.error = "Failed to start playback: \(error.localizedDescription)"
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
        teardownPlayer()
    }

    /// Shared cleanup: cancel tasks, invalidate observers, detach subtitle renderer, nil out player.
    private func teardownPlayer() {
        progressTimer?.cancel()
        countdownTask?.cancel()
        scrubTask?.cancel()
        controlsHideTask?.cancel()
        seekCommitTask?.cancel()
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let endObservation {
            NotificationCenter.default.removeObserver(endObservation)
            self.endObservation = nil
        }
        subtitleCancellable?.cancel()
        subtitleCancellable = nil
        if let currentItem = player?.currentItem {
            subtitleRenderer.detach(from: currentItem)
        }
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
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
            controlsHideTask?.cancel()
            showControlsIfHidden()
            reportCurrentProgress(isPaused: true)
        } else {
            player.play()
            isPlaying = true
            resetControlsTimer()
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

    func startContinuousScrub(forward: Bool) {
        scrubTask?.cancel()
        scrubSpeed = 2.0 // Start at 2x
        scrubTask = Task {
            while !Task.isCancelled {
                let delta = forward ? scrubSpeed : -scrubSpeed
                let target = max(0, min(currentTime + delta, duration))
                await player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))

                // Accelerate: increase speed every 100ms, cap at 60x
                try? await Task.sleep(for: .milliseconds(100))
                if scrubSpeed < 60 {
                    scrubSpeed *= 1.05
                }
            }
        }
    }

    func stopContinuousScrub() {
        scrubTask?.cancel()
        scrubTask = nil
        scrubSpeed = 1.0
    }

    func seek(to fraction: Double) {
        guard let player, fraction.isFinite else { return }
        let clampedFraction = min(max(fraction, 0), 1)
        let target = duration * clampedFraction
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Update the seek preview position by a delta (in seconds).
    func updateSeekPreview(delta: Double) {
        let current = seekPreviewTime ?? currentTime
        let target = max(0, min(current + delta, duration))
        seekPreviewTime = target
        showControlsIfHidden()
        resetSeekCommitTimer()
    }

    /// Set the seek preview to an absolute fraction of duration (0.0-1.0).
    func setSeekPreview(fraction: Double) {
        let target = max(0, min(duration * fraction, duration))
        seekPreviewTime = target
        showControlsIfHidden()
        resetSeekCommitTimer()
    }

    /// Commit the current seek preview position.
    func commitSeek() {
        seekCommitTask?.cancel()
        guard let target = seekPreviewTime, let player else {
            seekPreviewTime = nil
            return
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        seekPreviewTime = nil
        resetControlsTimer()
    }

    /// Cancel the seek preview without seeking.
    func cancelSeekPreview() {
        seekCommitTask?.cancel()
        seekPreviewTime = nil
    }

    /// Retry playback after an error.
    func retryPlayback() {
        guard !isLoading else { return }
        error = nil
        isLoading = true
        Task {
            await onAppear()
        }
    }

    private func resetSeekCommitTimer() {
        seekCommitTask?.cancel()
        seekCommitTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commitSeek()
        }
    }

    func toggleControls() {
        isControlsVisible.toggle()
        if isControlsVisible {
            resetControlsTimer()
        } else {
            controlsHideTask?.cancel()
        }
    }

    func showControlsIfHidden() {
        guard !isControlsVisible else { return }
        isControlsVisible = true
        resetControlsTimer()
    }

    func resetControlsTimer() {
        controlsHideTask?.cancel()
        guard isPlaying else { return }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            isControlsVisible = false
        }
    }

    // MARK: - Audio/Subtitle Selection

    func selectAudio(index: Int) {
        selectedAudioIndex = index
        updateTrackLabels()

        // Remember language preference
        if let stream = audioStreams.first(where: { $0.index == index }) {
            jellyfinService.preferredAudioLanguage = stream.language
        }

        // Switch audio track on the player
        guard let player, let currentItem = player.currentItem else {
            reportCurrentProgress(isPaused: !isPlaying)
            return
        }
        Task {
            await selectAudibleOption(for: index, on: currentItem)
        }

        reportCurrentProgress(isPaused: !isPlaying)
    }

    func selectSubtitle(index: Int?) {
        selectedSubtitleIndex = index
        updateTrackLabels()

        // Remember subtitle language preference
        if let index {
            if let stream = subtitleStreams.first(where: { $0.index == index }) {
                jellyfinService.preferredSubtitleLanguage = stream.language
            }
        } else {
            jellyfinService.preferredSubtitleLanguage = nil
        }

        guard let player, let currentItem = player.currentItem else { return }

        if let index {
            let subtitleStream = subtitleStreams.first { $0.index == index }

            if let subtitleStream, PlaybackService.requiresBurnIn(stream: subtitleStream) {
                // Burn-in: restart playback with subtitle index so server burns it into video
                subtitleText = ""
                currentBurnInSubtitleIndex = index
                Task {
                    await restartPlayback(audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: index)
                }
                return
            }

            // Non-burn-in subtitle: if we were previously burning in, restart without burn-in first
            if currentBurnInSubtitleIndex != nil {
                currentBurnInSubtitleIndex = nil
                subtitleText = ""
                Task {
                    await restartPlayback(audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: nil)
                    // After restart, select the legible option
                    if let newItem = self.player?.currentItem {
                        await selectLegibleOption(for: index, on: newItem)
                    }
                }
                return
            }

            // Standard embedded subtitle: select via AVMediaSelectionGroup
            Task {
                await selectLegibleOption(for: index, on: currentItem)
            }
        } else {
            // Subtitles off
            subtitleText = ""
            if currentBurnInSubtitleIndex != nil {
                // Was burning in — restart without burn-in
                currentBurnInSubtitleIndex = nil
                Task {
                    await restartPlayback(audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: nil)
                }
                return
            }
            Task {
                await deselectLegibleOptions(on: currentItem)
            }
        }

        reportCurrentProgress(isPaused: !isPlaying)
    }

    /// Select a legible (subtitle) media option by matching Jellyfin stream index
    /// to AVMediaSelectionOptions available in the HLS manifest.
    private func selectLegibleOption(for jellyfinIndex: Int, on playerItem: AVPlayerItem) async {
        guard let asset = playerItem.asset as? AVURLAsset ?? Optional(playerItem.asset) else { return }

        // Load the legible media selection group
        let group: AVMediaSelectionGroup?
        if #available(tvOS 16.0, macOS 13.0, *) {
            group = try? await asset.loadMediaSelectionGroup(for: .legible)
        } else {
            group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        }
        guard let group else { return }

        let targetStream = subtitleStreams.first { $0.index == jellyfinIndex }
        let targetLang = targetStream?.language
        let targetTitle = targetStream?.displayTitle

        // Try to match by language code first, then by display name
        let option = group.options.first { option in
            if let targetLang, let optionLang = option.locale?.language.languageCode?.identifier {
                return optionLang == targetLang
            }
            return false
        } ?? group.options.first { option in
            if let targetTitle {
                return option.displayName.localizedCaseInsensitiveContains(targetTitle)
            }
            return false
        } ?? group.options.first // Fallback: select first available

        playerItem.select(option, in: group)
    }

    /// Deselect all legible media options (turn subtitles off).
    private func deselectLegibleOptions(on playerItem: AVPlayerItem) async {
        let group: AVMediaSelectionGroup?
        if #available(tvOS 16.0, macOS 13.0, *) {
            group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible)
        } else {
            group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        }
        guard let group else { return }
        playerItem.select(nil, in: group)
    }

    /// Select an audible (audio) media option by matching Jellyfin stream index
    /// to AVMediaSelectionOptions available in the HLS manifest.
    private func selectAudibleOption(for jellyfinIndex: Int, on playerItem: AVPlayerItem) async {
        let group: AVMediaSelectionGroup?
        if #available(tvOS 16.0, macOS 13.0, *) {
            group = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible)
        } else {
            group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        }
        guard let group else { return }

        let targetStream = audioStreams.first { $0.index == jellyfinIndex }
        let targetLang = targetStream?.language
        let targetTitle = targetStream?.displayTitle

        // Match by language code first, then display name
        let option = group.options.first { option in
            if let targetLang, let optionLang = option.locale?.language.languageCode?.identifier {
                return optionLang == targetLang
            }
            return false
        } ?? group.options.first { option in
            if let targetTitle {
                return option.displayName.localizedCaseInsensitiveContains(targetTitle)
            }
            return false
        }

        if let option {
            playerItem.select(option, in: group)
        } else {
            // No matching option in manifest — need to restart playback with this audio index
            await restartPlayback(audioStreamIndex: jellyfinIndex, subtitleStreamIndex: currentBurnInSubtitleIndex)
        }
    }

    func togglePicker() {
        isPickerVisible.toggle()
    }

    // MARK: - Next Episode

    func playNextEpisode() {
        countdownTask?.cancel()
        guard let next = nextEpisode, let nextID = next.id else { return }
        showNextEpisodeOverlay = false

        // Reload the player in-place with the next episode
        Task {
            await loadEpisodeInPlace(nextID)
        }
    }

    /// Tears down the current playback and starts a new episode without navigation.
    private func loadEpisodeInPlace(_ newItemID: String) async {
        // Clean up current playback
        await onDisappear()

        // Reset state
        itemID = newItemID
        isLoading = true
        error = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isControlsVisible = true
        showResumeToast = false
        subtitleText = ""
        currentBurnInSubtitleIndex = nil
        seekPreviewTime = nil
        seekCommitTask?.cancel()
        showNextEpisodeOverlay = false
        nextEpisodeCountdown = 10
        nextEpisode = nil
        isPlaybackComplete = false

        // Start the new episode
        await onAppear()
    }

    /// Restart playback with different stream parameters (audio/subtitle indices).
    /// Used for burn-in subtitle selection and audio track fallback.
    private func restartPlayback(audioStreamIndex: Int?, subtitleStreamIndex: Int?) async {
        let savedTime = currentTime
        let wasPaused = !isPlaying

        // Tear down current playback
        teardownPlayer()

        // Report stop with current position
        if let streamInfo {
            let ticks = secondsToTicks(savedTime)
            await playbackService.reportStopped(
                itemID: itemID,
                mediaSourceID: streamInfo.mediaSource.id,
                playSessionID: streamInfo.playSessionID,
                positionTicks: ticks
            )
        }

        isLoading = true

        do {
            // Get new stream info with updated indices
            let info = try await playbackService.getStreamInfo(
                itemID: itemID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )
            streamInfo = info

            // Update tracks from new media source
            audioStreams = PlaybackService.audioStreams(from: info.mediaSource)
            subtitleStreams = PlaybackService.subtitleStreams(from: info.mediaSource)
            updateTrackLabels()

            // Create new player
            let playerItem = AVPlayerItem(url: info.url)

            // Only attach subtitle renderer if not using burn-in
            if currentBurnInSubtitleIndex == nil {
                subtitleRenderer.attach(to: playerItem)
                subtitleCancellable = subtitleRenderer.$currentText
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] text in
                        self?.subtitleText = text
                    }
            }

            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer

            // Observe errors
            statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if item.status == .failed {
                        self.error = item.error?.localizedDescription ?? "Playback failed"
                        self.isLoading = false
                    }
                }
            }

            // Seek to saved position
            if savedTime > 0 {
                await avPlayer.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600))
            }

            // Observe playback end (register before play to avoid race with short content)
            endObservation = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackEnd()
                }
            }

            // Resume or stay paused
            if !wasPaused {
                avPlayer.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            isLoading = false

            // Re-setup observers
            setupTimeObserver(avPlayer)
            setupTimeControlObserver(avPlayer)

            // Re-select non-burn-in subtitle if active
            if currentBurnInSubtitleIndex == nil, let subIndex = selectedSubtitleIndex {
                await selectLegibleOption(for: subIndex, on: playerItem)
            }

            // Report start
            await playbackService.reportStart(
                itemID: itemID,
                mediaSourceID: info.mediaSource.id,
                playSessionID: info.playSessionID,
                positionTicks: secondsToTicks(savedTime),
                playMethod: info.playMethod
            )

            startProgressReporting()

        } catch {
            self.error = "Failed to restart playback: \(error.localizedDescription)"
            isLoading = false
        }
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

    private func setupTimeControlObserver(_ player: AVPlayer) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .paused:
                    // Only update isPlaying if we didn't initiate the pause
                    // (user-initiated pauses are handled in togglePlayPause)
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                @unknown default:
                    break
                }
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
        guard scrubTask == nil else { return } // Skip during continuous scrub
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
        guard seconds.isFinite else { return 0 }
        return Int(seconds * 10_000_000)
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

    private func applyPreferredSubtitleLanguage() {
        guard let preferred = jellyfinService.preferredSubtitleLanguage else { return }
        if let match = subtitleStreams.first(where: { $0.language == preferred }) {
            selectedSubtitleIndex = match.index
            updateTrackLabels()
        }
    }

    private func loadNextEpisode(seriesID: String, seasonID: String) async {
        // Tier 1: Check same season for next episode (fast path)
        do {
            let episodes = try await jellyfinService.getEpisodes(
                seriesID: seriesID,
                seasonID: seasonID
            )
            if let currentIndex = episodes.firstIndex(where: { $0.id == itemID }),
               currentIndex + 1 < episodes.count {
                nextEpisode = episodes[currentIndex + 1]
                return
            }
        } catch {}

        // Tier 2: Use getNextUp API for cross-season detection (server-authoritative)
        do {
            if let nextUp = try await jellyfinService.getNextUp(seriesID: seriesID) {
                // Make sure it's not the current episode
                if nextUp.id != itemID {
                    nextEpisode = nextUp
                    return
                }
            }
        } catch {}

        // Tier 3: Manual season traversal fallback (for rewatching scenarios)
        do {
            let seasons = try await jellyfinService.getSeasons(seriesID: seriesID)
            let currentSeasonNumber = item?.parentIndexNumber ?? 0

            // Find next season by indexNumber
            let sortedSeasons = seasons
                .filter { ($0.indexNumber ?? 0) > currentSeasonNumber }
                .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }

            if let nextSeason = sortedSeasons.first, let nextSeasonID = nextSeason.id {
                let episodes = try await jellyfinService.getEpisodes(
                    seriesID: seriesID,
                    seasonID: nextSeasonID
                )
                if let firstEpisode = episodes.first {
                    nextEpisode = firstEpisode
                    return
                }
            }
        } catch {}

        // All tiers exhausted — no next episode available
    }

    private func checkNearEnd() {
        guard duration > 0, nextEpisode != nil, !showNextEpisodeOverlay else { return }
        let remaining = duration - currentTime
        if remaining <= 10 && remaining > 0 {
            showNextEpisodeOverlay = true
            startNextEpisodeCountdown()
        }
    }

    private func handlePlaybackEnd() {
        isPlaying = false
        controlsHideTask?.cancel()
        if nextEpisode != nil {
            // Trigger next episode overlay if not already shown
            if !showNextEpisodeOverlay {
                showNextEpisodeOverlay = true
                startNextEpisodeCountdown()
            }
        } else {
            isPlaybackComplete = true
        }
    }

    private func startNextEpisodeCountdown() {
        nextEpisodeCountdown = max(0, Int(duration - currentTime))
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
