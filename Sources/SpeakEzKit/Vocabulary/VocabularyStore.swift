import Foundation

/// Loads and saves the user's vocabulary and filler list as human-editable
/// JSON files, so power users can edit or version them outside the app.
public struct VocabularyStore: Sendable {
    public let directory: URL

    public var vocabularyURL: URL { directory.appendingPathComponent("vocabulary.json") }
    public var fillersURL: URL { directory.appendingPathComponent("fillers.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The conventional location: ~/Library/Application Support/speakEZ.
    public static func standard() -> VocabularyStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return VocabularyStore(directory: base.appendingPathComponent("speakEZ"))
    }

    public func loadVocabulary() -> [VocabTerm] {
        guard let data = try? Data(contentsOf: vocabularyURL) else { return [] }
        return (try? Self.decoder.decode([VocabTerm].self, from: data)) ?? []
    }

    public func saveVocabulary(_ terms: [VocabTerm]) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(terms)
        try data.write(to: vocabularyURL, options: .atomic)
    }

    public func loadFillers() -> FillerLexicon {
        guard let data = try? Data(contentsOf: fillersURL) else { return .standard }
        return (try? Self.decoder.decode(FillerLexicon.self, from: data)) ?? .standard
    }

    public func saveFillers(_ lexicon: FillerLexicon) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(lexicon)
        try data.write(to: fillersURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
