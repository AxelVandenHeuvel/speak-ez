import AppKit
import CoreGraphics

/// Watches the keyboard system-wide with a listen-only CGEventTap and reports
/// press/release of the trigger key, Esc presses, and any other key pressed
/// while the trigger is held (which cancels the hold so shortcuts like
/// option-arrow keep working without dictating).
///
/// Also provides a capture mode that reports the next key the user presses,
/// used by "Set Custom Trigger Key".
///
/// Requires the Input Monitoring permission.
@MainActor
final class HotkeyMonitor {
    var trigger: TriggerSpec = .rightOption

    var onTriggerDown: (() -> Void)?
    var onTriggerUp: ((_ heldFor: TimeInterval) -> Void)?
    var onEscape: (() -> Void)?
    var onOtherKeyDuringHold: (() -> Void)?

    /// While set, the next key press is reported here instead of being
    /// interpreted (nil means the user cancelled with Esc), and normal
    /// trigger handling is paused.
    var captureHandler: ((TriggerSpec?) -> Void)?

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
            | (1 << CGEventType.keyUp.rawValue)

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
        NSLog("HotkeyMonitor: tap installed, trigger=%@", trigger.displayName)
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
            return
        default:
            break
        }

        if captureHandler != nil {
            handleCapture(type: type, event: event)
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            guard trigger.kind == .modifier, keyCode == trigger.keyCode else { return }
            reportTrigger(pressed: trigger.isPressed(in: event.flags))

        case .keyDown:
            if trigger.kind == .regular, keyCode == trigger.keyCode {
                let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isAutorepeat {
                    reportTrigger(pressed: true)
                }
                return
            }
            if keyCode == Self.escapeKeyCode {
                onEscape?()
            } else if triggerDownSince != nil {
                // The user is typing a shortcut with the trigger key held
                // (for example option-arrow). Treat the hold as accidental.
                triggerDownSince = nil
                onOtherKeyDuringHold?()
            }

        case .keyUp:
            if trigger.kind == .regular, keyCode == trigger.keyCode {
                reportTrigger(pressed: false)
            }

        default:
            break
        }
    }

    private func reportTrigger(pressed: Bool) {
        if pressed, triggerDownSince == nil {
            triggerDownSince = Date()
            onTriggerDown?()
        } else if !pressed, let since = triggerDownSince {
            triggerDownSince = nil
            onTriggerUp?(Date().timeIntervalSince(since))
        }
    }

    private func handleCapture(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            if let spec = TriggerSpec.capturedModifier(keyCode: keyCode, flags: event.flags) {
                finishCapture(with: spec)
            }
        case .keyDown:
            if keyCode == Self.escapeKeyCode {
                finishCapture(with: nil)
            } else {
                finishCapture(with: TriggerSpec.capturedRegularKey(keyCode: keyCode))
            }
        default:
            break
        }
    }

    private func finishCapture(with spec: TriggerSpec?) {
        let handler = captureHandler
        captureHandler = nil
        triggerDownSince = nil
        handler?(spec)
    }
}
