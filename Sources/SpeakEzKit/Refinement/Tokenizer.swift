import Foundation

/// A transcript split into words and the stuff between them, losslessly.
enum Token: Equatable {
    case word(String)
    case whitespace(String)
    case punctuation(String)

    var text: String {
        switch self {
        case .word(let s), .whitespace(let s), .punctuation(let s):
            return s
        }
    }
}

enum Tokenizer {
    /// Characters that belong inside a word: letters, digits, apostrophes,
    /// and hyphens (so "don't" and "hold-to-talk" stay single tokens).
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
            || character == "-"
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentKind: Int = -1  // 0 word, 1 whitespace, 2 punctuation

        func flush() {
            guard !current.isEmpty else { return }
            switch currentKind {
            case 0: tokens.append(.word(current))
            case 1: tokens.append(.whitespace(current))
            default: tokens.append(.punctuation(current))
            }
            current = ""
        }

        for character in text {
            let kind = isWordCharacter(character) ? 0 : (character.isWhitespace ? 1 : 2)
            if kind != currentKind {
                flush()
                currentKind = kind
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    static func join(_ tokens: [Token]) -> String {
        tokens.map(\.text).joined()
    }
}
