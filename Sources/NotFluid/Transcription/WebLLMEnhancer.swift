import Foundation
import WebKit
import AppKit

enum WebLLMError: LocalizedError {
    case notReady
    case failed(String)
    case timeout
    case empty
    case webGPUUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady: return "WebLLM not loaded — try Download again, or turn LLM boost off (smart punctuation still runs)"
        case .failed(let m): return m
        case .timeout: return "WebLLM timed out (often hangs at GPU load in WebKit). Turn off LLM boost or retry."
        case .empty: return "LLM returned empty text"
        case .webGPUUnavailable: return "WebGPU unavailable in WebKit — LLM boost can't run on this Mac/Safari build"
        }
    }
}

/// Experimental local LLM polish via WebLLM + WebGPU in WKWebView.
/// Note: WebKit WebGPU often stalls at “stage 7/8” (shader/GPU load). We use an
/// on-screen tiny window, progress watchdog, and short timeouts so dictation never hangs forever.
@MainActor
final class WebLLMEnhancer: NSObject, ObservableObject {
    static let shared = WebLLMEnhancer()

    @Published var isLoading = false
    @Published var isReady = false
    @Published var progress: Double = 0
    @Published var statusText = "WebLLM idle"
    @Published var lastError: String?
    @Published var stageLabel = ""

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var loadContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var enhanceContinuations: [UUID: CheckedContinuation<String, Error>] = [:]
    private var bridgeReady = false
    private var lastProgressAt = Date()
    private var watchdogTask: Task<Void, Never>?
    private var loadedModelId: String?

    private override init() {
        super.init()
    }

    func prepare(model: SuggestedLLM) async throws {
        ensureWebView()
        let ok = await waitForBridge(seconds: 12)
        guard ok else {
            throw WebLLMError.failed("WebLLM bridge did not start (network or WebKit blocked)")
        }
        // Reuse if same model already loaded
        if isReady, loadedModelId == model.modelId { return }
        try await loadModel(modelId: model.modelId)
    }

    /// - Parameter style: `"clean"` light polish · `"articulate"` AI-prompt / idea structuring
    func enhance(_ text: String, model: SuggestedLLM, style: String = "clean") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        if !isReady || loadedModelId != model.modelId {
            try await prepare(model: model)
        }

        let id = UUID()
        statusText = style == "articulate" ? "Articulating with LLM…" : "Polishing with LLM…"

        let rawOut: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            enhanceContinuations[id] = cont

            let payload: [String: Any] = [
                "id": id.uuidString,
                "text": trimmed,
                "style": style
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                enhanceContinuations.removeValue(forKey: id)
                cont.resume(throwing: WebLLMError.failed("Could not encode enhance request"))
                return
            }

            runAsyncJS("window.notfluidEnhance(\(json))") { [weak self] error in
                guard let self, let error else { return }
                if let c = self.enhanceContinuations.removeValue(forKey: id) {
                    c.resume(throwing: WebLLMError.failed(error.localizedDescription))
                }
            }

            // Keep dictation snappy — don't wait 2 minutes on a hung GPU path
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if let c = self.enhanceContinuations.removeValue(forKey: id) {
                    self.statusText = "LLM polish timed out — using unpolished text"
                    c.resume(throwing: WebLLMError.timeout)
                }
            }
        }

        // Swift-side guard: never paste a chatty reply
        return Self.sanitizePolish(output: rawOut, original: trimmed)
    }

    /// Drop model output that looks like a conversation / meta-description instead of cleaned dictation.
    static func sanitizePolish(output: String, original: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return original }

        // Strip wrapping quotes/backticks/code fences
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.contains("```") {
            s = s.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lower = s.lowercased()

        // Meta commentary about cleaning (the failure mode you hit)
        let metaPhrases = [
            "grammatically correct", "punctuationally", "filler words",
            "unnecessary punctuation", "free of any imperfections",
            "the text is now", "the text has been", "has been spaced",
            "spaced properly", "meaning and language are clear",
            "no filler", "cleaned up version", "here is the cleaned",
            "i have cleaned", "i've cleaned", "revised version",
            "the corrected text", "as requested", "without changing the meaning",
            "the following text", "output only the", "return only the"
        ]
        let metaHits = metaPhrases.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        if metaHits >= 2 {
            return original
        }
        // Single strong meta openers
        if lower.hasPrefix("the text is") || lower.hasPrefix("the text has")
            || lower.hasPrefix("your text") || lower.hasPrefix("this text is") {
            return original
        }

        let chattyPrefixes = [
            "sure", "of course", "certainly", "absolutely", "here is", "here's",
            "i think you", "i believe you", "it seems like", "it looks like you",
            "as an ai", "as a language", "happy to help", "let me know",
            "the cleaned", "cleaned version", "corrected version", "i've corrected",
            "i have corrected", "you said", "you meant", "did you mean",
            "i've fixed", "i have fixed", "fixed version"
        ]
        for p in chattyPrefixes {
            if lower.hasPrefix(p) { return original }
        }

        // Content overlap: cleaned dictation should share real words with the original
        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "are",
            "was", "were", "be", "been", "it", "this", "that", "with", "as", "at",
            "by", "from", "has", "have", "had", "not", "no", "any", "now", "been"
        ]
        func tokens(_ str: String) -> Set<String> {
            str.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stop.contains($0) }
                .reduce(into: Set<String>()) { $0.insert($1) }
        }
        let origTok = tokens(original)
        let outTok = tokens(s)
        if !origTok.isEmpty {
            let overlap = origTok.intersection(outTok).count
            let ratio = Double(overlap) / Double(origTok.count)
            // Almost no shared content words → model invented a reply
            if ratio < 0.25 && origTok.count >= 3 {
                return original
            }
        }

        // Wildly longer than input → almost certainly a reply/essay
        if s.count > max(100, original.count * 2) {
            return original
        }

        // Model asked a question back
        if s.contains("?") && !original.contains("?") && s.count > original.count + 20 {
            let qCount = s.filter { $0 == "?" }.count
            if qCount >= 1 && s.split(separator: " ").count > original.split(separator: " ").count + 8 {
                return original
            }
        }

        return s.isEmpty ? original : s
    }

    func unload() {
        watchdogTask?.cancel()
        isReady = false
        isLoading = false
        progress = 0
        loadedModelId = nil
        statusText = "WebLLM unloaded"
        runAsyncJS("window.notfluidUnload && window.notfluidUnload()")
    }

    func cancelLoad() {
        watchdogTask?.cancel()
        for (_, cont) in loadContinuations {
            cont.resume(throwing: WebLLMError.failed("Cancelled"))
        }
        loadContinuations.removeAll()
        isLoading = false
        statusText = "Download cancelled"
    }

    private func runAsyncJS(_ expression: String, onRealError: ((Error?) -> Void)? = nil) {
        let js = """
        (function(){
          try { \(expression); return true; }
          catch (e) { return 'ERR:' + String(e && e.message ? e.message : e); }
        })()
        """
        webView?.evaluateJavaScript(js) { result, error in
            Task { @MainActor in
                if let error {
                    let msg = error.localizedDescription
                    if msg.localizedCaseInsensitiveContains("unsupported type") {
                        onRealError?(nil)
                        return
                    }
                    onRealError?(error)
                    return
                }
                if let s = result as? String, s.hasPrefix("ERR:") {
                    onRealError?(WebLLMError.failed(String(s.dropFirst(4))))
                    return
                }
                onRealError?(nil)
            }
        }
    }

    private func ensureWebView() {
        if webView != nil {
            // Keep tiny window on-screen so WebGPU can finish shader load
            hostWindow?.alphaValue = 0.02
            hostWindow?.orderFrontRegardless()
            return
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "notfluid")
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        if #available(macOS 14.0, *) {
            // Prefer desktop page for WebGPU feature detection
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 96, height: 96), configuration: config)
        wv.navigationDelegate = self

        // CRITICAL: Off-screen windows often hang WebGPU at stage 7/8 (GPU compile).
        // Use a real on-screen, nearly invisible window.
        let window = NSWindow(
            contentRect: NSRect(x: 8, y: 8, width: 96, height: 96),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.alphaValue = 0.02
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = wv
        window.orderFrontRegardless()
        hostWindow = window
        webView = wv

        wv.loadHTMLString(Self.bridgeHTML, baseURL: URL(string: "https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm@0.2.79/"))
        statusText = "Starting WebGPU bridge…"
    }

    private func waitForBridge(seconds: Double) async -> Bool {
        if bridgeReady { return true }
        let steps = Int(seconds * 10)
        for _ in 0..<steps {
            if bridgeReady { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return bridgeReady
    }

    private func loadModel(modelId: String) async throws {
        isLoading = true
        isReady = false
        lastError = nil
        progress = 0
        lastProgressAt = Date()
        statusText = "Loading \(modelId)…"
        stageLabel = "Starting…"
        hostWindow?.orderFrontRegardless()

        let id = UUID()
        startWatchdog(for: id)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            loadContinuations[id] = cont
            let payload: [String: Any] = ["id": id.uuidString, "modelId": modelId]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                loadContinuations.removeValue(forKey: id)
                cont.resume(throwing: WebLLMError.failed("Could not encode load request"))
                return
            }
            runAsyncJS("window.notfluidLoad(\(json))") { [weak self] error in
                guard let self, let error else { return }
                if let c = self.loadContinuations.removeValue(forKey: id) {
                    self.finishLoadFailure(error.localizedDescription)
                    c.resume(throwing: WebLLMError.failed(error.localizedDescription))
                }
            }

            // Hard cap 3 minutes
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                if let c = self.loadContinuations.removeValue(forKey: id) {
                    self.finishLoadFailure("Timed out (often stuck at GPU stage 7/8). Disable LLM boost or retry.")
                    c.resume(throwing: WebLLMError.timeout)
                }
            }
        }
        loadedModelId = modelId
    }

    /// If progress freezes > 45s (classic stage 7 hang), fail the load.
    private func startWatchdog(for id: UUID) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard loadContinuations[id] != nil else { return }
                if isReady { return }
                let stalled = Date().timeIntervalSince(lastProgressAt)
                // Allow long downloads early; after 50% freeze is almost always GPU hang
                if progress >= 0.55 && stalled > 40 {
                    if let c = loadContinuations.removeValue(forKey: id) {
                        finishLoadFailure(
                            "Stuck at \(stageLabel.isEmpty ? "GPU load" : stageLabel) (stage ~\(Int(progress * 8))/8). WebGPU hang — turn off LLM boost or retry later."
                        )
                        c.resume(throwing: WebLLMError.timeout)
                    }
                    return
                }
                if stalled > 90 && progress < 0.1 {
                    if let c = loadContinuations.removeValue(forKey: id) {
                        finishLoadFailure("No download progress — check network.")
                        c.resume(throwing: WebLLMError.timeout)
                    }
                    return
                }
            }
        }
    }

    private func finishLoadFailure(_ message: String) {
        watchdogTask?.cancel()
        isLoading = false
        isReady = false
        lastError = message
        statusText = "LLM failed"
        stageLabel = message
    }

    private static let bridgeHTML: String = """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8" /><title>n0tfluid WebLLM</title></head>
    <body style="background:#111;color:#eee;font:12px monospace">
      <div id="log">WebLLM…</div>
      <canvas id="c" width="64" height="64"></canvas>
      <script type="module">
        const log = (m) => {
          const el = document.getElementById('log');
          if (el) el.textContent = String(m).slice(0, 200);
          try { window.webkit.messageHandlers.notfluid.postMessage({ type: 'log', message: String(m) }); } catch (_) {}
        };
        const post = (obj) => {
          try { window.webkit.messageHandlers.notfluid.postMessage(obj); } catch (e) {}
        };

        let engine = null;

        // Probe WebGPU early
        async function checkGPU() {
          if (!navigator.gpu) {
            post({ type: 'error', id: 'gpu', message: 'navigator.gpu missing — WebGPU not available in this WebKit' });
            return false;
          }
          try {
            const adapter = await navigator.gpu.requestAdapter();
            if (!adapter) {
              post({ type: 'error', id: 'gpu', message: 'No WebGPU adapter' });
              return false;
            }
            log('WebGPU adapter OK');
            return true;
          } catch (e) {
            post({ type: 'error', id: 'gpu', message: 'WebGPU: ' + e });
            return false;
          }
        }

        // Copy-editor mode: emit the rewritten sentence itself, never a status report.
        const SYSTEM = `Copy-edit only. You receive raw dictation. You output the same content, cleaned.
    NEVER describe your work. NEVER say the text is correct/clean/spaced/grammatical.
    NEVER reply as an assistant. Output the dictation words only.
    Example input: um so like we should ship the build tomorrow period
    Example output: So we should ship the build tomorrow.
    Wrong output: The text is now grammatically correct and properly spaced.`;

        function stripChatty(out, original) {
          let s = (out || '').trim();
          if (!s) return original;
          s = s.replace(/^["'`]+|["'`]+$/g, '');
          const low = s.toLowerCase();
          const meta = [
            'grammatically', 'punctuationally', 'filler words', 'spaced properly',
            'the text is now', 'the text has been', 'free of any', 'imperfections',
            'cleaned version', 'here is the', 'i have cleaned', 'as an ai'
          ];
          let hits = 0;
          for (const m of meta) if (low.includes(m)) hits++;
          if (hits >= 2) return original;
          if (low.startsWith('the text is') || low.startsWith('the text has') || low.startsWith('your text')) return original;
          if (s.length > Math.max(100, original.length * 2)) return original;
          // word overlap
          const stop = new Set(['the','a','an','and','or','to','of','in','on','for','is','are','was','it','this','that','with','as','at','by','from','has','have','not','no','any','now']);
          const tok = (t) => new Set(t.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 2 && !stop.has(w)));
          const o = tok(original), u = tok(s);
          if (o.size >= 3) {
            let inter = 0;
            for (const w of o) if (u.has(w)) inter++;
            if (inter / o.size < 0.25) return original;
          }
          return s.trim() || original;
        }

        async function ensureWebLLM() {
          if (window.__webllm) return window.__webllm;
          log('Importing web-llm…');
          // Pin version; esm.run latest can break
          const webllm = await import('https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm@0.2.79/+esm');
          window.__webllm = webllm;
          return webllm;
        }

        window.notfluidLoad = (payload) => {
          const { id, modelId } = payload;
          (async () => {
            try {
              const gpuOk = await checkGPU();
              if (!gpuOk) throw new Error('WebGPU unavailable');
              const webllm = await ensureWebLLM();
              log('CreateMLCEngine ' + modelId);
              // Prefer smallest instruct models that finish GPU load reliably
              engine = await webllm.CreateMLCEngine(modelId, {
                initProgressCallback: (report) => {
                  post({
                    type: 'progress',
                    id,
                    progress: typeof report.progress === 'number' ? report.progress : 0,
                    text: report.text || ''
                  });
                }
              });
              post({ type: 'loaded', id, modelId });
              log('Ready');
            } catch (e) {
              post({ type: 'error', id, message: String(e && e.message ? e.message : e) });
              log('Err ' + e);
            }
          })();
          return true;
        };

        const SYSTEM_ARTICULATE = `You articulate rough spoken brainstorming into clear prose for AI coding assistants and project docs.
    Output ONLY the articulated text — never meta-commentary.
    Preserve intent and technical meaning. Use complete sentences, clean structure.
    Prefer concrete requirements over filler. Use short bullets if they listed features/steps.
    Do not invent requirements. Wrong: "The text is now clear." Right: the user's improved idea.`;

        window.notfluidEnhance = (payload) => {
          const { id, text, style } = payload;
          const mode = style || 'clean';
          (async () => {
            try {
              if (!engine) throw new Error('Model not loaded');
              const isArt = mode === 'articulate';
              const sys = isArt ? SYSTEM_ARTICULATE : SYSTEM;
              const messages = isArt ? [
                  { role: 'system', content: sys },
                  { role: 'user', content: 'um so i want like a menu bar app that does dictation and pastes into terminal' },
                  { role: 'assistant', content: 'I want a menu bar app for dictation that pastes transcribed text into the Terminal.' },
                  { role: 'user', content: 'also need rewrite mode and like better punctuation and then ship it' },
                  { role: 'assistant', content: 'Also add a rewrite mode and improved punctuation, then prepare it for release.' },
                  { role: 'user', content: 'Articulate this spoken brainstorm for an AI coding assistant. Return ONLY the improved text.\\n\\n---\\n' + text + '\\n---' }
                ] : [
                  { role: 'system', content: sys },
                  { role: 'user', content: 'um hello there comma how are you today question mark' },
                  { role: 'assistant', content: 'Hello there, how are you today?' },
                  { role: 'user', content: 'we need to fix the crash in audio capture period' },
                  { role: 'assistant', content: 'We need to fix the crash in audio capture.' },
                  { role: 'user', content: text }
                ];
              const result = await engine.chat.completions.create({
                messages,
                temperature: isArt ? 0.15 : 0.0,
                max_tokens: Math.min(isArt ? 512 : 256, Math.max(48, text.split(/\\s+/).length * 4 + 32))
              });
              let out = (result.choices?.[0]?.message?.content || '').trim();
              out = stripChatty(out, text);
              post({ type: 'result', id, text: out || text });
            } catch (e) {
              post({ type: 'error', id, message: String(e && e.message ? e.message : e) });
            }
          })();
          return true;
        };

        window.notfluidUnload = () => {
          (async () => {
            try { if (engine?.unload) await engine.unload(); } catch (_) {}
            engine = null;
          })();
          return true;
        };

        checkGPU().then(() => {
          post({ type: 'bridgeReady' });
          log('Bridge ready');
        });
      </script>
    </body>
    </html>
    """
}

extension WebLLMEnhancer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "bridgeReady":
            bridgeReady = true
            statusText = "WebGPU bridge ready"

        case "progress":
            let p = body["progress"] as? Double ?? 0
            let text = body["text"] as? String ?? ""
            progress = max(progress, p)
            lastProgressAt = Date()
            isLoading = true
            if !text.isEmpty {
                statusText = text
                stageLabel = text
            }

        case "loaded":
            watchdogTask?.cancel()
            isLoading = false
            isReady = true
            progress = 1
            statusText = "LLM ready"
            stageLabel = "Ready"
            // Hide helper window after success
            hostWindow?.alphaValue = 0.01
            if let idStr = body["id"] as? String, let id = UUID(uuidString: idStr),
               let cont = loadContinuations.removeValue(forKey: id) {
                cont.resume()
            }

        case "result":
            if let idStr = body["id"] as? String, let id = UUID(uuidString: idStr),
               let cont = enhanceContinuations.removeValue(forKey: id) {
                let text = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { cont.resume(throwing: WebLLMError.empty) }
                else { cont.resume(returning: text) }
            }

        case "error":
            let msg = body["message"] as? String ?? "Unknown WebLLM error"
            let idStr = body["id"] as? String
            // GPU probe errors before a real load id
            if idStr == "gpu" {
                lastError = msg
                statusText = msg
                isLoading = false
                return
            }
            finishLoadFailure(msg)
            if let idStr, let id = UUID(uuidString: idStr) {
                if let cont = loadContinuations.removeValue(forKey: id) {
                    cont.resume(throwing: WebLLMError.failed(msg))
                }
                if let cont = enhanceContinuations.removeValue(forKey: id) {
                    cont.resume(throwing: WebLLMError.failed(msg))
                }
            }

        case "log":
            if let m = body["message"] as? String, !m.isEmpty {
                if isLoading || !isReady { statusText = m }
            }

        default:
            break
        }
    }
}

extension WebLLMEnhancer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastError = error.localizedDescription
        statusText = "Bridge failed to load"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastError = error.localizedDescription
        statusText = "Bridge failed to load"
    }
}
