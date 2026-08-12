import AVFoundation
import FluidAudio
import Foundation

/// Owns the Parakeet models: downloads them on first launch, keeps them warm
/// in memory, and turns recorded audio segments into text.
actor TranscriptionService {
    enum Status: Equatable, Sendable {
        case notLoaded
        case downloading
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .notLoaded
    private var manager: AsrManager?
    private let converter = AudioConverter()

    /// Called whenever `status` changes, on the main actor (drives menu UI).
    private let onStatus: @MainActor @Sendable (Status) -> Void

    init(onStatus: @escaping @MainActor @Sendable (Status) -> Void) {
        self.onStatus = onStatus
    }

    private func setStatus(_ new: Status) async {
        status = new
        await onStatus(new)
    }

    /// Downloads (first run only) and loads the models, then runs a dummy
    /// inference so CoreML finishes ANE compilation before the first real use.
    func warmUp() async {
        guard manager == nil else { return }
        do {
            await setStatus(.downloading)
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            await setStatus(.loading)
            let asrManager = AsrManager(config: .default)
            try await asrManager.loadModels(models)
            manager = asrManager

            // One second of silence forces the CoreML graph to fully compile.
            var state = TdtDecoderState.make()
            _ = try await asrManager.transcribe(
                [Float](repeating: 0, count: 16_000), decoderState: &state)
            await setStatus(.ready)
        } catch {
            manager = nil
            await setStatus(.failed(error.localizedDescription))
        }
    }

    /// Transcribes a full recording in one shot. Segments may have different
    /// sample rates; each is resampled to 16 kHz and concatenated.
    /// FluidAudio handles long recordings internally with overlapping
    /// windows, so no chunking happens on our side: hand-rolled chunking
    /// split words at the seams and mangled the transcript.
    func transcribe(_ segments: [AudioSegment]) async throws -> String {
        guard let manager else {
            throw TranscriptionError.modelsNotReady
        }
        var samples16k = try resampled(segments)
        guard !samples16k.isEmpty else { return "" }

        // Half a second of trailing silence: without right context the
        // decoder tends to swallow the final word.
        samples16k.append(contentsOf: [Float](repeating: 0, count: 8000))

        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples16k, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resampled(_ segments: [AudioSegment]) throws -> [Float] {
        var samples16k: [Float] = []
        for segment in segments {
            if segment.sampleRate == 16_000 {
                samples16k.append(contentsOf: segment.samples)
            } else {
                samples16k.append(
                    contentsOf: try converter.resample(
                        segment.samples, from: segment.sampleRate))
            }
        }
        return samples16k
    }
}

enum TranscriptionError: LocalizedError {
    case modelsNotReady

    var errorDescription: String? {
        switch self {
        case .modelsNotReady:
            return "The speech model is still loading"
        }
    }
}
