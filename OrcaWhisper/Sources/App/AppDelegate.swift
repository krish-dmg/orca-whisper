import AppKit
import os
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyStateMachineDelegate {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "AppDelegate")

    private var menuBarManager: MenuBarManager?
    private var hotkeyManager: GlobalHotkeyManager?
    private let stateMachine = HotkeyStateMachine()
    private let audioRecorder = AudioRecorder()
    private let dictationClient = DictationClient()
    private let timingTracker = TimingTracker()
    private let pasteManager = PasteManager.shared
    private let notificationManager = NotificationManager.shared
    private let settings = AppSettings.shared
    private let cuePlayer = AudioCuePlayer.shared

    private var cancellables = Set<AnyCancellable>()
    private var isExplicitQuitAllowed = false
    private var recordingStartTime: Date?
    private var targetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce accessory policy by default (unless user opted to show Dock icon)
        if !settings.showDockIcon {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        // Prevent macOS from killing the app in background
        ProcessInfo.processInfo.disableAutomaticTermination("Voice dictation background service")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Setup menu bar item
        let manager = MenuBarManager()
        manager.onQuitRequested = { [weak self] in
            self?.quitAppExplicitly()
        }
        self.menuBarManager = manager

        // Setup state machine & hotkey manager
        stateMachine.delegate = self
        syncSettingsToStateMachine()

        let hotkey = GlobalHotkeyManager(stateMachine: stateMachine)
        hotkey.trigger = .singleModifier(settings.selectedModifier)
        hotkey.start()
        self.hotkeyManager = hotkey

        // Listen for settings changes and manual trigger notifications
        bindSettingsChanges()
        setupNotificationObservers()

        // Check permissions on launch
        checkInitialPermissions()

        // Stream real-time audio amplitude to floating HUD
        audioRecorder.onAudioLevelChange = { level in
            FloatingHUDController.shared.updateAudioLevel(level)
        }

        // Show main window on launch
        MainWindowController.shared.showWindow()

        logger.info("Orca Whisper application launched successfully.")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen from Finder, Spotlight, or Dock shows the main window
        hotkeyManager?.ensureEventTapActive()
        MainWindowController.shared.showWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hotkeyManager?.ensureEventTapActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the main window must never quit the application
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q or window close closes the main window and does not quit the app
        if isExplicitQuitAllowed {
            return .terminateNow
        }
        MainWindowController.shared.hideWindow()
        logger.debug("Cmd+Q or system termination intercepted: hiding main window instead.")
        return .terminateCancel
    }

    func quitAppExplicitly() {
        logger.info("User requested application termination via menu item.")
        isExplicitQuitAllowed = true
        hotkeyManager?.stop()
        audioRecorder.cancelRecording()
        NSApp.terminate(nil)
    }

    private func bindSettingsChanges() {
        settings.$selectedModifier
            .sink { [weak self] newMod in
                self?.hotkeyManager?.trigger = .singleModifier(newMod)
            }
            .store(in: &cancellables)

        settings.$hotkeyMode
            .sink { [weak self] newMode in
                self?.stateMachine.mode = newMode
            }
            .store(in: &cancellables)

        settings.$tapThreshold
            .sink { [weak self] ms in
                self?.stateMachine.tapThreshold = ms / 1000.0
            }
            .store(in: &cancellables)

        settings.$doubleTapWindow
            .sink { [weak self] ms in
                self?.stateMachine.doubleTapWindow = ms / 1000.0
            }
            .store(in: &cancellables)

        settings.$maxRecordingDuration
            .sink { [weak self] sec in
                self?.stateMachine.maxRecordingDuration = sec
            }
            .store(in: &cancellables)

        settings.$escapeToCancel
            .sink { [weak self] esc in
                self?.stateMachine.escapeToCancel = esc
            }
            .store(in: &cancellables)
    }

    private func syncSettingsToStateMachine() {
        stateMachine.tapThreshold = settings.tapThreshold / 1000.0
        stateMachine.doubleTapWindow = settings.doubleTapWindow / 1000.0
        stateMachine.maxRecordingDuration = settings.maxRecordingDuration
        stateMachine.mode = settings.hotkeyMode
        stateMachine.escapeToCancel = settings.escapeToCancel
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerStartRecording"), object: nil, queue: .main) { [weak self] _ in
            self?.handleStartRecording(isLatched: true)
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerStopRecording"), object: nil, queue: .main) { [weak self] _ in
            self?.handleStopAndSendRecording()
        }
    }

    private func checkInitialPermissions() {
        let micStatus = PermissionsHelper.shared.microphoneStatus()
        if micStatus == .notDetermined {
            PermissionsHelper.shared.requestMicrophoneAccess { [weak self] granted in
                if !granted {
                    self?.notificationManager.showNotification(
                        title: "Microphone Access Required",
                        body: "Orca Whisper needs microphone permission to capture audio for transcription."
                    )
                }
            }
        }

        if !PermissionsHelper.shared.isAccessibilityGranted() {
            PermissionsHelper.shared.requestAccessibilityPrompt()
        }
    }

    // MARK: - HotkeyStateMachineDelegate

    func stateMachine(_ sm: HotkeyStateMachine, didProduceAction action: StateMachineAction) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch action {
            case .startRecording(let isLatched):
                self.handleStartRecording(isLatched: isLatched)

            case .stopAndDiscardRecording:
                self.handleDiscardRecording()

            case .stopAndSendRecording:
                self.handleStopAndSendRecording()

            case .stateChanged(let state):
                self.handleStateChanged(state)
            }
        }
    }

    private func handleStartRecording(isLatched: Bool) {
        timingTracker.reset()
        recordingStartTime = Date()

        // Capture frontmost application before recording starts
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.targetApplication = frontApp
            logger.info("Captured target application for dictation: \(frontApp.localizedName ?? "unknown", privacy: .public)")
        }

        AppState.shared.updateStatus(isLatched ? .recordingLatched : .recordingHold)
        FloatingHUDController.shared.show(state: .listening(isLatched: isLatched))
        cuePlayer.playStartCue()

        do {
            _ = try audioRecorder.startRecording(
                deviceUID: settings.selectedAudioDeviceUID.isEmpty ? nil : settings.selectedAudioDeviceUID,
                bitRate: settings.aacBitRate
            )
        } catch {
            logger.error("Failed to start audio recording: \(error.localizedDescription)")
            AppState.shared.setError("Audio hardware error")
            FloatingHUDController.shared.show(state: .error("Mic Error"))
            notificationManager.showNotification(
                title: "Recording Error",
                body: "Unable to access microphone: \(error.localizedDescription)"
            )
            stateMachine.reset()
        }
    }

    private func handleDiscardRecording() {
        audioRecorder.cancelRecording()
        recordingStartTime = nil
        AppState.shared.updateStatus(.idle)
        FloatingHUDController.shared.hide()
        cuePlayer.playCancelCue()
    }

    private func handleStopAndSendRecording() {
        timingTracker.markKeyRelease()
        cuePlayer.playStopCue()

        // Check minimum recording length
        if let start = recordingStartTime {
            let durationMs = Date().timeIntervalSince(start) * 1000.0
            if durationMs < settings.minRecordingLengthMs {
                logger.debug("Speech duration (\(durationMs) ms) shorter than minimum threshold. Discarding.")
                audioRecorder.cancelRecording()
                recordingStartTime = nil
                AppState.shared.updateStatus(.idle)
                FloatingHUDController.shared.hide()
                stateMachine.setProcessingFinished()
                return
            }
        }

        guard let audioURL = audioRecorder.stopRecording() else {
            AppState.shared.updateStatus(.idle)
            FloatingHUDController.shared.hide()
            stateMachine.setProcessingFinished()
            return
        }

        timingTracker.markAudioReady()
        AppState.shared.updateStatus(.processing)
        FloatingHUDController.shared.show(state: .transcribing)

        let endpoint = settings.endpointURL
        let token = settings.bearerToken
        let timeout = settings.requestTimeout
        let retries = settings.retryCount
        let retry5xx = settings.retryOn5xxOnly
        let useRaw = settings.payloadFormatRaw

        let delivery = settings.deliveryMode
        let restoreClip = settings.restoreClipboard
        let restoreDelay = settings.restoreDelayMs
        let addSpace = settings.addTrailingSpace
        let addNewline = settings.addTrailingNewline
        let prefix = settings.prefixText
        let suffix = settings.suffixText

        Task {
            defer {
                self.audioRecorder.deleteFile(at: audioURL)
                self.stateMachine.setProcessingFinished()
                self.recordingStartTime = nil
                self.targetApplication = nil
            }

            self.timingTracker.markUploadStart()

            do {
                let transcription = try await self.dictationClient.transcribe(
                    fileURL: audioURL,
                    endpointURLString: endpoint,
                    token: token,
                    timeout: timeout,
                    maxRetries: retries,
                    retryOn5xxOnly: retry5xx,
                    useRawAudio: useRaw
                )
                self.timingTracker.markResponseReceived()

                if transcription.isEmpty {
                    self.logger.debug("Received empty transcription from remote model.")
                    await MainActor.run {
                        AppState.shared.updateStatus(.idle)
                        FloatingHUDController.shared.hide()
                        self.notificationManager.showNotification(
                            title: "Dictation Empty",
                            body: "No audible speech was recognized."
                        )
                    }
                    return
                }

                await MainActor.run {
                    self.pasteManager.deliver(
                        text: transcription,
                        targetApp: self.targetApplication,
                        deliveryMode: delivery,
                        restoreClipboard: restoreClip,
                        restoreDelayMs: restoreDelay,
                        addTrailingSpace: addSpace,
                        addTrailingNewline: addNewline,
                        prefixText: prefix,
                        suffixText: suffix
                    )
                    let timing = self.timingTracker.markPasteComplete()
                    AppState.shared.setTranscription(transcription, timing: timing)
                    FloatingHUDController.shared.show(state: .done)
                }

            } catch {
                self.logger.error("Transcription error: \(error.localizedDescription)")
                await MainActor.run {
                    AppState.shared.setError(error.localizedDescription)
                    FloatingHUDController.shared.show(state: .error("Transcription Failed"))
                    self.notificationManager.showNotification(
                        title: "Dictation Error",
                        body: error.localizedDescription
                    )
                }
            }
        }
    }

    private func handleStateChanged(_ state: HotkeyState) {
        switch state {
        case .idle:
            AppState.shared.updateStatus(.idle)
        case .holding:
            AppState.shared.updateStatus(.recordingHold)
        case .waitingForSecondTap:
            AppState.shared.updateStatus(.idle)
        case .latched:
            AppState.shared.updateStatus(.recordingLatched)
        case .processing:
            AppState.shared.updateStatus(.processing)
        }
    }
}
