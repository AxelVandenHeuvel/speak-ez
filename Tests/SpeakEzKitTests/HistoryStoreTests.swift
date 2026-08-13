import Foundation
import Testing
@testable import SpeakEzKit

@Suite struct HistoryStoreTests {
    private func makeStore(capacity: Int = 20) -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakez-history-tests-\(UUID().uuidString)")
        return HistoryStore(directory: directory, capacity: capacity)
    }

    @Test func emptyStoreLoadsNothing() {
        #expect(makeStore().load().isEmpty)
    }

    @Test func appendPutsNewestFirst() throws {
        let store = makeStore()
        try store.append(DictationRecord(raw: "raw one", inserted: "one", date: Date()))
        try store.append(DictationRecord(raw: "raw two", inserted: "two", date: Date()))
        let records = store.load()
        #expect(records.count == 2)
        #expect(records[0].inserted == "two")
        #expect(records[1].raw == "raw one")
    }

    @Test func capacityIsEnforced() throws {
        let store = makeStore(capacity: 3)
        for index in 1...5 {
            try store.append(
                DictationRecord(raw: "raw \(index)", inserted: "text \(index)", date: Date()))
        }
        let records = store.load()
        #expect(records.count == 3)
        #expect(records[0].inserted == "text 5")
        #expect(records[2].inserted == "text 3")
    }

    @Test func clearEmptiesTheStore() throws {
        let store = makeStore()
        try store.append(DictationRecord(raw: "a", inserted: "a", date: Date()))
        try store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func roundTripsThroughDisk() throws {
        let store = makeStore()
        let record = DictationRecord(
            raw: "um so the the fix works", inserted: "So the fix works.", date: Date())
        try store.append(record)
        let reloaded = store.load()[0]
        #expect(reloaded.raw == record.raw)
        #expect(reloaded.inserted == record.inserted)
    }
}
