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
    private var toastTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var playerActionTask: Task<Void, Never>?

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
        // Guard against double invocation from SwiftUI lifecycle quirks
        guard player == nil else { return }

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

            // First, get stream info without specific indices to discover available tracks
            let initialInfo = try await playbackService.getStreamInfo(itemID: itemID)

            // Setup audio/subtitle tracks from initial response
            audioStreams = PlaybackService.audioStreams(from: initialInfo.mediaSource)
            subtitleStreams = PlaybackService.subtitleStreams(from: initialInfo.mediaSource)
            selectedAudioIndex = initialInfo.mediaSource.defaultAudioStreamIndex
            selectedSubtitleIndex = initialInfo.mediaSource.defaultSubtitleStreamIndex
            updateTrackLabels()

            // Apply user's preferred language (may change selectedAudioIndex / selectedSubtitleIndex)
            applyPreferredAudioLanguage()
            applyPreferredSubtitleLanguage()

            // Now get the real stream info with the correct audio/subtitle indices so the
            // server generates the right transcode URL (e.g. correct burned-in subtitle).
            let info: StreamInfo
            if selectedAudioIndex != initialInfo.mediaSource.defaultAudioStreamIndex ||
               selectedSubtitleIndex != initialInfo.mediaSource.defaultSubtitleStreamIndex {
                info = try await playbackService.getStreamInfo(
                    itemID: itemID,
                    audioStreamIndex: selectedAudioIndex,
                    subtitleStreamIndex: selectedSubtitleIndex
                )
                // Re-sync tracks from the final response
                audioStreams = PlaybackService.audioStreams(from: info.mediaSource)
                subtitleStreams = PlaybackService.subtitleStreams(from: info.mediaSource)
                updateTrackLabels()
            } else {
                info = initialInfo
            }
            streamInfo = info

            #if DEBUG
            print("[SUBS] onAppear: final stream info")
            print("[SUBS]   playMethod=\(info.playMethod) url=\(info.url.absoluteString)")
            print("[SUBS]   selectedAudioIndex=\(String(describing: selectedAudioIndex)) selectedSubtitleIndex=\(String(describing: selectedSubtitleIndex))")
            print("[SUBS]   subtitle streams (\(subtitleStreams.count)):")
            for s in subtitleStreams {
                print("[SUBS]     index=\(s.index ?? -1) lang=\(s.language ?? "nil") title=\(s.displayTitle ?? "nil") codec=\(s.codec ?? "nil") isExternal=\(s.isExternal ?? false)")
            }
            #endif

            // Create player — pass token via Authorization header instead of URL query
            let asset: AVURLAsset
            if let token = info.accessToken {
                asset = AVURLAsset(url: info.url, options: [
                    "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "MediaBrowser Token=\"\(token)\""]
                ])
            } else {
                asset = AVURLAsset(url: info.url)
            }
            let playerItem = AVPlayerItem(asset: asset)

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
                let status = item.status
                let errorMessage = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .failed {
                        self.error = errorMessage ?? "Playback failed"
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
                toastTask?.cancel()
                toastTask = Task {
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

            // Auto-hide controls after playback starts
            resetControlsTimer()

            // Setup time observer
            setupTimeObserver(avPlayer)
            setupTimeControlObserver(avPlayer)

            // Select default subtitle if server specifies one
            if let defaultSubIndex = selectedSubtitleIndex {
                playerActionTask = Task {
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
        // Pause immediately so audio stops before the network call
        player?.pause()

        // Report stopped
        let ticks = secondsToTicks(currentTime)
        await playbackService.reportStopped(
            itemID: itemID,
            mediaSourceID: streamInfo?.mediaSource.id,
            playSessionID: streamInfo?.playSessionID,
            positionTicks: ticks
        )

        // Cleanup
        playerActionTask?.cancel()
        teardownPlayer()
    }

    /// Shared cleanup: cancel tasks, invalidate observers, detach subtitle renderer, nil out player.
    /// Note: does NOT cancel `playerActionTask` because `restartPlayback` calls teardownPlayer
    /// from within playerActionTask. Callers that need to cancel it should do so explicitly.
    private func teardownPlayer() {
        progressTimer?.cancel()
        countdownTask?.cancel()
        toastTask?.cancel()
        retryTask?.cancel()
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
        streamInfo = nil
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
    /// Preserves the user's current audio/subtitle selections so the server
    /// generates the correct stream (important for external/burn-in subtitles).
    func retryPlayback() {
        guard !isLoading else { return }
        error = nil
        isLoading = true

        // Save user selections before teardown
        let savedAudioIndex = selectedAudioIndex
        let savedSubtitleIndex = selectedSubtitleIndex
        let hadItem = item != nil

        playerActionTask?.cancel()
        teardownPlayer()
        retryTask?.cancel()
        retryTask = Task {
            if hadItem {
                // Item was already loaded — use restartPlayback which passes audio/subtitle
                // indices to the server, ensuring external/burn-in subtitles are included.
                await restartPlayback(
                    audioStreamIndex: savedAudioIndex,
                    subtitleStreamIndex: savedSubtitleIndex
                )
            } else {
                // Initial load failed — do full onAppear
                await onAppear()
            }
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
        playerActionTask?.cancel()
        playerActionTask = Task {
            await selectAudibleOption(for: index, on: currentItem)
        }

        reportCurrentProgress(isPaused: !isPlaying)
    }

    func selectSubtitle(index: Int?) {
        let previousIndex = selectedSubtitleIndex
        selectedSubtitleIndex = index
        updateTrackLabels()

        let stream = index.flatMap { idx in subtitleStreams.first(where: { $0.index == idx }) }
        #if DEBUG
        print("[SUBS] selectSubtitle called: index=\(String(describing: index)) prev=\(String(describing: previousIndex)) stream=\(stream?.displayTitle ?? "nil") lang=\(stream?.language ?? "nil") codec=\(stream?.codec ?? "nil") isExternal=\(stream?.isExternal ?? false)")
        print("[SUBS]   playMethod=\(String(describing: streamInfo?.playMethod))")
        #endif

        // Remember subtitle language preference
        if let index {
            if let stream = subtitleStreams.first(where: { $0.index == index }) {
                jellyfinService.preferredSubtitleLanguage = stream.language
            }
        } else {
            jellyfinService.preferredSubtitleLanguage = nil
        }

        guard let player, let currentItem = player.currentItem else {
            #if DEBUG
            print("[SUBS]   EARLY RETURN: player or currentItem is nil")
            #endif
            return
        }

        // For transcoded streams the server controls subtitle delivery (burn-in or HLS embed).
        // The only reliable way to switch subtitles is to restart with the new index so the
        // server generates a fresh transcode with the correct subtitle.
        if streamInfo?.playMethod == .transcode {
            #if DEBUG
            print("[SUBS]   -> PATH: transcode restart with subtitleStreamIndex=\(String(describing: index))")
            #endif
            subtitleText = ""
            currentBurnInSubtitleIndex = nil
            playerActionTask?.cancel()
            playerActionTask = Task {
                await restartPlayback(audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: index)
            }
            return
        }

        // Direct play / direct stream: subtitle tracks are in the container itself,
        // so we can switch via AVMediaSelectionGroup without restarting.
        if let index {
            #if DEBUG
            print("[SUBS]   -> PATH: direct play, selectLegibleOption for index=\(index)")
            #endif
            playerActionTask?.cancel()
            playerActionTask = Task {
                await selectLegibleOption(for: index, on: currentItem)
            }
        } else {
            #if DEBUG
            print("[SUBS]   -> PATH: direct play, deselect legible (subtitles off)")
            #endif
            playerActionTask?.cancel()
            playerActionTask = Task {
                await deselectLegibleOptions(on: currentItem)
            }
        }

        reportCurrentProgress(isPaused: !isPlaying)
    }

    /// Select a legible (subtitle) media option by matching Jellyfin stream index
    /// to AVMediaSelectionOptions available in the HLS manifest.
    private func selectLegibleOption(for jellyfinIndex: Int, on playerItem: AVPlayerItem) async {
        let asset = playerItem.asset

        // Load the legible media selection group
        let group: AVMediaSelectionGroup?
        if #available(tvOS 16.0, macOS 13.0, *) {
            group = try? await asset.loadMediaSelectionGroup(for: .legible)
        } else {
            group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        }
        guard let group else {
            #if DEBUG
            print("[SUBS] selectLegibleOption: NO legible group found in asset")
            #endif
            return
        }

        let targetStream = subtitleStreams.first { $0.index == jellyfinIndex }
        let targetTitle = targetStream?.displayTitle

        // Normalize Jellyfin's language code (3-letter ISO 639-2 like "dan", "eng") to
        // a 2-letter ISO 639-1 code ("da", "en") so it matches AVPlayer's locale identifiers.
        let targetLang: String? = targetStream?.language.flatMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }

        #if DEBUG
        print("[SUBS] selectLegibleOption: jellyfinIndex=\(jellyfinIndex) targetTitle=\(targetTitle ?? "nil") targetLang=\(targetLang ?? "nil") rawLang=\(targetStream?.language ?? "nil")")
        print("[SUBS]   available AVPlayer options (\(group.options.count)):")
        #endif
        for (i, opt) in group.options.enumerated() {
            let lang = opt.locale?.language.languageCode?.identifier ?? "nil"
            #if DEBUG
            print("[SUBS]     [\(i)] displayName=\"\(opt.displayName)\" lang=\(lang) locale=\(opt.locale?.identifier ?? "nil")")
            #endif
        }

        // Gather all AVPlayer options that match the target language
        let langMatches: [AVMediaSelectionOption] = targetLang.map { lang in
            group.options.filter { option in
                option.locale?.language.languageCode?.identifier == lang
            }
        } ?? []

        #if DEBUG
        print("[SUBS]   langMatches count=\(langMatches.count)")
        #endif

        let option: AVMediaSelectionOption?
        if langMatches.count == 1 {
            option = langMatches.first
            #if DEBUG
            print("[SUBS]   -> single lang match: \(option?.displayName ?? "nil")")
            #endif
        } else if langMatches.count > 1 {
            option = langMatches.first { $0.displayName.localizedCaseInsensitiveContains(targetTitle ?? "") }
                ?? {
                    let sameLanguageStreams = subtitleStreams.filter { $0.language == targetStream?.language }
                    let position = sameLanguageStreams.firstIndex(where: { $0.index == jellyfinIndex }) ?? 0
                    #if DEBUG
                    print("[SUBS]   -> multi lang match, positional: position=\(position)")
                    #endif
                    return position < langMatches.count ? langMatches[position] : langMatches.first
                }()
            #if DEBUG
            print("[SUBS]   -> multi lang match selected: \(option?.displayName ?? "nil")")
            #endif
        } else {
            option = group.options.first { opt in
                if let targetTitle {
                    return opt.displayName.localizedCaseInsensitiveContains(targetTitle)
                }
                return false
            } ?? group.options.first
            #if DEBUG
            print("[SUBS]   -> no lang match, fallback selected: \(option?.displayName ?? "nil")")
            #endif
        }

        if let option {
            #if DEBUG
            print("[SUBS]   SELECTING option: \(option.displayName)")
            #endif
            playerItem.select(option, in: group)
        } else {
            #if DEBUG
            print("[SUBS]   NO option to select!")
            #endif
        }
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
        let targetTitle = targetStream?.displayTitle

        // Normalize Jellyfin's language code (3-letter ISO 639-2 like "dan", "eng") to
        // a 2-letter ISO 639-1 code ("da", "en") so it matches AVPlayer's locale identifiers.
        let targetLang: String? = targetStream?.language.flatMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }

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
        playerActionTask?.cancel()
        playerActionTask = Task {
            await loadEpisodeInPlace(nextID)
        }
    }

    /// Tears down the current playback and starts a new episode without navigation.
    private func loadEpisodeInPlace(_ newItemID: String) async {
        // Clean up current playback without cancelling playerActionTask
        // (we are running inside it)
        player?.pause()

        let ticks = secondsToTicks(currentTime)
        await playbackService.reportStopped(
            itemID: itemID,
            mediaSourceID: streamInfo?.mediaSource.id,
            playSessionID: streamInfo?.playSessionID,
            positionTicks: ticks
        )

        teardownPlayer()

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

        // Preserve user's manual audio/subtitle choices across episode reloads
        // so onAppear's applyPreferred*Language() doesn't override them.
        let userAudioIndex = selectedAudioIndex
        let userSubtitleIndex = selectedSubtitleIndex

        // Start the new episode (this calls onAppear which applies defaults)
        await onAppear()

        // If the user had manually selected tracks, restore those choices
        // rather than the preference-based defaults that onAppear applied.
        if userAudioIndex != selectedAudioIndex || userSubtitleIndex != selectedSubtitleIndex {
            if userAudioIndex != selectedAudioIndex, let idx = userAudioIndex {
                selectAudio(index: idx)
            }
            if userSubtitleIndex != selectedSubtitleIndex {
                selectSubtitle(index: userSubtitleIndex)
            }
        }
    }

    /// Restart playback with different stream parameters (audio/subtitle indices).
    /// Used for burn-in subtitle selection and audio track fallback.
    /// Keeps the old player visible while loading the new stream to avoid a black flash.
    private func restartPlayback(audioStreamIndex: Int?, subtitleStreamIndex: Int?) async {
        #if DEBUG
        print("[SUBS] restartPlayback: audioStreamIndex=\(String(describing: audioStreamIndex)) subtitleStreamIndex=\(String(describing: subtitleStreamIndex))")
        #endif
        let savedTime = currentTime
        let wasPaused = !isPlaying

        // Capture references to the old player/session for cleanup
        let previousStreamInfo = streamInfo
        let oldPlayer = player
        let oldItem = oldPlayer?.currentItem

        // --- Keep the OLD player alive and visible while we fetch the new stream ---

        do {
            // Get new stream info with updated indices
            let info = try await playbackService.getStreamInfo(
                itemID: itemID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex
            )

            #if DEBUG
            print("[SUBS] restartPlayback: got new stream info")
            print("[SUBS]   playMethod=\(info.playMethod) url=\(info.url.absoluteString)")
            print("[SUBS]   transcodingURL=\(info.mediaSource.transcodingURL ?? "nil")")
            #endif
            let newSubStreams = PlaybackService.subtitleStreams(from: info.mediaSource)
            #if DEBUG
            print("[SUBS]   subtitle streams in new mediaSource (\(newSubStreams.count)):")
            for s in newSubStreams {
                print("[SUBS]     index=\(s.index ?? -1) lang=\(s.language ?? "nil") title=\(s.displayTitle ?? "nil") codec=\(s.codec ?? "nil") isExternal=\(s.isExternal ?? false)")
            }
            #endif

            // Prepare the new player item and seek BEFORE swapping
            let restartAsset: AVURLAsset
            if let token = info.accessToken {
                restartAsset = AVURLAsset(url: info.url, options: [
                    "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "MediaBrowser Token=\"\(token)\""]
                ])
            } else {
                restartAsset = AVURLAsset(url: info.url)
            }
            let playerItem = AVPlayerItem(asset: restartAsset)
            let avPlayer = AVPlayer(playerItem: playerItem)
            if savedTime > 0 {
                await avPlayer.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600))
            }

            // --- Clean up old player resources ---
            progressTimer?.cancel()
            countdownTask?.cancel()
            retryTask?.cancel()
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
            if let oldItem {
                subtitleRenderer.detach(from: oldItem)
            }
            if let observer = timeObserver {
                oldPlayer?.removeTimeObserver(observer)
                timeObserver = nil
            }
            oldPlayer?.pause()

            // Report stop for the old session
            if let previousStreamInfo {
                let ticks = secondsToTicks(savedTime)
                await playbackService.reportStopped(
                    itemID: itemID,
                    mediaSourceID: previousStreamInfo.mediaSource.id,
                    playSessionID: previousStreamInfo.playSessionID,
                    positionTicks: ticks
                )
            }

            // --- Swap in the new player (view instantly shows new video frame) ---
            streamInfo = info
            audioStreams = PlaybackService.audioStreams(from: info.mediaSource)
            subtitleStreams = PlaybackService.subtitleStreams(from: info.mediaSource)
            updateTrackLabels()

            // Attach subtitle renderer to the new item
            subtitleRenderer.attach(to: playerItem)
            subtitleCancellable = subtitleRenderer.$currentText
                .receive(on: DispatchQueue.main)
                .sink { [weak self] text in
                    self?.subtitleText = text
                }

            self.player = avPlayer

            // Observe errors
            statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                let status = item.status
                let errorMessage = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .failed {
                        self.error = errorMessage ?? "Playback failed"
                        self.isLoading = false
                    }
                }
            }

            // Observe playback end
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

            // Re-setup observers
            setupTimeObserver(avPlayer)
            setupTimeControlObserver(avPlayer)

            // Re-select non-burn-in subtitle if active
            if currentBurnInSubtitleIndex == nil, let subIndex = selectedSubtitleIndex {
                #if DEBUG
                print("[SUBS] restartPlayback: re-selecting legible option for subIndex=\(subIndex)")
                #endif
                await selectLegibleOption(for: subIndex, on: playerItem)
            } else {
                #if DEBUG
                print("[SUBS] restartPlayback: NOT re-selecting legible (burnIn=\(String(describing: currentBurnInSubtitleIndex)) selectedSub=\(String(describing: selectedSubtitleIndex)))")
                #endif
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
            // On error, tear down the old player (which is still running) and show error
            teardownPlayer()
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if let dur = self.player?.currentItem?.duration, dur.isNumeric {
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
