import AppKit

enum SoundPlayer {
    static func playStart() {
        NSSound(named: "Tink")?.play()
    }

    static func playStop() {
        NSSound(named: "Pop")?.play()
    }

    static func playSuccess() {
        NSSound(named: "Glass")?.play()
    }
}
