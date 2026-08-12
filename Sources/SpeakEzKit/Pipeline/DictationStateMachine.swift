import Foundation

/// The lifecycle of one dictation: what the app is doing right now.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording
    /// Transcribing and/or refining after the trigger key was released.
    case processing
    case inserting
}

/// Everything that can happen to the state machine, from the hotkey monitor,
/// the transcription pipeline, or timers.
public enum DictationEvent: Equatable, Sendable {
    case triggerPressed
    case triggerReleased(heldFor: TimeInterval)
    case escapePressed
    case maxDurationReached
    case transcriptReady
    case refinementFinished
    case insertionFinished
    case failed(reason: String)
}

/// Side effects the controller must perform after a transition.
/// The state machine stays pure; the controller owns audio, models, and UI.
public enum DictationCommand: Equatable, Sendable {
    case startRecording
    case stopRecordingThenTranscribe
    case discardRecording
    case refineTranscript
    case insertText
    case abortProcessing
    case reportError(String)
}

/// Pure hold-to-talk state machine.
///
/// idle -> recording (trigger down)
/// recording -> processing (trigger up after a real hold, or the 5-minute cap)
/// recording -> idle (accidental tap shorter than `minimumHoldDuration`, or Esc)
/// processing -> inserting -> idle, with Esc abandoning insertion.
public struct DictationStateMachine: Sendable {
    public private(set) var state: DictationState = .idle

    /// Holds shorter than this are treated as accidental taps and discarded.
    public let minimumHoldDuration: TimeInterval

    public init(minimumHoldDuration: TimeInterval = 0.3) {
        self.minimumHoldDuration = minimumHoldDuration
    }

    @discardableResult
    public mutating func handle(_ event: DictationEvent) -> [DictationCommand] {
        switch (state, event) {
        case (.idle, .triggerPressed):
            state = .recording
            return [.startRecording]

        case (.recording, .triggerReleased(let heldFor)):
            if heldFor < minimumHoldDuration {
                state = .idle
                return [.discardRecording]
            }
            state = .processing
            return [.stopRecordingThenTranscribe]

        case (.recording, .maxDurationReached):
            state = .processing
            return [.stopRecordingThenTranscribe]

        case (.recording, .escapePressed):
            state = .idle
            return [.discardRecording]

        case (.processing, .transcriptReady):
            return [.refineTranscript]

        case (.processing, .refinementFinished):
            state = .inserting
            return [.insertText]

        case (.processing, .escapePressed):
            state = .idle
            return [.abortProcessing]

        case (.inserting, .insertionFinished):
            state = .idle
            return []

        // A new hold arriving while we are still processing or inserting the
        // previous one is ignored: overlapping dictations are not supported.
        case (.processing, .triggerPressed), (.inserting, .triggerPressed):
            return []

        case (_, .failed(let reason)):
            state = .idle
            return [.reportError(reason)]

        default:
            return []
        }
    }
}
