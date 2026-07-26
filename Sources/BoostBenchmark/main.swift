import Foundation
import NotFluidSupport

// MARK: - Fixtures (STT → gold clean, plus simulated LLM outputs)

struct Fixture {
    let name: String
    let stt: String
    let goldClean: String
    let llmGood: String
    let llmBad: String
}

let fixtures: [Fixture] = [
    Fixture(
        name: "product_idea",
        stt: "um so i want like a menu bar app that does dictation and also pastes into terminal and has rewrite mode",
        goldClean: "I want a menu bar app for dictation that pastes into the Terminal and has a rewrite mode.",
        llmGood: "I want a menu bar dictation app that pastes into Terminal and includes rewrite mode.",
        llmBad: "The text is now grammatically correct, punctuationally sound, and has been spaced properly. There are no filler words."
    ),
    Fixture(
        name: "short_command",
        stt: "fix the crash in audio capture period",
        goldClean: "Fix the crash in audio capture.",
        llmGood: "Fix the crash in audio capture.",
        llmBad: "Sure! Here's the cleaned version: Fix the crash in audio capture."
    ),
    Fixture(
        name: "ramble_features",
        stt: "i was thinking we should add live partials and then also glass UI and then ship it on github",
        goldClean: "We should add live partials, a glass UI, and ship it on GitHub.",
        llmGood: "We should add live partials and a glass UI, then ship the project on GitHub.",
        llmBad: "As an AI, I've cleaned up your dictation and made it more professional for you."
    ),
    Fixture(
        name: "already_clean",
        stt: "Please add dark mode support to the settings panel.",
        goldClean: "Please add dark mode support to the settings panel.",
        llmGood: "Please add dark mode support to the settings panel.",
        llmBad: "The text is free of any imperfections and the meaning is clear."
    ),
    Fixture(
        name: "email_ish",
        stt: "hey so just wanted to follow up on the proposal and see if you had time to review it this week",
        goldClean: "I wanted to follow up on the proposal and see if you had time to review it this week.",
        llmGood: "I wanted to follow up on the proposal and check whether you had time to review it this week.",
        llmBad: "Here is a more professional version of your email for you to send."
    )
]

// MARK: - Metrics

func elapsedMs(_ body: () -> Void) -> Double {
    let t0 = DispatchTime.now().uptimeNanoseconds
    body()
    let t1 = DispatchTime.now().uptimeNanoseconds
    return Double(t1 - t0) / 1_000_000.0
}

func editDistanceRatio(_ a: String, _ b: String) -> Double {
    let A = Array(a), B = Array(b)
    let n = A.count, m = B.count
    if n == 0 { return m == 0 ? 0 : 1 }
    if m == 0 { return 1 }
    var prev = Array(0...m)
    var cur = [Int](repeating: 0, count: m + 1)
    for i in 1...n {
        cur[0] = i
        for j in 1...m {
            let cost = A[i - 1] == B[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        prev = cur
    }
    return Double(prev[m]) / Double(max(n, m))
}

func tokenOverlap(_ a: String, _ b: String) -> Double {
    func toks(_ s: String) -> Set<String> {
        Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }
    let A = toks(a), B = toks(b)
    if A.isEmpty && B.isEmpty { return 1 }
    if A.isEmpty || B.isEmpty { return 0 }
    return Double(A.intersection(B).count) / Double(A.union(B).count)
}

// MARK: - Paths

enum PathKind: String, CaseIterable {
    case none = "STT only (raw)"
    case punctuation = "STT + smart punctuation"
    case articulate = "STT + Articulate offline"
    case llmGood = "STT + LLM good + sanitize"
    case llmBad = "STT + LLM bad + sanitize"
}

struct PathResult {
    let kind: PathKind
    let output: String
    let ms: Double
    let fellBack: Bool
}

func runPath(_ kind: PathKind, fixture: Fixture) -> PathResult {
    var out = fixture.stt
    var fellBack = false

    func once() {
        switch kind {
        case .none:
            out = fixture.stt
        case .punctuation:
            var o = TranscriptFormatter.Options.default
            o.smartPunctuation = true
            o.stripLightFillers = true
            out = TranscriptFormatter.format(fixture.stt, options: o)
        case .articulate:
            out = ArticulateService.articulate(fixture.stt)
        case .llmGood:
            let base = ArticulateService.articulate(fixture.stt)
            let sanitized = PolishSanitizer.sanitize(output: fixture.llmGood, original: base)
            fellBack = sanitized == base && fixture.llmGood != base
            out = sanitized
        case .llmBad:
            let base = ArticulateService.articulate(fixture.stt)
            let sanitized = PolishSanitizer.sanitize(output: fixture.llmBad, original: base)
            fellBack = sanitized == base
            out = sanitized
        }
    }

    // Warm + average
    once()
    var times: [Double] = []
    for _ in 0..<25 {
        times.append(elapsedMs { once() })
    }
    let avg = times.reduce(0, +) / Double(times.count)
    return PathResult(kind: kind, output: out, ms: avg, fellBack: fellBack)
}

func line(_ s: String) {
    if let data = (s + "\n").data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

@main
struct BoostBenchmarkMain {
    static func main() {
        line("PushToType / n0tfluid — boost path benchmark")
        line("Offline only (no WebGPU). Bad LLM rows test sanitizer fallback.")
        line("")

        let paths = PathKind.allCases
        var sumDist: [PathKind: Double] = [:]
        var sumMs: [PathKind: Double] = [:]
        var sumOverlap: [PathKind: Double] = [:]
        var fallbackOK = 0
        var fallbackTotal = 0

        for f in fixtures {
            line("=== Fixture: \(f.name) ===")
            line("STT:  \(f.stt)")
            line("Gold: \(f.goldClean)")
            line("")

            for kind in paths {
                let r = runPath(kind, fixture: f)
                let dist = editDistanceRatio(r.output, f.goldClean)
                let ov = tokenOverlap(r.output, f.goldClean)
                sumDist[kind, default: 0] += dist
                sumMs[kind, default: 0] += r.ms
                sumOverlap[kind, default: 0] += ov

                let preview = r.output.replacingOccurrences(of: "\n", with: " | ")
                let short = preview.count > 110 ? String(preview.prefix(107)) + "..." : preview

                line("  [\(kind.rawValue)]")
                line(String(format: "    latency_ms=%.3f  edit_vs_gold=%.3f  overlap_vs_gold=%.3f", r.ms, dist, ov))
                if kind == .llmBad || kind == .llmGood {
                    line("    sanitize_fallback=\(r.fellBack ? "yes" : "no")")
                }
                line("    output: \(short)")
                line("")

                if kind == .llmBad {
                    fallbackTotal += 1
                    if r.fellBack { fallbackOK += 1 }
                }
            }
        }

        let n = Double(fixtures.count)
        line("=== SUMMARY (averages) ===")
        for kind in paths {
            let ms = (sumMs[kind] ?? 0) / n
            let ed = (sumDist[kind] ?? 0) / n
            let ov = (sumOverlap[kind] ?? 0) / n
            line("  \(kind.rawValue): ms=\(String(format: "%.3f", ms)) edit=\(String(format: "%.3f", ed)) overlap=\(String(format: "%.3f", ov))")
        }
        let rate = fallbackTotal > 0 ? 100 * Double(fallbackOK) / Double(fallbackTotal) : 0
        line("Bad-LLM sanitizer catch rate: \(fallbackOK)/\(fallbackTotal) (\(String(format: "%.0f", rate))%)")
        line("")
        line("How to read: lower edit + higher overlap vs gold is better; llmBad should fallback 100%.")
        line("Note: ms is offline CPU only — real WebLLM GPU time is separate and often 100ms-2s+.")

        if fallbackTotal > 0 && fallbackOK < fallbackTotal {
            line("RESULT: FAIL")
            exit(1)
        }
        line("RESULT: PASS")
        exit(0)
    }
}
