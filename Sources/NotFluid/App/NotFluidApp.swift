import SwiftUI
import AppKit

@main
struct NotFluidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
            if appState.isRecording {
                Text("REC")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .help(appState.statusText)
    }

    private var iconName: String {
        if appState.isEnhancing { return "brain.head.profile" }
        if appState.isTranscribing { return "waveform" }
        if appState.isRecording { return "mic.fill" }
        return "mic"
    }

    private var iconColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing || appState.isEnhancing { return .orange }
        return .primary
    }
}
