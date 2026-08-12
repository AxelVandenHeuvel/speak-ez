import Foundation

enum Levenshtein {
    /// Damerau-Levenshtein distance (edits: insert, delete, substitute, and
    /// transpose adjacent characters), with an early-out bound.
    static func distance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,  // deletion
                    current[j - 1] + 1,  // insertion
                    previous[j - 1] + cost  // substitution
                )
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = Swift.min(current[j], previousPrevious[j - 2] + 1)
                }
                rowMinimum = Swift.min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return limit + 1 }
            (previousPrevious, previous, current) = (previous, current, previousPrevious)
        }
        return previous[b.count]
    }
}
