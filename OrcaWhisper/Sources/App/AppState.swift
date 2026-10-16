import Foundation

enum AppStatus: Equatable {
    case idle
    case recordingHold
    case recordingLatched
    case processing
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Status: Ready"
        case .recordingHold:
            return "Status: Recording (Push-to-Talk)..."
        case .recordingLatched:
            return "Status: Hands-Free Recording..."
        case .processing:
            return "Status: Processing..."
        case .error(let msg):
            return "Status: Error (\(msg))"
        }
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: AppStatus = .idle
    @Published var lastTranscription: String?
    @Published var lastTiming: DictationTiming?

    private init() {}

    func updateStatus(_ newStatus: AppStatus) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }

    func setTranscription(_ text: String, timing: DictationTiming) {
        DispatchQueue.main.async {
            self.status = .idle
            self.lastTranscription = text
            self.lastTiming = timing
        }
    }

    func setError(_ message: String) {
        DispatchQueue.main.async {
            self.status = .error(message)
        }
    }
}
