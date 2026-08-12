import Testing
@testable import SpeakEzKit

@Suite struct TriggerInterpreterTests {
    @Test func holdModeIsPushToTalk() {
        var interpreter = TriggerInterpreter(mode: .hold)
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        #expect(interpreter.keyUp(heldFor: 2.0) == .end(heldFor: 2.0))
        // Short holds still report; the state machine discards them.
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        #expect(interpreter.keyUp(heldFor: 0.1) == .end(heldFor: 0.1))
    }

    @Test func toggleModeTapsStartAndStop() {
        var interpreter = TriggerInterpreter(mode: .toggle)
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        // Release of the starting tap does nothing.
        #expect(interpreter.keyUp(heldFor: 0.1) == .none)
        // Second tap stops.
        #expect(interpreter.keyDown(recordingFor: 5.0) == .end(heldFor: 5.0))
        // And its release is swallowed.
        #expect(interpreter.keyUp(heldFor: 0.1) == .none)
    }

    @Test func holdOrTapQuickTapTogglesOn() {
        var interpreter = TriggerInterpreter(mode: .holdOrTap)
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        // Quick release: recording keeps going.
        #expect(interpreter.keyUp(heldFor: 0.2) == .none)
        // Tap again to stop.
        #expect(interpreter.keyDown(recordingFor: 7.0) == .end(heldFor: 7.0))
        #expect(interpreter.keyUp(heldFor: 0.15) == .none)
    }

    @Test func holdOrTapLongHoldStopsOnRelease() {
        var interpreter = TriggerInterpreter(mode: .holdOrTap)
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        #expect(interpreter.keyUp(heldFor: 3.0) == .end(heldFor: 3.0))
    }

    @Test func suppressionResetsOnNextDown() {
        var interpreter = TriggerInterpreter(mode: .toggle)
        _ = interpreter.keyDown(recordingFor: nil)
        _ = interpreter.keyUp(heldFor: 0.1)
        _ = interpreter.keyDown(recordingFor: 4.0)  // stop tap, suppresses next up
        _ = interpreter.keyUp(heldFor: 0.1)
        // A fresh recording starts cleanly afterwards.
        #expect(interpreter.keyDown(recordingFor: nil) == .begin)
        #expect(interpreter.keyUp(heldFor: 0.1) == .none)
    }
}
