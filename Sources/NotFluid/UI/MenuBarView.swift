import SwiftUI
import AppKit

/// Control center shown in the status-item panel.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelDL = ModelDownloadService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
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
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 480)

            Divider().opacity(0.35).padding(.vertical, 10)
            footer
        }
        .padding(14)
        .frame(width: 360)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .onAppear {
            appState.refreshPermissions()
            Task { await appState.refreshModelStatus() }
        }
    }

    // MARK: - Bindings that refresh the panel

    private func bindBool(_ keyPath: ReferenceWritableKeyPath<AppState, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState[keyPath: keyPath] },
            set: { appState[keyPath: keyPath] = $0 }
        )
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 34, height: 34)
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("PushToType")
                    .font(.headline.weight(.semibold))
                Text("\(appState.mode.shortTitle) · \(shortEngine)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .padding(.bottom, 10)
    }

    private var shortEngine: String {
        switch appState.transcriptionEngine {
        case .appleSpeech: return "Speech"
        case .parakeet: return "Parakeet"
        case .whisper: return "Whisper"
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionBanner: some View {
        let p = appState.permissions
        if !p.allGood {
            VStack(alignment: .leading, spacing: 8) {
                section("Permissions")
                HStack(spacing: 6) {
                    permChip("Mic", p.microphone) {
                        PermissionDoctor.requestMicrophone()
                        PermissionDoctor.openMicrophoneSettings()
                    }
                    permChip("Access", p.accessibility) {
                        if !p.accessibility {
                            PermissionDoctor.requestAccessibility()
                            PermissionDoctor.openAccessibilitySettings()
                        }
                    }
                    permChip("Speech", p.speech) {
                        PermissionDoctor.requestSpeech()
                        PermissionDoctor.openSpeechSettings()
                    }
                }
            }
        }
    }

    private func permChip(_ title: String, _ ok: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(ok ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(title).font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Status")
            Text(appState.statusText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
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
                    .lineLimit(4)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
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
            section("Mode")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(DictationMode.allCases) { mode in
                    selectChip(mode.shortTitle, selected: appState.mode == mode) {
                        appState.mode = mode
                    }
                }
            }
            Text(appState.mode.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Engine")
            ForEach(TranscriptionEngine.allCases) { engine in
                Button {
                    appState.transcriptionEngine = engine
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: appState.transcriptionEngine == engine ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appState.transcriptionEngine == engine ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(engine.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(engineBlurb(engine))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(appState.transcriptionEngine == engine
                                  ? Color.accentColor.opacity(0.12)
                                  : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func engineBlurb(_ e: TranscriptionEngine) -> String {
        switch e {
        case .appleSpeech: return "Built-in · no download"
        case .parakeet: return "Fast local · NVIDIA"
        case .whisper: return "Multilingual · translate"
        }
    }

    @ViewBuilder
    private var engineOptionsSection: some View {
        switch appState.transcriptionEngine {
        case .parakeet:
            VStack(alignment: .leading, spacing: 6) {
                section("Parakeet model")
                ForEach(ParakeetModel.allCases) { m in
                    Button {
                        appState.selectedParakeetModel = m
                    } label: {
                        HStack {
                            Image(systemName: appState.selectedParakeetModel == m ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(appState.selectedParakeetModel == m ? Color.accentColor : .secondary)
                            Text(m == .tdt06bV2 ? "English (v2)" : "Multilingual (v3)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
                if !appState.modelReady {
                    Button {
                        appState.installParakeetRuntime()
                    } label: {
                        Text(appState.parakeetInstallBusy ? "Installing…" : "Install Parakeet runtime")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.parakeetInstallBusy)
                }
            }
        case .whisper:
            VStack(alignment: .leading, spacing: 6) {
                section("Whisper")
                // Use tags + explicit onChange only — avoid Picker set storms on section appear
                Picker("Preset", selection: $appState.speedPreset) {
                    ForEach(SpeedPreset.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(WhisperModel.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .onChange(of: appState.selectedModel) { _, _ in
                    Task { await appState.refreshModelStatus() }
                }

                if modelDL.isDownloading {
                    ProgressView(value: modelDL.progress) {
                        Text(modelDL.status).font(.caption2)
                    }
                } else if !modelDL.isDownloaded(appState.selectedModel) {
                    Button("Download model") {
                        appState.downloadWhisperModel()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .appleSpeech:
            VStack(alignment: .leading, spacing: 6) {
                section("macOS Speech")
                Button("Request Speech permission") {
                    PermissionDoctor.requestSpeech()
                    Task { await appState.refreshModelStatus() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Hotkey / language / options

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Hotkey")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(HotkeyPreset.allCases) { p in
                    selectChip(p.displayName, selected: appState.hotkeyPreset == p) {
                        appState.hotkeyPreset = p
                    }
                }
            }
            Text(appState.hotkeyPreset.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            section("Language")
            Picker("Language", selection: $appState.language) {
                Text("Auto").tag("auto")
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Portuguese").tag("pt")
                Text("Italian").tag("it")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
            }
            .labelsHidden()
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Options")
            Toggle("Auto-paste at cursor", isOn: bindBool(\.autoPaste)).font(.caption).controlSize(.small)
            Toggle("Live partials", isOn: bindBool(\.livePartials)).font(.caption).controlSize(.small)
            Toggle("Show live overlay", isOn: bindBool(\.showLiveOverlay)).font(.caption).controlSize(.small)
            Toggle("Smart punctuation", isOn: bindBool(\.smartPunctuation)).font(.caption).controlSize(.small)
            Toggle("Strip light fillers", isOn: bindBool(\.stripLightFillers)).font(.caption).controlSize(.small)
            Toggle("Play sounds", isOn: bindBool(\.playSounds)).font(.caption).controlSize(.small)
            Toggle("Warm model on launch", isOn: bindBool(\.warmModelOnLaunch)).font(.caption).controlSize(.small)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Actions")
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
            .buttonStyle(.borderedProminent)
            .disabled(appState.isTranscribing || appState.isEnhancing)

            if appState.isRecording {
                Button("Cancel") { appState.cancelDictation() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                Button("Copy last") { appState.copyLast() }
                    .buttonStyle(.bordered)
                    .disabled(appState.lastTranscript.isEmpty)
                Button("Paste last") { appState.pasteLast() }
                    .buttonStyle(.bordered)
                    .disabled(appState.lastTranscript.isEmpty)
            }

            Button("Test paste") {
                appState.injector.rememberTargetApp()
                let marker = "PushToType ✓"
                appState.injector.insertAfterDelay(marker, delay: 0.08) { method in
                    DispatchQueue.main.async {
                        appState.lastTranscript = marker
                        appState.livePreview = marker
                        if method != nil && method != .clipboardOnly {
                            appState.statusText = "Test paste OK"
                            appState.errorMessage = nil
                        } else {
                            appState.statusText = "Test paste failed — press ⌘V"
                        }
                    }
                }
            }
            .buttonStyle(.bordered)

            Text("Hold \(appState.hotkeyPreset.displayName) · release to insert")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !appState.filteredHistory.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    section("Recent")
                    Spacer()
                    Button("Clear") { appState.clearHistory() }
                        .font(.caption2)
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

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Advanced settings…") {
                StatusItemController.shared.hidePanel()
                // Open on Speech tab — where engine/models live
                SettingsWindowController.shared.show(appState: appState, tab: .speech)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit PushToType", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    // MARK: - Chips

    private func selectChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
