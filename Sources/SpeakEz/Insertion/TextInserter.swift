import AppKit
import Carbon.HIToolbox

enum InsertionOutcome: Equatable {
    case inserted
    /// A password field (secure input) has focus; we refuse to type into it.
    case blockedBySecureInput
}

/// Puts text at the user's cursor in whatever app has focus.
///
/// Primary strategy: write to the pasteboard, synthesize Cmd+V, then restore
/// the previous pasteboard contents. This works in virtually every app and is
/// instant regardless of text length. A typing fallback exists for apps that
/// block synthetic paste.
@MainActor
final class TextInserter {
    private static let vKeyCode: CGKeyCode = 9

    func insert(_ text: String) -> InsertionOutcome {
        guard !IsSecureEventInputEnabled() else {
            return .blockedBySecureInput
        }
        pasteViaClipboard(text)
        return .inserted
    }

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Snapshot whatever the user had copied so we can put it back.
        let snapshot: [[String: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type.rawValue] = data
                }
            }
            return entry
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        synthesizePaste()

        // Give the frontmost app time to service the paste before restoring.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            // Only restore if nobody (including the user) touched the
            // pasteboard in the meantime.
            guard pasteboard.changeCount == ourChangeCount else { return }
            pasteboard.clearContents()
            guard !snapshot.isEmpty else { return }
            let items = snapshot.map { entry in
                let item = NSPasteboardItem()
                for (rawType, data) in entry {
                    item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
                }
                return item
            }
            pasteboard.writeObjects(items)
        }
    }

    private func synthesizePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Avoid the user's still-held modifiers (like fn) leaking into
        // the synthetic keystroke.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalKeyboardEvents], state: .eventSuppressionStateSuppressionInterval)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Fallback for apps that ignore synthetic Cmd+V: type the text directly
    /// as unicode keyboard events, in small chunks on scalar boundaries.
    func typeDirectly(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let chunk = scalars[index..<min(index + 20, scalars.count)]
            let utf16 = Array(String(String.UnicodeScalarView(chunk)).utf16)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                event.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }
            index += 20
            usleep(3000)
        }
    }
}
