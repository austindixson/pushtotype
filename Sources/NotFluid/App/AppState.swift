import Foundation
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
    @Published var llmDownloadProgress: Double = 0
    @Published var llmStatus = "LLM off"
    @Published var permissions = PermissionDoctor.snapshot()
    @Published var modelDownloadProgress: Double = 0
    @Published var modelDownloadStatus = ""

    // MARK: - Settings
    @AppStorage("hotkeyPreset") var hotkeyPresetRaw: String = HotkeyPreset.rightOption.rawValue
    @AppStorage("mode") var modeRaw: String = DictationMode.transcribe.rawValue
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw: String = TranscriptionEngine.appleSpeech.rawValue
    @AppStorage("modelID") var modelID: String = WhisperModel.small.rawValue
    @AppStorage("speedPreset") var speedPresetRaw: String = SpeedPreset.balanced.rawValue
    @AppStorage("enhancementMode") var enhancementModeRaw: String = EnhancementMode.off.rawValue
    @AppStorage("suggestedLLM") var suggestedLLMRaw: String = SuggestedLLM.recommended.rawValue
    @AppStorage("autoPaste") var autoPaste = true
    @AppStorage("playSounds") var playSounds = false
    @AppStorage("showLiveOverlay") var showLiveOverlay = true
    @AppStorage("livePartials") var livePartials = true
    @AppStorage("overlayPosition") var overlayPositionRaw: String = OverlayPosition.top.rawValue
    @AppStorage("language") var language: String = "auto"

    var overlayPosition: OverlayPosition {
        get { OverlayPosition(rawValue: overlayPositionRaw) ?? .top }
        set {
            overlayPositionRaw = newValue.rawValue
            noteOverlayContentChanged()
        }
    }

    /// Resize/reposition overlay when transcript grows or settings change.
    func noteOverlayContentChanged() {
        overlay?.refreshLayout()
    }
    @AppStorage("smartPunctuation") var smartPunctuation = true
    @AppStorage("stripLightFillers") var stripLightFillers = false
    @AppStorage("warmModelOnLaunch") var warmModelOnLaunch = true

    var mode: DictationMode {
        get { DictationMode(rawValue: modeRaw) ?? .transcribe }
        set { modeRaw = newValue.rawValue }
    }

    var hotkeyPreset: HotkeyPreset {
        get { HotkeyPreset(rawValue: hotkeyPresetRaw) ?? .rightOption }
        set {
            hotkeyPresetRaw = newValue.rawValue
            rebindHotkey()
        }
    }

    var speedPreset: SpeedPreset {
        get { SpeedPreset(rawValue: speedPresetRaw) ?? .balanced }
        set {
            speedPresetRaw = newValue.rawValue
            applySpeedPreset(newValue)
        }
    }

    var transcriptionEngine: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .appleSpeech }
        set {
            transcriptionEngineRaw = newValue.rawValue
            Task { await refreshModelStatus() }
        }
    }

    var selectedModel: WhisperModel {
        get { WhisperModel(rawValue: modelID) ?? .small }
        set { modelID = newValue.rawValue }
    }

    var enhancementMode: EnhancementMode {
        get { EnhancementMode(rawValue: enhancementModeRaw) ?? .off }
        set { enhancementModeRaw = newValue.rawValue }
    }

    var suggestedLLM: SuggestedLLM {
        get { SuggestedLLM(rawValue: suggestedLLMRaw) ?? .recommended }
        set { suggestedLLMRaw = newValue.rawValue }
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
    let injector = TextInjector()
    let hotkey = HotkeyService()
    let webLLM = WebLLMEnhancer.shared
    let dictionary = DictionaryStore.shared
    let modelDownloader = ModelDownloadService.shared
    private var overlay: OverlayController?
    private var llmCancellables = Set<AnyCancellable>()
    private var pipelineTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var rewriteSourceText: String?

    private init() {}

    func bootstrap() {
        overlay = OverlayController(appState: self)
        loadHistory()
        bindLLMStatus()
        bindModelDownload()
        rebindHotkey()
        playSounds = false
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
            if self.warmModelOnLaunch, self.transcriptionEngine == .whisper {
                await self.warmWhisper()
            }
        }

        if !permissions.accessibility {
            TextInjector.requestAccessibilityPrompt()
            statusText = "Enable Accessibility to paste at cursor"
        }
    }

    func rebindHotkey() {
        hotkey.register(preset: hotkeyPreset)
        if !isRecording && !isTranscribing {
            statusText = "Hold \(hotkeyPreset.displayName) to dictate"
        }
    }

    func applySpeedPreset(_ preset: SpeedPreset) {
        selectedModel = preset.whisperModel
        if let lang = preset.preferredLanguage {
            language = lang
        }
        if transcriptionEngine != .whisper {
            transcriptionEngine = .whisper
        }
        Task { await refreshModelStatus() }
    }

    func refreshPermissions() {
        permissions = PermissionDoctor.snapshot()
    }

    private func bindLLMStatus() {
        webLLM.$statusText.receive(on: RunLoop.main).sink { [weak self] t in self?.llmStatus = t }.store(in: &llmCancellables)
        webLLM.$progress.receive(on: RunLoop.main).sink { [weak self] p in self?.llmDownloadProgress = p }.store(in: &llmCancellables)
        webLLM.$isReady.receive(on: RunLoop.main).sink { [weak self] ready in
            guard let self, self.enhancementMode == .webLLM else { return }
            self.llmStatus = ready ? "LLM ready" : self.webLLM.statusText
        }.store(in: &llmCancellables)
    }

    private func bindModelDownload() {
        modelDownloader.$progress.receive(on: RunLoop.main).sink { [weak self] p in
            self?.modelDownloadProgress = p
        }.store(in: &llmCancellables)
        modelDownloader.$status.receive(on: RunLoop.main).sink { [weak self] s in
            self?.modelDownloadStatus = s
        }.store(in: &llmCancellables)
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
        }
        if enhancementMode == .webLLM {
            llmStatus = webLLM.isReady ? "LLM ready" : webLLM.statusText
        } else {
            llmStatus = "LLM off"
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

    func downloadSuggestedLLM() {
        enhancementMode = .webLLM
        Task {
            do {
                statusText = "Downloading LLM… (if stuck at stage 7/8, cancel & use without LLM)"
                try await webLLM.prepare(model: suggestedLLM)
                statusText = "LLM ready"
                llmStatus = "LLM ready"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusText = "LLM failed — dictation still works with smart punctuation"
                llmStatus = error.localizedDescription
                // Don't leave boost "on" in a broken state for every utterance
                // User can retry; enhance() only runs when isReady
            }
        }
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

    // MARK: - Dictation

    func startDictation() {
        guard !isRecording else { return }
        if isTranscribing || isEnhancing { return }

        errorMessage = nil
        livePreview = ""
        rewriteSourceText = nil

        if mode == .translate && transcriptionEngine == .appleSpeech {
            errorMessage = "Translate needs Whisper — switch engine in Settings."
            statusText = "Translate needs Whisper"
            return
        }

        injector.rememberTargetApp()

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
            try audio.start(livePartials: livePartials, language: language)
            sessionID = UUID()
            isRecording = true
            showOverlay = true
            switch mode {
            case .translate: statusText = "Listening (translate)…"
            case .rewrite: statusText = "Listening (rewrite)…"
            case .articulate: statusText = "Listening (articulate)…"
            case .transcribe: statusText = "Listening… \(hotkeyPreset.displayName)"
            }
            if playSounds { SoundPlayer.playStart() }
            overlay?.show()
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
        overlay?.show()
        showOverlay = true

        let thisSession = sessionID
        let engine = transcriptionEngine
        let whisperModel = selectedModel
        let dictationMode = mode
        let lang = language
        let wantEnhance = enhancementMode == .webLLM && webLLM.isReady
        let wantPaste = autoPaste
        let llm = suggestedLLM
        let selectedForRewrite = rewriteSourceText
        let targetBundle = injector.targetApp?.bundleIdentifier

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
                self.statusText = engine == .whisper ? "Transcribing with Whisper…" : "Transcribing with macOS Speech…"

                let sttMode: DictationMode = (dictationMode == .rewrite || dictationMode == .articulate)
                    ? .transcribe : dictationMode

                var text = try await self.transcribeAudio(
                    at: sampleURL,
                    engine: engine,
                    whisperModel: whisperModel,
                    mode: sttMode,
                    language: lang
                )
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Rewrite mode: treat spoken text as instruction over selection
                if dictationMode == .rewrite, let source = selectedForRewrite, !source.isEmpty {
                    text = self.applyRewrite(source: source, instruction: text)
                }

                // Punctuation + dictionary + app-aware rules
                if !text.isEmpty {
                    let opts = TranscriptFormatter.options(
                        forBundleID: targetBundle,
                        smartPunctuation: self.smartPunctuation,
                        stripFillers: self.stripLightFillers || dictationMode == .articulate
                    )
                    text = TranscriptFormatter.format(text, options: opts)
                    text = self.dictionary.apply(text)
                }

                // Articulate: ALWAYS transform (offline is aggressive; LLM optional boost)
                if dictationMode == .articulate, !text.isEmpty {
                    let before = text
                    self.isEnhancing = true
                    self.statusText = "Articulating…"
                    self.livePreview = text
                    self.showOverlay = true
                    self.overlay?.show()
                    self.overlay?.refreshLayout()

                    // Offline articulator first (always changes structure when multi-idea)
                    text = ArticulateService.articulate(text)
                    text = self.dictionary.apply(text)
                    self.livePreview = text
                    self.overlay?.refreshLayout()

                    // Optional LLM on top of offline result
                    if self.webLLM.isReady {
                        self.statusText = "Articulating with LLM…"
                        do {
                            let polished = try await self.webLLM.enhance(
                                text,
                                model: llm,
                                style: "articulate"
                            )
                            // Only keep LLM if it still looks like content (not meta)
                            if !polished.isEmpty, polished != before {
                                let merged = ArticulateService.articulate(polished)
                                if !merged.isEmpty { text = self.dictionary.apply(merged) }
                            }
                        } catch {
                            // keep offline result
                        }
                    }

                    // If somehow unchanged, force a visible structure pass once more
                    if text.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(before) == .orderedSame {
                        text = ArticulateService.articulate("I want the following: " + before)
                    }

                    self.statusText = "Articulated"
                    self.isEnhancing = false
                    self.livePreview = text
                    self.overlay?.refreshLayout()
                } else if wantEnhance, !text.isEmpty {
                    self.isEnhancing = true
                    self.statusText = "Polishing with LLM…"
                    self.livePreview = text
                    self.showOverlay = true
                    self.overlay?.show()
                    self.overlay?.refreshLayout()
                    do {
                        if self.webLLM.isReady {
                            let polished = try await self.webLLM.enhance(
                                text,
                                model: llm,
                                style: "clean"
                            )
                            if !polished.isEmpty {
                                text = TranscriptFormatter.format(
                                    polished,
                                    options: TranscriptFormatter.options(
                                        forBundleID: targetBundle,
                                        smartPunctuation: self.smartPunctuation,
                                        stripFillers: false
                                    )
                                )
                                text = self.dictionary.apply(text)
                            }
                        } else {
                            self.errorMessage = "LLM not ready — used smart punctuation instead"
                        }
                    } catch {
                        self.errorMessage = "LLM polish skipped: \(error.localizedDescription)"
                    }
                    self.isEnhancing = false
                    self.livePreview = text
                    self.overlay?.refreshLayout()
                }

                self.lastTranscript = text
                self.livePreview = text.isEmpty ? "(no speech detected)" : text
                // Always show full transcript in overlay
                if self.showLiveOverlay {
                    self.showOverlay = true
                    self.overlay?.show()
                    self.overlay?.refreshLayout()
                }

                guard !text.isEmpty else {
                    self.statusText = "No speech detected"
                    self.keepOverlayBrieflyThenHide()
                    try? FileManager.default.removeItem(at: sampleURL)
                    return
                }

                self.appendHistory(text)
                self.injector.copyToClipboard(text)

                if wantPaste {
                    let intoTerminal = self.injector.isTerminalTarget()
                    self.statusText = intoTerminal ? "Pasting…" : "Inserting…"
                    self.livePreview = text
                    // Keep text visible; only lower our activation so target app gets paste
                    self.showOverlay = false
                    self.overlay?.hide()
                    NSApp.deactivate()

                    var method = await self.insertText(text)

                    if dictationMode == .rewrite,
                       let pid = self.injector.targetApp?.processIdentifier,
                       SelectionService.replaceSelectedText(text, targetPID: pid) {
                        method = .accessibility
                    }

                    // Show complete output again after paste
                    self.livePreview = text
                    if self.showLiveOverlay {
                        self.showOverlay = true
                        self.overlay?.show()
                        self.overlay?.refreshLayout()
                    }

                    switch method {
                    case .accessibility, .appleScriptPaste, .terminalPaste:
                        self.statusText = intoTerminal ? "Pasted ✓" : "Inserted ✓"
                        if self.errorMessage?.contains("LLM") != true {
                            self.errorMessage = nil
                        }
                    case .clipboardPaste:
                        self.statusText = "Sent paste — ⌘V if missing"
                    case .clipboardOnly, .none:
                        self.statusText = "Press ⌘V to paste"
                        self.errorMessage = "Enable Accessibility for NotFluid"
                        TextInjector.requestAccessibilityPrompt()
                    }
                    self.keepOverlayBrieflyThenHide(seconds: 2.5)
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

    /// Lightweight rewrite without LLM: apply instruction keywords or append.
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
                delay: 0.04,
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
