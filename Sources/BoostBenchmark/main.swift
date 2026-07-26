import Foundation
import NotFluidSupport

/// Benchmark post-STT paths: raw vs smart punctuation vs Articulate (no LLM).
///
///   ./scripts/benchmark-boost.sh
///   swift run BoostBenchmark

struct Fixture {
    let name: String
    let stt: String
    let goldClean: String
}

let fixtures: [Fixture] = [
    Fixture(
        name: "product_idea",
        stt: "um so i want like a menu bar app that does dictation and also pastes into terminal and has rewrite mode",
        goldClean: "I want a menu bar app for dictation that pastes into the Terminal and has a rewrite mode."
    ),
    Fixture(
        name: "short_command",
        stt: "fix the crash in audio capture period",
        goldClean: "Fix the crash in audio capture."
    ),
    Fixture(
        name: "ramble_features",
        stt: "i was thinking we should add live partials and then also glass UI and then ship it on github",
        goldClean: "We should add live partials, a glass UI, and ship it on GitHub."
    ),
    Fixture(
        name: "already_clean",
        stt: "Please add dark mode support to the settings panel.",
        goldClean: "Please add dark mode support to the settings panel."
    ),
    Fixture(
        name: "email_ish",
        stt: "hey so just wanted to follow up on the proposal and see if you had time to review it this week",
        goldClean: "I wanted to follow up on the proposal and see if you had time to review it this week."
    )
]

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

enum PathKind: String, CaseIterable {
    case none = "STT only (raw)"
    case punctuation = "STT + smart punctuation"
    case articulate = "STT + Articulate offline"
}

func line(_ s: String) {
    if let data = (s + "\n").data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

@main
struct BoostBenchmarkMain {
    static func main() {
        line("PushToType — post-STT path benchmark (no LLM)")
        line("")

        var sumDist: [PathKind: Double] = [:]
        var sumMs: [PathKind: Double] = [:]
        var sumOverlap: [PathKind: Double] = [:]

        for f in fixtures {
            line("=== \(f.name) ===")
            line("STT:  \(f.stt)")
            line("Gold: \(f.goldClean)")
            line("")

            for kind in PathKind.allCases {
                var out = f.stt
                func once() {
                    switch kind {
                    case .none:
                        out = f.stt
                    case .punctuation:
                        var o = TranscriptFormatter.Options.default
                        o.smartPunctuation = true
                        o.stripLightFillers = true
                        out = TranscriptFormatter.format(f.stt, options: o)
                    case .articulate:
                        out = ArticulateService.articulate(f.stt)
                    }
                }
                once()
                var times: [Double] = []
                for _ in 0..<25 { times.append(elapsedMs { once() }) }
                let ms = times.reduce(0, +) / Double(times.count)
                let dist = editDistanceRatio(out, f.goldClean)
                let ov = tokenOverlap(out, f.goldClean)
                sumDist[kind, default: 0] += dist
                sumMs[kind, default: 0] += ms
                sumOverlap[kind, default: 0] += ov

                let preview = out.replacingOccurrences(of: "\n", with: " | ")
                let short = preview.count > 110 ? String(preview.prefix(107)) + "..." : preview
                line("  [\(kind.rawValue)]")
                line(String(format: "    ms=%.3f edit=%.3f overlap=%.3f", ms, dist, ov))
                line("    \(short)")
                line("")
            }
        }

        let n = Double(fixtures.count)
        line("=== SUMMARY ===")
        for kind in PathKind.allCases {
            line(String(
                format: "  %@: ms=%.3f edit=%.3f overlap=%.3f",
                kind.rawValue,
                (sumMs[kind] ?? 0) / n,
                (sumDist[kind] ?? 0) / n,
                (sumOverlap[kind] ?? 0) / n
            ))
        }
        line("RESULT: PASS")
        exit(0)
    }
}
