import Foundation

/// Turns rough spoken brainstorming into clear, structured prose for AI tools.
/// Offline path is intentionally aggressive so results *feel* different from Dictate.
enum ArticulateService {

    /// Offline articulation — always runs in Articulate mode.
    static func articulate(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        // 1) Heavy cleanup
        var opts = TranscriptFormatter.Options.default
        opts.smartPunctuation = true
        opts.stripLightFillers = true
        opts.plainShellSafe = false
        s = TranscriptFormatter.format(s, options: opts)
        s = stripHesitationAggressive(s)
        s = expandCasualisms(s)
        s = tightenPhrasing(s)
        s = TranscriptFormatter.format(s, options: opts)

        // 2) Structural rewrite into AI-facing brief when possible
        let structured = structureForAI(s)
        s = structured

        // 3) Final polish
        s = TranscriptFormatter.format(s, options: opts)
        s = ensureStrongClose(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI-oriented structure

    /// Split rambling speech into Goal + Requirements when there are multiple ideas.
    private static func structureForAI(_ input: String) -> String {
        let clauses = splitIntoClauses(input)
        guard !clauses.isEmpty else { return input }

        // Single short thought → one polished sentence
        if clauses.count == 1 || input.count < 90 {
            return polishSingleIntent(clauses.joined(separator: " "))
        }

        // Multi-clause: first = goal, rest = requirements
        let goal = polishSingleIntent(clauses[0])
        let rest = Array(clauses.dropFirst()).map { polishRequirement($0) }.filter { !$0.isEmpty }

        if rest.isEmpty {
            return goal
        }

        var out = goal
        if !goal.hasSuffix(".") && !goal.hasSuffix("!") && !goal.hasSuffix("?") {
            out += "."
        }
        out += "\n\nRequirements:\n"
        for (i, r) in rest.enumerated() {
            var line = r
            if !line.hasSuffix(".") && !line.hasSuffix("!") {
                line += "."
            }
            // Capitalize requirement start
            line = capitalizeFirst(line)
            out += "\(i + 1). \(line)\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitIntoClauses(_ input: String) -> [String] {
        var s = input
        // Normalize list connectors into separators
        let connectors = [
            #"\s+and then\s+"#,
            #"\s+and also\s+"#,
            #"\s+also\s+"#,
            #"\s+plus\s+"#,
            #"\s+as well as\s+"#,
            #"\s+and\s+(?=I |we |it |the |a |an |then |also |need |want |have |add |make |build |fix |ship )"#,
            #"\s*;\s*"#,
            #"\s*\.\s+"#,
            #"\s+,\s+and\s+"#,
        ]
        for pat in connectors {
            if let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: " || ")
            }
        }

        return s
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    private static func polishSingleIntent(_ clause: String) -> String {
        var s = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        s = reframeIntent(s)
        s = capitalizeFirst(s)
        // Ensure ends with sentence punctuation
        if let last = s.last, !".!?".contains(last) {
            s += "."
        }
        return s
    }

    private static func polishRequirement(_ clause: String) -> String {
        var s = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading "I want" / "we need" duplication in bullets
        let leadStrip = [
            #"^(?i)i (?:also )?(?:want|need|would like)(?: to)?\s+"#,
            #"^(?i)we (?:also )?(?:want|need|should|could)\s+"#,
            #"^(?i)and\s+"#,
            #"^(?i)then\s+"#,
            #"^(?i)also\s+"#,
            #"^(?i)please\s+"#,
        ]
        for pat in leadStrip {
            if let re = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        s = reframeIntent(s)
        // Prefer imperative for requirements: "add X" not "I want to add X"
        s = toImperativeIfPossible(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "i want a menu bar app that…" → clearer intent framing
    private static func reframeIntent(_ input: String) -> String {
        var s = input
        let map: [(String, String)] = [
            (#"(?i)^so\s+"#, ""),
            (#"(?i)^well\s+"#, ""),
            (#"(?i)^okay\s+"#, ""),
            (#"(?i)^right\s+"#, ""),
            (#"(?i)^look\s+"#, ""),
            (#"(?i)^i was thinking(?: that)?\s+"#, "I want "),
            (#"(?i)^i was wondering if\s+"#, "Please check whether "),
            (#"(?i)^what if we\s+"#, "We should "),
            (#"(?i)^maybe we (?:could|should|can)\s+"#, "We should "),
            (#"(?i)^it would be (?:cool|nice|great|awesome) if (?:we |you )?"#, "Please "),
            (#"(?i)^can you (?:please )?"#, "Please "),
            (#"(?i)^could you (?:please )?"#, "Please "),
            (#"(?i)^i need you to\s+"#, "Please "),
            (#"(?i)^i need\s+"#, "I need "),
            (#"(?i)^i want to like\s+"#, "I want to "),
            (#"(?i)^i wanna\s+"#, "I want to "),
            (#"(?i)^i'm trying to\s+"#, "I want to "),
            (#"(?i)^i'm looking to\s+"#, "I want to "),
            (#"(?i)^let's\s+"#, "We should "),
            (#"(?i)^we gotta\s+"#, "We need to "),
            (#"(?i)^we need to like\s+"#, "We need to "),
        ]
        for (pat, rep) in map {
            if let re = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: rep)
            }
        }
        return s
    }

    private static func toImperativeIfPossible(_ input: String) -> String {
        var s = input
        // "to add a button" → "Add a button"
        if let re = try? NSRegularExpression(pattern: #"^(?i)to\s+(add|build|create|fix|make|implement|support|enable|ship|paste|dictate)\b"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }
        // "adding a button" → "Add a button"
        if let re = try? NSRegularExpression(pattern: #"^(?i)(adding|building|creating|fixing|making|implementing|supporting|enabling)\s+"#) {
            let range = NSRange(s.startIndex..., in: s)
            if let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: s) {
                let gerund = String(s[r]).lowercased()
                let map = [
                    "adding": "Add", "building": "Build", "creating": "Create",
                    "fixing": "Fix", "making": "Make", "implementing": "Implement",
                    "supporting": "Support", "enabling": "Enable"
                ]
                if let imp = map[gerund] {
                    s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "\(imp) ")
                }
            }
        }
        return s
    }

    private static func capitalizeFirst(_ input: String) -> String {
        guard let first = input.unicodeScalars.first else { return input }
        if CharacterSet.lowercaseLetters.contains(first) {
            return String(input[input.startIndex]).uppercased() + input.dropFirst()
        }
        return input
    }

    private static func ensureStrongClose(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // If still a single paragraph without structure and long enough, keep as-is with period
        if !s.contains("\n"), let last = s.last, !".!?".contains(last), s.count > 20 {
            s += "."
        }
        return s
    }

    // MARK: - Aggressive cleanup

    private static func stripHesitationAggressive(_ input: String) -> String {
        var s = input
        let patterns = [
            #"\b(um|uh|uhh|erm|hmm|ah|oh|oh well|you know|i mean|kind of|kinda|sort of|sorta|right|okay|ok so|so yeah)\b[,.]?"#,
            #"\blike\b"#,  // aggressive for articulate
            #"\bbasically\b"#,
            #"\bliterally\b"#,
            #"\bactually\b"#,
            #"\bhonestly\b"#,
            #"\bjust\b"#,
            #"\breally\b"#,
            #"\bvery\b"#,
            #"\bquite\b"#,
            #"\bsort of like\b"#,
            #"\bkind of like\b"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
            }
        }
        return s
    }

    private static func expandCasualisms(_ input: String) -> String {
        var s = input
        let map: [(String, String)] = [
            (#"\bgonna\b"#, "going to"),
            (#"\bwanna\b"#, "want to"),
            (#"\bgotta\b"#, "need to"),
            (#"\bkinda\b"#, ""),
            (#"\bsorta\b"#, ""),
            (#"\bcuz\b"#, "because"),
            (#"\bcause\b"#, "because"),
            (#"\byeah\b"#, "yes"),
            (#"\byep\b"#, "yes"),
            (#"\bnope\b"#, "no"),
            (#"\bidk\b"#, "I don't know"),
            (#"\btbh\b"#, "to be honest"),
            (#"\bnvm\b"#, "never mind"),
            (#"\bwip\b"#, "work in progress"),
            (#"\brepo\b"#, "repository"),
            (#"\bui\b"#, "UI"),
            (#"\bapi\b"#, "API"),
            (#"\bpr\b"#, "pull request"),
            (#"\bci\b"#, "CI"),
        ]
        for (pat, rep) in map {
            if let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: rep)
            }
        }
        return s
    }

    private static func tightenPhrasing(_ input: String) -> String {
        var s = input
        let reps: [(String, String)] = [
            (#"(?i)\bi want to like\b"#, "I want to"),
            (#"(?i)\bi was thinking(?: that)?\b"#, "I want"),
            (#"(?i)\bwhat if we\b"#, "We should"),
            (#"(?i)\bmaybe we (?:could|should|can)\b"#, "We should"),
            (#"(?i)\bit would be (?:cool|nice|great|awesome) if\b"#, "Please"),
            (#"(?i)\bcan you (?:please )?help me\b"#, "Help me"),
            (#"(?i)\bi need you to\b"#, "Please"),
            (#"(?i)\bso basically\b"#, ""),
            (#"(?i)\bthe thing is\b"#, ""),
            (#"(?i)\bat the end of the day\b"#, ""),
            (#"(?i)\bin order to\b"#, "to"),
            (#"(?i)\ba lot of\b"#, "many"),
            (#"(?i)\bmake sure (?:that )?\b"#, "ensure "),
            (#"(?i)\bi'm trying to\b"#, "I want to"),
            (#"(?i)\bi feel like\b"#, "I think"),
            (#"(?i)\bwe should probably\b"#, "We should"),
            (#"(?i)\bit needs to\b"#, "It must"),
            (#"(?i)\bhas to be able to\b"#, "must"),
            (#"(?i)\bbe able to\b"#, "can"),
        ]
        for (pat, rep) in reps {
            if let re = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: rep)
            }
        }
        return s
    }
}
