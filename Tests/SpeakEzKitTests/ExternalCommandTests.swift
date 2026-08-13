import Foundation
import Testing
@testable import SpeakEzKit

@Suite struct ExternalCommandTests {
    @Test func parsesHostForm() {
        #expect(ExternalCommand(url: URL(string: "speakez://toggle")!) == .toggle)
        #expect(ExternalCommand(url: URL(string: "speakez://start")!) == .start)
        #expect(ExternalCommand(url: URL(string: "speakez://stop")!) == .stop)
        #expect(ExternalCommand(url: URL(string: "speakez://cancel")!) == .cancel)
    }

    @Test func parsesPathForm() {
        #expect(ExternalCommand(url: URL(string: "speakez:///toggle")!) == .toggle)
    }

    @Test func isCaseInsensitive() {
        #expect(ExternalCommand(url: URL(string: "speakez://Toggle")!) == .toggle)
    }

    @Test func rejectsForeignSchemesAndUnknownCommands() {
        #expect(ExternalCommand(url: URL(string: "https://toggle")!) == nil)
        #expect(ExternalCommand(url: URL(string: "speakez://selfdestruct")!) == nil)
    }
}
