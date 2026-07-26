import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Inserts dictated text at the caret of the app you were using.
/// Optimized for low latency: CGEvent ⌘V first, minimal waits, AX for GUI apps.
final class TextInjector {

    enum InsertMethod: String {
        case accessibility
        case terminalPaste
        case appleScriptPaste
        case clipboardPaste
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
        "co.zeit.hyper"
    ]

    private static let terminalNameHints = [
        "terminal", "iterm", "kitty", "alacritty", "wezterm", "warp", "ghostty", "hyper"
    ]

    // MARK: - Target

    func rememberTargetApp() {
        let skip = Set([
            "dev.n0tfluid.app",
            Bundle.main.bundleIdentifier ?? ""
        ].filter { !$0.isEmpty })

        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           !skip.contains(bid),
           front.activationPolicy == .regular {
            targetApp = front
            return
        }
        if let existing = targetApp, !existing.isTerminated { return }
        targetApp = NSWorkspace.shared.runningApplications.first(where: {
            !$0.isTerminated
                && $0.activationPolicy == .regular
                && !skip.contains($0.bundleIdentifier ?? "")
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
                || lower.contains("ghostty") {
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
    }

    func paste(_ text: String) {
        insertAfterDelay(text)
    }

    /// Fast path: copy → clear modifiers → activate → paste. Target ~100–250ms after release.
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
        // Copy immediately so clipboard is ready
        copyToClipboard(text)
        prepareFocus?()

        let terminal = isTerminalTarget()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Brief wait only if Option is still physically down
            self.waitForClearModifiers(maxWait: 0.2) {
                self.forceActivateTargetFast()
                // Tiny settle for focus — terminals need a hair more than Notes
                let settle: TimeInterval = terminal ? 0.08 : 0.04
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                    self.copyToClipboard(text)
                    let method = self.insertNow(text)
                    self.lastMethod = method
                    completion?(method)
                }
            }
        }
    }

    @discardableResult
    func insertNowSync(_ text: String, activateTarget: Bool = true) -> InsertMethod {
        copyToClipboard(text)
        if activateTarget {
            forceActivateTargetFast()
            Thread.sleep(forTimeInterval: 0.06)
        }
        copyToClipboard(text)
        let method = insertNow(text) ?? .clipboardOnly
        lastMethod = method
        return method
    }

    // MARK: - Activate (Cocoa only — AppleScript activate is ~300ms+)

    private func forceActivateTargetFast() {
        if let app = targetApp, !app.isTerminated {
            app.activate()
            return
        }
        rememberTargetApp()
        targetApp?.activate()
    }

    // MARK: - Insert

    private func insertNow(_ text: String) -> InsertMethod? {
        copyToClipboard(text)

        if isTerminalTarget() {
            return insertIntoTerminalFast(text)
        }

        // GUI: AX is instant when it works
        if Self.accessibilityGranted(), insertViaAccessibilityIntoTarget(text) {
            return .accessibility
        }

        // Fast CGEvent ⌘V
        neutralizeModifiersQuick()
        performPasteKeystroke()
        return Self.accessibilityGranted() ? .clipboardPaste : .clipboardOnly
    }

    /// Terminal: skip AX, skip AppleScript (slow). Clipboard + CGEvent ⌘V only.
    private func insertIntoTerminalFast(_ text: String) -> InsertMethod {
        copyToClipboard(text)
        neutralizeModifiersQuick()
        // Ensure frontmost
        forceActivateTargetFast()
        performPasteKeystroke()
        return .terminalPaste
    }

    private func neutralizeModifiersQuick() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        // Only Option matters for our PTT key — don't spam every modifier
        for key in [CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)] {
            if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - AX

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

    // MARK: - CGEvent paste (fast)

    private func performPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        let cmdKey = CGKeyCode(kVK_Command)
        let vKey = CGKeyCode(kVK_ANSI_V)

        // Compact ⌘V — minimal gaps
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cghidEventTap)
        }
        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
        }
        if let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cghidEventTap)
        }
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false) {
            cmdUp.flags = []
            cmdUp.post(tap: .cghidEventTap)
        }
    }

    private func waitForClearModifiers(maxWait: TimeInterval, then: @escaping () -> Void) {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty {
            then()
            return
        }
        // Option still down right after PTT release — short poll
        let start = Date()
        func tick() {
            let f = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if f.isEmpty || Date().timeIntervalSince(start) >= maxWait {
                then()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015, execute: tick)
            }
        }
        tick()
    }

    // MARK: - Permissions

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
