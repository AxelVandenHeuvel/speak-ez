import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

/// Checks and requests the three permissions the app cannot work without.
@MainActor
final class PermissionsManager {
    var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Needed for the listen-only keyboard event tap.
    var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Needed to post the synthetic Cmd+V that inserts text.
    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var allGranted: Bool {
        microphoneGranted && inputMonitoringGranted && accessibilityGranted
    }

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Triggers the system prompt (first time) or just reports current state.
    @discardableResult
    func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        // kAXTrustedCheckOptionPrompt is a C global the compiler cannot prove
        // is concurrency-safe; its string value is ABI-stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings(anchor: String) {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
