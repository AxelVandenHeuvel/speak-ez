import Foundation

/// Fixes near-miss transcriptions of user vocabulary.
///
/// Matching is deliberately conservative so ordinary words never get mangled
/// into jargon:
/// - exact match (case-insensitive) -> canonical casing,
/// - explicit aliases (case-insensitive) -> canonical spelling,
/// - fuzzy match only within Damerau-Levenshtein distance 1, and only for
///   words of 4+ characters that share the term's first letter.
///
/// Anything more aggressive (phonetic matching, distance 2) turns real words
/// like "harder" into terms like "herdr", which is far worse than missing an
/// occasional correction. Users can always add an alias for a specific
/// mishearing instead.
public struct VocabularyCorrector: Sendable {
    private struct Entry: Sendable {
        let canonical: String
        let canonicalLowercased: [Character]
    }

    private let exactMatches: [String: String]  // lowercased term/alias -> canonical
    private let fuzzyEntries: [Entry]

    public init(terms: [VocabTerm]) {
        var exact: [String: String] = [:]
        var fuzzy: [Entry] = []
        for term in terms where term.enabled {
            let canonical = term.text
            exact[canonical.lowercased()] = canonical
            for alias in term.aliases {
                exact[alias.lowercased()] = canonical
            }
            if canonical.count >= 4 {
                fuzzy.append(
                    Entry(
                        canonical: canonical,
                        canonicalLowercased: Array(canonical.lowercased())))
            }
        }
        self.exactMatches = exact
        self.fuzzyEntries = fuzzy
    }

    /// Returns the canonical spelling when two adjacent transcript words
    /// match a multi-word alias like "tea mux" -> "tmux", or nil.
    public func correctPair(_ first: String, _ second: String) -> String? {
        exactMatches["\(first.lowercased()) \(second.lowercased())"]
    }

    /// Returns the corrected spelling for a transcript word, or nil when the
    /// word is fine (or is nobody's business).
    public func correct(_ word: String) -> String? {
        let lowercased = word.lowercased()

        if let canonical = exactMatches[lowercased] {
            return canonical == word ? nil : canonical
        }

        guard lowercased.count >= 4 else { return nil }
        let characters = Array(lowercased)
        for entry in fuzzyEntries {
            guard entry.canonicalLowercased.first == characters.first else { continue }
            if Levenshtein.distance(characters, entry.canonicalLowercased, limit: 1) <= 1 {
                return entry.canonical
            }
        }
        return nil
    }
}
