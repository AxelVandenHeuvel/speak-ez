import AppKit
import ServiceManagement
import SpeakEzKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = PermissionsManager()
    private let controller = DictationController()
    private let settings = AppSettings.shared
    private var modelStatus: TranscriptionService.Status = .notLoaded
    private var hotkeyRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("waveform")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStateChange = { [weak self] state in
            switch state {
            case .idle: self?.setIcon("waveform")
            case .recording: self?.setIcon("record.circle.fill")
            case .processing: self?.setIcon("ellipsis.circle")
            case .inserting: self?.setIcon("text.cursor")
            }
        }
        controller.onModelStatus = { [weak self] status in
            self?.modelStatus = status
        }

        Task { [weak self] in
            await self?.requestPermissionsAndStart()
        }
    }

    private func requestPermissionsAndStart() async {
        NSLog(
            "Permissions at launch: mic=%d input=%d ax=%d",
            permissions.microphoneGranted ? 1 : 0,
            permissions.inputMonitoringGranted ? 1 : 0,
            permissions.accessibilityGranted ? 1 : 0)
        if !permissions.microphoneGranted {
            _ = await permissions.requestMicrophone()
        }
        if !permissions.inputMonitoringGranted {
            permissions.requestInputMonitoring()
        }
        if !permissions.accessibilityGranted {
            permissions.requestAccessibility()
        }

        controller.start()
        if !controller.startHotkey() {
            // Input Monitoring not granted yet: retry until it is, so the
            // user does not have to relaunch after flipping the toggle.
            setIcon("exclamationmark.triangle")
            hotkeyRetryTimer = Timer.scheduledTimer(
                withTimeInterval: 3, repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.controller.startHotkey() {
                        self.hotkeyRetryTimer?.invalidate()
                        self.hotkeyRetryTimer = nil
                        self.setIcon("waveform")
                    }
                }
            }
        }
    }

    private func setIcon(_ symbolName: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName, accessibilityDescription: "speakEZ")
    }

    // MARK: - Menu

    /// The menu is rebuilt every time it opens so statuses are always fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(modelStatusTitle))
        menu.addItem(.separator())

        // The event tap actually running is the ground truth for Input
        // Monitoring; the permission API can lag or lie after re-signing.
        let inputMonitoringOK = controller.hotkeyActive || permissions.inputMonitoringGranted
        let allOK =
            permissions.microphoneGranted && inputMonitoringOK
            && permissions.accessibilityGranted

        if !allOK {
            menu.addItem(permissionItem(
                "Microphone", granted: permissions.microphoneGranted,
                anchor: "Privacy_Microphone"))
            menu.addItem(permissionItem(
                "Input Monitoring", granted: inputMonitoringOK,
                anchor: "Privacy_ListenEvent"))
            menu.addItem(permissionItem(
                "Accessibility", granted: permissions.accessibilityGranted,
                anchor: "Privacy_Accessibility"))

            let relaunchItem = NSMenuItem(
                title: "Relaunch speakEZ (apply new permissions)",
                action: #selector(relaunch), keyEquivalent: "")
            relaunchItem.target = self
            menu.addItem(relaunchItem)
            menu.addItem(.separator())
        }

        menu.addItem(disabledItem("Hold \(settings.triggerKey.displayName) to dictate"))
        menu.addItem(.separator())

        // Refinement level picker.
        let refinementMenu = NSMenu()
        for level in RefinementLevel.allCases {
            let item = NSMenuItem(
                title: refinementTitle(level),
                action: #selector(selectRefinement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
            item.state = settings.refinementLevel == level ? .on : .off
            refinementMenu.addItem(item)
        }
        let refinementRoot = NSMenuItem(title: "Refinement", action: nil, keyEquivalent: "")
        refinementRoot.submenu = refinementMenu
        menu.addItem(refinementRoot)

        // Trigger key picker.
        let triggerMenu = NSMenu()
        for key in TriggerKey.allCases {
            let item = NSMenuItem(
                title: key.displayName,
                action: #selector(selectTriggerKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            item.state = settings.triggerKey == key ? .on : .off
            triggerMenu.addItem(item)
        }
        let triggerRoot = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        triggerRoot.submenu = triggerMenu
        menu.addItem(triggerRoot)

        let vocabItem = NSMenuItem(
            title: "Edit Vocabulary…", action: #selector(editVocabulary), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)

        let fillersItem = NSMenuItem(
            title: "Edit Filler Words…", action: #selector(editFillers), keyEquivalent: "")
        fillersItem.target = self
        menu.addItem(fillersItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin),
            keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit speakEZ", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
    }

    private var modelStatusTitle: String {
        switch modelStatus {
        case .notLoaded: return "Speech model: waiting"
        case .downloading: return "Speech model: downloading…"
        case .loading: return "Speech model: loading…"
        case .ready: return "Speech model: ready"
        case .failed(let message): return "Speech model failed: \(message)"
        }
    }

    private func refinementTitle(_ level: RefinementLevel) -> String {
        if level == .ai, let reason = AIRefiner.unavailabilityReason {
            return "\(level.displayName) (\(reason))"
        }
        return level.displayName
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func permissionItem(_ title: String, granted: Bool, anchor: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(granted ? "✓" : "✗") \(title)",
            action: granted ? nil : #selector(openPermissionSettings(_:)),
            keyEquivalent: "")
        item.target = self
        item.representedObject = anchor
        return item
    }

    // MARK: - Actions

    @objc private func selectRefinement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let level = RefinementLevel(rawValue: raw)
        else { return }
        settings.refinementLevel = level
        if level == .ai {
            AIRefiner.prewarm()
        }
    }

    @objc private func selectTriggerKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let key = TriggerKey(rawValue: raw)
        else { return }
        controller.applyTriggerKey(key)
    }

    /// Quits and reopens the app: needed after granting Input Monitoring or
    /// Accessibility, which macOS only applies at process launch.
    @objc private func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func editVocabulary() {
        let store = VocabularyStore.standard()
        if !FileManager.default.fileExists(atPath: store.vocabularyURL.path) {
            // Seed with an example so the JSON format is self-explanatory.
            try? store.saveVocabulary([
                VocabTerm(text: "tmux", aliases: ["tea mux"], enabled: true)
            ])
        }
        NSWorkspace.shared.open(store.vocabularyURL)
    }

    @objc private func editFillers() {
        let store = VocabularyStore.standard()
        if !FileManager.default.fileExists(atPath: store.fillersURL.path) {
            try? store.saveFillers(.standard)
        }
        NSWorkspace.shared.open(store.fillersURL)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login toggle failed: %@", error.localizedDescription)
        }
    }

    @objc private func openPermissionSettings(_ sender: NSMenuItem) {
        guard let anchor = sender.representedObject as? String else { return }
        PermissionsManager.openSystemSettings(anchor: anchor)
    }
}
