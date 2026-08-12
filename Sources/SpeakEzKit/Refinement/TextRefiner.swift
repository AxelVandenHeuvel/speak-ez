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
