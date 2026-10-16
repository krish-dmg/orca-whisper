import Foundation
import os

enum HotkeyState: Equatable {
    case idle
    case holding(startTime: Date)
    case waitingForSecondTap(firstTapUpTime: Date)
    case latched(startTime: Date)
    case processing
}

enum StateMachineAction {
    case startRecording(isLatched: Bool)
    case stopAndDiscardRecording
    case stopAndSendRecording
    case stateChanged(HotkeyState)
}

protocol HotkeyStateMachineDelegate: AnyObject {
    func stateMachine(_ sm: HotkeyStateMachine, didProduceAction action: StateMachineAction)
}

final class HotkeyStateMachine {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "HotkeyStateMachine")

    weak var delegate: HotkeyStateMachineDelegate?

    private(set) var currentState: HotkeyState = .idle {
        didSet {
            delegate?.stateMachine(self, didProduceAction: .stateChanged(currentState))
        }
    }

    var tapThreshold: TimeInterval = 0.250 // 250 ms
    var doubleTapWindow: TimeInterval = 0.350 // 350 ms
    var maxRecordingDuration: TimeInterval = 300.0 // 5 minutes
    var escapeToCancel: Bool = true
    var mode: HotkeyMode = .holdAndDoubleTap

    private var doubleTapTimer: Timer?
    private var capTimer: Timer?

    init(tapThreshold: TimeInterval = 0.250,
         doubleTapWindow: TimeInterval = 0.350,
         maxRecordingDuration: TimeInterval = 300.0,
         mode: HotkeyMode = .holdAndDoubleTap) {
        self.tapThreshold = tapThreshold
        self.doubleTapWindow = doubleTapWindow
        self.maxRecordingDuration = maxRecordingDuration
        self.mode = mode
    }

    func handleKeyDown() {
        if mode == .toggleTap {
            handleKeyDownToggleMode()
            return
        }

        switch currentState {
        case .idle:
            let now = Date()
            currentState = .holding(startTime: now)
            startCapTimer()
            delegate?.stateMachine(self, didProduceAction: .startRecording(isLatched: false))

        case .waitingForSecondTap:
            cancelDoubleTapTimer()
            let now = Date()
            currentState = .latched(startTime: now)
            startCapTimer()
            delegate?.stateMachine(self, didProduceAction: .startRecording(isLatched: true))

        case .latched:
            // Single tap while latched stops latched recording and sends audio
            cancelCapTimer()
            currentState = .processing
            delegate?.stateMachine(self, didProduceAction: .stopAndSendRecording)

        case .holding, .processing:
            break
        }
    }

    private func handleKeyDownToggleMode() {
        switch currentState {
        case .idle:
            let now = Date()
            currentState = .latched(startTime: now)
            startCapTimer()
            delegate?.stateMachine(self, didProduceAction: .startRecording(isLatched: true))
        case .latched, .holding:
            cancelCapTimer()
            currentState = .processing
            delegate?.stateMachine(self, didProduceAction: .stopAndSendRecording)
        case .waitingForSecondTap, .processing:
            break
        }
    }

    func handleKeyUp() {
        if mode == .toggleTap {
            // Releasing the key in toggle mode does not change state
            return
        }

        switch currentState {
        case .holding(let startTime):
            cancelCapTimer()
            let duration = Date().timeIntervalSince(startTime)
            if duration >= tapThreshold {
                currentState = .processing
                delegate?.stateMachine(self, didProduceAction: .stopAndSendRecording)
            } else {
                delegate?.stateMachine(self, didProduceAction: .stopAndDiscardRecording)
                currentState = .waitingForSecondTap(firstTapUpTime: Date())
                startDoubleTapTimer()
            }

        case .latched:
            break

        case .idle, .waitingForSecondTap, .processing:
            break
        }
    }

    func handleEscape() {
        guard escapeToCancel else { return }

        switch currentState {
        case .holding, .latched:
            logger.debug("Escape pressed during recording. Discarding audio.")
            cancelCapTimer()
            currentState = .idle
            delegate?.stateMachine(self, didProduceAction: .stopAndDiscardRecording)

        case .waitingForSecondTap:
            cancelDoubleTapTimer()
            currentState = .idle

        case .idle, .processing:
            break
        }
    }

    func setProcessingFinished() {
        if currentState == .processing {
            currentState = .idle
        }
    }

    private func startDoubleTapTimer() {
        cancelDoubleTapTimer()
        doubleTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if case .waitingForSecondTap = self.currentState {
                self.logger.debug("Double tap window expired. Discarding ambiguous tap.")
                self.currentState = .idle
            }
        }
    }

    private func cancelDoubleTapTimer() {
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
    }

    private func startCapTimer() {
        cancelCapTimer()
        capTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            switch self.currentState {
            case .holding, .latched:
                self.logger.debug("Recording cap reached (\(self.maxRecordingDuration)s). Automatically sending.")
                self.currentState = .processing
                self.delegate?.stateMachine(self, didProduceAction: .stopAndSendRecording)
            default:
                break
            }
        }
    }

    private func cancelCapTimer() {
        capTimer?.invalidate()
        capTimer = nil
    }

    func reset() {
        cancelDoubleTapTimer()
        cancelCapTimer()
        currentState = .idle
    }
}
