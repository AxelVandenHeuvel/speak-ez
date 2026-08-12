import AppKit
import SwiftUI

/// What the floating capsule is currently showing.
enum OverlayPhase: Equatable {
    case hidden
    case recording
    case processing
    case error(String)
    /// An instruction to the user, e.g. during trigger-key capture.
    case prompt(String)
}

@MainActor
@Observable
final class OverlayModel {
    var phase: OverlayPhase = .hidden
    /// Smoothed mic level, 0...1.
    var level: Float = 0
    /// Secondary caption, e.g. "Tap Right Option to stop" in toggle mode.
    var hint: String?
}

/// A small always-on-top, non-activating capsule at the bottom of the screen.
/// It never takes focus and ignores clicks, so it cannot steal the user's
/// cursor away from the app they are dictating into.
@MainActor
final class RecordingOverlayPanel {
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayView>
    let model = OverlayModel()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hostingView = NSHostingView(
            rootView: OverlayView(phase: .hidden, hint: nil, model: model))
        panel.contentView = hostingView
    }

    func show(_ phase: OverlayPhase) {
        model.phase = phase
        model.hint = nil
        refreshLayout()
        panel.orderFrontRegardless()
    }

    /// Resizes the panel to fit its content. The phase and hint are passed
    /// into the view directly (not read through the observable model) so the
    /// measurement below sees the new content synchronously; otherwise the
    /// panel gets sized against the previous state and clips or hides text.
    func refreshLayout() {
        hostingView.rootView = OverlayView(phase: model.phase, hint: model.hint, model: model)
        var size = hostingView.fittingSize
        size.width = max(size.width, 60)
        size.height = max(size.height, 44)
        panel.setContentSize(size)
        position()
    }

    func hide() {
        model.phase = .hidden
        model.level = 0
        model.hint = nil
        panel.orderOut(nil)
    }

    private func position() {
        // NSScreen.main is the screen with keyboard focus, which is where the
        // user is dictating.
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 60
            ))
    }
}

struct OverlayView: View {
    let phase: OverlayPhase
    let hint: String?
    /// Only the live mic level is read through the model; it animates
    /// without affecting layout.
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            switch phase {
            case .hidden:
                EmptyView()
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                LevelBars(level: model.level)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .processing:
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.callout)
                    .lineLimit(1)
            case .prompt(let message):
                Image(systemName: "keyboard")
                Text(message)
                    .font(.callout)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(4)
        .opacity(phase == .hidden ? 0 : 1)
    }
}

/// Five bars that dance with the mic level, like every dictation UI ever.
struct LevelBars: View {
    let level: Float
    private static let weights: [Float] = [0.45, 0.75, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.weights.count, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
        // Fixed footprint so the capsule never resizes with the voice level.
        .frame(width: 27, height: 22)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let weighted = level * Self.weights[index]
        return CGFloat(4 + weighted * 18)
    }
}
