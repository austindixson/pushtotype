import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelDL = ModelDownloadService.shared
    @ObservedObject private var dictionary = DictionaryStore.shared
    @State private var newFind = ""
    @State private var newReplace = ""

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            engineTab.tabItem { Label("Speech", systemImage: "waveform") }
            dictionaryTab.tabItem { Label("Dictionary", systemImage: "textformat.abc") }
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 480)
        .background(.ultraThinMaterial)
    }

    private var generalTab: some View {
        Form {
            Section("Dictation") {
                Picker("Mode", selection: Binding(
                    get: { appState.mode },
                    set: { appState.mode = $0 }
                )) {
                    ForEach(DictationMode.allCases) { Text($0.title).tag($0) }
                }
                Text(appState.mode.subtitle).font(.caption).foregroundStyle(.secondary)
                if appState.mode == .articulate {
                    Text("Articulate turns rough spoken ideas into clear prose for AI chats, specs, and planning. Runs fully offline.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto-paste into active app", isOn: $appState.autoPaste)
                Toggle("Smart punctuation & spacing", isOn: $appState.smartPunctuation)
                Toggle("Strip light fillers (um, uh, like)", isOn: $appState.stripLightFillers)
                Toggle("Live partials while holding", isOn: $appState.livePartials)
                Toggle("Show live overlay", isOn: $appState.showLiveOverlay)
                Toggle("Play sounds", isOn: $appState.playSounds)

                Picker("Overlay position", selection: Binding(
                    get: { appState.overlayPosition },
                    set: { appState.overlayPosition = $0 }
                )) {
                    ForEach(OverlayPosition.allCases) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                Text("Full transcript shows in the overlay (multi-line). Live partials need Speech Recognition permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                Picker("Push-to-talk", selection: Binding(
                    get: { appState.hotkeyPreset },
                    set: { appState.hotkeyPreset = $0 }
                )) {
                    ForEach(HotkeyPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(appState.hotkeyPreset.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Recognition language", selection: $appState.language) {
                    Text("Auto / system").tag("auto")
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
                    Text("Arabic").tag("ar")
                    Text("Hindi").tag("hi")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var engineTab: some View {
        Form {
            Section("Engine") {
                Picker("Engine", selection: Binding(
                    get: { appState.transcriptionEngine },
                    set: { appState.transcriptionEngine = $0 }
                )) {
                    ForEach(TranscriptionEngine.allCases) { e in
                        Label(e.displayName, systemImage: e.icon).tag(e)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(appState.transcriptionEngine.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Status") {
                    Text(appState.modelStatus)
                        .foregroundStyle(appState.modelReady ? .green : .orange)
                        .multilineTextAlignment(.trailing)
                }
            }

            switch appState.transcriptionEngine {
            case .whisper:
                Section("Speed preset") {
                    Picker("Preset", selection: Binding(
                        get: { appState.speedPreset },
                        set: { appState.speedPreset = $0 }
                    )) {
                        ForEach(SpeedPreset.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    Text(appState.speedPreset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Warm model on launch", isOn: $appState.warmModelOnLaunch)
                }

                Section("Whisper model") {
                    Picker("Model", selection: Binding(
                        get: { appState.selectedModel },
                        set: { m in
                            appState.selectedModel = m
                            Task { await appState.refreshModelStatus() }
                        }
                    )) {
                        ForEach(WhisperModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(appState.selectedModel.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if modelDL.isDownloading {
                        ProgressView(value: modelDL.progress) {
                            Text(modelDL.status).font(.caption)
                        }
                    } else {
                        Text(modelDL.isDownloaded(appState.selectedModel) ? "Model file present" : "Model not downloaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Download selected model") {
                        appState.downloadWhisperModel(appState.selectedModel)
                    }
                    .disabled(modelDL.isDownloading)

                    Button("Recheck / warm") {
                        Task {
                            await appState.refreshModelStatus()
                            await appState.warmWhisper()
                        }
                    }
                }

            case .parakeet:
                Section("Parakeet (NVIDIA)") {
                    Text("Fast local dictation via onnx-asr. One-time setup downloads a Python runtime + ONNX models (~0.5–1 GB).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Model", selection: Binding(
                        get: { appState.selectedParakeetModel },
                        set: { appState.selectedParakeetModel = $0 }
                    )) {
                        ForEach(ParakeetModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(appState.selectedParakeetModel.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Warm Parakeet on launch", isOn: $appState.warmModelOnLaunch)

                    if appState.parakeetInstallBusy {
                        ProgressView {
                            Text("Installing… first run can take several minutes")
                                .font(.caption)
                        }
                    }

                    Button(appState.parakeetInstallBusy ? "Installing…" : "Install / update Parakeet runtime") {
                        appState.installParakeetRuntime()
                    }
                    .disabled(appState.parakeetInstallBusy)

                    Button("Recheck / warm") {
                        Task {
                            await appState.refreshModelStatus()
                            await appState.warmParakeet()
                        }
                    }
                    .disabled(appState.parakeetInstallBusy)

                    if !appState.parakeetInstallLog.isEmpty {
                        ScrollView {
                            Text(appState.parakeetInstallLog)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                }

            case .appleSpeech:
                Section("macOS Speech") {
                    Text("Zero download. Grant Speech Recognition for live partials and final STT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Request Speech permission") {
                        PermissionDoctor.requestSpeech()
                        Task { await appState.refreshModelStatus() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var dictionaryTab: some View {
        Form {
            Section("Replacements") {
                Text("Applied after speech-to-text (case-insensitive). Longer matches win.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(dictionary.entries) { e in
                    HStack {
                        Text("\(e.find) → \(e.replace)")
                            .font(.callout)
                        Spacer()
                        Button(role: .destructive) {
                            dictionary.remove(id: e.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section("Add") {
                TextField("Find", text: $newFind)
                TextField("Replace with", text: $newReplace)
                Button("Add replacement") {
                    dictionary.add(find: newFind, replace: newReplace)
                    newFind = ""
                    newReplace = ""
                }
                .disabled(newFind.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var permissionsTab: some View {
        Form {
            Section("Status") {
                let p = appState.permissions
                LabeledContent("Microphone") {
                    Text(p.microphone ? "Granted" : "Missing")
                        .foregroundStyle(p.microphone ? .green : .red)
                }
                LabeledContent("Accessibility") {
                    Text(p.accessibility ? "Granted" : "Missing — required for paste")
                        .foregroundStyle(p.accessibility ? .green : .red)
                }
                LabeledContent("Speech Recognition") {
                    Text(p.speech ? "Granted" : "Optional / for live partials")
                        .foregroundStyle(p.speech ? .green : .orange)
                }
                Button("Refresh") { appState.refreshPermissions() }
            }
            Section("Fix") {
                Button("Request Microphone") { PermissionDoctor.requestMicrophone() }
                Button(appState.permissions.accessibility ? "Accessibility granted ✓" : "Request Accessibility") {
                    if !appState.permissions.accessibility {
                        PermissionDoctor.requestAccessibility()
                        PermissionDoctor.openAccessibilitySettings()
                    }
                }
                .disabled(appState.permissions.accessibility)
                Button("Request Speech Recognition") { PermissionDoctor.requestSpeech() }
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section {
                Text("Accessibility is checked quietly. System prompts only appear if permission is missing and you request it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { appState.refreshPermissions() }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PushToType").font(.title2.weight(.bold))
            Text("Local Mac dictation — Whisper or macOS Speech, Terminal-aware paste, smart punctuation, live partials.")
                .foregroundStyle(.secondary)
            Divider()
            Group {
                Text("Hotkey: \(appState.hotkeyPreset.displayName)")
                Text("Engine: \(appState.transcriptionEngine.displayName)")
            }
            .font(.callout)
            Spacer()
            Text("Not affiliated with FluidVoice / altic-dev.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Window host (menu-bar apps can't rely on showSettingsWindow:)

/// Opens Settings as a real key window. Accessory (`LSUIElement`) apps ignore
/// `showSettingsWindow:` / Settings scene presentation unless activated as regular.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(appState: AppState) {
        if let window, window.isVisible {
            bringToFront(window)
            return
        }

        let root = SettingsView()
            .environmentObject(appState)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 500)

        let win = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "PushToType Settings"
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.center()
        win.delegate = self
        win.isOpaque = true
        win.backgroundColor = NSColor.windowBackgroundColor
        window = win
        bringToFront(win)
    }

    private func bringToFront(_ win: NSWindow) {
        // Accessory apps need a brief regular activation so the window can key
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Return to menu-bar-only presence after a beat so MenuBarExtra stays healthy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
