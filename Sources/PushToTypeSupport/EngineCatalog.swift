import Foundation

/// The engine used when someone has not chosen one yet.
///
/// A benchmark on a real Mac picks the shipped default. Change `engine` and nothing else.
public enum DictationDefaults {
    public static let engine: TranscriptionEngine = .appleSpeech
}

public enum EngineSelection {
    public static func resolve(stored raw: String?) -> TranscriptionEngine {
        guard let raw, let engine = TranscriptionEngine(rawValue: raw) else {
            return DictationDefaults.engine
        }
        return engine
    }
}

public struct RemoteFile: Equatable, Sendable {
    public var name: String
    public var bytes: Int64
    public var sha256: String

    public init(name: String, bytes: Int64, sha256: String) {
        self.name = name
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public struct HuggingFaceModel: Equatable, Sendable {
    public var id: String
    public var repo: String
    public var revision: String
    public var runtime: String
    public var files: [RemoteFile]

    public init(id: String, repo: String, revision: String, runtime: String, files: [RemoteFile]) {
        self.id = id
        self.repo = repo
        self.revision = revision
        self.runtime = runtime
        self.files = files
    }

    public var bytes: Int64 {
        files.reduce(0) { $0 + $1.bytes }
    }

    public var downloadSizeLabel: String {
        ByteCount.megabytes(bytes)
    }

    public var pageURL: URL {
        HuggingFace.url(repo: repo, revision: revision, file: nil)
    }

    public func fileURL(_ name: String) -> URL {
        HuggingFace.url(repo: repo, revision: revision, file: name)
    }
}

enum HuggingFace {
    static func url(repo: String, revision: String, file: String?) -> URL {
        var text = "https://huggingface.co/\(repo)"
        if let file {
            text += "/resolve/\(revision)/\(file)"
        } else {
            text += "/tree/\(revision)"
        }
        guard let url = URL(string: text) else {
            preconditionFailure("Bad Hugging Face URL")
        }
        return url
    }
}

public enum ByteCount {
    public static func megabytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb.rounded())
    }
}

public enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    case appleSpeech
    case whisper
    case parakeet
    case phonon
    case openAI
    case bark30
    case bark30Clean
    case bark30Plus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleSpeech: return "macOS Speech"
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        case .phonon: return "Phonon 2"
        case .openAI: return "OpenAI"
        case .bark30: return "Bark 3.0"
        case .bark30Clean: return "Bark 3.0 Clean"
        case .bark30Plus: return "Bark 3.0 Plus"
        }
    }

    public var detail: String {
        switch self {
        case .appleSpeech:
            return "Built into macOS · no download · live partials · no translate"
        case .whisper:
            return "whisper.cpp · download an open model · multilingual and translate"
        case .parakeet:
            return "NVIDIA Parakeet TDT via onnx-asr · local · no translate"
        case .phonon:
            return "Phonon 2 · English · Apple silicon · local download"
        case .openAI:
            return "OpenAI transcription · your API key stays in the Keychain · audio is sent to OpenAI"
        case .bark30:
            return "Underdog Bark 3.0 · English · MLX · \(BarkModel.v3.model.downloadSizeLabel)"
        case .bark30Clean:
            return "Underdog Bark 3.0 Clean · drops fillers and false starts · MLX · \(BarkModel.v3Clean.model.downloadSizeLabel)"
        case .bark30Plus:
            return "Underdog Bark 3.0 Plus · English · MLX · \(BarkModel.v3Plus.model.downloadSizeLabel)"
        }
    }

    public var icon: String {
        switch self {
        case .appleSpeech: return "apple.logo"
        case .whisper: return "arrow.down.circle"
        case .parakeet: return "bolt.horizontal.circle"
        case .phonon: return "waveform"
        case .openAI: return "cloud"
        case .bark30, .bark30Clean, .bark30Plus: return "dog"
        }
    }

    public var menuBlurb: String {
        switch self {
        case .appleSpeech: return "Built-in · no download"
        case .whisper: return "Multilingual · translate"
        case .parakeet: return "Fast local · NVIDIA"
        case .phonon: return "English · Apple silicon"
        case .openAI: return "Cloud · your API key"
        case .bark30: return "MLX · Bark 3.0"
        case .bark30Clean: return "MLX · fewer fillers"
        case .bark30Plus: return "MLX · Bark 3.0 Plus"
        }
    }

    public var barkModel: BarkModel? {
        switch self {
        case .bark30: return .v3
        case .bark30Clean: return .v3Clean
        case .bark30Plus: return .v3Plus
        case .appleSpeech, .whisper, .parakeet, .phonon, .openAI:
            return nil
        }
    }
}

public enum AppleSpeechCatalog {
    public static let modelID = "macos-sfspeechrecognizer"
    public static let runtime = "Apple Speech.framework (SFSpeechRecognizer)"
}

public enum OpenAITranscriptionCatalog {
    public static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public static let primaryModel = "gpt-4o-transcribe"
    public static let fallbackModel = "whisper-1"
    public static let runtime = "OpenAI Audio transcriptions API"
}

public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    case tiny
    case base
    case small
    case smallEn = "small.en"
    case distillSmallEn = "distil-small.en"

    public var id: String { rawValue }

    public static var recommended: WhisperModel { .small }

    private static let whisperRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    private static let distilRevision = "9e4a67ca4569c30be43a3fe7fba1621e504f0093"

    public var model: HuggingFaceModel {
        switch self {
        case .tiny:
            return whisper("ggml-tiny", file: "ggml-tiny.bin", bytes: 77_691_713, sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21")
        case .base:
            return whisper("ggml-base", file: "ggml-base.bin", bytes: 147_951_465, sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe")
        case .small:
            return whisper("ggml-small", file: "ggml-small.bin", bytes: 487_601_967, sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b")
        case .smallEn:
            return whisper("ggml-small.en", file: "ggml-small.en.bin", bytes: 487_614_201, sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d")
        case .distillSmallEn:
            return HuggingFaceModel(
                id: "distil-small.en",
                repo: "distil-whisper/distil-small.en",
                revision: Self.distilRevision,
                runtime: "whisper.cpp (ggml)",
                files: [RemoteFile(name: "ggml-distil-small.en.bin", bytes: 336_191_657, sha256: "7691eb11167ab7aaf6b3e05d8266f2fd9ad89c550e433f86ac266ebdee6c970a")]
            )
        }
    }

    public var displayName: String {
        switch self {
        case .tiny: return "Whisper Tiny"
        case .base: return "Whisper Base"
        case .small: return "Whisper Small"
        case .smallEn: return "Whisper Small (English)"
        case .distillSmallEn: return "Distil-Whisper Small EN"
        }
    }

    public var downloadSizeLabel: String { model.downloadSizeLabel }

    public var detail: String {
        switch self {
        case .tiny: return "\(downloadSizeLabel) · fastest · lower accuracy · multilingual"
        case .base: return "\(downloadSizeLabel) · fast · good · multilingual"
        case .small: return "\(downloadSizeLabel) · dictation and translate"
        case .smallEn: return "\(downloadSizeLabel) · English only"
        case .distillSmallEn: return "\(downloadSizeLabel) · distilled English · no translate"
        }
    }

    public var ggmlFileName: String { model.files[0].name }

    public var downloadURL: URL { model.fileURL(ggmlFileName) }

    public var sha256: String { model.files[0].sha256 }

    public var supportsTranslate: Bool {
        switch self {
        case .smallEn, .distillSmallEn: return false
        case .tiny, .base, .small: return true
        }
    }

    private func whisper(_ id: String, file: String, bytes: Int64, sha256: String) -> HuggingFaceModel {
        HuggingFaceModel(
            id: id,
            repo: "ggerganov/whisper.cpp",
            revision: Self.whisperRevision,
            runtime: "whisper.cpp (ggml)",
            files: [RemoteFile(name: file, bytes: bytes, sha256: sha256)]
        )
    }
}

public enum ParakeetModel: String, CaseIterable, Identifiable, Sendable {
    case tdt06bV2 = "tdt-0.6b-v2"
    case tdt06bV3 = "tdt-0.6b-v3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tdt06bV2: return "Parakeet TDT 0.6B v2 (English)"
        case .tdt06bV3: return "Parakeet TDT 0.6B v3 (multilingual)"
        }
    }

    public var detail: String {
        "\(model.downloadSizeLabel) · int8 ONNX · \(model.runtime)"
    }

    public var onnxAsrName: String {
        switch self {
        case .tdt06bV2: return "nemo-parakeet-tdt-0.6b-v2"
        case .tdt06bV3: return "nemo-parakeet-tdt-0.6b-v3"
        }
    }

    public var localDirName: String {
        switch self {
        case .tdt06bV2: return "tdt-0.6b-v2-int8"
        case .tdt06bV3: return "tdt-0.6b-v3-int8"
        }
    }

    public var model: HuggingFaceModel {
        switch self {
        case .tdt06bV2:
            return HuggingFaceModel(
                id: "nemo-parakeet-tdt-0.6b-v2",
                repo: "istupakov/parakeet-tdt-0.6b-v2-onnx",
                revision: "0bbb45a3365852604aef28b538a8f066f4ccaa85",
                runtime: "onnx-asr (ONNX Runtime, int8)",
                files: [
                    RemoteFile(name: "encoder-model.int8.onnx", bytes: 652_184_014, sha256: "3e0581fda6ab843888b51e56d7ee78b6d5bc3237ec113af1f732d1d5286aa155"),
                    RemoteFile(name: "decoder_joint-model.int8.onnx", bytes: 8_998_286, sha256: "a449f49acd68979d418651dd2dcb737cc0f1bf0225e009e29ee326354edbf7d3"),
                    RemoteFile(name: "nemo128.onnx", bytes: 139_764, sha256: "a9fde1486ebfcc08f328d75ad4610c67835fea58c73ba57e3209a6f6cf019e9f"),
                ]
            )
        case .tdt06bV3:
            return HuggingFaceModel(
                id: "nemo-parakeet-tdt-0.6b-v3",
                repo: "istupakov/parakeet-tdt-0.6b-v3-onnx",
                revision: "8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce",
                runtime: "onnx-asr (ONNX Runtime, int8)",
                files: [
                    RemoteFile(name: "encoder-model.int8.onnx", bytes: 652_183_999, sha256: "6139d2fa7e1b086097b277c7149725edbab89cc7c7ae64b23c741be4055aff09"),
                    RemoteFile(name: "decoder_joint-model.int8.onnx", bytes: 18_202_004, sha256: "eea7483ee3d1a30375daedc8ed83e3960c91b098812127a0d99d1c8977667a70"),
                    RemoteFile(name: "nemo128.onnx", bytes: 139_764, sha256: "a9fde1486ebfcc08f328d75ad4610c67835fea58c73ba57e3209a6f6cf019e9f"),
                ]
            )
        }
    }
}

public enum BarkModel: String, CaseIterable, Identifiable, Sendable {
    case v3 = "bark-3.0"
    case v3Clean = "bark-3.0-clean"
    case v3Plus = "bark-3.0-plus"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .v3: return "Bark 3.0"
        case .v3Clean: return "Bark 3.0 Clean"
        case .v3Plus: return "Bark 3.0 Plus"
        }
    }

    public var engine: TranscriptionEngine {
        switch self {
        case .v3: return .bark30
        case .v3Clean: return .bark30Clean
        case .v3Plus: return .bark30Plus
        }
    }

    public var model: HuggingFaceModel {
        switch self {
        case .v3:
            return bark(
                id: "Underdog-Bark-3.0",
                repo: "ConwayResearch/Underdog-Bark-3.0",
                revision: "85db2ad18ab41e534a222ee253c29191d77ed919",
                bytes: 163_398_645,
                sha256: "c18de9418d73cbeb80b8c1287b392d480a56e191ef4a81d1baaa1b02e66d92ed"
            )
        case .v3Clean:
            return bark(
                id: "Underdog-Bark-3.0-Clean",
                repo: "ConwayResearch/Underdog-Bark-3.0-Clean",
                revision: "6d34ed8639b2b9a33e764acf06748519bbb950cf",
                bytes: 179_458_613,
                sha256: "b67ca90d94b79a36af4616f1cb3f241884925de7aa9f3e673a8d5c6c4cfd3436"
            )
        case .v3Plus:
            return bark(
                id: "Underdog-Bark-3.0-Plus",
                repo: "ConwayResearch/Underdog-Bark-3.0-Plus",
                revision: "d4fab2f8b95681e5ad3cfb4e8c5f4e0c009b3deb",
                bytes: 179_524_845,
                sha256: "fdd9f1052e4fdead07d71e8cd2138813eb0c209fd6ff8b1b6f47737e1e501857"
            )
        }
    }

    private func bark(id: String, repo: String, revision: String, bytes: Int64, sha256: String) -> HuggingFaceModel {
        HuggingFaceModel(
            id: id,
            repo: repo,
            revision: revision,
            runtime: "mlx-audio Parakeet graph via bark_mlx.py (MLX, Apple silicon)",
            files: [RemoteFile(name: "model.bark", bytes: bytes, sha256: sha256)]
        )
    }
}

public enum PhononCatalog {
    public static let model = HuggingFaceModel(
        id: "phonon-2",
        repo: "FermionResearch/Phonon-2",
        revision: "3e6ab3a81d73b4d424ff34cc72535deb606378ef",
        runtime: "fermion-research 0.2.4 on MLX (Apple silicon)",
        files: [RemoteFile(
            name: "phonon-2.bps.tar.zst",
            bytes: 163_515_201,
            sha256: "98125795b6dda72f5c6eee9ba33d19815df65dcb18b50a357bf9f73c9935309e"
        )]
    )
    public static let packageVersion = "0.2.4"
    /// Astral uv installer pinned by the Phonon setup script. Apache-2.0.
    public static let uvSHA256 = "b88bda573e566ef9bced66b155fe0408626fbbc053aee1c30ba686f0728c9447"
    public static let uvURL = URL(string: "https://github.com/astral-sh/uv/releases/download/0.12.21/uv-aarch64-apple-darwin.tar.gz")!
}
