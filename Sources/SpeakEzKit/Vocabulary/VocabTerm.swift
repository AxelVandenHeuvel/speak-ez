import Foundation

/// A user-defined term the transcriber tends to get wrong: dev jargon,
/// product names, unusual spellings.
public struct VocabTerm: Codable, Equatable, Sendable, Identifiable {
    /// The canonical spelling, exactly as it should be inserted.
    public var text: String
    /// Sound-alike spellings the speech model produces for this term,
    /// e.g. "tea mux" or "teemux" for "tmux".
    public var aliases: [String]
    public var enabled: Bool

    public var id: String { text }

    public init(text: String, aliases: [String] = [], enabled: Bool = true) {
        self.text = text
        self.aliases = aliases
        self.enabled = enabled
    }
}
