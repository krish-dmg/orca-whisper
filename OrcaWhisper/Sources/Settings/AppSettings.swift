import Foundation
import ServiceManagement
import AVFoundation
import AppKit
import os

enum HotkeyMode: String, CaseIterable, Identifiable, Codable {
    case holdAndDoubleTap = "Hold & Double-Tap Latch"
    case toggleTap = "Toggle (Tap to Start / Tap to Stop)"

    var id: String { rawValue }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Codable {
    case logo = "Orca Fin Logo"
    case sfSymbol = "Microphone SF Symbol"

    var id: String { rawValue }
}

enum DeliveryMode: String, CaseIterable, Identifiable, Codable {
    case paste = "Clipboard Paste (Cmd+V)"
    case typeDirectly = "Type Characters Directly"

    var id: String { rawValue }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let logger = Logger(subsystem: "com.orca.whisper", category: "AppSettings")
    private let keychain = KeychainHelper.shared

    // Default credentials (empty for open source; configure your own Cloudflare Worker)
    static let defaultEndpointURL = ""
    static let defaultBearerToken = ""

    private let keychainEndpointKey = "remoteEndpointURL"
    private let keychainTokenKey = "bearerAuthToken"

    // Hotkey & Trigger
    @Published var selectedModifier: ModifierKey {
        didSet { UserDefaults.standard.set(selectedModifier.rawValue, forKey: "hotkeyModifier") }
    }
    @Published var hotkeyMode: HotkeyMode {
        didSet { UserDefaults.standard.set(hotkeyMode.rawValue, forKey: "hotkeyMode") }
    }
    @Published var tapThreshold: Double {
        didSet { UserDefaults.standard.set(tapThreshold, forKey: "tapThreshold") }
    }
    @Published var doubleTapWindow: Double {
        didSet { UserDefaults.standard.set(doubleTapWindow, forKey: "doubleTapWindow") }
    }
    @Published var maxRecordingDuration: Double {
        didSet { UserDefaults.standard.set(maxRecordingDuration, forKey: "maxRecordingDuration") }
    }
    @Published var escapeToCancel: Bool {
        didSet { UserDefaults.standard.set(escapeToCancel, forKey: "escapeToCancel") }
    }

    // Audio & Recording
    @Published var selectedAudioDeviceUID: String {
        didSet { UserDefaults.standard.set(selectedAudioDeviceUID, forKey: "audioDeviceUID") }
    }
    @Published var aacBitRate: Int {
        didSet { UserDefaults.standard.set(aacBitRate, forKey: "aacBitRate") }
    }
    @Published var minRecordingLengthMs: Double {
        didSet { UserDefaults.standard.set(minRecordingLengthMs, forKey: "minRecordingLengthMs") }
    }
    @Published var playAudioCues: Bool {
        didSet { UserDefaults.standard.set(playAudioCues, forKey: "playAudioCues") }
    }

    // Network & Transcription
    @Published var endpointURL: String {
        didSet { _ = keychain.save(key: keychainEndpointKey, value: endpointURL) }
    }
    @Published var bearerToken: String {
        didSet { _ = keychain.save(key: keychainTokenKey, value: bearerToken) }
    }
    @Published var requestTimeout: Double {
        didSet { UserDefaults.standard.set(requestTimeout, forKey: "requestTimeout") }
    }
    @Published var retryCount: Int {
        didSet { UserDefaults.standard.set(retryCount, forKey: "retryCount") }
    }
    @Published var retryOn5xxOnly: Bool {
        didSet { UserDefaults.standard.set(retryOn5xxOnly, forKey: "retryOn5xxOnly") }
    }
    @Published var payloadFormatRaw: Bool {
        didSet { UserDefaults.standard.set(payloadFormatRaw, forKey: "payloadFormatRaw") }
    }

    // Delivery & Output
    @Published var deliveryMode: DeliveryMode {
        didSet {
            UserDefaults.standard.set(true, forKey: "hasSetCustomDeliveryMode")
            UserDefaults.standard.set(deliveryMode.rawValue, forKey: "deliveryMode")
        }
    }
    @Published var restoreClipboard: Bool {
        didSet { UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    @Published var restoreDelayMs: Double {
        didSet { UserDefaults.standard.set(restoreDelayMs, forKey: "restoreDelayMs") }
    }
    @Published var addTrailingSpace: Bool {
        didSet { UserDefaults.standard.set(addTrailingSpace, forKey: "addTrailingSpace") }
    }
    @Published var addTrailingNewline: Bool {
        didSet { UserDefaults.standard.set(addTrailingNewline, forKey: "addTrailingNewline") }
    }
    @Published var prefixText: String {
        didSet { UserDefaults.standard.set(prefixText, forKey: "prefixText") }
    }
    @Published var suffixText: String {
        didSet { UserDefaults.standard.set(suffixText, forKey: "suffixText") }
    }

    // Appearance & System
    @Published var showFloatingHUD: Bool {
        didSet { UserDefaults.standard.set(showFloatingHUD, forKey: "showFloatingHUD") }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle") }
    }
    @Published var showTimingInMenu: Bool {
        didSet { UserDefaults.standard.set(showTimingInMenu, forKey: "showTimingInMenu") }
    }
    @Published var showTranscriptInMenu: Bool {
        didSet { UserDefaults.standard.set(showTranscriptInMenu, forKey: "showTranscriptInMenu") }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyDockIconVisibility(showDockIcon)
        }
    }
    @Published var logLevel: String {
        didSet { UserDefaults.standard.set(logLevel, forKey: "logLevel") }
    }

    private init() {
        let savedURL = keychain.load(key: keychainEndpointKey) ?? ""
        let savedToken = keychain.load(key: keychainTokenKey) ?? ""

        self.endpointURL = savedURL
        self.bearerToken = savedToken

        if let raw = UserDefaults.standard.string(forKey: "hotkeyModifier"), let mod = ModifierKey(rawValue: raw) {
            self.selectedModifier = mod
        } else {
            self.selectedModifier = .rightOption
        }

        if let raw = UserDefaults.standard.string(forKey: "hotkeyMode"), let mode = HotkeyMode(rawValue: raw) {
            self.hotkeyMode = mode
        } else {
            self.hotkeyMode = .holdAndDoubleTap
        }

        let tap = UserDefaults.standard.double(forKey: "tapThreshold")
        self.tapThreshold = tap > 0 ? tap : 250.0

        let dTap = UserDefaults.standard.double(forKey: "doubleTapWindow")
        self.doubleTapWindow = dTap > 0 ? dTap : 350.0

        let maxRec = UserDefaults.standard.double(forKey: "maxRecordingDuration")
        self.maxRecordingDuration = maxRec > 0 ? maxRec : 300.0

        self.escapeToCancel = UserDefaults.standard.object(forKey: "escapeToCancel") == nil ? true : UserDefaults.standard.bool(forKey: "escapeToCancel")

        self.selectedAudioDeviceUID = UserDefaults.standard.string(forKey: "audioDeviceUID") ?? ""

        let bitRate = UserDefaults.standard.integer(forKey: "aacBitRate")
        self.aacBitRate = bitRate > 0 ? bitRate : 32000

        let minRec = UserDefaults.standard.double(forKey: "minRecordingLengthMs")
        self.minRecordingLengthMs = minRec > 0 ? minRec : 400.0

        self.playAudioCues = UserDefaults.standard.object(forKey: "playAudioCues") == nil ? true : UserDefaults.standard.bool(forKey: "playAudioCues")

        let timeout = UserDefaults.standard.double(forKey: "requestTimeout")
        self.requestTimeout = timeout > 0 ? timeout : 30.0

        let retries = UserDefaults.standard.integer(forKey: "retryCount")
        self.retryCount = retries >= 0 ? retries : 1

        self.retryOn5xxOnly = UserDefaults.standard.object(forKey: "retryOn5xxOnly") == nil ? true : UserDefaults.standard.bool(forKey: "retryOn5xxOnly")
        self.payloadFormatRaw = UserDefaults.standard.object(forKey: "payloadFormatRaw") == nil ? true : UserDefaults.standard.bool(forKey: "payloadFormatRaw")

        if UserDefaults.standard.object(forKey: "hasSetCustomDeliveryMode") == nil {
            self.deliveryMode = .typeDirectly
        } else if let raw = UserDefaults.standard.string(forKey: "deliveryMode"), let del = DeliveryMode(rawValue: raw) {
            self.deliveryMode = del
        } else {
            self.deliveryMode = .typeDirectly
        }

        self.restoreClipboard = UserDefaults.standard.object(forKey: "restoreClipboard") == nil ? false : UserDefaults.standard.bool(forKey: "restoreClipboard")

        let restoreDel = UserDefaults.standard.double(forKey: "restoreDelayMs")
        self.restoreDelayMs = restoreDel > 0 ? restoreDel : 300.0

        self.addTrailingSpace = UserDefaults.standard.bool(forKey: "addTrailingSpace")
        self.addTrailingNewline = UserDefaults.standard.bool(forKey: "addTrailingNewline")
        self.prefixText = UserDefaults.standard.string(forKey: "prefixText") ?? ""
        self.suffixText = UserDefaults.standard.string(forKey: "suffixText") ?? ""

        self.showFloatingHUD = UserDefaults.standard.object(forKey: "showFloatingHUD") == nil ? true : UserDefaults.standard.bool(forKey: "showFloatingHUD")

        if let raw = UserDefaults.standard.string(forKey: "menuBarIconStyle"), let iconStyle = MenuBarIconStyle(rawValue: raw) {
            self.menuBarIconStyle = iconStyle
        } else {
            self.menuBarIconStyle = .logo
        }

        self.showTimingInMenu = UserDefaults.standard.object(forKey: "showTimingInMenu") == nil ? true : UserDefaults.standard.bool(forKey: "showTimingInMenu")
        self.showTranscriptInMenu = UserDefaults.standard.object(forKey: "showTranscriptInMenu") == nil ? true : UserDefaults.standard.bool(forKey: "showTranscriptInMenu")

        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        self.logLevel = UserDefaults.standard.string(forKey: "logLevel") ?? "debug"

        if UserDefaults.standard.object(forKey: "hasConfiguredLaunchAtLogin") == nil {
            UserDefaults.standard.set(true, forKey: "hasConfiguredLaunchAtLogin")
            self.launchAtLogin = true
            applyLaunchAtLogin(true)
        }

        if showDockIcon {
            applyDockIconVisibility(true)
        }
    }

    func resetToDefaults() {
        endpointURL = Self.defaultEndpointURL
        bearerToken = Self.defaultBearerToken
        selectedModifier = .rightOption
        hotkeyMode = .holdAndDoubleTap
        tapThreshold = 250.0
        doubleTapWindow = 350.0
        maxRecordingDuration = 300.0
        escapeToCancel = true
        selectedAudioDeviceUID = ""
        aacBitRate = 32000
        minRecordingLengthMs = 400.0
        playAudioCues = true
        requestTimeout = 30.0
        retryCount = 1
        retryOn5xxOnly = true
        payloadFormatRaw = true
        deliveryMode = .paste
        restoreClipboard = true
        restoreDelayMs = 300.0
        addTrailingSpace = false
        addTrailingNewline = false
        prefixText = ""
        suffixText = ""
        menuBarIconStyle = .logo
        showTimingInMenu = true
        showTranscriptInMenu = true
        showDockIcon = false
        logLevel = "debug"
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered app with SMAppService.")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    logger.info("Unregistered app from SMAppService.")
                }
            }
        } catch {
            logger.error("Failed to update SMAppService: \(error.localizedDescription)")
        }
    }

    private func applyDockIconVisibility(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
