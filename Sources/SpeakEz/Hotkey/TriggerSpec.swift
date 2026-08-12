import CoreGraphics
import Foundation

/// Any key that can act as the dictation trigger.
///
/// Modifier keys (option, command, fn, ...) arrive as `.flagsChanged` events
/// and are matched by key code plus flag mask. Every other key (F13, space,
/// letters) arrives as `.keyDown`/`.keyUp`. Because the event tap is
/// listen-only, a regular key keeps its normal action; modifiers and the
/// high F-keys are therefore the sensible choices.
struct TriggerSpec: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case modifier
        case regular
        /// One or more modifiers plus a regular key, like Control+S.
        case chord
    }

    let kind: Kind
    /// The regular key for .regular and .chord; the modifier's own key code
    /// for .modifier.
    let keyCode: Int64
    /// .modifier: the flag bit that is on while held.
    /// .chord: the exact set of modifier flags that must be held.
    let flagMaskRaw: UInt64?
    let displayName: String

    var flagMask: CGEventFlags? { flagMaskRaw.map { CGEventFlags(rawValue: $0) } }

    /// The modifier bits we compare; everything else (caps lock, device
    /// bits, numeric pad) is ignored.
    static let relevantModifierFlags: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
    ]

    func isPressed(in flags: CGEventFlags) -> Bool {
        guard let flagMask else { return false }
        return flags.contains(flagMask)
    }

    /// Chord matching: the held modifiers must be exactly the required set,
    /// so a Cmd+Ctrl+S shortcut never triggers a Ctrl+S trigger.
    func chordFlagsMatch(_ flags: CGEventFlags) -> Bool {
        guard let flagMaskRaw else { return false }
        return flags.rawValue & Self.relevantModifierFlags.rawValue == flagMaskRaw
    }

    // MARK: - Presets

    static let rightOption = modifier(61, .maskAlternate, "Right Option")
    static let rightCommand = modifier(54, .maskCommand, "Right Command")
    static let rightControl = modifier(62, .maskControl, "Right Control")
    static let fn = modifier(63, .maskSecondaryFn, "fn (globe)")

    static let presets: [TriggerSpec] = [.rightOption, .rightCommand, .rightControl, .fn]

    private static func modifier(
        _ keyCode: Int64, _ mask: CGEventFlags, _ name: String
    ) -> TriggerSpec {
        TriggerSpec(
            kind: .modifier, keyCode: keyCode, flagMaskRaw: mask.rawValue, displayName: name)
    }

    // MARK: - Capture

    /// All modifier key codes we allow as triggers. Caps Lock is excluded
    /// on purpose: it toggles state and would fight its own light.
    private static let modifierInfo: [Int64: (CGEventFlags, String)] = [
        54: (.maskCommand, "Right Command"),
        55: (.maskCommand, "Left Command"),
        56: (.maskShift, "Left Shift"),
        58: (.maskAlternate, "Left Option"),
        59: (.maskControl, "Left Control"),
        60: (.maskShift, "Right Shift"),
        61: (.maskAlternate, "Right Option"),
        62: (.maskControl, "Right Control"),
        63: (.maskSecondaryFn, "fn (globe)"),
    ]

    /// Interpret a flags-changed event during capture. Returns a spec only
    /// when this is a supported modifier being pressed (not released).
    static func capturedModifier(keyCode: Int64, flags: CGEventFlags) -> TriggerSpec? {
        guard let (mask, name) = modifierInfo[keyCode], flags.contains(mask) else {
            return nil
        }
        return TriggerSpec(
            kind: .modifier, keyCode: keyCode, flagMaskRaw: mask.rawValue, displayName: name)
    }

    /// Interpret a key-down during capture: with modifiers held it becomes
    /// a chord, without it is a plain key trigger.
    static func capturedKeyDown(keyCode: Int64, flags: CGEventFlags) -> TriggerSpec {
        let held = CGEventFlags(rawValue: flags.rawValue & relevantModifierFlags.rawValue)
        guard !held.isEmpty else {
            return TriggerSpec(
                kind: .regular, keyCode: keyCode, flagMaskRaw: nil,
                displayName: keyName(for: keyCode))
        }
        var symbols = ""
        if held.contains(.maskSecondaryFn) { symbols += "fn " }
        if held.contains(.maskControl) { symbols += "⌃" }
        if held.contains(.maskAlternate) { symbols += "⌥" }
        if held.contains(.maskShift) { symbols += "⇧" }
        if held.contains(.maskCommand) { symbols += "⌘" }
        return TriggerSpec(
            kind: .chord, keyCode: keyCode, flagMaskRaw: held.rawValue,
            displayName: "\(symbols)\(keyName(for: keyCode))")
    }

    /// Whether this key has no default system/typing action, making it a
    /// good trigger choice.
    var isRecommendable: Bool {
        kind == .modifier || Self.highFunctionKeys.contains(keyCode)
    }

    private static let highFunctionKeys: Set<Int64> = [105, 107, 113, 106, 64, 79, 80, 90]

    // MARK: - Key names (US layout for character keys)

    private static let keyNames: [Int64: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
        49: "Space", 48: "Tab", 36: "Return", 51: "Delete", 117: "Forward Delete",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
        41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9",
    ]

    private static func keyName(for keyCode: Int64) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }
}
