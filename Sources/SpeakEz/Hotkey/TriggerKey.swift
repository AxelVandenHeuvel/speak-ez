import CoreGraphics

/// Keys that can act as the hold-to-talk trigger.
/// All of them are modifier-style keys that arrive as `.flagsChanged` events,
/// which lets us detect both press and release without swallowing typing.
enum TriggerKey: String, CaseIterable, Codable, Sendable {
    // Order is the menu order. Right Option is the default: held alone it
    // never triggers a macOS or app shortcut, so it collides with nothing.
    case rightOption
    case rightCommand
    case rightControl
    case fn

    var displayName: String {
        switch self {
        case .fn: return "fn (globe)"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        case .rightControl: return "Right Control"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }

    /// The flag that is set while this key is held down.
    var flagMask: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightCommand: return .maskCommand
        case .rightOption: return .maskAlternate
        case .rightControl: return .maskControl
        }
    }

    /// Whether a flags-changed event for this key code means "now pressed".
    func isPressed(in flags: CGEventFlags) -> Bool {
        flags.contains(flagMask)
    }
}
