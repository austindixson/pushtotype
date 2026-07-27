import SwiftUI
import AppKit

@main
struct NotFluidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // No MenuBarExtra window — StatusItemController owns the menu bar UI.
        // Keep a Settings scene for system shortcuts / completeness.
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.bootstrap()
        StatusItemController.shared.setup(appState: AppState.shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.showPanel()
        return true
    }
}
