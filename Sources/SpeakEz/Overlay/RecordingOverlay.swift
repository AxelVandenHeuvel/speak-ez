import AppKit
import SwiftUI

/// What the floating capsule is currently showing.
enum OverlayPhase: Equatable {
    case hidden
    case recording
    case processing
    case error(String)
}

@MainActor
@Observable
final class OverlayModel {
    var phase: OverlayPhase = .hidden
    /// Smoothed mic level, 0...1.
    var level: Float = 0
}

/// A small always-on-top, non-activating capsule at the bottom of the screen.
/// It never takes focus and ignores clicks, so it cannot steal the user's
/// cursor away from the app they are dictating into.
@MainActor
final class RecordingOverlayPanel {
    private let panel: NSPanel
    let model = OverlayModel()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
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
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show(_ phase: OverlayPhase) {
        model.phase = phase
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        model.phase = .hidden
        model.level = 0
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
    let model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .hidden:
                EmptyView()
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                LevelBars(level: model.level)
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.phase == .hidden ? 0 : 1)
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
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let weighted = level * Self.weights[index]
        return CGFloat(4 + weighted * 18)
    }
}
