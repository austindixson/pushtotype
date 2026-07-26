import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit

enum PermissionDoctor {
    static func snapshot() -> PermissionSnapshot {
        let mic: Bool = {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return true
            default: return false
            }
        }()
        let speech: Bool = {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return true
            default: return false
            }
        }()
        return PermissionSnapshot(
            microphone: mic,
            accessibility: AXIsProcessTrusted(),
            speech: speech
        )
    }

    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    static func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    static func requestAccessibility() {
        TextInjector.requestAccessibilityPrompt()
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openSpeechSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        TextInjector.openAccessibilitySettings()
    }
}
