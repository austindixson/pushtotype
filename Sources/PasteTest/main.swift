import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Verifies paste into TextEdit using target-app-scoped AX (same strategy as the app).
@main
struct PasteTestMain {
    static func main() {
        let _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            print("Enable Accessibility for this tool, then re-run.")
            Thread.sleep(forTimeInterval: 2)
        }
        print("AX trusted:", AXIsProcessTrusted())

        let marker = "n0tfluid-paste-ok-\(Int(Date().timeIntervalSince1970))"
        print("Marker:", marker)

        var err: NSDictionary?
        NSAppleScript(source: """
        tell application "TextEdit"
          activate
          make new document
        end tell
        """)?.executeAndReturnError(&err)
        Thread.sleep(forTimeInterval: 0.8)

        guard let te = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.TextEdit"
        }) else {
            print("FAIL: TextEdit not running")
            exit(1)
        }
        te.activate()
        Thread.sleep(forTimeInterval: 0.4)

        // Target-app-scoped AX (what NotFluid now does)
        let appEl = AXUIElementCreateApplication(te.processIdentifier)
        var focusedRef: CFTypeRef?
        let okFocus = AXUIElementCopyAttributeValue(
            appEl,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success

        var method = "none"
        if okFocus, let focusedRef {
            let focused = focusedRef as! AXUIElement
            if AXUIElementSetAttributeValue(
                focused,
                kAXSelectedTextAttribute as CFString,
                marker as CFTypeRef
            ) == .success {
                method = "ax-selectedText"
            }
        }

        if method == "none" {
            // Fallback: clipboard + System Events into TextEdit process
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.declareTypes([.string], owner: nil)
            pb.setString(marker, forType: .string)
            var asErr: NSDictionary?
            NSAppleScript(source: """
            tell application "System Events"
              set frontmost of process "TextEdit" to true
              delay 0.15
              keystroke "v" using command down
            end tell
            """)?.executeAndReturnError(&asErr)
            method = asErr == nil ? "applescript" : "fail-as"
            if let asErr { print("AS error:", asErr) }
        }

        print("Method:", method)
        Thread.sleep(forTimeInterval: 0.4)

        var readErr: NSDictionary?
        let result = NSAppleScript(source: """
        tell application "TextEdit"
          if (count of documents) is 0 then return ""
          return text of front document
        end tell
        """)?.executeAndReturnError(&readErr)
        let body = result?.stringValue ?? ""
        print("Content:", body.isEmpty ? "(empty)" : body)

        if body.contains(marker) {
            print("SUCCESS")
            exit(0)
        } else {
            print("FAIL")
            exit(1)
        }
    }
}
