import SwiftUI
import AppKit

/// Full control center in the menu-bar popup — almost everything without opening Settings.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelDL = ModelDownloadService.shared

    private let maxScrollHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    permissionBanner
                    statusBlock
                    modeSection
                    engineSection
                    engineOptionsSection
                    hotkeySection
                    optionsSection
                    actionsSection
                    historySection
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: maxScrollHeight)

            GlassDivider()
                .padding(.vertical, 10)
            footer
        }
        .padding(14)
        .frame(width: GlassTheme.panelWidth)
        .background {
            GlassBackground(cornerRadius: GlassTheme.cornerLarge, material: .ultraThinMaterial, intense: true)
                .shadow(color: GlassTheme.softShadow, radius: 28, y: 12)
        }
        .padding(6)
        .onAppear {
            appState.refreshPermissions()
            Task { await appState.refreshModelStatus() }
        }
    }

    // MARK: - Helpers

    private func bindBool(_ keyPath: ReferenceWritableKeyPath<AppState, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState[keyPath: keyPath] },
            set: {
                appState.objectWillChange.send()
                appState[keyPath: keyPath] = $0
            }
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        GlassSectionLabel(text: text)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))

            VStack(alignment: .leading, spacing: 2) {
                Text("PushToType")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var headerSubtitle: String {
        "\(appState.mode.shortTitle) · \(appState.transcriptionEngine.displayName)"
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionBanner: some View {
        let p = appState.permissions
        if !p.allGood {
            GlassCard(padding: 10, cornerRadius: GlassTheme.cornerSmall) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Permissions")
                    HStack(spacing: 6) {
                        GlassChip(title: "Mic", ok: p.microphone) {
                            PermissionDoctor.requestMicrophone()
                            PermissionDoctor.openMicrophoneSettings()
                        }
                        GlassChip(title: "Access", ok: p.accessibility) {
                            if !p.accessibility {
                                PermissionDoctor.requestAccessibility()
                                PermissionDoctor.openAccessibilitySettings()
                            }
                        }
                        GlassChip(title: "Speech", ok: p.speech) {
                            PermissionDoctor.requestSpeech()
                            PermissionDoctor.openSpeechSettings()
                        }
                    }
                    Text("Paste needs Accessibility enabled for PushToType.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status

    private var statusBlock: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.55), radius: 3)
                    Text(appState.statusText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(appState.modelStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let err = appState.errorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(3)
                }
                if !appState.livePreview.isEmpty {
                    Text(appState.livePreview)
                        .font(.caption)
                        .lineLimit(5)
                        .truncationMode(.tail)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
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

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Mode")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(DictationMode.allCases) { mode in
                    chip(mode.shortTitle, selected: appState.mode == mode) {
                        appState.mode = mode
                    }
                }
            }
            Text(appState.mode.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Engine")
            ForEach(TranscriptionEngine.allCases) { engine in
                engineRow(engine)
            }
        }
    }

    private func engineRow(_ engine: TranscriptionEngine) -> some View {
        let selected = appState.transcriptionEngine == engine
        return Button {
            appState.transcriptionEngine = engine
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(engineBlurb(engine))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.1),
                        lineWidth: selected ? 1 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func engineBlurb(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .appleSpeech: return "Built-in · no download"
        case .parakeet: return "Fast local · NVIDIA"
        case .whisper: return "Multilingual · translate"
        }
    }

    // MARK: - Engine-specific options

    @ViewBuilder
    private var engineOptionsSection: some View {
        switch appState.transcriptionEngine {
        case .parakeet:
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Parakeet model")
                ForEach(ParakeetModel.allCases) { model in
                    optionRow(
                        title: model == .tdt06bV2 ? "English (v2)" : "Multilingual (v3)",
                        subtitle: model.detail,
                        selected: appState.selectedParakeetModel == model
                    ) {
                        appState.selectedParakeetModel = model
                    }
                }
                if !appState.modelReady {
                    Button {
                        appState.installParakeetRuntime()
                    } label: {
                        Label(
                            appState.parakeetInstallBusy ? "Installing Parakeet…" : "Install Parakeet runtime",
                            systemImage: "arrow.down.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                    .disabled(appState.parakeetInstallBusy)
                } else {
                    Button("Warm Parakeet") {
                        Task { await appState.warmParakeet() }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                }
            }

        case .whisper:
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Whisper")
                Picker("Preset", selection: Binding(
                    get: { appState.speedPreset },
                    set: { appState.speedPreset = $0 }
                )) {
                    ForEach(SpeedPreset.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Model", selection: Binding(
                    get: { appState.selectedModel },
                    set: { m in
                        appState.selectedModel = m
                        Task { await appState.refreshModelStatus() }
                    }
                )) {
                    ForEach(WhisperModel.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()

                if modelDL.isDownloading {
                    ProgressView(value: modelDL.progress) {
                        Text(modelDL.status).font(.caption2)
                    }
                } else if !modelDL.isDownloaded(appState.selectedModel) {
                    Button("Download \(appState.selectedModel.displayName)") {
                        appState.downloadWhisperModel(appState.selectedModel)
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                } else {
                    Button("Warm Whisper") {
                        Task { await appState.warmWhisper() }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                }
            }

        case .appleSpeech:
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("macOS Speech")
                Text("Uses system speech recognition. Grant Speech permission if live partials fail.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Request Speech permission") {
                    PermissionDoctor.requestSpeech()
                    Task { await appState.refreshModelStatus() }
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Hotkey + language

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Hotkey")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(HotkeyPreset.allCases) { preset in
                    chip(preset.displayName, selected: appState.hotkeyPreset == preset) {
                        appState.hotkeyPreset = preset
                    }
                }
            }
            Text(appState.hotkeyPreset.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            sectionLabel("Language")
            Picker("Language", selection: Binding(
                get: { appState.language },
                set: {
                    appState.objectWillChange.send()
                    appState.language = $0
                }
            )) {
                Text("Auto").tag("auto")
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Portuguese").tag("pt")
                Text("Italian").tag("it")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
                Text("Korean").tag("ko")
                Text("Russian").tag("ru")
            }
            .labelsHidden()
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Options")
            toggleRow("Auto-paste at cursor", bindBool(\.autoPaste))
            toggleRow("Live partials while holding", bindBool(\.livePartials))
            toggleRow("Show live overlay", bindBool(\.showLiveOverlay))
            toggleRow("Smart punctuation", bindBool(\.smartPunctuation))
            toggleRow("Strip light fillers", bindBool(\.stripLightFillers))
            toggleRow("Play sounds", bindBool(\.playSounds))
            toggleRow("Warm model on launch", bindBool(\.warmModelOnLaunch))

            Picker("Overlay", selection: Binding(
                get: { appState.overlayPosition },
                set: { appState.overlayPosition = $0 }
            )) {
                ForEach(OverlayPosition.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Actions")
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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(appState.isTranscribing || appState.isEnhancing)

            if appState.isRecording {
                Button("Cancel recording") { appState.cancelDictation() }
                    .buttonStyle(GlassSecondaryButtonStyle())
            }

            HStack(spacing: 6) {
                Button("Copy last") { appState.copyLast() }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(appState.lastTranscript.isEmpty)
                Button("Paste last") { appState.pasteLast() }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(appState.lastTranscript.isEmpty)
            }

            Button("Test paste") {
                appState.injector.rememberTargetApp()
                let marker = "PushToType ✓"
                appState.showOverlay = false
                NSApp.deactivate()
                appState.injector.insertAfterDelay(marker, delay: 0.08, prepareFocus: nil) { method in
                    DispatchQueue.main.async {
                        appState.lastTranscript = marker
                        appState.livePreview = marker
                        if method == .accessibility || method == .appleScriptPaste
                            || method == .terminalPaste || method == .clipboardPaste || method == .typedText {
                            appState.statusText = "Test paste OK"
                            appState.errorMessage = nil
                        } else {
                            appState.statusText = "Test paste failed — press ⌘V"
                            if !TextInjector.accessibilityGranted() {
                                appState.errorMessage = "Enable Accessibility"
                            }
                        }
                    }
                }
            }
            .buttonStyle(GlassSecondaryButtonStyle())

            Text("Hold \(appState.hotkeyPreset.displayName) · release to insert")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        if !appState.filteredHistory.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("Recent")
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

                ForEach(appState.filteredHistory.prefix(5)) { entry in
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
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button("Advanced settings…") {
                    SettingsWindowController.shared.show(appState: appState)
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                Spacer(minLength: 0)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit PushToType", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle(destructive: true))
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Shared chips / rows

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0.28 : 0.1), lineWidth: 0.6)
                }
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func optionRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            }
        }
        .buttonStyle(.plain)
    }
}
