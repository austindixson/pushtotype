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

            if appState.transcriptionEngine == .whisper {
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
                    Toggle("Warm Whisper on launch", isOn: $appState.warmModelOnLaunch)
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
            } else {
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
                Button("Request Accessibility") {
                    PermissionDoctor.requestAccessibility()
                    PermissionDoctor.openAccessibilitySettings()
                }
                Button("Request Speech Recognition") { PermissionDoctor.requestSpeech() }
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section {
                Text("Ad-hoc builds get a new code signature each compile — re-enable Accessibility after ./scripts/build-app.sh. Use scripts/sign-stable.sh when you have an Apple Development cert.")
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
            Text("n0tfluid").font(.title2.weight(.bold))
            Text("Local Mac dictation — Whisper or macOS Speech, Terminal-aware paste, smart punctuation, live partials.")
                .foregroundStyle(.secondary)
            Divider()
            Group {
                Text("Hotkey: \(appState.hotkeyPreset.displayName)")
                Text("Engine: \(appState.transcriptionEngine.displayName)")
                Text("See BUILD_PLAN.md for the full roadmap")
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
