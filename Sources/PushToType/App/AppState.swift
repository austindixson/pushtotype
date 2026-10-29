import Foundation
import PushToTypeSupport
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
    @Published var transcriptionEngine: TranscriptionEngine = DictationDefaults.engine {
        didSet {
            guard !isHydrating, oldValue != transcriptionEngine else { return }
            UserDefaults.standard.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine")
            Task { await refreshModelStatus() }
        }
    }
    @Published var selectedModel: WhisperModel = DictationDefaults.whisperModel {
        didSet {
            guard !isHydrating, oldValue != selectedModel else { return }
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
            guard oldValue != speedPreset else { return }
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

    @Published var runtimeSetupBusy = false
    @Published var runtimeSetupLog = ""
    @Published var openAIKeySaved = false

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
    let phonon = PhononService()
    let bark = BarkService()
    let openAI = OpenAITranscriptionService()
    let injector = TextInjector()
    let hotkey = HotkeyService()
    let dictionary = DictionaryStore.shared
    let modelDownloader = ModelDownloadService.shared
    private var overlay: OverlayController?
    private var cancellables = Set<AnyCancellable>()
    private var pipelineTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var rewriteSourceText: String?
    /// Set when this take used macOS Speech because the selected Whisper model was not available.
    /// The saved engine is left alone.
    private var takeNotice: String?

    private init() {
        loadPersistedSettings()
    }

    private func loadPersistedSettings() {
        SettingsMigration.copyLegacyDomainIfNeeded()
        isHydrating = true
        defer { isHydrating = false }
        let defaults = UserDefaults.standard
        loadChoiceSettings(defaults)
        loadToggleSettings(defaults)
        openAIKeySaved = APIKeyStore.hasKey
    }

    private func loadChoiceSettings(_ defaults: UserDefaults) {
        if let value = defaults.string(forKey: "hotkeyPreset"), let preset = HotkeyPreset(rawValue: value) {
            hotkeyPreset = preset
        }
        if let value = defaults.string(forKey: "mode"), let stored = DictationMode(rawValue: value) { mode = stored }
        transcriptionEngine = EngineSelection.resolve(stored: defaults.string(forKey: "transcriptionEngine"))
        if let value = defaults.string(forKey: "speedPreset"), let preset = SpeedPreset(rawValue: value) {
            speedPreset = preset
        }
        selectedModel = EngineSelection.resolveWhisperModel(stored: defaults.string(forKey: "modelID"))
        if let value = defaults.string(forKey: "parakeetModelID"), let model = ParakeetModel(rawValue: value) {
            selectedParakeetModel = model
        }
        if let value = defaults.string(forKey: "language") { language = value }
        if let value = defaults.string(forKey: "overlayPosition"), let position = OverlayPosition(rawValue: value) {
            overlayPosition = position
        }
    }

    private func loadToggleSettings(_ defaults: UserDefaults) {
        autoPaste = storedBool(defaults, key: "autoPaste", current: autoPaste)
        playSounds = storedBool(defaults, key: "playSounds", current: playSounds)
        showLiveOverlay = storedBool(defaults, key: "showLiveOverlay", current: showLiveOverlay)
        livePartials = storedBool(defaults, key: "livePartials", current: livePartials)
        smartPunctuation = storedBool(defaults, key: "smartPunctuation", current: smartPunctuation)
        stripLightFillers = storedBool(defaults, key: "stripLightFillers", current: stripLightFillers)
        warmModelOnLaunch = storedBool(defaults, key: "warmModelOnLaunch", current: warmModelOnLaunch)
    }

    private func storedBool(_ defaults: UserDefaults, key: String, current: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return current }
        return defaults.bool(forKey: key)
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
            if self.warmModelOnLaunch {
                await self.warmActiveEngine()
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
        let status = await currentModelStatus()
        modelReady = status.ready
        modelStatus = status.message
        if !modelReady { statusText = modelStatus }
    }

    private func currentModelStatus() async -> ModelReadyStatus {
        switch transcriptionEngine {
        case .appleSpeech:
            return await appleSpeech.ensureReady(language: language)
        case .whisper:
            return await whisper.ensureReady(model: selectedModel)
        case .parakeet:
            return await parakeet.ensureReady(model: selectedParakeetModel)
        case .phonon:
            return await phonon.ensureReady()
        case .openAI:
            return await openAI.ensureReady()
        case .bark30, .bark30Clean, .bark30Plus:
            guard let model = transcriptionEngine.barkModel else {
                return ModelReadyStatus(ready: false, message: "Bark model is not configured")
            }
            return await bark.ensureReady(model)
        }
    }

    private func warmActiveEngine() async {
        switch transcriptionEngine {
        case .whisper:
            await warmWhisper()
        case .parakeet:
            await warmParakeet()
        case .phonon:
            await phonon.warm()
        case .bark30, .bark30Clean, .bark30Plus:
            if let model = transcriptionEngine.barkModel { await bark.warm(model) }
        case .appleSpeech, .openAI:
            break
        }
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

    func installParakeetRuntime() {
        runSetup(script: "setup-parakeet.sh", environment: [:], ready: .parakeet)
    }

    func installPhonon() {
        runSetup(script: "setup-phonon.sh", environment: [:], ready: .phonon)
    }

    func installBark() {
        guard let model = transcriptionEngine.barkModel else { return }
        let spec = model.model
        let weight = spec.files[0]
        let directory = BarkRuntime.modelDir(model)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        runSetup(
            script: "setup-bark.sh",
            environment: [
                "BARK_DIR": directory.path,
                "BARK_REPO": spec.repo,
                "BARK_REVISION": spec.revision,
                "BARK_SHA256": weight.sha256,
                "BARK_URL": spec.fileURL(weight.name).absoluteString,
                "BARK_HELPERS": model.loaderChecksumJSON,
            ],
            ready: model.engine
        )
    }

    func saveOpenAIKey(_ key: String) {
        do {
            try APIKeyStore.save(key)
            openAIKeySaved = true
            errorMessage = nil
            Task { await refreshModelStatus() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearOpenAIKey() {
        APIKeyStore.delete()
        openAIKeySaved = false
        Task { await refreshModelStatus() }
    }

    private func runSetup(script name: String, environment: [String: String], ready: TranscriptionEngine) {
        guard !runtimeSetupBusy else { return }
        guard let script = setupScript(name) else {
            runtimeSetupLog = "\(name) not found"
            errorMessage = runtimeSetupLog
            return
        }
        runtimeSetupBusy = true
        runtimeSetupLog = "Starting \(name)…\n"
        modelStatus = "Installing…"
        let env = environment
        Task.detached { [weak self] in
            await Self.streamSetup(script: script, environment: env, ready: ready, owner: self)
        }
    }

    private static func streamSetup(
        script: String,
        environment: [String: String],
        ready: TranscriptionEngine,
        owner: AppState?
    ) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        proc.environment = env
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = out
        do {
            try proc.run()
            await drainSetup(proc, pipe: out, owner: owner)
            let code = proc.terminationStatus
            await MainActor.run {
                owner?.finishSetup(code: code, ready: ready)
            }
        } catch {
            await MainActor.run {
                owner?.runtimeSetupBusy = false
                owner?.errorMessage = error.localizedDescription
            }
        }
    }

    private static func drainSetup(_ proc: Process, pipe: Pipe, owner: AppState?) async {
        while proc.isRunning {
            let data = pipe.fileHandleForReading.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                await MainActor.run { owner?.appendSetupLog(text) }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: rest, encoding: .utf8), !text.isEmpty {
            await MainActor.run { owner?.appendSetupLog(text) }
        }
    }

    private func appendSetupLog(_ text: String) {
        runtimeSetupLog += text
        modelDownloadStatus = text.split(separator: "\n").last.map(String.init) ?? modelDownloadStatus
    }

    private func finishSetup(code: Int32, ready: TranscriptionEngine) {
        runtimeSetupBusy = false
        if code == 0 {
            errorMessage = nil
            transcriptionEngine = ready
            modelStatus = "\(ready.displayName) installed"
            Task { await refreshModelStatus() }
            return
        }
        errorMessage = "\(ready.displayName) install failed (exit \(code))"
        modelStatus = "Install failed"
    }

    private func setupScript(_ name: String) -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name).path {
            candidates.append(bundled)
        }
        candidates.append(FileManager.default.currentDirectoryPath + "/scripts/" + name)
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
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
        Task { await self.warmActiveEngine() }

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
            try audio.start(
                livePartials: wantsLivePartials,
                language: language,
                transcriptionEngine: transcriptionEngine
            )
            sessionID = UUID()
            isRecording = true
            showListeningUI()
            if playSounds { SoundPlayer.playStart() }
        } catch {
            showMicError(error)
        }
    }

    private var wantsLivePartials: Bool {
        livePartials && (transcriptionEngine == .appleSpeech || showLiveOverlay)
    }

    private func showListeningUI() {
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
    }

    private func showMicError(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Mic error"
        livePreview = error.localizedDescription
        showOverlay = true
        overlay?.show()
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
            await self.finishTake(
                sampleResult: sampleResult,
                engine: engine,
                whisperModel: whisperModel,
                parakeetModel: parakeetModel,
                dictationMode: dictationMode,
                language: lang,
                wantPaste: wantPaste,
                selectedForRewrite: selectedForRewrite,
                targetBundle: targetBundle,
                smart: smart,
                strip: strip
            )
        }
    }

    private func finishTake(
        sampleResult: Result<URL, Error>,
        engine: TranscriptionEngine,
        whisperModel: WhisperModel,
        parakeetModel: ParakeetModel,
        dictationMode: DictationMode,
        language: String,
        wantPaste: Bool,
        selectedForRewrite: String?,
        targetBundle: String?,
        smart: Bool,
        strip: Bool
    ) async {
        let sampleURL: URL
        switch sampleResult {
        case .failure(let error):
            showRecordingFailure(error)
            return
        case .success(let url):
            sampleURL = url
        }
        do {
            let text = try await cleanedTranscript(
                sampleURL: sampleURL,
                engine: engine,
                whisperModel: whisperModel,
                parakeetModel: parakeetModel,
                dictationMode: dictationMode,
                language: language,
                selectedForRewrite: selectedForRewrite,
                targetBundle: targetBundle,
                smart: smart,
                strip: strip
            )
            try await publishTranscript(text, sampleURL: sampleURL, wantPaste: wantPaste, dictationMode: dictationMode)
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Failed: \(error.localizedDescription)"
            livePreview = error.localizedDescription
            keepOverlayBrieflyThenHide(seconds: 2.0)
        }
        try? FileManager.default.removeItem(at: sampleURL)
        refreshPermissions()
    }

    private func showRecordingFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Recording failed"
        livePreview = error.localizedDescription
        keepOverlayBrieflyThenHide()
    }

    private func cleanedTranscript(
        sampleURL: URL,
        engine: TranscriptionEngine,
        whisperModel: WhisperModel,
        parakeetModel: ParakeetModel,
        dictationMode: DictationMode,
        language: String,
        selectedForRewrite: String?,
        targetBundle: String?,
        smart: Bool,
        strip: Bool
    ) async throws -> String {
        statusText = "Transcribing…"
        let sttMode: DictationMode = (dictationMode == .rewrite || dictationMode == .articulate) ? .transcribe : dictationMode
        var text = try await transcribeAudio(
            at: sampleURL,
            engine: engine,
            whisperModel: whisperModel,
            parakeetModel: parakeetModel,
            mode: sttMode,
            language: language
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if dictationMode == .rewrite, let source = selectedForRewrite, !source.isEmpty {
            text = applyRewrite(source: source, instruction: text)
        }
        text = formatDictation(text, bundleID: targetBundle, smart: smart, strip: strip, mode: dictationMode)
        if dictationMode == .articulate {
            text = articulate(text, bundleID: targetBundle)
        }
        return text
    }

    private func formatDictation(
        _ text: String,
        bundleID: String?,
        smart: Bool,
        strip: Bool,
        mode: DictationMode
    ) -> String {
        guard !text.isEmpty else { return text }
        let options = TranscriptFormatter.options(
            forBundleID: bundleID,
            smartPunctuation: smart,
            stripFillers: strip || mode == .articulate
        )
        let formatted = TranscriptFormatter.format(text, options: options)
        return dictionary.apply(formatted, bundleID: bundleID)
    }

    private func articulate(_ text: String, bundleID: String?) -> String {
        guard !text.isEmpty else { return text }
        isEnhancing = true
        statusText = "Articulating…"
        livePreview = text
        var next = ArticulateService.articulate(text)
        next = dictionary.apply(next, bundleID: bundleID)
        if next.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(text) == .orderedSame {
            next = ArticulateService.articulate("I want the following: " + text)
        }
        statusText = "Articulated"
        isEnhancing = false
        livePreview = next
        return next
    }

    private func publishTranscript(
        _ text: String,
        sampleURL: URL,
        wantPaste: Bool,
        dictationMode: DictationMode
    ) async throws {
        lastTranscript = text
        livePreview = text.isEmpty ? "(no speech detected)" : text
        guard !text.isEmpty else {
            statusText = "No speech detected"
            errorMessage = takeNotice
            takeNotice = nil
            keepOverlayBrieflyThenHide()
            try? FileManager.default.removeItem(at: sampleURL)
            return
        }
        injector.copyToClipboard(text)
        appendHistory(text)
        if wantPaste {
            await pasteTranscript(text, dictationMode: dictationMode)
        } else {
            statusText = "Copied"
            errorMessage = takeNotice
            takeNotice = nil
            if showLiveOverlay {
                showOverlay = true
                overlay?.show()
                overlay?.refreshLayout()
            }
            keepOverlayBrieflyThenHide(seconds: 2.5)
        }
        if playSounds { SoundPlayer.playSuccess() }
    }

    private func pasteTranscript(_ text: String, dictationMode: DictationMode) async {
        let intoTerminal = injector.isTerminalTarget()
        let targetName = injector.targetApp?.localizedName ?? "app"
        statusText = intoTerminal ? "Pasting…" : "Inserting…"
        showOverlay = false
        overlay?.hide()
        NSApp.deactivate()
        var method = await insertText(text)
        if dictationMode == .rewrite,
           let pid = injector.targetApp?.processIdentifier,
           SelectionService.replaceSelectedText(text, targetPID: pid) {
            method = .accessibility
        }
        livePreview = text
        if showLiveOverlay {
            showOverlay = true
            overlay?.show()
        }
        reportPaste(method, intoTerminal: intoTerminal, targetName: targetName)
        keepOverlayBrieflyThenHide(seconds: 1.5)
    }

    private func reportPaste(_ method: TextInjector.InsertMethod?, intoTerminal: Bool, targetName: String) {
        switch method {
        case .accessibility, .appleScriptPaste, .terminalPaste, .typedText:
            statusText = intoTerminal ? "Pasted into \(targetName) ✓" : "Inserted into \(targetName) ✓"
            errorMessage = takeNotice
        case .clipboardPaste:
            statusText = "Sent paste to \(targetName)"
            errorMessage = takeNotice
        case .clipboardOnly, nil:
            statusText = "Copied — press ⌘V in \(targetName)"
            errorMessage = combinedNotice(pasteFailureDetail())
        }
        takeNotice = nil
    }

    private func combinedNotice(_ detail: String?) -> String? {
        if let notice = takeNotice, let detail {
            return "\(notice) \(detail)"
        }
        if let notice = takeNotice {
            return notice
        }
        return detail
    }

    private func pasteFailureDetail() -> String? {
        if let detail = injector.lastErrorDetail { return detail }
        if !TextInjector.accessibilityGranted() { return "Accessibility not granted (menu → Access)" }
        return nil
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
        takeNotice = nil
        switch engine {
        case .appleSpeech:
            return try await appleSpeech.transcribe(audioURL: url, language: language, mode: mode)
        case .whisper:
            let status = await whisper.ensureReady(model: whisperModel)
            let plan = EngineSelection.engineForTake(
                selected: .whisper,
                whisperReady: status.ready,
                translating: mode == .translate,
                unavailableNotice: EngineSelection.whisperUnavailableNotice(reason: status.message)
            )
            if plan.engine == .appleSpeech {
                let text = try await appleSpeech.transcribe(
                    audioURL: url,
                    language: language,
                    mode: mode,
                    route: .whisperFallback,
                    whisperMessage: status.message
                )
                takeNotice = plan.notice
                return text
            }
            if !status.ready {
                throw WhisperError.processFailed(status.message)
            }
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
        case .phonon:
            return try await phonon.transcribe(audioURL: url, mode: mode, language: language)
        case .openAI:
            return try await openAI.transcribe(audioURL: url, mode: mode)
        case .bark30, .bark30Clean, .bark30Plus:
            guard let barkModel = engine.barkModel else {
                throw LocalModelError.modelMissing("Bark model is not configured")
            }
            return try await bark.transcribe(audioURL: url, model: barkModel, mode: mode)
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
        AppSupport.directory().appendingPathComponent("history.json")
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
        let md = "# pushtotype history\n\n" + lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pushtotype-history.md")
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
