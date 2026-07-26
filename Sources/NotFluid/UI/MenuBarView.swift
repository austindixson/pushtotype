import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            permissionBanner
            GlassDivider()
            modePicker
            GlassDivider()
            statusBlock
            GlassDivider()
            actions
            if !appState.filteredHistory.isEmpty {
                GlassDivider()
                historyBlock
            }
            GlassDivider()
            footer
        }
        .padding(16)
        .frame(width: GlassTheme.panelWidth)
        .background {
            GlassBackground(cornerRadius: GlassTheme.cornerLarge, material: .ultraThinMaterial, intense: true)
                .shadow(color: GlassTheme.softShadow, radius: 28, y: 12)
        }
        .padding(6)
        .onAppear { appState.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.95))
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text("n0tfluid")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(headerSubtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var headerSubtitle: String {
        var parts = [appState.transcriptionEngine.displayName]
        if appState.transcriptionEngine == .whisper {
            parts.append(appState.speedPreset.displayName)
        }
        if appState.enhancementMode == .webLLM { parts.append("LLM") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var permissionBanner: some View {
        let p = appState.permissions
        if !p.allGood {
            GlassCard(padding: 10, cornerRadius: GlassTheme.cornerSmall) {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionLabel(text: "Permissions")
                    HStack(spacing: 8) {
                        GlassChip(title: "Mic", ok: p.microphone) {
                            PermissionDoctor.requestMicrophone()
                            PermissionDoctor.openMicrophoneSettings()
                        }
                        GlassChip(title: "Access", ok: p.accessibility) {
                            PermissionDoctor.requestAccessibility()
                            PermissionDoctor.openAccessibilitySettings()
                        }
                        if appState.transcriptionEngine == .appleSpeech || appState.livePartials {
                            GlassChip(title: "Speech", ok: p.speech) {
                                PermissionDoctor.requestSpeech()
                                PermissionDoctor.openSpeechSettings()
                            }
                        }
                    }
                    Text("Paste needs Accessibility. Rebuilds may require re-enabling it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionLabel(text: "Mode")
            // 4 modes: two rows of chips (segmented gets too tight)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(DictationMode.allCases) { mode in
                    Button {
                        appState.mode = mode
                    } label: {
                        Text(mode.shortTitle)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(appState.mode == mode ? Color.accentColor.opacity(0.85) : Color.clear)
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .opacity(appState.mode == mode ? 0 : 1)
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        appState.mode == mode ? Color.white.opacity(0.3) : Color.white.opacity(0.12),
                                        lineWidth: 0.6
                                    )
                            }
                            .foregroundStyle(appState.mode == mode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(appState.mode.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GlassSectionLabel(text: "Engine")
                .padding(.top, 4)
            Picker("Engine", selection: Binding(
                get: { appState.transcriptionEngine },
                set: { appState.transcriptionEngine = $0 }
            )) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Live partials", isOn: $appState.livePartials)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
            Toggle("LLM boost (WebGPU)", isOn: Binding(
                get: { appState.enhancementMode == .webLLM },
                set: { on in
                    appState.enhancementMode = on ? .webLLM : .off
                    if on && !WebLLMEnhancer.shared.isReady {
                        appState.downloadSuggestedLLM()
                    }
                }
            ))
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var statusBlock: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.6), radius: 4)
                    Text(appState.statusText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(appState.modelStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if appState.enhancementMode == .webLLM {
                    Text(appState.llmStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let err = appState.errorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(3)
                }
                if !appState.livePreview.isEmpty {
                    Text(appState.livePreview)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(6)
                        .truncationMode(.tail)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        }
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing || appState.isEnhancing { return .orange }
        if appState.modelReady && appState.permissions.allGood { return .green }
        return .yellow
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    if appState.isRecording {
                        appState.stopDictationAndTranscribe()
                    } else {
                        appState.startDictation()
                    }
                } label: {
                    Label(
                        appState.isRecording ? "Stop & Transcribe" : "Start Dictation",
                        systemImage: appState.isRecording ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(GlassProminentButtonStyle())
                .disabled(appState.isTranscribing || appState.isEnhancing)

                if appState.isRecording {
                    Button("Cancel") { appState.cancelDictation() }
                        .buttonStyle(GlassSecondaryButtonStyle())
                }
            }

            HStack(spacing: 6) {
                Button("Copy last") { appState.copyLast() }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(appState.lastTranscript.isEmpty)
                Button("Paste last") { appState.pasteLast() }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(appState.lastTranscript.isEmpty)
                Button("Test paste") {
                    appState.injector.rememberTargetApp()
                    let marker = "n0tfluid ✓"
                    appState.showOverlay = false
                    NSApp.deactivate()
                    appState.injector.insertAfterDelay(
                        marker,
                        delay: 0.1,
                        prepareFocus: nil,
                        completion: { method in
                            DispatchQueue.main.async {
                                appState.lastTranscript = marker
                                appState.livePreview = marker
                                if method == .accessibility || method == .appleScriptPaste || method == .terminalPaste {
                                    appState.statusText = "Test paste OK"
                                    appState.errorMessage = nil
                                } else {
                                    appState.statusText = "Test paste failed"
                                    appState.errorMessage = "Enable Accessibility"
                                    TextInjector.openAccessibilitySettings()
                                }
                            }
                        }
                    )
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                Spacer(minLength: 0)
            }

            Text("Hold \(appState.hotkeyPreset.displayName) · release to insert")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GlassSectionLabel(text: "Recent")
                Spacer()
                Button("Export") {
                    if let url = appState.exportHistoryMarkdown() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                Button("Clear") { appState.clearHistory() }
                    .buttonStyle(GlassSecondaryButtonStyle())
            }
            TextField("Search history", text: $appState.historyFilter)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }

            ForEach(appState.filteredHistory.prefix(6)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        appState.togglePin(entry.id)
                    } label: {
                        Image(systemName: entry.pinned ? "pin.fill" : "pin")
                            .font(.caption2)
                            .foregroundStyle(entry.pinned ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        appState.injector.copyToClipboard(entry.text)
                        appState.lastTranscript = entry.text
                        appState.statusText = "Copied from history"
                    } label: {
                        Text(entry.text)
                            .font(.caption)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate()
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                Spacer()
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit n0tfluid", systemImage: "power")
            }
            .buttonStyle(GlassProminentButtonStyle(destructive: true))
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
