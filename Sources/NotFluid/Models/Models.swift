import Foundation
import AppKit

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
        case .fastEnglish: return "Distil-Whisper Small EN · quick · English only"
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

// MARK: - Speech engines

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case appleSpeech
    case whisper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "macOS Speech"
        case .whisper: return "Whisper (download)"
        }
    }

    var detail: String {
        switch self {
        case .appleSpeech:
            return "Built into macOS · zero download · live partials · no translate"
        case .whisper:
            return "Open-source · download model · best accuracy · translate"
        }
    }

    var icon: String {
        switch self {
        case .appleSpeech: return "apple.logo"
        case .whisper: return "arrow.down.circle"
        }
    }
}

// MARK: - Whisper models

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case smallEn = "small.en"
    case distillSmallEn = "distil-small.en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Whisper Tiny"
        case .base: return "Whisper Base"
        case .small: return "Whisper Small ⭐"
        case .smallEn: return "Whisper Small (English)"
        case .distillSmallEn: return "Distil-Whisper Small EN"
        }
    }

    var detail: String {
        switch self {
        case .tiny: return "~75 MB · fastest · lower accuracy · 99 langs"
        case .base: return "~142 MB · fast · good · 99 langs"
        case .small: return "~466 MB · best small balance · dictation + translate"
        case .smallEn: return "~466 MB · English-only · slightly sharper EN"
        case .distillSmallEn: return "~166 MB · distilled EN · very fast"
        }
    }

    var ggmlFileName: String {
        switch self {
        case .tiny: return "ggml-tiny.bin"
        case .base: return "ggml-base.bin"
        case .small: return "ggml-small.bin"
        case .smallEn: return "ggml-small.en.bin"
        case .distillSmallEn: return "ggml-distil-small.en.bin"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(ggmlFileName)")!
    }

    var supportsTranslate: Bool {
        switch self {
        case .smallEn, .distillSmallEn: return false
        default: return true
        }
    }

    static var recommended: WhisperModel { .small }
}

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

// MARK: - LLM enhancement

enum EnhancementMode: String, CaseIterable, Identifiable {
    case off
    case webLLM

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .webLLM: return "WebLLM (WebGPU)"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Rule-based punctuation only"
        case .webLLM: return "Local LLM polish via WebGPU"
        }
    }
}

enum SuggestedLLM: String, CaseIterable, Identifiable {
    case qwen25_05b = "Qwen2.5-0.5B-Instruct-q4f16_1-MLC"
    case llama32_1b = "Llama-3.2-1B-Instruct-q4f16_1-MLC"
    case qwen25_15b = "Qwen2.5-1.5B-Instruct-q4f16_1-MLC"
    case phi35_mini = "Phi-3.5-mini-instruct-q4f16_1-MLC"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen25_05b: return "Qwen2.5 0.5B ⭐"
        case .llama32_1b: return "Llama 3.2 1B"
        case .qwen25_15b: return "Qwen2.5 1.5B"
        case .phi35_mini: return "Phi-3.5 Mini (~3.8B)"
        }
    }

    var detail: String {
        switch self {
        case .qwen25_05b: return "~0.5B · fastest polish"
        case .llama32_1b: return "~1B · stronger English"
        case .qwen25_15b: return "~1.5B · multilingual"
        case .phi35_mini: return "~3.8B · highest quality"
        }
    }

    var modelId: String { rawValue }
    static var recommended: SuggestedLLM { .qwen25_05b }
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
