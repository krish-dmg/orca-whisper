import AppKit
import SwiftUI
import Combine

final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private var openWindowMenuItem: NSMenuItem!
    private var stateMenuItem: NSMenuItem!
    private var transcriptionPreviewMenuItem: NSMenuItem!
    private var copyTranscriptionMenuItem: NSMenuItem!
    private var timingMenuItem: NSMenuItem!
    private var separatorItem1: NSMenuItem!
    private var separatorItem2: NSMenuItem!
    private var quitMenuItem: NSMenuItem!

    private var cancellables = Set<AnyCancellable>()

    var onQuitRequested: (() -> Void)?

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        bindAppState()
        bindSettings()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(AppState.shared.status)
        statusItem?.menu = menu
    }

    private func setupMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        openWindowMenuItem = NSMenuItem(title: "Open Orca Whisper…", action: #selector(openMainWindow), keyEquivalent: "")
        openWindowMenuItem.target = self
        menu.addItem(openWindowMenuItem)

        stateMenuItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)

        separatorItem1 = NSMenuItem.separator()
        menu.addItem(separatorItem1)

        transcriptionPreviewMenuItem = NSMenuItem(title: "Last: (None)", action: nil, keyEquivalent: "")
        transcriptionPreviewMenuItem.isEnabled = false
        menu.addItem(transcriptionPreviewMenuItem)

        copyTranscriptionMenuItem = NSMenuItem(title: "Copy Last Transcription", action: #selector(copyLastTranscription), keyEquivalent: "")
        copyTranscriptionMenuItem.target = self
        copyTranscriptionMenuItem.isEnabled = false
        menu.addItem(copyTranscriptionMenuItem)

        timingMenuItem = NSMenuItem(title: "Timing: None", action: nil, keyEquivalent: "")
        timingMenuItem.isEnabled = false
        menu.addItem(timingMenuItem)

        separatorItem2 = NSMenuItem.separator()
        menu.addItem(separatorItem2)

        // "Quit OrcaWhisper" is the only way to quit the application. No Cmd+Q key equivalent.
        quitMenuItem = NSMenuItem(title: "Quit OrcaWhisper", action: #selector(quitClicked), keyEquivalent: "")
        quitMenuItem.target = self
        quitMenuItem.isEnabled = true
        menu.addItem(quitMenuItem)
    }

    private func bindAppState() {
        AppState.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateStatusUI(status)
            }
            .store(in: &cancellables)

        AppState.shared.$lastTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcription in
                self?.updateTranscriptionUI(transcription)
            }
            .store(in: &cancellables)

        AppState.shared.$lastTiming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timing in
                self?.updateTimingUI(timing)
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        AppSettings.shared.$menuBarIconStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon(AppState.shared.status)
            }
            .store(in: &cancellables)

        AppSettings.shared.$showTimingInMenu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                self?.timingMenuItem.isHidden = !show
            }
            .store(in: &cancellables)

        AppSettings.shared.$showTranscriptInMenu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                self?.transcriptionPreviewMenuItem.isHidden = !show
                self?.copyTranscriptionMenuItem.isHidden = !show
            }
            .store(in: &cancellables)
    }

    private func updateStatusUI(_ status: AppStatus) {
        stateMenuItem.title = status.description
        updateStatusIcon(status)
    }

    private func updateStatusIcon(_ status: AppStatus) {
        guard let button = statusItem?.button else { return }

        if AppSettings.shared.menuBarIconStyle == .logo {
            let isRec = (status == .recordingHold || status == .recordingLatched)
            let icon = MenuBarIconDrawer.createOrcaIcon(isRecording: isRec)
            button.image = icon
            button.imagePosition = .imageOnly
            return
        }

        let iconName: String
        switch status {
        case .idle:
            iconName = "mic"
        case .recordingHold:
            iconName = "record.circle.fill"
        case .recordingLatched:
            iconName = "waveform.circle.fill"
        case .processing:
            iconName = "arrow.triangle.2.circlepath"
        case .error:
            iconName = "exclamationmark.triangle"
        }

        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: status.description)
        image?.isTemplate = (status != .recordingHold)
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func updateTranscriptionUI(_ text: String?) {
        guard let text = text, !text.isEmpty else {
            transcriptionPreviewMenuItem.title = "Last: (None)"
            copyTranscriptionMenuItem.isEnabled = false
            return
        }

        let preview = text.count > 40 ? String(text.prefix(37)) + "..." : text
        transcriptionPreviewMenuItem.title = "Last: \"\(preview)\""
        copyTranscriptionMenuItem.isEnabled = true
    }

    private func updateTimingUI(_ timing: DictationTiming?) {
        guard let timing = timing else {
            timingMenuItem.title = "Timing: None"
            return
        }
        timingMenuItem.title = timing.menuSummary
    }

    @objc func openMainWindow() {
        MainWindowController.shared.showWindow()
    }

    @objc private func copyLastTranscription() {
        guard let text = AppState.shared.lastTranscription, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func quitClicked() {
        onQuitRequested?()
    }
}
