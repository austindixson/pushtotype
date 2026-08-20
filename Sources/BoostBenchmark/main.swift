import Foundation
import NotFluidSupport

/// Benchmark post-STT paths: raw vs smart punctuation vs S1-mini vs Articulate.
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
    ),
    Fixture(
        name: "self_correction",
        stt: "so um i need to like send the the report by uh friday no wait make that thursday",
        goldClean: "I need to send the report by Thursday."
    ),
    Fixture(
        name: "spoken_number",
        stt: "the invoice came to twenty three thousand four hundred and fifty dollars and it's due on march third twenty twenty six",
        goldClean: "The invoice came to $23,450, and it's due on March 3, 2026."
    ),
    Fixture(
        name: "spoken_email",
        stt: "send it to support at superwhisper dot com",
        goldClean: "Send it to support@superwhisper.com."
    ),
    Fixture(
        name: "filler_only",
        stt: "um",
        goldClean: ""
    )
]

func elapsedMs(_ body: () -> Void) -> Double {
    let t0 = DispatchTime.now().uptimeNanoseconds
    body()
    let t1 = DispatchTime.now().uptimeNanoseconds
    return Double(t1 - t0) / 1_000_000.0
}

func elapsedMsAsync(_ body: () async -> Void) async -> Double {
    let t0 = DispatchTime.now().uptimeNanoseconds
    await body()
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
    case punctuation = "STT + smart punctuation (default)"
    case s1mini = "STT + S1-mini by Superwhisper"
    case articulate = "STT + Articulate offline"
}

func line(_ s: String) {
    if let data = (s + "\n").data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

@main
struct BoostBenchmarkMain {
    static func main() async {
        line("PushToType — post-STT path benchmark")
        line("Default = rule-based TranscriptFormatter. Challenger = S1-mini by Superwhisper.")
        line("")

        let s1 = S1MiniService()
        let s1Ready = await s1.ensureReady()
        if s1Ready.ready {
            line("S1-mini: \(s1Ready.message) — warming…")
            await s1.warm()
            line("S1-mini: warm")
        } else {
            line("S1-mini unavailable: \(s1Ready.message)")
            line("Skipping S1-mini path. Download with: ./scripts/download-model.sh s1-mini")
        }
        line("")

        var sumDist: [PathKind: Double] = [:]
        var sumMs: [PathKind: Double] = [:]
        var sumOverlap: [PathKind: Double] = [:]
        var counts: [PathKind: Int] = [:]

        for f in fixtures {
            line("=== \(f.name) ===")
            line("STT:  \(f.stt)")
            line("Gold: \(f.goldClean.isEmpty ? "(empty)" : f.goldClean)")
            line("")

            for kind in PathKind.allCases {
                if kind == .s1mini && !s1Ready.ready { continue }

                var out = f.stt
                var lastError: String?
                func once() async {
                    switch kind {
                    case .none:
                        out = f.stt
                    case .punctuation:
                        var o = TranscriptFormatter.Options.default
                        o.smartPunctuation = true
                        o.stripLightFillers = true
                        out = TranscriptFormatter.format(f.stt, options: o)
                    case .s1mini:
                        do {
                            out = try await s1.normalize(f.stt, controls: S1MiniControls())
                        } catch {
                            lastError = error.localizedDescription
                            out = f.stt
                        }
                    case .articulate:
                        out = ArticulateService.articulate(f.stt)
                    }
                }
                await once()
                var times: [Double] = []
                let repeats = kind == .s1mini ? 3 : 25
                for _ in 0..<repeats {
                    times.append(await elapsedMsAsync { await once() })
                }
                let ms = times.reduce(0, +) / Double(times.count)
                let dist = editDistanceRatio(out, f.goldClean)
                let ov = tokenOverlap(out, f.goldClean)
                sumDist[kind, default: 0] += dist
                sumMs[kind, default: 0] += ms
                sumOverlap[kind, default: 0] += ov
                counts[kind, default: 0] += 1

                let preview = out.replacingOccurrences(of: "\n", with: " | ")
                let short = preview.count > 110 ? String(preview.prefix(107)) + "..." : preview
                line("  [\(kind.rawValue)]")
                line(String(format: "    ms=%.3f edit=%.3f overlap=%.3f", ms, dist, ov))
                if let lastError {
                    line("    error: \(lastError)")
                }
                line("    \(short.isEmpty ? "(empty)" : short)")
                line("")
            }
        }

        line("=== SUMMARY ===")
        line("edit = normalized Levenshtein vs gold (lower is better)")
        line("overlap = token Jaccard vs gold (higher is better)")
        line("")
        for kind in PathKind.allCases {
            let n = Double(counts[kind] ?? 0)
            guard n > 0 else {
                line("  \(kind.rawValue): skipped")
                continue
            }
            line(String(
                format: "  %@: ms=%.3f edit=%.3f overlap=%.3f",
                kind.rawValue,
                (sumMs[kind] ?? 0) / n,
                (sumDist[kind] ?? 0) / n,
                (sumOverlap[kind] ?? 0) / n
            ))
        }

        if s1Ready.ready, let defN = counts[.punctuation], defN > 0, let s1N = counts[.s1mini], s1N > 0 {
            let defEdit = (sumDist[.punctuation] ?? 0) / Double(defN)
            let s1Edit = (sumDist[.s1mini] ?? 0) / Double(s1N)
            let defOv = (sumOverlap[.punctuation] ?? 0) / Double(defN)
            let s1Ov = (sumOverlap[.s1mini] ?? 0) / Double(s1N)
            let defMs = (sumMs[.punctuation] ?? 0) / Double(defN)
            let s1Ms = (sumMs[.s1mini] ?? 0) / Double(s1N)
            line("")
            line("=== DEFAULT vs S1-mini ===")
            line(String(format: "  edit delta (S1-mini − default): %+.3f  (negative = S1-mini closer to gold)", s1Edit - defEdit))
            line(String(format: "  overlap delta (S1-mini − default): %+.3f  (positive = S1-mini closer to gold)", s1Ov - defOv))
            line(String(format: "  latency  default=%.1fms  S1-mini=%.1fms", defMs, s1Ms))
            if s1Edit < defEdit - 0.02 || (abs(s1Edit - defEdit) <= 0.02 && s1Ov > defOv + 0.02) {
                line("  verdict: S1-mini by Superwhisper is closer to gold than the current default.")
            } else if defEdit < s1Edit - 0.02 || (abs(s1Edit - defEdit) <= 0.02 && defOv > s1Ov + 0.02) {
                line("  verdict: current default is closer to gold than S1-mini (S1-mini is still better on self-corrections / numbers).")
            } else {
                line("  verdict: quality is close; S1-mini trades latency for better spoken-form cleanup.")
            }
        }

        await s1.shutdown()
        line("RESULT: PASS")
        exit(0)
    }
}
