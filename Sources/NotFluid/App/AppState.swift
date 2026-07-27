import Foundation
import NotFluidSupport
import Combine
import AppKit
import SwiftUI
import Speech

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - UI state
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isEnhancing = false
    @Published var lastTranscript = ""
    @Published var livePreview = ""
    @Published var statusText = "Ready"
    @Published var errorMessage: String?
    @Published var showOverlay = false
    @Published var modelReady = false
    @Published var modelStatus = "Checking engine…"
    @Published var history: [DictationEntry] = []
    @Published var historyFilter = ""
    @Published var permissions = PermissionDoctor.snapshot()
    @Published var modelDownloadProgress: Double = 0
    @Published var modelDownloadStatus = ""

    // MARK: - Settings (UserDefaults-backed @Published so UI selection never “snaps back”)
    // @AppStorage on ObservableObject is flaky for multi-control menus: views can re-render
    // mid-write and revert highlight. Prefer explicit defaults + @Published.

    /// Suppress didSet persistence / side-effects while hydrating from UserDefaults.
    private var isHydrating = false

    @Published var hotkeyPreset: HotkeyPreset = .rightOption {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(hotkeyPreset.rawValue, forKey: "hotkeyPreset")
            rebindHotkey()
        }
    }
    @Published var mode: DictationMode = .transcribe {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
        }
    }
    @Published var transcriptionEngine: TranscriptionEngine = .appleSpeech {
        didSet {
            guard !isHydrating, oldValue != transcriptionEngine else { return }
            UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine")
            Task { await refreshModelStatus() }
        }
    }
    @Published var selectedModel: WhisperModel = .small {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "modelID")
        }
    }
    @Published var selectedParakeetModel: ParakeetModel = .tdt06bV2 {
        didSet {
            guard !isHydrating, oldValue != selectedParakeetModel else { return }
            UserDefaults.standard.set(selectedParakeetModel.rawValue, forKey: "parakeetModelID")
            Task { await refreshModelStatus() }
        }
    }
    @Published var speedPreset: SpeedPreset = .balanced {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(speedPreset.rawValue, forKey: "speedPreset")
            // Only tweak Whisper model/language — never force-switch engine (that caused snap-back)
            selectedModel = speedPreset.whisperModel
            if let lang = speedPreset.preferredLanguage {
                language = lang
            }
        }
    }
    @Published var autoPaste = true {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(autoPaste, forKey: "autoPaste")
        }
    }
    @Published var playSounds = false {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(playSounds, forKey: "playSounds")
        }
    }
    @Published var showLiveOverlay = true {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(showLiveOverlay, forKey: "showLiveOverlay")
        }
    }
    @Published var livePartials = true {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(livePartials, forKey: "livePartials")
        }
    }
    @Published var language: String = "auto" {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(language, forKey: "language")
        }
    }
    @Published var smartPunctuation = true {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(smartPunctuation, forKey: "smartPunctuation")
        }
    }
    @Published var stripLightFillers = false {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(stripLightFillers, forKey: "stripLightFillers")
        }
    }
    @Published var warmModelOnLaunch = true {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(warmModelOnLaunch, forKey: "warmModelOnLaunch")
        }
    }
    @Published var overlayPosition: OverlayPosition = .top {
        didSet {
            guard !isHydrating else { return }
            UserDefaults.standard.set(overlayPosition.rawValue, forKey: "overlayPosition")
            noteOverlayContentChanged()
        }
    }

    @Published var parakeetInstallBusy = false
    @Published var parakeetInstallLog = ""

    /// Resize/reposition overlay when transcript grows or settings change.
    func noteOverlayContentChanged() {
        overlay?.refreshLayout()
    }

    var filteredHistory: [DictationEntry] {
        let q = historyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = history.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.createdAt > b.createdAt
        }
        guard !q.isEmpty else { return base }
        return base.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    // MARK: - Services
    let audio = AudioCaptureService()
    let whisper = WhisperService()
    let appleSpeech = AppleSpeechService()
    let parakeet = ParakeetService()
    let injector = TextInjector()
    let hotkey = HotkeyService()
    let dictionary = DictionaryStore.shared
    let modelDownloader = ModelDownloadService.shared
    private var overlay: OverlayController?
    private var cancellables = Set<AnyCancellable>()
    private var pipelineTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var rewriteSourceText: String?

    private init() {
        loadPersistedSettings()
    }

    private func loadPersistedSettings() {
        isHydrating = true
        defer { isHydrating = false }
        let d = UserDefaults.standard
        if let v = d.string(forKey: "hotkeyPreset"), let p = HotkeyPreset(rawValue: v) { hotkeyPreset = p }
        if let v = d.string(forKey: "mode"), let m = DictationMode(rawValue: v) { mode = m }
        if let v = d.string(forKey: "transcriptionEngine"), let e = TranscriptionEngine(rawValue: v) {
            transcriptionEngine = e
        }
        if let v = d.string(forKey: "speedPreset"), let p = SpeedPreset(rawValue: v) { speedPreset = p }
        if let v = d.string(forKey: "modelID"), let m = WhisperModel(rawValue: v) { selectedModel = m }
        if let v = d.string(forKey: "parakeetModelID"), let m = ParakeetModel(rawValue: v) {
            selectedParakeetModel = m
        }
        if d.object(forKey: "autoPaste") != nil { autoPaste = d.bool(forKey: "autoPaste") }
        if d.object(forKey: "playSounds") != nil { playSounds = d.bool(forKey: "playSounds") }
        if d.object(forKey: "showLiveOverlay") != nil { showLiveOverlay = d.bool(forKey: "showLiveOverlay") }
        if d.object(forKey: "livePartials") != nil { livePartials = d.bool(forKey: "livePartials") }
        if let v = d.string(forKey: "language") { language = v }
        if d.object(forKey: "smartPunctuation") != nil { smartPunctuation = d.bool(forKey: "smartPunctuation") }
        if d.object(forKey: "stripLightFillers") != nil { stripLightFillers = d.bool(forKey: "stripLightFillers") }
        if d.object(forKey: "warmModelOnLaunch") != nil { warmModelOnLaunch = d.bool(forKey: "warmModelOnLaunch") }
        if let v = d.string(forKey: "overlayPosition"), let p = OverlayPosition(rawValue: v) {
            overlayPosition = p
        }
    }

    func bootstrap() {
        overlay = OverlayController(appState: self)
        loadHistory()
        bindModelDownload()
        rebindHotkey()
        playSounds = false
        UserDefaults.standard.set(false, forKey: "playSounds")
        statusText = "Hold \(hotkeyPreset.displayName) to dictate"
        refreshPermissions()

        audio.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.livePreview = text
                if self.showLiveOverlay {
                    self.showOverlay = true
                    self.overlay?.show()
                    self.overlay?.refreshLayout()
                }
            }
        }

        hotkey.onToggle = { [weak self] pressed in
            DispatchQueue.main.async {
                guard let self else { return }
                if pressed { self.startDictation() }
                else { self.stopDictationAndTranscribe() }
            }
        }

        Task {
            await refreshModelStatus()
            // Always try to warm the active engine so first dictation isn't cold
            if self.warmModelOnLaunch || self.transcriptionEngine == .parakeet {
                switch self.transcriptionEngine {
                case .whisper: await self.warmWhisper()
                case .parakeet: await self.warmParakeet()
                case .appleSpeech: break
                }
            }
        }

        // Quiet status only — never auto-prompt if already granted (or even if missing on launch)
        if !permissions.accessibility {
            statusText = "Hold \(hotkeyPreset.displayName) to dictate"
        }
    }

    func rebindHotkey() {
        hotkey.register(preset: hotkeyPreset)
        if !isRecording && !isTranscribing {
            statusText = "Hold \(hotkeyPreset.displayName) to dictate"
        }
    }

    func applySpeedPreset(_ preset: SpeedPreset) {
        // Explicit user action from Settings only — never auto-force engine from UI rebuilds
        speedPreset = preset
        if transcriptionEngine != .whisper {
            transcriptionEngine = .whisper
        }
        Task { await refreshModelStatus() }
    }

    func refreshPermissions() {
        permissions = PermissionDoctor.snapshot()
    }


    private func bindModelDownload() {
        modelDownloader.$progress.receive(on: RunLoop.main).sink { [weak self] p in
            self?.modelDownloadProgress = p
        }.store(in: &cancellables)
        modelDownloader.$status.receive(on: RunLoop.main).sink { [weak self] s in
            self?.modelDownloadStatus = s
        }.store(in: &cancellables)
    }

    func refreshModelStatus() async {
        refreshPermissions()
        switch transcriptionEngine {
        case .appleSpeech:
            let status = await appleSpeech.ensureReady(language: language)
            modelReady = status.ready
            modelStatus = status.message
        case .whisper:
            let status = await whisper.ensureReady(model: selectedModel)
            modelReady = status.ready
            modelStatus = status.message
        case .parakeet:
            let status = await parakeet.ensureReady(model: selectedParakeetModel)
            modelReady = status.ready
            modelStatus = status.message
        }
        if !modelReady { statusText = modelStatus }
    }

    /// Touch whisper binary + model so first dictation is snappier (page cache).
    func warmWhisper() async {
        guard transcriptionEngine == .whisper else { return }
        modelStatus = "Warming Whisper…"
        let status = await whisper.ensureReady(model: selectedModel)
        modelReady = status.ready
        modelStatus = status.ready ? "\(selectedModel.displayName) warm" : status.message
    }

    func warmParakeet() async {
        guard transcriptionEngine == .parakeet else { return }
        modelStatus = "Warming Parakeet…"
        await parakeet.warm(model: selectedParakeetModel)
        await refreshModelStatus()
    }

    func downloadWhisperModel(_ model: WhisperModel? = nil) {
        let m = model ?? selectedModel
        Task {
            do {
                try await modelDownloader.download(m)
                selectedModel = m
                await refreshModelStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Install Python venv + onnx-asr + download Parakeet ONNX models (one-time).
    func installParakeetRuntime() {
        guard !parakeetInstallBusy else { return }
        parakeetInstallBusy = true
        parakeetInstallLog = "Starting Parakeet setup…"
        modelStatus = "Installing Parakeet…"

        var scriptCandidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("setup-parakeet.sh").path {
            scriptCandidates.append(bundled)
        }
        scriptCandidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/PushToType/scripts/setup-parakeet.sh").path
        )
        scriptCandidates.append(FileManager.default.currentDirectoryPath + "/scripts/setup-parakeet.sh")

        guard let script = scriptCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            parakeetInstallBusy = false
            parakeetInstallLog = "setup-parakeet.sh not found"
            errorMessage = parakeetInstallLog
            return
        }

        // Prefer project Resources worker for setup copy
        Task.detached { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [script]
            // setup-parakeet.sh resolves worker relative to repo; if run from bundle Resources,
            // also ensure Application Support gets the bundled worker after setup.
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = out
            do {
                try proc.run()
                // Stream log
                while proc.isRunning {
                    let data = out.fileHandleForReading.availableData
                    if !data.isEmpty, let s = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            self?.parakeetInstallLog += s
                            self?.modelDownloadStatus = s.split(separator: "\n").last.map(String.init) ?? ""
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                let rest = out.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: rest, encoding: .utf8), !s.isEmpty {
                    await MainActor.run { self?.parakeetInstallLog += s }
                }
                let code = proc.terminationStatus
                await MainActor.run {
                    self?.parakeetInstallBusy = false
                    if code == 0 {
                        self?.modelStatus = "Parakeet installed"
                        self?.errorMessage = nil
                        self?.transcriptionEngine = .parakeet
                        Task { await self?.refreshModelStatus(); await self?.warmParakeet() }
                    } else {
                        self?.errorMessage = "Parakeet install failed (exit \(code)) — see log in Settings"
                        self?.modelStatus = "Parakeet install failed"
                    }
                }
            } catch {
                await MainActor.run {
                    self?.parakeetInstallBusy = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Dictation

    func startDictation() {
        guard !isRecording else { return }
        if isTranscribing || isEnhancing { return }

        errorMessage = nil
        livePreview = ""
        rewriteSourceText = nil

        if mode == .translate && transcriptionEngine != .whisper {
            errorMessage = "Translate needs Whisper — switch engine in Settings."
            statusText = "Translate needs Whisper"
            return
        }

        injector.rememberTargetApp()

        // Warm STT while user is still holding — hides model-load latency on release
        Task {
            switch transcriptionEngine {
            case .parakeet: await warmParakeet()
            case .whisper where warmModelOnLaunch: await warmWhisper()
            default: break
            }
        }

        if mode == .rewrite {
            let pid = injector.targetApp?.processIdentifier
            rewriteSourceText = SelectionService.readSelectedText(targetPID: pid)
            if rewriteSourceText == nil || rewriteSourceText?.isEmpty == true {
                errorMessage = "Select text first, then hold hotkey and speak rewrite instructions"
                statusText = "Select text for rewrite"
                return
            }
        }

        do {
            // Live partials only when wanted — Apple Speech path is cheaper without them for pure final STT
            let usePartials = livePartials && (transcriptionEngine == .appleSpeech || showLiveOverlay)
            try audio.start(livePartials: usePartials, language: language)
            sessionID = UUID()
            isRecording = true
            // Lightweight UI while holding (full overlay only if enabled)
            if showLiveOverlay {
                showOverlay = true
                overlay?.show()
            }
            switch mode {
            case .translate: statusText = "Listening (translate)…"
            case .rewrite: statusText = "Listening (rewrite)…"
            case .articulate: statusText = "Listening (articulate)…"
            case .transcribe: statusText = "Listening… \(hotkeyPreset.displayName)"
            }
            if playSounds { SoundPlayer.playStart() }
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Mic error"
            livePreview = error.localizedDescription
            showOverlay = true
            overlay?.show()
        }
    }

    func stopDictationAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        isTranscribing = true
        statusText = "Transcribing…"
        if livePreview.isEmpty { livePreview = "…" }
        if playSounds { SoundPlayer.playStop() }
        // Don't raise overlay during STT when auto-pasting — keeps target app focused
        if showLiveOverlay && !autoPaste {
            overlay?.show()
            showOverlay = true
        } else {
            overlay?.hide()
            showOverlay = false
        }

        let thisSession = sessionID
        let engine = transcriptionEngine
        let whisperModel = selectedModel
        let parakeetModel = selectedParakeetModel
        let dictationMode = mode
        let lang = language
        let wantPaste = autoPaste
        let selectedForRewrite = rewriteSourceText
        let targetBundle = injector.targetApp?.bundleIdentifier
        let smart = smartPunctuation
        let strip = stripLightFillers

        let sampleResult: Result<URL, Error>
        do { sampleResult = .success(try audio.stop()) }
        catch { sampleResult = .failure(error) }

        pipelineTask?.cancel()
        pipelineTask = Task { @MainActor in
            defer {
                if self.sessionID == thisSession {
                    self.isTranscribing = false
                    self.isEnhancing = false
                }
            }

            let sampleURL: URL
            switch sampleResult {
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.statusText = "Recording failed"
                self.livePreview = error.localizedDescription
                self.keepOverlayBrieflyThenHide()
                return
            case .success(let url):
                sampleURL = url
            }

            do {
                self.statusText = engine == .whisper ? "Transcribing…" : "Transcribing…"

                let sttMode: DictationMode = (dictationMode == .rewrite || dictationMode == .articulate)
                    ? .transcribe : dictationMode

                // Prefer live partial as a head-start display while Whisper runs
                // (final STT still overwrites with the accurate result)

                var text = try await self.transcribeAudio(
                    at: sampleURL,
                    engine: engine,
                    whisperModel: whisperModel,
                    parakeetModel: parakeetModel,
                    mode: sttMode,
                    language: lang
                )
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Rewrite mode: treat spoken text as instruction over selection
                if dictationMode == .rewrite, let source = selectedForRewrite, !source.isEmpty {
                    text = self.applyRewrite(source: source, instruction: text)
                }

                // Punctuation + dictionary (use values captured at stop — no extra main-actor hops)
                if !text.isEmpty {
                    let opts = TranscriptFormatter.options(
                        forBundleID: targetBundle,
                        smartPunctuation: smart,
                        stripFillers: strip || dictationMode == .articulate
                    )
                    text = TranscriptFormatter.format(text, options: opts)
                    text = self.dictionary.apply(text)
                }

                // Articulate: offline-only restructuring for AI prompts / specs
                if dictationMode == .articulate, !text.isEmpty {
                    let before = text
                    self.isEnhancing = true
                    self.statusText = "Articulating…"
                    self.livePreview = text

                    text = ArticulateService.articulate(text)
                    text = self.dictionary.apply(text)

                    if text.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(before) == .orderedSame {
                        text = ArticulateService.articulate("I want the following: " + before)
                    }

                    self.statusText = "Articulated"
                    self.isEnhancing = false
                    self.livePreview = text
                }

                self.lastTranscript = text
                self.livePreview = text.isEmpty ? "(no speech detected)" : text

                guard !text.isEmpty else {
                    self.statusText = "No speech detected"
                    self.keepOverlayBrieflyThenHide()
                    try? FileManager.default.removeItem(at: sampleURL)
                    return
                }

                // Clipboard ASAP so paste can race with history write
                self.injector.copyToClipboard(text)
                self.appendHistory(text)

                if wantPaste {
                    let intoTerminal = self.injector.isTerminalTarget()
                    let targetName = self.injector.targetApp?.localizedName ?? "app"
                    self.statusText = intoTerminal ? "Pasting…" : "Inserting…"
                    // Keep target focused — no overlay until after paste
                    self.showOverlay = false
                    self.overlay?.hide()
                    NSApp.deactivate()

                    var method = await self.insertText(text)

                    if dictationMode == .rewrite,
                       let pid = self.injector.targetApp?.processIdentifier,
                       SelectionService.replaceSelectedText(text, targetPID: pid) {
                        method = .accessibility
                    }

                    self.livePreview = text
                    // Brief confirmation only if user wants overlay (not mid-keystroke)
                    if self.showLiveOverlay {
                        self.showOverlay = true
                        self.overlay?.show()
                    }

                    switch method {
                    case .accessibility, .appleScriptPaste, .terminalPaste, .typedText:
                        self.statusText = intoTerminal
                            ? "Pasted into \(targetName) ✓"
                            : "Inserted into \(targetName) ✓"
                        self.errorMessage = nil
                    case .clipboardPaste:
                        self.statusText = "Sent paste to \(targetName)"
                        self.errorMessage = nil
                    case .clipboardOnly, .none:
                        self.statusText = "Copied — press ⌘V in \(targetName)"
                        if let detail = self.injector.lastErrorDetail {
                            self.errorMessage = detail
                        } else if !TextInjector.accessibilityGranted() {
                            self.errorMessage = "Accessibility not granted (menu → Access)"
                        }
                    }
                    self.keepOverlayBrieflyThenHide(seconds: 1.5)
                } else {
                    self.statusText = "Copied"
                    if self.showLiveOverlay {
                        self.showOverlay = true
                        self.overlay?.show()
                        self.overlay?.refreshLayout()
                    }
                    self.keepOverlayBrieflyThenHide(seconds: 2.5)
                }

                if self.playSounds { SoundPlayer.playSuccess() }
            } catch {
                self.errorMessage = error.localizedDescription
                self.statusText = "Failed: \(error.localizedDescription)"
                self.livePreview = error.localizedDescription
                self.keepOverlayBrieflyThenHide(seconds: 2.0)
            }

            try? FileManager.default.removeItem(at: sampleURL)
            self.refreshPermissions()
        }
    }

    /// Lightweight rewrite: apply instruction keywords or replace selection.
    private func applyRewrite(source: String, instruction: String) -> String {
        let instr = instruction.lowercased()
        if instr.contains("upper") { return source.uppercased() }
        if instr.contains("lower") { return source.lowercased() }
        if instr.contains("title") {
            return source.capitalized
        }
        if instr.contains("shorter") || instr.contains("summar") {
            let words = source.split(separator: " ")
            if words.count > 12 {
                return words.prefix(12).joined(separator: " ") + "…"
            }
        }
        // Default: if instruction looks like a full rewrite, use it; else prefix note
        if instruction.split(separator: " ").count >= 4 {
            return instruction
        }
        return source
    }

    private func insertText(_ text: String) async -> TextInjector.InsertMethod? {
        await withCheckedContinuation { cont in
            injector.insertAfterDelay(
                text,
                delay: 0.0,
                prepareFocus: { [weak self] in
                    self?.overlay?.hide()
                    self?.showOverlay = false
                    NSApp.deactivate()
                },
                completion: { method in cont.resume(returning: method) }
            )
        }
    }

    private func keepOverlayBrieflyThenHide(seconds: Double = 1.0) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !self.isRecording {
                self.showOverlay = false
                self.overlay?.hide()
            }
        }
    }

    private func transcribeAudio(
        at url: URL,
        engine: TranscriptionEngine,
        whisperModel: WhisperModel,
        parakeetModel: ParakeetModel,
        mode: DictationMode,
        language: String
    ) async throws -> String {
        switch engine {
        case .appleSpeech:
            return try await appleSpeech.transcribe(audioURL: url, language: language, mode: mode)
        case .whisper:
            return try await whisper.transcribe(
                audioURL: url,
                model: whisperModel,
                mode: mode,
                language: language
            )
        case .parakeet:
            return try await parakeet.transcribe(
                audioURL: url,
                model: parakeetModel,
                mode: mode,
                language: language
            )
        }
    }

    func cancelDictation() {
        guard isRecording else { return }
        audio.cancel()
        isRecording = false
        isTranscribing = false
        showOverlay = false
        overlay?.hide()
        statusText = "Cancelled"
        livePreview = ""
        rewriteSourceText = nil
    }

    // MARK: - History

    private var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            history = []
            return
        }
        history = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func appendHistory(_ text: String) {
        history.insert(DictationEntry(text: text, mode: mode.rawValue), at: 0)
        if history.count > 150 { history = Array(history.prefix(150)) }
        saveHistory()
    }

    func clearHistory() {
        history = []
        try? FileManager.default.removeItem(at: historyURL)
    }

    func togglePin(_ id: UUID) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].pinned.toggle()
        saveHistory()
    }

    func exportHistoryMarkdown() -> URL? {
        let lines = filteredHistory.map { e -> String in
            let pin = e.pinned ? "📌 " : ""
            let date = ISO8601DateFormatter().string(from: e.createdAt)
            return "### \(pin)\(date)\n\n\(e.text)\n"
        }
        let md = "# n0tfluid history\n\n" + lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("n0tfluid-history.md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func copyLast() {
        guard !lastTranscript.isEmpty else { return }
        injector.copyToClipboard(lastTranscript)
        statusText = "Copied"
    }

    func pasteLast() {
        guard !lastTranscript.isEmpty else { return }
        injector.rememberTargetApp()
        showOverlay = false
        overlay?.hide()
        Task {
            let method = await insertText(lastTranscript)
            statusText = (method == .clipboardOnly || method == nil) ? "Press ⌘V" : "Inserted ✓"
            livePreview = lastTranscript
            showOverlay = true
            overlay?.show()
            keepOverlayBrieflyThenHide(seconds: 1.0)
        }
    }
}
