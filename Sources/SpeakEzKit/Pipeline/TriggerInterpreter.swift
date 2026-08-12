import Foundation

/// Translates raw trigger-key downs/ups into recording begin/end decisions,
/// according to the user's chosen trigger mode. Pure and synchronous so the
/// gesture logic is unit-testable.
public struct TriggerInterpreter: Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Classic push-to-talk: record while held.
        case hold
        /// Tap starts, tap again stops. Releases are ignored.
        case toggle

        public var displayName: String {
            switch self {
            case .hold: return "Hold to Talk"
            case .toggle: return "Tap to Toggle"
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case begin
        case end(heldFor: TimeInterval)
        case none
    }

    public var mode: Mode

    /// Set when a key-down stopped a toggle recording, so the matching
    /// key-up must not be interpreted again.
    private var suppressNextUp = false

    public init(mode: Mode = .hold) {
        self.mode = mode
    }

    /// `recordingFor` is non-nil (elapsed seconds) while a recording is
    /// active. Returns what the controller should do.
    public mutating func keyDown(recordingFor elapsed: TimeInterval?) -> Action {
        guard let elapsed else {
            suppressNextUp = false
            return .begin
        }
        switch mode {
        case .hold:
            // A second key-down while recording in hold mode cannot really
            // happen (the key is already down); ignore defensively.
            return .none
        case .toggle:
            suppressNextUp = true
            return .end(heldFor: elapsed)
        }
    }

    public mutating func keyUp(heldFor: TimeInterval) -> Action {
        if suppressNextUp {
            suppressNextUp = false
            return .none
        }
        switch mode {
        case .hold:
            return .end(heldFor: heldFor)
        case .toggle:
            return .none
        }
    }
}
