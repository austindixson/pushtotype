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

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        _ = pb.setString(text, forType: .string)
        _ = pb.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
    }

    func paste(_ text: String) {
        insertAfterDelay(text)
    }

    /// Fast path: copy → clear PTT modifiers → activate → paste. Target ~100–250ms after release.
    func insertAfterDelay(
        _ text: String,
        delay: TimeInterval = 0.05,
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

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Only wait if Option is still physically down (Right-⌥ PTT)
            self.waitForClearModifiers(maxWait: 0.2) {
                self.forceActivateTarget()
                // Minimal settle — paste is rarely the bottleneck vs STT
                let settle: TimeInterval = terminal ? 0.05 : 0.02
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                    self.copyToClipboard(text)
                    let method = self.insertNow(text, pid: pid ?? self.targetApp?.processIdentifier)
                    self.lastMethod = method
                    completion?(method)
                }
            }
        }
    }

    @discardableResult
    func insertNowSync(_ text: String, activateTarget: Bool = true) -> InsertMethod {
        ensurePasteTarget()
        copyToClipboard(text)
        if activateTarget {
            forceActivateTarget()
            Thread.sleep(forTimeInterval: 0.06)
        }
        copyToClipboard(text)
        let method = insertNow(text, pid: targetApp?.processIdentifier) ?? .clipboardOnly
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

    private func forceActivateTarget() {
        if NSApp.isActive { NSApp.deactivate() }
        ensurePasteTarget()
        guard let app = targetApp, !app.isTerminated else { return }
        app.activate()
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: - Insert

    private func insertNow(_ text: String, pid: pid_t?) -> InsertMethod? {
        copyToClipboard(text)
        neutralizeModifiers(to: pid)

        if isTerminalTarget() {
            return insertIntoTerminalOrTUI(text, pid: pid)
        }

        // GUI apps: AX first
        if Self.accessibilityGranted(), insertViaAccessibilityIntoTarget(text) {
            return .accessibility
        }

        forceActivateTarget()
        copyToClipboard(text)
        neutralizeModifiers(to: pid)
        performPasteKeystroke(to: pid)
        return Self.accessibilityGranted() ? .clipboardPaste : .clipboardOnly
    }

    /// Terminal + Grok Build: ⌘V to host PID first (instant). Type only if paste can't run.
    private func insertIntoTerminalOrTUI(_ text: String, pid: pid_t?) -> InsertMethod {
        let pid = pid ?? targetApp?.processIdentifier
        copyToClipboard(text)
        neutralizeModifiers(to: pid)
        forceActivateTarget()
        copyToClipboard(text)

        // 1) Fast PID-targeted ⌘V (one shot — no multi-second typing)
        neutralizeModifiers(to: pid)
        performPasteKeystroke(to: pid)
        return .terminalPaste
    }

    // MARK: - PID-targeted CGEvent helpers

    private func post(_ event: CGEvent, to pid: pid_t?) {
        event.setIntegerValueField(.eventSourceUserData, value: HotkeyService.syntheticEventMarker)
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func neutralizeModifiers(to pid: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        let keys: [CGKeyCode] = [
            CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption),
            CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand),
            CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl),
            CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift)
        ]
        for key in keys {
            if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                up.flags = []
                post(up, to: pid)
            }
        }
    }

    private func performPasteKeystroke(to pid: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        let cmdKey = CGKeyCode(kVK_Command)
        let vKey = CGKeyCode(kVK_ANSI_V)

        if let e = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true) {
            e.flags = .maskCommand
            post(e, to: pid)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            e.flags = .maskCommand
            post(e, to: pid)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            e.flags = .maskCommand
            post(e, to: pid)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false) {
            e.flags = []
            post(e, to: pid)
        }
    }

    @discardableResult
    private func typeUnicode(to pid: pid_t?, text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        var ok = false
        for scalar in text.utf16 {
            var chars = [UniChar](repeating: 0, count: 1)
            chars[0] = scalar
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                post(down, to: pid)
                ok = true
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                post(up, to: pid)
            }
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
