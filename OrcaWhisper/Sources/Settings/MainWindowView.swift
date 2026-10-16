import SwiftUI
import AVFoundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case hotkey = "Hotkey"
    case recording = "Recording"
    case transcription = "Transcription"
    case output = "Output"
    case appearance = "Appearance"
    case general = "General"
    case privacy = "Privacy"
    case diagnostics = "Diagnostics"
    case about = "About"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .overview: return "waveform"
        case .hotkey: return "command"
        case .recording: return "mic"
        case .transcription: return "antenna.radiowaves.left.and.right"
        case .output: return "doc.on.clipboard"
        case .appearance: return "sparkles"
        case .general: return "gearshape"
        case .privacy: return "lock.shield"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var appState = AppState.shared
    @State private var selectedSection: SidebarSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.iconName)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedSection ?? .overview {
                case .overview:
                    OverviewSectionView()
                case .hotkey:
                    HotkeySectionView()
                case .recording:
                    RecordingSectionView()
                case .transcription:
                    TranscriptionSectionView()
                case .output:
                    OutputSectionView()
                case .appearance:
                    AppearanceSectionView()
                case .general:
                    GeneralSectionView()
                case .privacy:
                    PrivacySectionView()
                case .diagnostics:
                    DiagnosticsSectionView()
                case .about:
                    AboutSectionView()
                }
            }
            .frame(minWidth: 480, idealWidth: 540, maxWidth: .infinity, minHeight: 450, idealHeight: 550, maxHeight: .infinity)
            .padding(20)
        }
    }
}

// MARK: - 1. Overview Section
struct OverviewSectionView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var isTestSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview")
                    .font(.title2.bold())

                if !PermissionsHelper.shared.isAccessibilityGranted() {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Accessibility Permission Required to Paste")
                                .font(.headline)
                            Spacer()
                            Button("Enable in Settings") {
                                PermissionsHelper.shared.requestAccessibilityPrompt()
                                PermissionsHelper.shared.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("macOS prevents Orca Whisper from pasting transcribed text into Terminal, browsers, or other apps until you enable OrcaWhisper in System Settings > Privacy & Security > Accessibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                    )
                }

                // Status Banner
                GroupBox("Current Status") {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(appState.status.description)
                            .font(.headline)
                        Spacer()

                        Button(isRecordingActive ? "Stop Dictation" : "Test Recording") {
                            toggleManualRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecordingActive ? .red : .accentColor)
                    }
                    .padding(6)
                }

                // Last Transcription
                GroupBox("Last Transcript") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let text = appState.lastTranscription, !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)

                            HStack {
                                Spacer()
                                Button("Copy to Clipboard") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(text, forType: .string)
                                }
                            }
                        } else {
                            Text("No transcriptions recorded yet.")
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(6)
                        }
                    }
                    .padding(4)
                }

                // Timing Breakdown
                GroupBox("Timing Breakdown") {
                    if let timing = appState.lastTiming {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("Total Latency:").bold()
                                Text(String(format: "%.2f s", timing.totalDuration))
                            }
                            GridRow {
                                Text("Audio Encoding:")
                                Text(String(format: "%.2f s", timing.audioFinalizeDuration))
                            }
                            GridRow {
                                Text("Worker & AI Inference:")
                                Text(String(format: "%.2f s", timing.uploadDuration))
                            }
                            GridRow {
                                Text("Text Insertion:")
                                Text(String(format: "%.2f s", timing.pasteDuration))
                            }
                        }
                        .padding(6)
                    } else {
                        Text("No timing metrics available yet.")
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }

                // Connection Test
                GroupBox("Cloudflare Worker Connectivity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(action: runConnectionTest) {
                                if isTesting {
                                    ProgressView().controlSize(.small).padding(.trailing, 4)
                                }
                                Text("Test Worker Connection")
                            }
                            .disabled(isTesting || settings.endpointURL.isEmpty)

                            if let res = testResult {
                                Text(res)
                                    .font(.callout)
                                    .foregroundStyle(isTestSuccess ? .green : .red)
                                    .padding(.leading, 8)
                            }
                        }
                        Text("Target: \(settings.endpointURL)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
            }
        }
    }

    private var isRecordingActive: Bool {
        switch appState.status {
        case .recordingHold, .recordingLatched: return true
        default: return false
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .green
        case .recordingHold, .recordingLatched: return .red
        case .processing: return .orange
        case .error: return .yellow
        }
    }

    private func toggleManualRecording() {
        if isRecordingActive {
            NotificationCenter.default.post(name: NSNotification.Name("TriggerStopRecording"), object: nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("TriggerStartRecording"), object: nil)
        }
    }

    private func runConnectionTest() {
        isTesting = true
        testResult = nil
        isTestSuccess = false

        Task {
            let client = DictationClient()
            do {
                let msg = try await client.testConnection(
                    endpointURLString: settings.endpointURL,
                    token: settings.bearerToken
                )
                await MainActor.run {
                    self.isTesting = false
                    self.isTestSuccess = true
                    self.testResult = msg
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.isTestSuccess = false
                    self.testResult = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 2. Hotkey Section
struct HotkeySectionView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Trigger Key") {
                Picker("Modifier Key", selection: $settings.selectedModifier) {
                    ForEach(ModifierKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .pickerStyle(.menu)

                Picker("Activation Mode", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            }

            Section("Timing & Gestures") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hold vs Tap Threshold")
                        Spacer()
                        Text("\(Int(settings.tapThreshold)) ms").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.tapThreshold, in: 100...500, step: 25)
                    Text("Presses shorter than this count as a tap. Longer presses start a push-to-talk hold.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Double-Tap Window")
                        Spacer()
                        Text("\(Int(settings.doubleTapWindow)) ms").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.doubleTapWindow, in: 200...700, step: 25)
                    Text("Two taps within this window start latched hands-free recording.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recording Safety Cap")
                        Spacer()
                        Text("\(Int(settings.maxRecordingDuration)) s (\(Int(settings.maxRecordingDuration / 60)) min)").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.maxRecordingDuration, in: 60...900, step: 60)
                    Text("Automatically finalizes and sends audio when the cap is reached.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Toggle("Cancel recording on Escape key", isOn: $settings.escapeToCancel)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 3. Recording Section
struct RecordingSectionView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var availableDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section("Audio Input Device") {
                Picker("Microphone", selection: $settings.selectedAudioDeviceUID) {
                    Text("System Default Microphone").tag("")
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onAppear {
                    availableDevices = AudioRecorder.availableInputDevices()
                }

                HStack {
                    Text("Sample Rate")
                    Spacer()
                    Text("16.0 kHz Mono (Whisper Native)")
                        .foregroundStyle(.secondary)
                }

                Picker("AAC Encoding Bitrate", selection: $settings.aacBitRate) {
                    Text("16 kbps (Smallest footprint)").tag(16000)
                    Text("32 kbps (Recommended)").tag(32000)
                    Text("48 kbps (Higher fidelity)").tag(48000)
                    Text("64 kbps (Maximum fidelity)").tag(64000)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Minimum Speech Length")
                        Spacer()
                        Text("\(Int(settings.minRecordingLengthMs)) ms").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.minRecordingLengthMs, in: 200...1000, step: 50)
                    Text("Recordings shorter than this duration are discarded without querying the model.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Toggle("Play start and stop sound cues", isOn: $settings.playAudioCues)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 4. Transcription Section
struct TranscriptionSectionView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showToken = false

    var body: some View {
        Form {
            Section("Remote Worker Endpoint") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://...", text: $settings.endpointURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bearer Token").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(showToken ? "Hide" : "Reveal") {
                            showToken.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    if showToken {
                        TextField("Worker secret", text: $settings.bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Worker secret", text: $settings.bearerToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("Pre-configured and encrypted in macOS Keychain.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("Network Policy") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Request Timeout")
                        Spacer()
                        Text("\(Int(settings.requestTimeout)) s").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.requestTimeout, in: 10...60, step: 5)
                }

                Picker("Retry Attempts", selection: $settings.retryCount) {
                    Text("None (0)").tag(0)
                    Text("1 Retry (Default)").tag(1)
                    Text("2 Retries").tag(2)
                }

                Toggle("Retry only on 5xx server errors", isOn: $settings.retryOn5xxOnly)

                Picker("Audio Payload Format", selection: $settings.payloadFormatRaw) {
                    Text("Raw Audio Body (audio/m4a)").tag(true)
                    Text("Multipart Form Data (file field)").tag(false)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 5. Output Section
struct OutputSectionView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Text Delivery Method") {
                Picker("Mode", selection: $settings.deliveryMode) {
                    ForEach(DeliveryMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.deliveryMode == .paste {
                    Toggle("Restore clipboard contents after pasting", isOn: $settings.restoreClipboard)
                    if settings.restoreClipboard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Clipboard Restore Delay")
                                Spacer()
                                Text("\(Int(settings.restoreDelayMs)) ms").foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.restoreDelayMs, in: 150...800, step: 50)
                            Text("Time granted to the target app to consume Cmd+V before previous clipboard is restored.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Formatting & Spacing") {
                Toggle("Append trailing space after dictation", isOn: $settings.addTrailingSpace)
                Toggle("Append trailing newline after dictation", isOn: $settings.addTrailingNewline)

                HStack {
                    Text("Text Prefix")
                    Spacer()
                    TextField("None", text: $settings.prefixText)
                        .frame(width: 180)
                }

                HStack {
                    Text("Text Suffix")
                    Spacer()
                    TextField("None", text: $settings.suffixText)
                        .frame(width: 180)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 6. Appearance Section
struct AppearanceSectionView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Menu Bar Presentation") {
                Picker("Menu Bar Icon Style", selection: $settings.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }

                Toggle("Show latency metrics in status menu", isOn: $settings.showTimingInMenu)
                Toggle("Show latest transcript snippet in status menu", isOn: $settings.showTranscriptInMenu)
            }

            Section("On-Screen Visual Indicators") {
                Toggle("Show floating status pill during dictation", isOn: $settings.showFloatingHUD)
                Text("Displays an elegant floating indicator showing when Orca Whisper is listening, transcribing, and finished.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 7. General Section
struct GeneralSectionView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("System & Startup") {
                Toggle("Launch Orca Whisper at login", isOn: $settings.launchAtLogin)
                Toggle("Show icon in macOS Dock", isOn: $settings.showDockIcon)
                Text("When disabled, Orca Whisper runs purely as a menu bar accessory.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Factory Reset") {
                Button("Reset All Settings to Defaults", role: .destructive) {
                    showResetConfirmation = true
                }
                .confirmationDialog("Reset all configurations?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                    Button("Reset Settings", role: .destructive) {
                        settings.resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This restores all hotkey, timing, audio, and network preferences back to factory defaults.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 8. Privacy Section
struct PrivacySectionView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var hasClearedTranscript = false
    @State private var hasClearedKeychain = false

    var body: some View {
        Form {
            Section("Data & Transcripts") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In-Memory Transcript")
                        Text("Orca Whisper keeps only the most recent transcript in RAM.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(hasClearedTranscript ? "Cleared" : "Clear Now") {
                        appState.lastTranscription = nil
                        hasClearedTranscript = true
                    }
                    .disabled(hasClearedTranscript)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keychain Credentials")
                        Text("Removes saved Worker URL and Bearer token from macOS Keychain.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(hasClearedKeychain ? "Reset" : "Reset Keychain") {
                        _ = KeychainHelper.shared.delete(key: "remoteEndpointURL")
                        _ = KeychainHelper.shared.delete(key: "bearerAuthToken")
                        hasClearedKeychain = true
                    }
                    .disabled(hasClearedKeychain)
                }
            }

            Section("Data Transmission Notice") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What leaves this Mac")
                        .font(.headline)
                    Text("Audio captured during dictation is compressed locally into AAC (M4A) and transmitted directly to your personal Cloudflare Worker over encrypted TLS. No audio, telemetry, keystrokes, or transcripts are stored on disk or sent to any third parties.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 9. Diagnostics Section
struct DiagnosticsSectionView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var copiedStatus = false

    var body: some View {
        Form {
            Section("Permissions Status") {
                HStack {
                    Text("Microphone Access")
                    Spacer()
                    if PermissionsHelper.shared.microphoneStatus() == .granted {
                        Text("Granted").foregroundStyle(.green).bold()
                    } else {
                        Button("Open Settings") {
                            PermissionsHelper.shared.openSystemSettingsMicrophone()
                        }
                    }
                }

                HStack {
                    Text("Accessibility & Paste")
                    Spacer()
                    if PermissionsHelper.shared.isAccessibilityGranted() {
                        Text("Granted").foregroundStyle(.green).bold()
                    } else {
                        Button("Open Settings") {
                            PermissionsHelper.shared.requestAccessibilityPrompt()
                            PermissionsHelper.shared.openSystemSettingsAccessibility()
                        }
                    }
                }
            }

            Section("Diagnostics & Logging") {
                Picker("Logging Level", selection: $settings.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Notice").tag("notice")
                    Text("Error").tag("error")
                }

                HStack {
                    Text("Export System Status")
                    Spacer()
                    Button(copiedStatus ? "Copied to Clipboard" : "Export Diagnostic Report") {
                        copyDiagnosticReport()
                        copiedStatus = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnosticReport() {
        let report = """
        Orca Whisper Diagnostic Report
        ------------------------------
        macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: arm64
        Endpoint: \(settings.endpointURL)
        Hotkey Modifier: \(settings.selectedModifier.rawValue)
        Hotkey Mode: \(settings.hotkeyMode.rawValue)
        Tap Threshold: \(settings.tapThreshold) ms
        Double-Tap Window: \(settings.doubleTapWindow) ms
        Bitrate: \(settings.aacBitRate) bps
        Microphone Permission: \(PermissionsHelper.shared.microphoneStatus() == .granted ? "Granted" : "Not Granted")
        Accessibility Permission: \(PermissionsHelper.shared.isAccessibilityGranted() ? "Granted" : "Not Granted")
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }
}

// MARK: - 10. About Section
struct AboutSectionView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
                .cornerRadius(20)

            Text("Orca Whisper")
                .font(.title.bold())

            Text("Version 1.0.0 (Build 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Truly native macOS voice dictation powered by Cloudflare Workers AI.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Divider().padding(.vertical, 8)

            VStack(spacing: 6) {
                Text("Remote Worker")
                    .font(.caption).bold()
                Text(settings.endpointURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
