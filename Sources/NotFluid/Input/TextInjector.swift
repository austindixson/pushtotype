import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Inserts text into the app you were using (Terminal / Grok Build / Notes / …).
///
/// Critical for Grok Build: it runs *inside* Terminal.app. We post keyboard
/// events **to Terminal's PID** via `CGEvent.postToPid` (not session-wide taps
/// that often go nowhere, and not AppleScript Automation which is a separate
/// TCC grant that often fails silently).
final class TextInjector {

    enum InsertMethod: String {
        case accessibility
        case terminalPaste
        case appleScriptPaste
        case clipboardPaste
        case typedText
        case clipboardOnly
    }

    private(set) var targetApp: NSRunningApplication?
    private(set) var lastMethod: InsertMethod?
    private(set) var lastErrorDetail: String?

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "co.zeit.hyper",
        // Editors with integrated terminals (Grok Build often runs here)
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92" // Cursor (common id; name-hint covers others)
    ]

    private static let terminalNameHints = [
        "terminal", "iterm", "kitty", "alacritty", "wezterm", "warp", "ghostty", "hyper",
        "cursor", "code", "visual studio"
    ]

    /// Browsers / webviews: AX insert is unreliable (caret, contenteditable, cross-process).
    /// Prefer real clipboard ⌘V for these.
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "company.thebrowser.Browser", // Arc
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", // Orion
        "com.apple.MobileSafari", // unlikely desktop host
        "org.chromium.Chromium",
        "com.duckduckgo.macos.browser",
        "com.sigmaos.sigmaos.macos",
        "app.zen-browser.zen",
        "com.openai.chat", // ChatGPT desktop (Electron webviews)
        "com.anthropic.claudefordesktop"
    ]

    private static let browserNameHints = [
        "safari", "chrome", "firefox", "arc", "brave", "edge", "opera", "vivaldi",
        "orion", "chromium", "duckduckgo", "sigmaos", "zen browser", "dia"
    ]

    private static let ourBundleIDs: Set<String> = {
        var s: Set<String> = ["dev.n0tfluid.app"]
        if let b = Bundle.main.bundleIdentifier { s.insert(b) }
        return s
    }()

    // MARK: - Target

    func rememberTargetApp() {
        let skip = Self.ourBundleIDs

        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           !skip.contains(bid),
           front.activationPolicy == .regular {
            targetApp = front
            return
        }
        if let existing = targetApp, !existing.isTerminated,
           let bid = existing.bundleIdentifier, !skip.contains(bid) {
            return
        }
        if let term = runningTerminalHost() {
            targetApp = term
            return
        }
        targetApp = NSWorkspace.shared.runningApplications.first(where: {
            !$0.isTerminated
                && $0.activationPolicy == .regular
                && !skip.contains($0.bundleIdentifier ?? "")
        })
    }

    private func runningTerminalHost() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        if let exact = apps.first(where: { Self.terminalBundleIDs.contains($0.bundleIdentifier ?? "") }) {
            return exact
        }
        return apps.first(where: {
            let bid = ($0.bundleIdentifier ?? "").lowercased()
            let name = ($0.localizedName ?? "").lowercased()
            return bid.contains("terminal") || bid.contains("iterm") || bid.contains("ghostty")
                || bid.contains("kitty") || bid.contains("warp") || bid.contains("alacritty")
                || bid.contains("todesktop") || bid.contains("vscode") || bid.contains("cursor")
                || Self.terminalNameHints.contains { name.contains($0) }
        })
    }

    func isTerminalTarget(_ app: NSRunningApplication? = nil) -> Bool {
        let app = app ?? targetApp
        guard let app else { return false }
        if let bid = app.bundleIdentifier {
            if bid == "com.apple.dt.Xcode" { return false }
            if Self.terminalBundleIDs.contains(bid) { return true }
            let lower = bid.lowercased()
            if lower.contains("terminal") || lower.contains("iterm") || lower.contains("kitty")
                || lower.contains("alacritty") || lower.contains("wezterm") || lower.contains("warp")
                || lower.contains("ghostty") || lower.contains("todesktop") || lower.contains("vscode")
                || lower.contains("cursor") {
                return true
            }
        }
        let name = (app.localizedName ?? "").lowercased()
        return Self.terminalNameHints.contains { name.contains($0) }
    }

    /// Web browsers / Electron chat apps: form fields ignore AX set-value more often than not.
    func isBrowserTarget(_ app: NSRunningApplication? = nil) -> Bool {
        let app = app ?? targetApp
        guard let app else { return false }
        if let bid = app.bundleIdentifier {
            if Self.browserBundleIDs.contains(bid) { return true }
            let lower = bid.lowercased()
            if lower.contains("safari") || lower.contains("chrome") || lower.contains("firefox")
                || lower.contains("brave") || lower.contains("edgemac") || lower.contains("chromium")
                || lower.contains("thebrowser") || lower.contains("opera") || lower.contains("vivaldi")
                || lower.contains("orion") || lower.contains("duckduckgo") {
                return true
            }
        }
        let name = (app.localizedName ?? "").lowercased()
        return Self.browserNameHints.contains { name.contains($0) }
    }

    /// Prefer ⌘V over AX when the app hosts web content or complex editable views.
    private func prefersClipboardPaste(_ app: NSRunningApplication? = nil) -> Bool {
        if isBrowserTarget(app) { return true }
        // Slack / Discord / Notion / Linear etc. are Electron or web-heavy
        guard let bid = (app ?? targetApp)?.bundleIdentifier?.lowercased() else { return false }
        let webby = ["slack", "discord", "notion", "figma", "linear", "spotify", "zoom",
                     "teams", "webex", "whatsapp", "telegram", "signal", "obsidian",
                     "craft", "coda", "airtable", "asana", "trello", "clickup"]
        return webby.contains { bid.contains($0) }
    }

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        // writeObjects is the modern path Chrome/X.com actually read on paste.
        _ = pb.writeObjects([text as NSString])
        // Extra plain-text types for picky web editors (Draft.js / Lexical).
        let utf8 = NSPasteboard.PasteboardType("public.utf8-plain-text")
        _ = pb.setString(text, forType: .string)
        _ = pb.setData(Data(text.utf8), forType: utf8)
        _ = pb.setString(text, forType: NSPasteboard.PasteboardType("public.plain-text"))
    }

    func paste(_ text: String) {
        insertAfterDelay(text)
    }

    /// Fast path: copy → clear PTT modifiers → activate → paste/type.
    /// Browsers (Grok/ChatGPT contenteditable) get paste + verified type fallback.
    func insertAfterDelay(
        _ text: String,
        delay: TimeInterval = 0.02,
        prepareFocus: (() -> Void)? = nil,
        completion: ((InsertMethod?) -> Void)? = nil
    ) {
        guard !text.isEmpty else {
            completion?(nil)
            return
        }

        lastErrorDetail = nil
        lastMethod = nil
        copyToClipboard(text)
        prepareFocus?()
        ensurePasteTarget()

        let terminal = isTerminalTarget()
        let pid = targetApp?.processIdentifier
        let browserish = prefersClipboardPaste()

        let runInsert = {
            // Don't bounce an already-frontmost browser — that drops the X.com caret.
            self.forceActivateTarget(onlyIfNeeded: browserish)

            let settle: TimeInterval
            if browserish {
                settle = 0.2
            } else if terminal {
                settle = 0.03
            } else {
                settle = 0.02
            }

            let finish = {
                self.copyToClipboard(text)
                let targetPID = pid ?? self.targetApp?.processIdentifier

                if browserish {
                    self.insertIntoBrowser(text, pid: targetPID) { method in
                        self.lastMethod = method
                        completion?(method)
                    }
                } else {
                    let method = self.insertNow(text, pid: targetPID)
                    self.lastMethod = method
                    completion?(method)
                }
            }
            if settle > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: finish)
            } else {
                finish()
            }
        }

        let afterDelay = {
            // PTT (Right-⌥) must be fully up — Option+⌘V is not paste.
            let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags.isEmpty {
                runInsert()
            } else {
                self.waitForClearModifiers(maxWait: 0.5, then: runInsert)
            }
        }

        if delay <= 0 {
            afterDelay()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: afterDelay)
        }
    }

    @discardableResult
    func insertNowSync(_ text: String, activateTarget: Bool = true) -> InsertMethod {
        ensurePasteTarget()
        copyToClipboard(text)
        if activateTarget {
            forceActivateTarget(onlyIfNeeded: prefersClipboardPaste())
            Thread.sleep(forTimeInterval: prefersClipboardPaste() ? 0.12 : 0.06)
        }
        copyToClipboard(text)
        let pid = targetApp?.processIdentifier
        // Sync browser path: same paste strategy as async (not Unicode — X.com ignores it).
        if prefersClipboardPaste() {
            neutralizeModifiers(to: pid, delivery: .session)
            refocusFocusedElement(pid: pid)
            copyToClipboard(text)
            if pasteViaSystemEvents() {
                lastMethod = .appleScriptPaste
                return .appleScriptPaste
            }
            performPasteKeystroke(to: pid, delivery: .session)
            lastMethod = .clipboardPaste
            return .clipboardPaste
        }
        let method = insertNow(text, pid: pid) ?? .clipboardOnly
        lastMethod = method
        return method
    }

    private func ensurePasteTarget() {
        let skip = Self.ourBundleIDs
        if let t = targetApp, !t.isTerminated,
           let bid = t.bundleIdentifier, !skip.contains(bid) {
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           !skip.contains(bid),
           front.activationPolicy == .regular {
            targetApp = front
            return
        }
        // Grok Build always lives in a terminal host
        if let term = runningTerminalHost() {
            targetApp = term
            return
        }
        rememberTargetApp()
    }

    private func forceActivateTarget(onlyIfNeeded: Bool = false) {
        ensurePasteTarget()
        guard let app = targetApp, !app.isTerminated else { return }

        let alreadyFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if onlyIfNeeded && alreadyFront && !NSApp.isActive {
            return
        }

        if NSApp.isActive { NSApp.deactivate() }
        // Yield so a menu-bar / accessory app can hand frontmost cleanly (macOS 14+).
        NSApp.yieldActivation(to: app)
        app.activate()
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: - Insert

    private func insertNow(_ text: String, pid: pid_t?) -> InsertMethod? {
        copyToClipboard(text)
        neutralizeModifiers(to: pid, delivery: .session)

        if isTerminalTarget() {
            return insertIntoTerminalOrTUI(text, pid: pid)
        }

        // Browsers should use the async path (insertIntoBrowser). Sync callers still paste.
        if prefersClipboardPaste() {
            return insertViaClipboardPaste(text, pid: pid)
        }

        // Native GUI: AX at caret when available, else ⌘V
        if Self.accessibilityGranted(), insertViaAccessibilityIntoTarget(text) {
            return .accessibility
        }

        return insertViaClipboardPaste(text, pid: pid)
    }

    /// Terminal + Grok Build: PID-targeted ⌘V (avoids stealing focus from other apps).
    private func insertIntoTerminalOrTUI(_ text: String, pid: pid_t?) -> InsertMethod {
        let pid = pid ?? targetApp?.processIdentifier
        copyToClipboard(text)
        neutralizeModifiers(to: pid, delivery: .pid)
        forceActivateTarget(onlyIfNeeded: true)
        copyToClipboard(text)

        neutralizeModifiers(to: pid, delivery: .pid)
        performPasteKeystroke(to: pid, delivery: .pid)
        return .terminalPaste
    }

    /// Clipboard + ⌘V for native apps / sync callers.
    private func insertViaClipboardPaste(_ text: String, pid: pid_t?) -> InsertMethod {
        let pid = pid ?? targetApp?.processIdentifier
        forceActivateTarget(onlyIfNeeded: true)
        copyToClipboard(text)
        neutralizeModifiers(to: pid, delivery: .session)
        performPasteKeystroke(to: pid, delivery: .session)
        return Self.accessibilityGranted() ? .clipboardPaste : .clipboardOnly
    }

    /// X.com / Grok / ChatGPT / Draft.js / Lexical path.
    ///
    /// These editors want a real paste event. Unicode key synthesis is ignored.
    /// Primary: System Events ⌘V (same path Keyboard Maestro uses for Chrome).
    /// Fallback: timed CGEvent ⌘V chord (single tap — never double-post one event).
    private func insertIntoBrowser(_ text: String, pid: pid_t?, completion: @escaping (InsertMethod?) -> Void) {
        let pid = pid ?? targetApp?.processIdentifier

        guard Self.accessibilityGranted() else {
            copyToClipboard(text)
            lastErrorDetail = "Accessibility not granted — required to paste into browsers"
            completion(.clipboardOnly)
            return
        }

        copyToClipboard(text)
        neutralizeModifiers(to: pid, delivery: .session)
        refocusFocusedElement(pid: pid)
        // Clipboard again right before paste — Chrome reads at keystroke time.
        copyToClipboard(text)

        // 1) System Events (most reliable into Chrome / X.com contenteditable)
        if pasteViaSystemEvents() {
            completion(.appleScriptPaste)
            return
        }

        // 2) CGEvent timed chord
        performPasteKeystrokeTimed(to: pid, delivery: .session) {
            completion(.clipboardPaste)
        }
    }

    // MARK: - Focus / verify helpers

    private struct TextSnapshot {
        var value: String?
        var selected: String?
    }

    private func focusedElement(pid: pid_t?) -> AXUIElement? {
        if let pid {
            let appEl = AXUIElementCreateApplication(pid)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                appEl,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success, let focusedRef {
                return (focusedRef as! AXUIElement)
            }
        }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }
        let focused = focusedRef as! AXUIElement
        var elPid: pid_t = 0
        if AXUIElementGetPid(focused, &elPid) == .success,
           elPid == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        return focused
    }

    private func readFocusedTextSnapshot(pid: pid_t?) -> TextSnapshot {
        guard let el = focusedElement(pid: pid) else { return TextSnapshot() }
        var snap = TextSnapshot()
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success {
            if let s = valueRef as? String { snap.value = s }
            else if let a = valueRef as? NSAttributedString { snap.value = a.string }
        }
        var selRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &selRef) == .success {
            if let s = selRef as? String { snap.selected = s }
        }
        return snap
    }

    /// Ask the browser to keep keyboard focus on its current AX focused element.
    /// (Do not AX-press — that can activate buttons near chat composers.)
    private func refocusFocusedElement(pid: pid_t?) {
        guard let el = focusedElement(pid: pid) else { return }
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    @discardableResult
    private func pasteViaSystemEvents() -> Bool {
        // Prefer unix id — process name is ambiguous ("Google Chrome" vs "Chrome").
        let pid = targetApp?.processIdentifier
        let source: String
        if let pid {
            source = """
            tell application "System Events"
              try
                set p to first process whose unix id is \(pid)
                set frontmost of p to true
                delay 0.08
                keystroke "v" using command down
                return true
              on error
                return false
              end try
            end tell
            """
        } else if let name = targetApp?.localizedName, !name.isEmpty {
            let proc = name.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            source = """
            tell application "System Events"
              try
                set frontmost of process "\(proc)" to true
                delay 0.08
                keystroke "v" using command down
                return true
              on error
                return false
              end try
            end tell
            """
        } else {
            return false
        }
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if let error {
            lastErrorDetail = "System Events paste failed: \(error)"
            return false
        }
        return result.booleanValue || (result.stringValue?.lowercased() != "false")
    }

    // MARK: - CGEvent helpers

    private enum EventDelivery {
        /// Target process only (terminals / TUI hosts).
        case pid
        /// Session-wide HID tap — required for browsers after the target is frontmost.
        case session
        /// Both: PID first, then a *fresh* session event (never post one CGEvent twice).
        case pidThenSession
    }

    private func makeEventSource() -> CGEventSource? {
        // combinedSessionState matches a real keyboard more closely for Chrome paste.
        // (hidSystemState alone is often dropped by Chromium for ⌘V.)
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        return source
    }

    private func post(_ event: CGEvent, to pid: pid_t?, delivery: EventDelivery) {
        event.setIntegerValueField(.eventSourceUserData, value: HotkeyService.syntheticEventMarker)
        switch delivery {
        case .pid:
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cghidEventTap)
            }
        case .session:
            // One tap only — posting the same CGEvent twice is undefined and breaks Chrome chords.
            event.post(tap: .cghidEventTap)
        case .pidThenSession:
            if let pid {
                event.postToPid(pid)
            } else {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func postKey(
        virtualKey: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        pid: pid_t?,
        delivery: EventDelivery
    ) {
        let source = makeEventSource()
        switch delivery {
        case .pid, .session:
            if let e = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) {
                e.flags = flags
                post(e, to: pid, delivery: delivery)
            }
        case .pidThenSession:
            if let pid, let e = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) {
                e.flags = flags
                post(e, to: pid, delivery: .pid)
            }
            if let e = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) {
                e.flags = flags
                post(e, to: pid, delivery: .session)
            }
        }
    }

    private func neutralizeModifiers(to pid: pid_t?, delivery: EventDelivery = .session) {
        let keys: [CGKeyCode] = [
            CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption),
            CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand),
            CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl),
            CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift)
        ]
        for key in keys {
            postKey(virtualKey: key, keyDown: false, flags: [], pid: pid, delivery: delivery)
        }
    }

    private func performPasteKeystroke(to pid: pid_t?, delivery: EventDelivery = .session) {
        // Full ⌘-v chord — Chrome is more reliable with explicit ⌘ down/up than flag-only.
        let cmdKey = CGKeyCode(kVK_Command)
        let vKey = CGKeyCode(kVK_ANSI_V)
        postKey(virtualKey: cmdKey, keyDown: true, flags: .maskCommand, pid: pid, delivery: delivery)
        postKey(virtualKey: vKey, keyDown: true, flags: .maskCommand, pid: pid, delivery: delivery)
        postKey(virtualKey: vKey, keyDown: false, flags: .maskCommand, pid: pid, delivery: delivery)
        postKey(virtualKey: cmdKey, keyDown: false, flags: [], pid: pid, delivery: delivery)
    }

    /// Timed paste chord — Chrome / X.com often drop zero-delay synthetic chords.
    private func performPasteKeystrokeTimed(
        to pid: pid_t?,
        delivery: EventDelivery = .session,
        completion: @escaping () -> Void
    ) {
        let cmdKey = CGKeyCode(kVK_Command)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let gap: TimeInterval = 0.012

        postKey(virtualKey: cmdKey, keyDown: true, flags: .maskCommand, pid: pid, delivery: delivery)
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
            self.postKey(virtualKey: vKey, keyDown: true, flags: .maskCommand, pid: pid, delivery: delivery)
            DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
                self.postKey(virtualKey: vKey, keyDown: false, flags: .maskCommand, pid: pid, delivery: delivery)
                DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
                    self.postKey(virtualKey: cmdKey, keyDown: false, flags: [], pid: pid, delivery: delivery)
                    // Small tail so the host processes the chord before we continue.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: completion)
                }
            }
        }
    }

    /// Type text via Unicode keyboard events (up to 20 UTF-16 units per event).
    /// This is what actually works in Grok / React contenteditable when ⌘V is ignored.
    @discardableResult
    private func typeUnicode(to pid: pid_t?, text: String, delivery: EventDelivery = .session) -> Bool {
        let source = makeEventSource()
        let units = Array(text.utf16)
        guard !units.isEmpty else { return false }
        var ok = false
        var index = 0
        let chunk = 20 // CGEvent keyboardSetUnicodeString hard limit
        while index < units.count {
            let end = min(index + chunk, units.count)
            var chars = Array(units[index..<end])
            let len = chars.count
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.flags = []
                down.keyboardSetUnicodeString(stringLength: len, unicodeString: &chars)
                post(down, to: pid, delivery: delivery)
                ok = true
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.flags = []
                up.keyboardSetUnicodeString(stringLength: len, unicodeString: &chars)
                post(up, to: pid, delivery: .session == delivery ? .session : delivery)
            }
            index = end
        }
        return ok
    }

    private func waitForClearModifiers(maxWait: TimeInterval, then: @escaping () -> Void) {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty {
            then()
            return
        }
        let start = Date()
        func tick() {
            let f = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if f.isEmpty || Date().timeIntervalSince(start) >= maxWait {
                then()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: tick)
            }
        }
        tick()
    }

    // MARK: - AX (GUI apps)

    private func insertViaAccessibilityIntoTarget(_ text: String) -> Bool {
        if let app = targetApp, !app.isTerminated {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                appEl,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success, let focusedRef {
                if setTextOnElement(focusedRef as! AXUIElement, text: text) {
                    return true
                }
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else {
            return false
        }
        let focused = focusedRef as! AXUIElement
        var pid: pid_t = 0
        if AXUIElementGetPid(focused, &pid) == .success,
           pid == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        return setTextOnElement(focused, text: text)
    }

    private func setTextOnElement(_ element: AXUIElement, text: String) -> Bool {
        if AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success {
            return true
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else {
            return false
        }

        let current: String
        if let s = valueRef as? String {
            current = s
        } else if let a = valueRef as? NSAttributedString {
            current = a.string
        } else {
            return false
        }

        var range = CFRange(location: (current as NSString).length, length: 0)
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        }

        let ns = current as NSString
        let loc = max(0, min(range.location, ns.length))
        let len = max(0, min(range.length, ns.length - loc))
        let updated = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: text)

        guard AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updated as CFTypeRef
        ) == .success else {
            return false
        }

        var newRange = CFRange(location: loc + (text as NSString).length, length: 0)
        if let axVal = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axVal)
        }
        return true
    }

    // MARK: - Permissions

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    private static var didPromptThisSession = false

    @discardableResult
    static func requestAccessibilityPromptIfNeeded(force: Bool = false) -> Bool {
        if accessibilityGranted() { return true }
        if didPromptThisSession && !force { return false }
        didPromptThisSession = true
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func requestAccessibilityPrompt() {
        _ = requestAccessibilityPromptIfNeeded(force: false)
    }

    static func openAccessibilitySettings() {
        guard !accessibilityGranted() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
