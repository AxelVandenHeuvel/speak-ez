import Foundation

/// Deterministic, instant transcript cleanup:
/// 1. strips filler words and phrases ("um", "uh", ...),
/// 2. collapses stutters ("the the", "I think I think"),
/// 3. applies custom vocabulary corrections,
/// 4. tidies the punctuation and capitalization damage the edits leave behind.
///
/// Runs in well under a millisecond for any realistic dictation, so it adds
/// nothing to the release-to-text latency.
public struct RulesRefiner: TextRefiner {
    private let fillerWords: Set<String>
    private let fillerPhrases: [[String]]
    private let corrector: VocabularyCorrector?

    public init(lexicon: FillerLexicon = .standard, vocabulary: [VocabTerm] = []) {
        self.fillerWords = Set(lexicon.words)
        self.fillerPhrases = lexicon.phrases.map { $0.split(separator: " ").map(String.init) }
        self.corrector = vocabulary.isEmpty ? nil : VocabularyCorrector(terms: vocabulary)
    }

    public func refine(_ text: String) async throws -> String {
        refineSync(text)
    }

    public func refineSync(_ text: String) -> String {
        var tokens = Tokenizer.tokenize(text)
        tokens = removeFillers(tokens)
        tokens = collapseRepeats(tokens)
        if let corrector {
            tokens = applyVocabulary(tokens, corrector: corrector)
        }
        return Self.tidy(tokens)
    }

    // MARK: - Fillers

    private func removeFillers(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var index = 0
        while index < tokens.count {
            if case .word(let word) = tokens[index] {
                if let phraseLength = matchPhrase(tokens, at: index) {
                    index = skipRemoved(tokens, wordSpan: phraseLength, from: index)
                    continue
                }
                if fillerWords.contains(word.lowercased()) {
                    index = skipRemoved(tokens, wordSpan: 1, from: index)
                    continue
                }
            }
            result.append(tokens[index])
            index += 1
        }
        return result
    }

    /// Returns the number of word tokens matched when a filler phrase starts
    /// at `index`, or nil.
    private func matchPhrase(_ tokens: [Token], at index: Int) -> Int? {
        outer: for phrase in fillerPhrases {
            var tokenIndex = index
            for (wordPosition, phraseWord) in phrase.enumerated() {
                guard tokenIndex < tokens.count,
                    case .word(let word) = tokens[tokenIndex],
                    word.lowercased() == phraseWord
                else { continue outer }
                if wordPosition < phrase.count - 1 {
                    guard tokenIndex + 1 < tokens.count,
                        case .whitespace = tokens[tokenIndex + 1]
                    else { continue outer }
                    tokenIndex += 2
                }
            }
            return phrase.count
        }
        return nil
    }

    /// Consumes `wordSpan` filler words starting at `from`, plus one trailing
    /// comma (the "Um, ..." case) and the whitespace the removal orphans.
    private func skipRemoved(_ tokens: [Token], wordSpan: Int, from: Int) -> Int {
        var index = from
        var wordsConsumed = 0
        while index < tokens.count, wordsConsumed < wordSpan {
            if case .word = tokens[index] { wordsConsumed += 1 }
            index += 1
        }
        // Swallow " ," or "," directly after the filler.
        var lookahead = index
        if lookahead < tokens.count, case .whitespace = tokens[lookahead] {
            lookahead += 1
        }
        if lookahead < tokens.count, case .punctuation(let p) = tokens[lookahead], p == "," {
            index = lookahead + 1
        }
        // Swallow the whitespace after the removed span so we don't leave
        // a double space behind.
        if index < tokens.count, case .whitespace = tokens[index] {
            index += 1
        }
        return index
    }

    // MARK: - Stutters

    private func collapseRepeats(_ tokens: [Token]) -> [Token] {
        var result = collapseNGramRepeats(tokens, n: 2)
        result = collapseNGramRepeats(result, n: 1)
        return result
    }

    /// Drops immediate repeats of an n-word sequence, case-insensitively:
    /// "the the" -> "the", "I think I think" -> "I think".
    private func collapseNGramRepeats(_ tokens: [Token], n: Int) -> [Token] {
        // Work on word indices; whitespace between repeats must be plain.
        var tokens = tokens
        var changed = true
        while changed {
            changed = false
            let wordIndices = tokens.indices.filter {
                if case .word = tokens[$0] { return true }
                return false
            }
            guard wordIndices.count >= n * 2 else { break }
            for start in 0...(wordIndices.count - n * 2) {
                let firstSpan = (0..<n).map { wordIndices[start + $0] }
                let secondSpan = (0..<n).map { wordIndices[start + n + $0] }
                // The whole region must be words separated by single spaces.
                let regionStart = firstSpan[0]
                let regionEnd = secondSpan[n - 1]
                guard regionIsPlainWords(tokens, from: regionStart, to: regionEnd) else {
                    continue
                }
                let firstWords = firstSpan.map { tokens[$0].text.lowercased() }
                let secondWords = secondSpan.map { tokens[$0].text.lowercased() }
                if firstWords == secondWords {
                    // Remove the second span plus the whitespace before it.
                    let removalStart = firstSpan[n - 1] + 1
                    tokens.removeSubrange(removalStart...regionEnd)
                    changed = true
                    break
                }
            }
        }
        return tokens
    }

    private func regionIsPlainWords(_ tokens: [Token], from: Int, to: Int) -> Bool {
        for index in from...to {
            switch tokens[index] {
            case .word: continue
            case .whitespace(let s) where !s.contains("\n"): continue
            default: return false
            }
        }
        return true
    }

    // MARK: - Vocabulary

    private func applyVocabulary(_ tokens: [Token], corrector: VocabularyCorrector) -> [Token] {
        var tokens = tokens
        // Pair pass first, so "tea mux" wins over any single-word match.
        var index = 0
        while index < tokens.count {
            if case .word(let first) = tokens[index],
                index + 2 < tokens.count,
                case .whitespace = tokens[index + 1],
                case .word(let second) = tokens[index + 2],
                let canonical = corrector.correctPair(first, second)
            {
                tokens.replaceSubrange(index...(index + 2), with: [.word(canonical)])
            }
            index += 1
        }
        return tokens.map { token in
            if case .word(let word) = token, let fixed = corrector.correct(word) {
                return .word(fixed)
            }
            return token
        }
    }

    // MARK: - Tidy-up

    /// Repairs the seams left by removals: duplicate separators, orphaned
    /// commas, missing sentence capitalization.
    static func tidy(_ tokens: [Token]) -> String {
        var text = Tokenizer.join(tokens)

        // Collapse runs of spaces (but keep newlines).
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        // No space before closing punctuation.
        text = text.replacingOccurrences(
            of: #" +([,.!?;:])"#, with: "$1", options: .regularExpression)
        // ", ," and ",," -> ","
        text = text.replacingOccurrences(
            of: #",\s*,"#, with: ",", options: .regularExpression)
        // ",." -> "." (comma orphaned right before a sentence end)
        text = text.replacingOccurrences(
            of: #",([.!?])"#, with: "$1", options: .regularExpression)
        // A comma or period left dangling at the very start.
        text = text.replacingOccurrences(
            of: #"^[\s,.]+"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return capitalizeSentenceStarts(text)
    }

    /// Capitalizes the first letter of the text and of each sentence.
    /// A sentence boundary is an ender followed by whitespace, so decimals
    /// and abbreviations ("3.5 gb") are left alone.
    private static func capitalizeSentenceStarts(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true
        var sawSentenceEnder = false
        for character in text {
            if character.isWhitespace {
                if sawSentenceEnder { capitalizeNext = true }
                sawSentenceEnder = false
                result.append(character)
                continue
            }
            if character == "." || character == "!" || character == "?" {
                sawSentenceEnder = true
                result.append(character)
                continue
            }
            sawSentenceEnder = false
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                if character.isLetter || character.isNumber { capitalizeNext = false }
                result.append(character)
            }
        }
        return result
    }
}
