import Foundation
import AVFoundation
import os

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

final class AudioRecorder {
    private let logger = Logger(subsystem: "com.orca.whisper", category: "AudioRecorder")

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?
    private var converter: AVAudioConverter?
    private var targetPcmFormat: AVAudioFormat?

    private(set) var isRecording = false
    var onAudioLevelChange: ((Float) -> Void)?

    static func availableInputDevices() -> [AudioInputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func startRecording(deviceUID: String? = nil, bitRate: Int = 32000) throws -> URL {
        if isRecording {
            cancelRecording()
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            logger.error("Invalid audio hardware sample rate: \(hardwareFormat.sampleRate)")
            throw NSError(domain: "com.orca.whisper.audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone hardware is unavailable or has an invalid sample rate."])
        }

        // 16 kHz Mono Float32 PCM target
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw NSError(domain: "com.orca.whisper.audio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate 16 kHz mono format."])
        }
        self.targetPcmFormat = pcmFormat

        guard let audioConverter = AVAudioConverter(from: hardwareFormat, to: pcmFormat) else {
            throw NSError(domain: "com.orca.whisper.audio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize sample rate converter."])
        }
        self.converter = audioConverter

        let safeBitRate = (bitRate >= 16000 && bitRate <= 64000) ? bitRate : 32000
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: safeBitRate
        ]

        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let tempURL = cachesDirectory.appendingPathComponent("orca_\(UUID().uuidString).m4a")
        self.currentRecordingURL = tempURL

        let file = try AVAudioFile(forWriting: tempURL, settings: outputSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.audioFile = file

        let bufferCapacity: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferCapacity, format: hardwareFormat) { [weak self] (buffer, when) in
            guard let self = self, let converter = self.converter, let audioFile = self.audioFile, let targetFormat = self.targetPcmFormat else {
                return
            }

            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                return
            }

            var error: NSError?
            var isInputConsumed = false

            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                if isInputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                isInputConsumed = true
                return buffer
            }

            let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            if status != .error && error == nil && convertedBuffer.frameLength > 0 {
                do {
                    try audioFile.write(from: convertedBuffer)
                } catch {
                    self.logger.error("Error writing audio frames to file: \(error.localizedDescription)")
                }

                // Compute real-time RMS audio level for waveform visualizer
                if let channelData = convertedBuffer.floatChannelData {
                    let ptr = channelData.pointee
                    let frames = Int(convertedBuffer.frameLength)
                    if frames > 0 {
                        var sum: Float = 0.0
                        let strideBy = 8
                        let samplesCount = frames / strideBy
                        for i in stride(from: 0, to: frames, by: strideBy) {
                            let s = ptr[i]
                            sum += s * s
                        }
                        let rms = sqrt(sum / Float(max(samplesCount, 1)))
                        // Threshold background ambient noise (~0.005) and scale speech range (0.005 ... 0.12)
                        let normalized = min(max((rms - 0.004) / 0.09, 0.0), 1.0)
                        DispatchQueue.main.async { [weak self] in
                            self?.onAudioLevelChange?(normalized)
                        }
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        logger.debug("Audio recording started to file: \(tempURL.lastPathComponent, privacy: .public)")
        return tempURL
    }

    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        converter = nil
        targetPcmFormat = nil
        isRecording = false
        onAudioLevelChange?(0.0)

        let url = currentRecordingURL
        currentRecordingURL = nil
        logger.debug("Audio recording stopped.")
        return url
    }

    func cancelRecording() {
        guard isRecording || currentRecordingURL != nil else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        converter = nil
        targetPcmFormat = nil
        isRecording = false
        onAudioLevelChange?(0.0)

        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
        }
        logger.debug("Audio recording cancelled and file removed.")
    }

    func deleteFile(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                logger.debug("Deleted temporary audio file: \(url.lastPathComponent, privacy: .public)")
            }
        } catch {
            logger.error("Failed to delete temporary audio file: \(error.localizedDescription)")
        }
    }
}
