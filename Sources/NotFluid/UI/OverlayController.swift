import AppKit
import SwiftUI

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top of screen"
        case .bottom: return "Bottom of screen"
        }
    }
}

/// Floating glass overlay for live + final transcript.
@MainActor
final class OverlayController {
    private var window: NSPanel?
    private weak var appState: AppState?
    private var hosting: NSHostingView<AnyView>?

    private let panelWidth: CGFloat = 500
    private let minHeight: CGFloat = 92
    private let maxHeight: CGFloat = 300

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if window == nil { buildWindow() }
        resizeToFit()
        position(window!)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func setBusy(_ busy: Bool) {
        _ = busy
        resizeToFit()
        if let window { position(window) }
    }

    func refreshLayout() {
        guard window != nil else { return }
        resizeToFit()
        if let window, window.isVisible {
            position(window)
        }
    }

    private func buildWindow() {
        guard let appState else { return }

        let root = AnyView(
            OverlayView()
                .environmentObject(appState)
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: minHeight)
        hosting = host

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // we draw glass shadow in SwiftUI
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        position(panel)
        window = panel
    }

    private func resizeToFit() {
        guard let hosting, let appState else { return }
        let text = displayTextEstimate(appState)
        let lines = max(2, min(10, estimatedLines(text)))
        let height = min(maxHeight, max(minHeight, 56 + CGFloat(lines) * 20))
        let size = NSSize(width: panelWidth, height: height)
        hosting.frame = NSRect(origin: .zero, size: size)
        window?.setContentSize(size)
    }

    private func estimatedLines(_ text: String) -> Int {
        let charsPerLine = 54
        let n = max(1, (text.count + charsPerLine - 1) / charsPerLine)
        let newlines = text.components(separatedBy: "\n").count
        return max(n, newlines)
    }

    private func displayTextEstimate(_ state: AppState) -> String {
        if !state.livePreview.isEmpty { return state.livePreview }
        return state.statusText
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let margin: CGFloat = 22
        let y: CGFloat
        switch appState?.overlayPosition ?? .top {
        case .top:
            y = visible.maxY - size.height - margin
        case .bottom:
            y = visible.minY + margin
        }
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}

struct OverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [dotColor.opacity(0.95), dotColor.opacity(0.55)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 18
                        )
                    )
                    .frame(width: 34, height: 34)
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.7)
                    .frame(width: 34, height: 34)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: dotColor.opacity(0.35), radius: 8, y: 2)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(phaseLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    Spacer(minLength: 0)
                    if appState.isEnhancing || appState.isTranscribing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Text(fullBodyText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(width: 500, alignment: .leading)
        .background {
            GlassBackground(cornerRadius: 22, material: .ultraThinMaterial, intense: true)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 24, y: 10)
        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
        .onChange(of: appState.livePreview) { _, _ in
            appState.noteOverlayContentChanged()
        }
        .onChange(of: appState.statusText) { _, _ in
            appState.noteOverlayContentChanged()
        }
        .onChange(of: appState.overlayPosition) { _, _ in
            appState.noteOverlayContentChanged()
        }
    }

    private var fullBodyText: String {
        let raw: String
        if !appState.livePreview.isEmpty {
            raw = appState.livePreview
        } else if appState.isRecording {
            raw = "Listening… release \(appState.hotkeyPreset.displayName) when done"
        } else {
            raw = appState.statusText
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : raw
    }

    private var dotColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing || appState.isEnhancing { return .orange }
        if appState.statusText.contains("✓") || appState.statusText.contains("Inserted") || appState.statusText.contains("Pasted") {
            return .green
        }
        return Color.accentColor
    }

    private var iconName: String {
        if appState.isEnhancing { return "brain" }
        if appState.isTranscribing { return "waveform" }
        if appState.isRecording { return "mic.fill" }
        if appState.statusText.contains("✓") { return "checkmark" }
        return "mic.fill"
    }

    private var phaseLabel: String {
        if appState.isEnhancing {
            if appState.statusText.localizedCaseInsensitiveContains("articulat") {
                return "ARTICULATING"
            }
            return "POLISHING"
        }
        if appState.isRecording {
            if appState.mode == .articulate { return "ARTICULATE · LISTEN" }
            return appState.livePreview.isEmpty ? "LISTENING" : "LISTENING · LIVE"
        }
        if appState.isTranscribing {
            if appState.statusText.localizedCaseInsensitiveContains("insert")
                || appState.statusText.localizedCaseInsensitiveContains("past") {
                return "INSERTING"
            }
            return "TRANSCRIBING"
        }
        if appState.statusText.contains("✓") { return "DONE" }
        if appState.statusText.contains("⌘V") { return "CLIPBOARD" }
        if appState.statusText.hasPrefix("Failed") { return "ERROR" }
        return "N0TFLUID"
    }
}
