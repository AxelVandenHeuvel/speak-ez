import AppKit
import CoreGraphics

/// Watches the keyboard system-wide with a listen-only CGEventTap and reports
/// hold/release of the trigger key, Esc presses, and any other key pressed
/// while the trigger is held (which cancels the hold so shortcuts like
/// fn+arrow keep working without dictating).
///
/// Requires the Input Monitoring permission.
@MainActor
final class HotkeyMonitor {
    var triggerKey: TriggerKey = .rightOption

    var onTriggerDown: (() -> Void)?
    var onTriggerUp: ((_ heldFor: TimeInterval) -> Void)?
    var onEscape: (() -> Void)?
    var onOtherKeyDuringHold: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var triggerDownSince: Date?

    private static let escapeKeyCode: Int64 = 53

    /// Returns false when the event tap could not be created,
    /// which almost always means Input Monitoring is not granted.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    // The tap runs on the run loop it was added to: main.
                    MainActor.assumeIsolated {
                        monitor.handle(type: type, event: event)
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: selfPtr
            )
        else {
            NSLog("HotkeyMonitor: CGEvent.tapCreate returned nil")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HotkeyMonitor: tap installed, trigger=%@", triggerKey.rawValue)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        triggerDownSince = nil
    }

    var isHolding: Bool { triggerDownSince != nil }

    /// True when the keyboard tap is actually installed and listening: the
    /// ground truth for whether dictation can trigger, regardless of what
    /// the permission APIs claim.
    var isRunning: Bool { eventTap != nil }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that stall; re-enable ours.
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == triggerKey.keyCode else { return }
            let pressed = triggerKey.isPressed(in: event.flags)
            if pressed, triggerDownSince == nil {
                triggerDownSince = Date()
                onTriggerDown?()
            } else if !pressed, let since = triggerDownSince {
                triggerDownSince = nil
                onTriggerUp?(Date().timeIntervalSince(since))
            }

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Self.escapeKeyCode {
                onEscape?()
            } else if triggerDownSince != nil {
                // The user is typing a shortcut with the trigger key held
                // (for example fn+arrow). Treat the hold as accidental.
                triggerDownSince = nil
                onOtherKeyDuringHold?()
            }

        default:
            break
        }
    }
}
