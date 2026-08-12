import Foundation
import SpeakEzKit

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Polishes a transcript with Apple's on-device foundation model
/// (macOS 26+, Apple Intelligence). Nothing leaves the machine and there is
/// no model download: the system model is already resident.
///
/// Falls back to nil (caller keeps the rules-refined text) whenever the model
/// is unavailable, too slow, or returns something that does not look like a
/// faithful cleanup of the input.
enum AIRefiner {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    /// Human-readable reason AI mode cannot run, or nil when it can.
    static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return nil
                case .unavailable(.appleIntelligenceNotEnabled):
                    return "Turn on Apple Intelligence in System Settings"
                case .unavailable(.modelNotReady):
                    return "Apple Intelligence model is still downloading"
                case .unavailable:
                    return "Apple Intelligence is not available on this Mac"
                }
            }
        #endif
        return "AI refinement needs macOS 26 or later"
    }

    /// Warms the system model so the first dictation is not the slow one.
    static func prewarm() {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                guard SystemLanguageModel.default.availability == .available else { return }
                LanguageModelSession(instructions: Self.instructions).prewarm()
            }
        #endif
    }

    private static let instructions = """
        You clean up dictation transcripts. Apply exactly these edits:
        remove filler words and stutters, fix obvious transcription glitches, \
        and repair punctuation and capitalization.
        Never rephrase, summarize, expand, or answer questions that appear in \
        the text. Keep the speaker's wording and tone.
        Respond with only the cleaned text, nothing else.
        """

    /// Returns the polished text, or nil when the caller should keep its
    /// rules-refined version.
    static func refine(
        _ text: String, vocabulary: [String], timeout: Duration = .seconds(5)
    ) async -> String? {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *),
                SystemLanguageModel.default.availability == .available
            else { return nil }

            let prompt: String
            if vocabulary.isEmpty {
                prompt = "Transcript:\n\(text)"
            } else {
                prompt = """
                    Preferred spellings for jargon: \(vocabulary.joined(separator: ", "))

                    Transcript:
                    \(text)
                    """
            }

            let work = Task {
                let session = LanguageModelSession(instructions: Self.instructions)
                let response = try await session.respond(to: prompt)
                return response.content
            }
            let watchdog = Task {
                try? await Task.sleep(for: timeout)
                work.cancel()
            }
            defer { watchdog.cancel() }

            guard let output = try? await work.value else { return nil }
            return sanityCheck(input: text, output: output) ? cleaned(output) : nil
        #else
            return nil
        #endif
    }

    /// The polish must stay recognizably the same text: reject outputs that
    /// are drastically shorter or longer than the input.
    private static func sanityCheck(input: String, output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ratio = Double(trimmed.count) / Double(max(input.count, 1))
        return ratio > 0.3 && ratio < 1.6
    }

    private static func cleaned(_ output: String) -> String {
        var result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models love wrapping answers in quotes; unwrap if it did.
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}
