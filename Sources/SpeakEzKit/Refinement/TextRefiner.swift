import Foundation

/// How much cleanup gets applied to a raw transcript before insertion.
public enum RefinementLevel: String, Codable, CaseIterable, Sendable {
    /// Insert the transcript exactly as the speech model produced it.
    case off
    /// Instant, deterministic cleanup: fillers, stutters, vocabulary fixes.
    case basic
    /// Basic cleanup plus a small local language model polishing the result.
    case ai

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .basic: return "Basic"
        case .ai: return "AI"
        }
    }
}

public protocol TextRefiner: Sendable {
    func refine(_ text: String) async throws -> String
}

/// Which of the rule-based cleanup passes are enabled. Punctuation seam
/// repair (orphaned commas, double spaces) is not an option: it is part of
/// doing the enabled removals correctly, so it always runs.
public struct RefinementOptions: Codable, Equatable, Sendable {
    public var removeFillers: Bool
    public var collapseStutters: Bool
    public var applyVocabulary: Bool
    public var fixCapitalization: Bool

    public init(
        removeFillers: Bool = true,
        collapseStutters: Bool = true,
        applyVocabulary: Bool = true,
        fixCapitalization: Bool = true
    ) {
        self.removeFillers = removeFillers
        self.collapseStutters = collapseStutters
        self.applyVocabulary = applyVocabulary
        self.fixCapitalization = fixCapitalization
    }

    public static let all = RefinementOptions()
}
