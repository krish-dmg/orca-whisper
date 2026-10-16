import SwiftUI
import AppKit

enum HUDState: Equatable {
    case hidden
    case listening(isLatched: Bool)
    case transcribing
    case done
    case error(String)
}

final class HUDViewModel: ObservableObject {
    @Published var state: HUDState = .hidden
    @Published var audioLevel: CGFloat = 0.0
}

// MARK: - Pulsing Sonar Recording Indicator
struct PulsingDotView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.35))
                .frame(width: 18, height: 18)
                .scaleEffect(isPulsing ? 1.4 : 0.8)
                .opacity(isPulsing ? 0.0 : 0.8)
                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: isPulsing)

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: Color.red.opacity(0.6), radius: 3)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Fluid Liquid Waveform Bars (Listening synced to speech volume)
struct FluidWaveBarsView: View {
    let audioLevel: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    let offset = Double(index) * 0.72
                    let harmonic = abs(sin(time * 7.5 + offset))
                    // When idle/silent, rests at 3.5 pt. When speaking, surges up to 22 pt in sync with voice
                    let dynamicHeight = 3.5 + (audioLevel * (5.0 + 13.5 * harmonic))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color(red: 1.0, green: 0.38, blue: 0.45)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: min(max(dynamicHeight, 3.5), 22.0))
                }
            }
            .frame(height: 22)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.8), value: audioLevel)
        }
    }
}

// MARK: - Liquid Transcribing Indicator (Processing)
struct FluidTranscribingWaveView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<4) { index in
                    let offset = Double(index) * 0.85
                    let raw = sin(time * 4.2 + offset)
                    let height = 4.0 + 10.0 * abs(raw)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.8, blue: 1.0)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: CGFloat(height))
                }
            }
            .frame(height: 20)
        }
    }
}

// MARK: - Done Spring Indicator
struct DoneCheckmarkView: View {
    @State private var scale: CGFloat = 0.35

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.green)
            .shadow(color: Color.green.opacity(0.4), radius: 4)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Main Floating HUD Body
struct FloatingHUDView: View {
    @ObservedObject var viewModel: HUDViewModel

    var body: some View {
        HStack(spacing: 11) {
            switch viewModel.state {
            case .hidden:
                EmptyView()

            case .listening(let isLatched):
                PulsingDotView()

                Text(isLatched ? "Listening (Hands-Free)…" : "Listening…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                FluidWaveBarsView(audioLevel: viewModel.audioLevel)

            case .transcribing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)

                Text("Transcribing…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                FluidTranscribingWaveView()

            case .done:
                DoneCheckmarkView()

                Text("Done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.yellow)

                Text(msg)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: viewModel.state)
    }
}

// MARK: - Floating HUD Window Controller
final class FloatingHUDController {
    static let shared = FloatingHUDController()

    private var window: NSPanel?
    private let viewModel = HUDViewModel()
    private var dismissTimer: Timer?

    private init() {
        setupWindow()
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: FloatingHUDView(viewModel: viewModel))
        panel.contentView = hostingView
        self.window = panel
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.viewModel.state != .hidden else { return }
            self.viewModel.audioLevel = CGFloat(level)
        }
    }

    func show(state: HUDState) {
        guard AppSettings.shared.showFloatingHUD else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil

            self.viewModel.state = state

            if state == .hidden {
                window.orderOut(nil)
                return
            }

            self.positionWindow(window)

            if !window.isVisible {
                window.alphaValue = 0.0
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1.0
                }
            }

            if state == .done {
                self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                    self?.hide()
                }
            } else if case .error = state {
                self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                    self?.hide()
                }
            }
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window, window.isVisible else { return }
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                window.orderOut(nil)
                self.viewModel.state = .hidden
            })
        }
    }

    private func positionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return }

        let screenRect = targetScreen.visibleFrame
        let windowWidth: CGFloat = 240
        let windowHeight: CGFloat = 50
        let x = screenRect.midX - (windowWidth / 2.0)
        let y = screenRect.minY + 68

        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
}
