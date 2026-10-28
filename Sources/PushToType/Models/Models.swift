import Foundation
import PushToTypeSupport

// MARK: - Dictation mode

enum DictationMode: String, CaseIterable, Identifiable {
    case transcribe
    case articulate
    case translate
    case rewrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcribe: return "Dictate"
        case .articulate: return "Articulate"
        case .translate: return "Translate"
        case .rewrite: return "Rewrite"
        }
    }

    /// Short label for tight segmented controls
    var shortTitle: String {
        switch self {
        case .transcribe: return "Dictate"
        case .articulate: return "Articulate"
        case .translate: return "Translate"
        case .rewrite: return "Rewrite"
        }
    }

    var subtitle: String {
        switch self {
        case .transcribe: return "Speech → text as spoken (cleaned)"
        case .articulate: return "Clarify & structure ideas for AI prompts, specs, and planning"
        case .translate: return "Any language → English (Whisper)"
        case .rewrite: return "Select text, hold hotkey, speak how to rewrite it"
        }
    }
}

// MARK: - Speed / quality presets

enum SpeedPreset: String, CaseIterable, Identifiable {
    case fastEnglish
    case balanced
    case accurate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fastEnglish: return "Fast English"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }

    var detail: String {
        switch self {
        case .fastEnglish: return "Distil-Whisper Small EN · English only · \(WhisperModel.distillSmallEn.downloadSizeLabel)"
        case .balanced: return "Whisper Small · quality + multilingual + translate"
        case .accurate: return "Whisper Small · same model, prefer when clarity matters"
        }
    }

    var whisperModel: WhisperModel {
        switch self {
        case .fastEnglish: return .distillSmallEn
        case .balanced, .accurate: return .small
        }
    }

    var preferredLanguage: String? {
        switch self {
        case .fastEnglish: return "en"
        default: return nil
        }
    }
}

// Speech engines and Whisper models live in PushToTypeSupport (`DictationDefaults.engine`).

// MARK: - Hotkey presets

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case rightOption
    case rightCommand
    case fnF13
    case optionSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .fnF13: return "F13"
        case .optionSpace: return "⌥Space"
        }
    }

    var hint: String {
        switch self {
        case .rightOption: return "Hold Right Option (recommended)"
        case .rightCommand: return "Hold Right Command"
        case .fnF13: return "Hold F13 (if keyboard has it)"
        case .optionSpace: return "Hold Option + Space"
        }
    }
}

// MARK: - Dictionary

struct DictionaryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var find: String
    var replace: String

    init(id: UUID = UUID(), find: String, replace: String) {
        self.id = id
        self.find = find
        self.replace = replace
    }
}

// MARK: - History / models

struct DictationEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let mode: String
    let createdAt: Date
    var pinned: Bool

    init(id: UUID = UUID(), text: String, mode: String, createdAt: Date = Date(), pinned: Bool = false) {
        self.id = id
        self.text = text
        self.mode = mode
        self.createdAt = createdAt
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        mode = try c.decode(String.self, forKey: .mode)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

struct ModelReadyStatus {
    let ready: Bool
    let message: String
}

// MARK: - Permissions snapshot

struct PermissionSnapshot {
    var microphone: Bool
    var accessibility: Bool
    var speech: Bool

    var allGood: Bool { microphone && accessibility }
}
