import AVFoundation
import Foundation

/// One stretch of captured audio at a fixed sample rate.
/// A recording is a list of segments because the input device (and with it the
/// sample rate) can change mid-recording, for example when AirPods connect.
struct AudioSegment: Sendable {
    let samples: [Float]  // mono
    let sampleRate: Double
}

/// Captures microphone audio with AVAudioEngine, downmixed to mono Float32 at
/// the device's native sample rate. Rate conversion to the 16 kHz the speech
/// model needs happens later, once, in the transcription service.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var segments: [AudioSegment] = []
    private var currentSamples: [Float] = []
    private var currentRate: Double = 0
    private var recording = false

    /// Called on the main thread with a 0...1 level for the overlay meter.
    var onLevel: (@MainActor @Sendable (Float) -> Void)?

    /// Called on the main thread when capture died mid-recording and could
    /// not be revived, so the user is told instead of losing speech silently.
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    /// Total seconds captured so far across all segments.
    var capturedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let sealed = segments.reduce(0.0) { $0 + Double($1.samples.count) / $1.sampleRate }
        let current = currentRate > 0 ? Double(currentSamples.count) / currentRate : 0
        return sealed + current
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    func start() throws {
        lock.lock()
        segments = []
        currentSamples = []
        recording = true
        lock.unlock()
        try installTapAndStart()
    }

    /// Stops capture and returns everything recorded since `start()`.
    func stop() -> [AudioSegment] {
        tearDownTap()
        lock.lock()
        defer { lock.unlock() }
        recording = false
        sealCurrentSegmentLocked()
        let result = segments
        segments = []
        return result
    }

    func discard() {
        tearDownTap()
        lock.lock()
        defer { lock.unlock() }
        recording = false
        segments = []
        currentSamples = []
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        lock.lock()
        currentRate = format.sampleRate
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func tearDownTap() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frames)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<frames {
                mono[frame] += data[frame]
            }
        }
        if channelCount > 1 {
            let scale = 1.0 / Float(channelCount)
            for frame in 0..<frames { mono[frame] *= scale }
        }

        lock.lock()
        let isRecording = recording
        if isRecording {
            currentSamples.append(contentsOf: mono)
        }
        lock.unlock()
        guard isRecording else { return }

        // RMS -> perceptual 0...1 level for the meter (-50 dB floor).
        var sumOfSquares: Float = 0
        for sample in mono { sumOfSquares += sample * sample }
        let rms = (sumOfSquares / Float(frames)).squareRoot()
        let db = 20 * log10(max(rms, .leastNormalMagnitude))
        let level = max(0, min(1, (db + 50) / 50))
        if let onLevel {
            Task { @MainActor in onLevel(level) }
        }
    }

    /// Must be called with `lock` held.
    private func sealCurrentSegmentLocked() {
        if !currentSamples.isEmpty, currentRate > 0 {
            segments.append(AudioSegment(samples: currentSamples, sampleRate: currentRate))
        }
        currentSamples = []
    }

    private func handleConfigurationChange() {
        lock.lock()
        let wasRecording = recording
        sealCurrentSegmentLocked()
        lock.unlock()
        guard wasRecording else { return }

        // The input device or its format changed mid-recording (new mic,
        // AirPods, a screen recorder grabbing the input, ...). Rebuild the
        // tap in the new native format and keep appending as a fresh
        // segment. This must not fail silently: a dead engine here means
        // every word after this moment would be lost.
        NSLog("AudioRecorder: input configuration changed mid-recording, rebuilding tap")
        tearDownTap()
        var lastError: Error?
        for attempt in 1...3 {
            do {
                try installTapAndStart()
                NSLog("AudioRecorder: tap rebuilt (attempt %d)", attempt)
                return
            } catch {
                lastError = error
                NSLog("AudioRecorder: rebuild attempt %d failed: %@", attempt, "\(error)")
                usleep(100_000)
            }
        }
        lock.lock()
        recording = false
        lock.unlock()
        NSLog("AudioRecorder: giving up, capture is dead: %@", "\(String(describing: lastError))")
        if let onFailure {
            Task { @MainActor in
                onFailure("The microphone was interrupted")
            }
        }
    }
}
