import Foundation

/// Commands that can arrive from outside the app via the speakez:// URL
/// scheme (Raycast, Shortcuts, Stream Deck, scripts).
public enum ExternalCommand: String, CaseIterable, Sendable {
    case toggle
    case start
    case stop
    case cancel

    /// Parses speakez://toggle, speakez://start, etc. Accepts the command
    /// as either the host (speakez://toggle) or the path (speakez:///toggle)
    /// since both forms appear in the wild depending on how tools build URLs.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "speakez" else { return nil }
        let name = (url.host ?? url.path.trimmingCharacters(in: ["/"])).lowercased()
        self.init(rawValue: name)
    }
}
