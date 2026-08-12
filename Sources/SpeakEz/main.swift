import AppKit

TranscribeCLI.runIfRequested()
TranscribeCLI.runRefineIfRequested()

// NSLog goes to stderr; keep a copy on disk so problems are diagnosable
// regardless of how the app was launched (unified log hides our entries).
let logDirectory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("speakEZ")
try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
let logPath = logDirectory.appendingPathComponent("debug.log").path
// Start fresh each launch; this is diagnostics, not history.
try? FileManager.default.removeItem(atPath: logPath)
freopen(logPath, "a", stderr)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
