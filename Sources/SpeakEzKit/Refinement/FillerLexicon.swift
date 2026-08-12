import Foundation

/// The words and phrases the rules refiner strips out.
/// Defaults are deliberately conservative: only sounds that are never
/// meaningful. Context-dependent fillers like "you know" or "like" stay in
/// unless the user adds them, because rules cannot judge context.
public struct FillerLexicon: Codable, Equatable, Sendable {
    /// Single filler words, lowercase.
    public var words: [String]
    /// Multi-word fillers, lowercase, single-space separated.
    public var phrases: [String]

    public init(words: [String], phrases: [String] = []) {
        self.words = words.map { $0.lowercased() }
        self.phrases = phrases.map { $0.lowercased() }
    }

    public static let standard = FillerLexicon(
        words: ["um", "uh", "umm", "uhm", "uhh", "er", "erm", "mm", "mhm", "hmm"]
    )
}
