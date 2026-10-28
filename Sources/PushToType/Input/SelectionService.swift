import Foundation
import AppKit
import ApplicationServices

/// Read / replace selected text in the frontmost app (rewrite mode).
enum SelectionService {
    static func readSelectedText(targetPID: pid_t? = nil) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let element: AXUIElement
        if let pid = targetPID {
            let app = AXUIElementCreateApplication(pid)
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                app,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success, let focused else { return nil }
            element = focused as! AXUIElement
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success, let focused else { return nil }
            element = focused as! AXUIElement
        }

        var selected: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        ) == .success, let s = selected as? String, !s.isEmpty {
            return s
        }
        return nil
    }

    static func replaceSelectedText(_ text: String, targetPID: pid_t? = nil) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let element: AXUIElement
        if let pid = targetPID {
            let app = AXUIElementCreateApplication(pid)
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                app,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success, let focused else { return false }
            element = focused as! AXUIElement
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success, let focused else { return false }
            element = focused as! AXUIElement
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }
}
