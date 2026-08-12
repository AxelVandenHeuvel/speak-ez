import AppKit
import Foundation
import SpeakEzKit

/// Wires the hotkey, recorder, overlay, transcription, refinement, and
/// insertion together, driven by the pure `DictationStateMachine`.
@MainActor
final class DictationController {
    static let maxRecordingDuration: TimeInterval = 5 * 60

    private var machine = DictationStateMachine()
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let overlay = RecordingOverlayPanel()
    private let inserter = TextInserter()
    private(set) var transcription: TranscriptionService!

    /// Reflects state changes in the menu-bar icon.
    var onStateChange: ((DictationState) -> Void)?
    /// Latest model status, for the menu.
    var onModelStatus: ((TranscriptionService.Status) -> Void)?

    private let settings = AppSettings.shared
    private let store = VocabularyStore.standard()

    private var interpreter = TriggerInterpreter()
    private var recordingStartedAt: Date?

    private var maxDurationTimer: Timer?
    private var chunkTimer: Timer?
    private var pipelineTask: Task<Void, Never>?
    private var pendingTranscript: String = ""
    private var modelReady = false

    /// Serializes chunked-session operations so chunks always reach the
    /// transcriber in recording order.
    private var chunkChain: Task<Void, Never>?

    /// How often mid-recording audio is handed to the transcriber.
    private static let chunkInterval: TimeInterval = 10

    /// Sets up everything except the keyboard tap. Call once at launch.
    func start() {
        hotkey.trigger = settings.trigger
        interpreter.mode = settings.triggerMode
        if settings.refinementLevel == .ai {
            AIRefiner.prewarm()
        }
        transcription = TranscriptionService { [weak self] status in
            self?.modelReady = status == .ready
            self?.onModelStatus?(status)
        }
        Task { [transcription] in
            await transcription?.warmUp()
        }

        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            // Light smoothing so the meter does not flicker.
            let smoothed = self.overlay.model.level * 0.6 + level * 0.4
            self.overlay.model.level = smoothed
        }

        hotkey.onTriggerDown = { [weak self] in
            guard let self else { return }
            let elapsed =
                machine.state == .recording
                ? recordingStartedAt.map { -$0.timeIntervalSinceNow } : nil
            self.apply(self.interpreter.keyDown(recordingFor: elapsed))
        }
        hotkey.onTriggerUp = { [weak self] heldFor in
            guard let self else { return }
            let action = self.interpreter.keyUp(heldFor: heldFor)
            self.apply(action)
            // A quick tap that left the recording running: tell the user how
            // to end it.
            if action == .none, machine.state == .recording {
                overlay.model.hint = "Tap \(settings.trigger.displayName) to stop"
            }
        }
        hotkey.onEscape = { [weak self] in
            guard let self, machine.state != .idle else { return }
            self.handle(.escapePressed)
        }
        hotkey.onOtherKeyDuringHold = { [weak self] in
            // Trigger was part of a shortcut, not a dictation hold.
            self?.handle(.escapePressed)
        }

        // Note: no AVAudioEngine prewarm here. A bare `engine.prepare()` on
        // an engine with no tap installed hangs the main thread on macOS 26,
        // and the real spin-up on first recording costs only ~100 ms.
    }

    /// Tries to install the keyboard tap. False means Input Monitoring is
    /// not granted yet; safe to call again later.
    func startHotkey() -> Bool {
        hotkey.start()
    }

    /// Whether the keyboard tap is live (dictation can actually trigger).
    var hotkeyActive: Bool { hotkey.isRunning }

    private func apply(_ action: TriggerInterpreter.Action) {
        switch action {
        case .begin:
            handle(.triggerPressed)
        case .end(let heldFor):
            handle(.triggerReleased(heldFor: heldFor))
        case .none:
            break
        }
    }

    private func handle(_ event: DictationEvent) {
        let commands = machine.handle(event)
        onStateChange?(machine.state)
        for command in commands {
            execute(command)
        }
    }

    private func execute(_ command: DictationCommand) {
        switch command {
        case .startRecording:
            do {
                try recorder.start()
                recordingStartedAt = Date()
                overlay.show(.recording)
                startMaxDurationTimer()
                if modelReady {
                    enqueueChunkOperation { transcription in
                        await transcription.beginChunkedSession()
                    }
                    startChunkTimer()
                }
            } catch {
                NSLog("DictationController: mic start failed: %@", "\(error)")
                handle(.failed(reason: "Could not start the microphone"))
            }

        case .stopRecordingThenTranscribe:
            stopMaxDurationTimer()
            stopChunkTimer()
            recordingStartedAt = nil
            let segments = recorder.stop()
            overlay.show(.processing)
            pipelineTask = Task { [weak self] in
                await self?.runTranscription(segments)
            }

        case .refineTranscript:
            pipelineTask = Task { [weak self] in
                await self?.runRefinement()
            }

        case .insertText:
            deliver(pendingTranscript)

        case .discardRecording:
            stopMaxDurationTimer()
            stopChunkTimer()
            recordingStartedAt = nil
            recorder.discard()
            abandonChunkSession()
            overlay.hide()

        case .abortProcessing:
            pipelineTask?.cancel()
            pipelineTask = nil
            abandonChunkSession()
            overlay.hide()

        case .reportError(let message):
            stopMaxDurationTimer()
            stopChunkTimer()
            recordingStartedAt = nil
            recorder.discard()
            abandonChunkSession()
            pipelineTask?.cancel()
            pipelineTask = nil
            flashError(message)
        }
    }

    // MARK: - Pipeline steps

    private func runTranscription(_ segments: [AudioSegment]) async {
        do {
            let text: String
            // Wait for any in-flight chunk transcriptions, then decide path.
            await chunkChain?.value
            if await transcription.hasActiveChunkSession {
                text = try await transcription.finishChunkedSession(tail: segments)
            } else {
                text = try await transcription.transcribe(segments)
            }
            guard !Task.isCancelled, machine.state == .processing else { return }
            if text.isEmpty {
                machine.handle(.failed(reason: ""))
                onStateChange?(machine.state)
                overlay.show(.error("Didn't catch anything"))
                hideOverlaySoon()
                return
            }
            pendingTranscript = text
            handle(.transcriptReady)
        } catch {
            guard !Task.isCancelled else { return }
            handle(.failed(reason: error.localizedDescription))
        }
    }

    private func runRefinement() async {
        guard machine.state == .processing else { return }
        let level = settings.refinementLevel
        if level != .off {
            let vocabulary = store.loadVocabulary()
            let rules = RulesRefiner(lexicon: store.loadFillers(), vocabulary: vocabulary)
            let ruleRefined = rules.refineSync(pendingTranscript)
            pendingTranscript = ruleRefined

            if level == .ai {
                let terms = vocabulary.filter(\.enabled).map(\.text)
                if let polished = await AIRefiner.refine(ruleRefined, vocabulary: terms) {
                    pendingTranscript = polished
                }
            }
        }
        guard !Task.isCancelled, machine.state == .processing else { return }
        handle(.refinementFinished)
    }

    /// Called when the user changes the trigger key in the menu or settings.
    func applyTrigger(_ spec: TriggerSpec) {
        settings.trigger = spec
        hotkey.trigger = spec
    }

    func applyTriggerMode(_ mode: TriggerInterpreter.Mode) {
        settings.triggerMode = mode
        interpreter.mode = mode
    }

    /// Shows a prompt and reports the next key the user presses.
    /// The completion receives nil if the user cancelled with Esc.
    func captureTrigger(completion: @escaping (TriggerSpec?) -> Void) {
        overlay.show(.prompt("Press the key to use as the trigger. Esc cancels."))
        hotkey.captureHandler = { [weak self] spec in
            self?.overlay.hide()
            completion(spec)
        }
    }

    private func deliver(_ text: String) {
        let outcome = inserter.insert(text)
        overlay.hide()
        switch outcome {
        case .inserted:
            handle(.insertionFinished)
        case .blockedBySecureInput:
            machine.handle(.insertionFinished)
            onStateChange?(machine.state)
            flashError("Can't dictate into a password field")
        }
        pendingTranscript = ""
    }

    // MARK: - Helpers

    private func flashError(_ message: String) {
        if message.isEmpty {
            overlay.hide()
            return
        }
        overlay.show(.error(message))
        hideOverlaySoon()
    }

    private func hideOverlaySoon() {
        let phaseWhenScheduled = overlay.model.phase
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.overlay.model.phase == phaseWhenScheduled else { return }
            self.overlay.hide()
        }
    }

    // MARK: - Chunked transcription while recording

    /// Appends an operation to the serial chunk chain, preserving order.
    private func enqueueChunkOperation(
        _ operation: @escaping @Sendable (TranscriptionService) async -> Void
    ) {
        let previous = chunkChain
        let transcription = transcription!
        chunkChain = Task {
            await previous?.value
            await operation(transcription)
        }
    }

    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(
            withTimeInterval: Self.chunkInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.drainChunk()
            }
        }
    }

    private func stopChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = nil
    }

    private func drainChunk() {
        guard machine.state == .recording,
            let segments = recorder.drainForChunking()
        else { return }
        enqueueChunkOperation { transcription in
            try? await transcription.feedChunk(segments)
        }
    }

    /// Clears any chunked session once in-flight chunk work has drained.
    private func abandonChunkSession() {
        enqueueChunkOperation { transcription in
            await transcription.abandonChunkedSession()
        }
    }

    // MARK: - 5 minute cap

    private func startMaxDurationTimer() {
        maxDurationTimer = Timer.scheduledTimer(
            withTimeInterval: Self.maxRecordingDuration, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handle(.maxDurationReached)
            }
        }
    }

    private func stopMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }
}
