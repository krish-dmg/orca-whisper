import Foundation
import os

struct DictationTiming {
    var audioFinalizeDuration: TimeInterval = 0.0
    var uploadDuration: TimeInterval = 0.0
    var pasteDuration: TimeInterval = 0.0

    var totalDuration: TimeInterval {
        return audioFinalizeDuration + uploadDuration + pasteDuration
    }

    var menuSummary: String {
        if totalDuration <= 0 {
            return "No dictation timing yet"
        }
        return String(format: "Last: %.2fs (Audio: %.2fs, Net: %.2fs, Paste: %.2fs)",
                      totalDuration, audioFinalizeDuration, uploadDuration, pasteDuration)
    }
}

final class TimingTracker {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "Timing")

    private var keyReleaseTimestamp: Date?
    private var audioReadyTimestamp: Date?
    private var uploadStartTimestamp: Date?
    private var responseReceivedTimestamp: Date?
    private var pasteCompleteTimestamp: Date?

    func markKeyRelease() {
        keyReleaseTimestamp = Date()
    }

    func markAudioReady() {
        audioReadyTimestamp = Date()
    }

    func markUploadStart() {
        uploadStartTimestamp = Date()
    }

    func markResponseReceived() {
        responseReceivedTimestamp = Date()
    }

    func markPasteComplete() -> DictationTiming {
        let now = Date()
        pasteCompleteTimestamp = now

        var timing = DictationTiming()

        if let t0 = keyReleaseTimestamp, let t1 = audioReadyTimestamp {
            timing.audioFinalizeDuration = max(0, t1.timeIntervalSince(t0))
        }

        if let t2 = uploadStartTimestamp, let t3 = responseReceivedTimestamp {
            timing.uploadDuration = max(0, t3.timeIntervalSince(t2))
        }

        if let t3 = responseReceivedTimestamp {
            timing.pasteDuration = max(0, now.timeIntervalSince(t3))
        }

        logger.debug("Dictation timing: total=\(timing.totalDuration)s, audio=\(timing.audioFinalizeDuration)s, upload=\(timing.uploadDuration)s, paste=\(timing.pasteDuration)s")

        return timing
    }

    func reset() {
        keyReleaseTimestamp = nil
        audioReadyTimestamp = nil
        uploadStartTimestamp = nil
        responseReceivedTimestamp = nil
        pasteCompleteTimestamp = nil
    }
}
