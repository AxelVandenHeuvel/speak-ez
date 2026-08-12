import FluidAudio
import Foundation

/// Headless self-test: `SpeakEz --transcribe file.wav` prints the transcript
/// and timing to stdout and exits. Used by the integration test and for
/// verifying the speech stack without launching the UI.
enum TranscribeCLI {
    /// Headless AI refinement check: `speakEZ --refine "some text"` prints
    /// the polished text, or the reason AI mode is unavailable.
    static func runRefineIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--refine"),
            flagIndex + 1 < arguments.count
        else { return }
        let text = arguments[flagIndex + 1]

        Task {
            if let reason = AIRefiner.unavailabilityReason {
                print("AI UNAVAILABLE: \(reason)")
                exit(1)
            }
            let start = Date()
            if let polished = await AIRefiner.refine(text, vocabulary: []) {
                print("REFINED: \(polished)")
                FileHandle.standardError.write(
                    String(format: "took %.2fs\n", Date().timeIntervalSince(start))
                        .data(using: .utf8)!)
                exit(0)
            }
            print("AI FELL BACK (timeout or sanity check)")
            exit(2)
        }
        RunLoop.main.run()
    }

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--transcribe"),
            flagIndex + 1 < arguments.count
        else { return }
        let url = URL(fileURLWithPath: arguments[flagIndex + 1])

        Task {
            do {
                let loadStart = Date()
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                let loadSeconds = Date().timeIntervalSince(loadStart)

                let converter = AudioConverter()
                let samples = try converter.resampleAudioFile(url)
                let audioSeconds = Double(samples.count) / 16_000

                let transcribeStart = Date()
                var state = TdtDecoderState.make()
                let result = try await manager.transcribe(samples, decoderState: &state)
                let transcribeSeconds = Date().timeIntervalSince(transcribeStart)

                print("TRANSCRIPT: \(result.text)")
                FileHandle.standardError.write(
                    String(
                        format:
                            "load: %.2fs  audio: %.2fs  transcribe: %.3fs  rtf: %.0fx\n",
                        loadSeconds, audioSeconds, transcribeSeconds,
                        audioSeconds / max(transcribeSeconds, 0.001)
                    ).data(using: .utf8)!)
                exit(0)
            } catch {
                FileHandle.standardError.write(
                    "self-test failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        RunLoop.main.run()
    }
}
