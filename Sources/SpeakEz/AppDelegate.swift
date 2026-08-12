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

    /// The idle menu-bar glyph: a little "ez", drawn as a template image so
    /// it follows the menu bar's light/dark appearance.
    private static let ezIcon: NSImage = {
        let base = NSFont.systemFont(ofSize: 14, weight: .heavy)
        let font =
            base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 14) } ?? base
        let text = NSAttributedString(
            string: "ez", attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: 16))
        image.lockFocus()
        text.draw(at: NSPoint(x: 0, y: (16 - textSize.height) / 2))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIdleIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStateChange = { [weak self] state in
            switch state {
            case .idle: self?.setIdleIcon()
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
                        self.setIdleIcon()
                    }
                }
            }
        }
    }

    private func setIdleIcon() {
        statusItem.button?.image = Self.ezIcon
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

        let verb = settings.triggerMode == .toggle ? "Tap" : "Hold"
        menu.addItem(disabledItem("\(verb) \(settings.trigger.displayName) to dictate"))
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

        // Trigger mode picker (hold vs tap-to-toggle).
        let modeMenu = NSMenu()
        for mode in TriggerInterpreter.Mode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectTriggerMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.triggerMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        let modeRoot = NSMenuItem(title: "Trigger Mode", action: nil, keyEquivalent: "")
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        // Trigger key picker: presets plus a press-any-key recorder.
        let triggerMenu = NSMenu()
        for (index, preset) in TriggerSpec.presets.enumerated() {
            let item = NSMenuItem(
                title: preset.displayName,
                action: #selector(selectPresetTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = settings.trigger == preset ? .on : .off
            triggerMenu.addItem(item)
        }
        if !TriggerSpec.presets.contains(settings.trigger) {
            let custom = NSMenuItem(
                title: "Custom: \(settings.trigger.displayName)", action: nil, keyEquivalent: "")
            custom.state = .on
            triggerMenu.addItem(custom)
        }
        triggerMenu.addItem(.separator())
        let recordItem = NSMenuItem(
            title: "Set Custom Trigger Key…",
            action: #selector(recordCustomTrigger), keyEquivalent: "")
        recordItem.target = self
        triggerMenu.addItem(recordItem)

        let triggerRoot = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        triggerRoot.submenu = triggerMenu
        menu.addItem(triggerRoot)

        let addTermItem = NSMenuItem(
            title: "Add Vocabulary Term…", action: #selector(addVocabularyTerm),
            keyEquivalent: "")
        addTermItem.target = self
        menu.addItem(addTermItem)

        let vocabItem = NSMenuItem(
            title: "Edit Vocabulary File…", action: #selector(editVocabulary), keyEquivalent: "")
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

    @objc private func selectPresetTrigger(_ sender: NSMenuItem) {
        guard TriggerSpec.presets.indices.contains(sender.tag) else { return }
        controller.applyTrigger(TriggerSpec.presets[sender.tag])
    }

    @objc private func recordCustomTrigger() {
        controller.captureTrigger { [weak self] spec in
            guard let self, let spec else { return }
            self.controller.applyTrigger(spec)
            if !spec.isRecommendable {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Heads up: \(spec.displayName) keeps its normal action"
                alert.informativeText =
                    "speakEZ listens without blocking keys, so pressing "
                    + "\(spec.displayName) will still do what it usually does "
                    + "while also triggering dictation. Modifier keys or F13 to F19 "
                    + "make cleaner triggers."
                alert.runModal()
            }
        }
    }

    @objc private func selectTriggerMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let mode = TriggerInterpreter.Mode(rawValue: raw)
        else { return }
        controller.applyTriggerMode(mode)
    }

    @objc private func addVocabularyTerm() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Vocabulary Term"
        alert.informativeText =
            "The exact spelling to insert, and optionally the things the "
            + "transcriber mishears for it, separated by commas."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let termField = NSTextField(frame: NSRect(x: 0, y: 34, width: 260, height: 24))
        termField.placeholderString = "Term, e.g. tmux"
        let aliasField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        aliasField.placeholderString = "Sound-alikes, e.g. tea mux, teemux"
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        accessory.addSubview(termField)
        accessory.addSubview(aliasField)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = termField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let term = termField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        let aliases = aliasField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let store = VocabularyStore.standard()
        var terms = store.loadVocabulary()
        if let existing = terms.firstIndex(where: {
            $0.text.lowercased() == term.lowercased()
        }) {
            // Merge new aliases into the existing entry.
            let merged = Set(terms[existing].aliases + aliases)
            terms[existing] = VocabTerm(
                text: terms[existing].text, aliases: merged.sorted(), enabled: true)
        } else {
            terms.append(VocabTerm(text: term, aliases: aliases, enabled: true))
        }
        do {
            try store.saveVocabulary(terms)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not save the vocabulary"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
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
