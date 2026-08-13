import Foundation

/// One completed dictation: what the speech model heard, and what actually
/// got inserted after refinement.
public struct DictationRecord: Codable, Equatable, Sendable {
    public let raw: String
    public let inserted: String
    public let date: Date

    public init(raw: String, inserted: String, date: Date) {
        self.raw = raw
        self.inserted = inserted
        self.date = date
    }
}

/// Persists the last few dictations as JSON so users can inspect what the
/// refiner did and re-copy past text. Everything stays on disk locally;
/// newest record first.
public struct HistoryStore: Sendable {
    public let fileURL: URL
    public let capacity: Int

    public init(directory: URL, capacity: Int = 20) {
        self.fileURL = directory.appendingPathComponent("history.json")
        self.capacity = capacity
    }

    /// The conventional location: ~/Library/Application Support/speakEZ.
    public static func standard() -> HistoryStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HistoryStore(directory: base.appendingPathComponent("speakEZ"))
    }

    public func load() -> [DictationRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? Self.decoder.decode([DictationRecord].self, from: data)) ?? []
    }

    public func append(_ record: DictationRecord) throws {
        var records = load()
        records.insert(record, at: 0)
        if records.count > capacity {
            records.removeLast(records.count - capacity)
        }
        try write(records)
    }

    public func clear() throws {
        try write([])
    }

    private func write(_ records: [DictationRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
