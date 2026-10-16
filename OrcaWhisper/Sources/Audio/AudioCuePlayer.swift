import AppKit
import AudioToolbox

final class AudioCuePlayer {
    static let shared = AudioCuePlayer()

    private init() {}

    func playStartCue() {
        guard AppSettings.shared.playAudioCues else { return }
        NSSound(named: "Pop")?.play()
    }

    func playStopCue() {
        guard AppSettings.shared.playAudioCues else { return }
        NSSound(named: "Tink")?.play()
    }

    func playCancelCue() {
        guard AppSettings.shared.playAudioCues else { return }
        NSSound(named: "Basso")?.play()
    }
}
