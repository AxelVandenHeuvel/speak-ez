import Testing
@testable import SpeakEzKit

@Suite struct DictationStateMachineTests {
    @Test func happyPath() {
        var machine = DictationStateMachine()
        #expect(machine.handle(.triggerPressed) == [.startRecording])
        #expect(machine.state == .recording)
        #expect(machine.handle(.triggerReleased(heldFor: 2.0)) == [.stopRecordingThenTranscribe])
        #expect(machine.state == .processing)
        #expect(machine.handle(.transcriptReady) == [.refineTranscript])
        #expect(machine.handle(.refinementFinished) == [.insertText])
        #expect(machine.state == .inserting)
        #expect(machine.handle(.insertionFinished) == [])
        #expect(machine.state == .idle)
    }

    @Test func accidentalTapIsDiscarded() {
        var machine = DictationStateMachine(minimumHoldDuration: 0.3)
        machine.handle(.triggerPressed)
        #expect(machine.handle(.triggerReleased(heldFor: 0.1)) == [.discardRecording])
        #expect(machine.state == .idle)
    }

    @Test func escapeCancelsRecording() {
        var machine = DictationStateMachine()
        machine.handle(.triggerPressed)
        #expect(machine.handle(.escapePressed) == [.discardRecording])
        #expect(machine.state == .idle)
    }

    @Test func escapeAbandonsProcessing() {
        var machine = DictationStateMachine()
        machine.handle(.triggerPressed)
        machine.handle(.triggerReleased(heldFor: 1.0))
        #expect(machine.handle(.escapePressed) == [.abortProcessing])
        #expect(machine.state == .idle)
    }

    @Test func maxDurationBehavesLikeRelease() {
        var machine = DictationStateMachine()
        machine.handle(.triggerPressed)
        #expect(machine.handle(.maxDurationReached) == [.stopRecordingThenTranscribe])
        #expect(machine.state == .processing)
    }

    @Test func failureFromAnyStateReturnsToIdle() {
        var machine = DictationStateMachine()
        machine.handle(.triggerPressed)
        machine.handle(.triggerReleased(heldFor: 1.0))
        #expect(machine.handle(.failed(reason: "model not loaded")) == [.reportError("model not loaded")])
        #expect(machine.state == .idle)
    }

    @Test func overlappingTriggerWhileProcessingIsIgnored() {
        var machine = DictationStateMachine()
        machine.handle(.triggerPressed)
        machine.handle(.triggerReleased(heldFor: 1.0))
        #expect(machine.handle(.triggerPressed) == [])
        #expect(machine.state == .processing)
    }

    @Test func releaseWithoutRecordingDoesNothing() {
        var machine = DictationStateMachine()
        #expect(machine.handle(.triggerReleased(heldFor: 1.0)) == [])
        #expect(machine.state == .idle)
    }
}
