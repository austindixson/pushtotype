import Foundation

/// Rule-based cleanup for dictation: spacing, punctuation, capitalization.
/// Runs instantly after STT (before optional LLM polish).
public enum TranscriptFormatter {

    public struct Options: Sendable {
        /// Fix spaces, punctuation glue, capitalization.
        public var smartPunctuation: Bool = true
        /// Collapse "um" / "uh" / "like" filler (light; not aggressive).
        public var stripLightFillers: Bool = false
        /// Terminal / code: skip sentence capitalization and curly quotes.
        public var plainShellSafe: Bool = false

        public static let `default` = Options()
        public static let terminal = Options(smartPunctuation: true, stripLightFillers: false, plainShellSafe: true)
    }

    /// App-aware options from frontmost bundle id.
    public static func options(
        forBundleID bundleID: String?,
        smartPunctuation: Bool,
        stripFillers: Bool
    ) -> Options {
        let id = (bundleID ?? "").lowercased()
        let terminal =
            id.contains("terminal") || id.contains("iterm") || id.contains("kitty")
            || id.contains("alacritty") || id.contains("warp") || id.contains("ghostty")
            || id.contains("wezterm") || id == "com.apple.terminal"
        var opts = terminal ? Options.terminal : Options.default
        opts.smartPunctuation = smartPunctuation
        opts.stripLightFillers = stripFillers && !terminal
        return opts
    }

    public static func format(_ raw: String, options: Options = .default) -> String {
        var s = raw
        if s.isEmpty { return s }

        // Normalize newlines / weird unicode spaces
        s = s
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ") // nbsp
            .replacingOccurrences(of: "\u{200B}", with: "")  // zero-width
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        // Spoken punctuation → symbols (common dictation phrases)
        if options.smartPunctuation {
            s = applySpokenPunctuation(s)
        }

        if options.stripLightFillers {
            s = stripFillers(s)
        }

        // Whitespace cleanup
        s = collapseWhitespace(s)

        if options.smartPunctuation {
            s = fixPunctuationSpacing(s)
            if !options.plainShellSafe {
                s = capitalizeSentences(s)
                s = ensureTerminalPunctuation(s)
            } else {
                // Still capitalize first letter of the whole string lightly
                s = capitalizeFirst(s)
            }
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Spoken punctuation

    /// "period" "comma" "question mark" etc. when spoken as words.
    private static func applySpokenPunctuation(_ input: String) -> String {
        var s = input
        // Order matters: longer phrases first
        let replacements: [(String, String)] = [
            (#"(?i)\s+question\s+mark\b"#, "?"),
            (#"(?i)\s+exclamation\s+(?:point|mark)\b"#, "!"),
            (#"(?i)\s+new\s+paragraph\b"#, "\n\n"),
            (#"(?i)\s+new\s+line\b"#, "\n"),
            (#"(?i)\s+period\b"#, "."),
            (#"(?i)\s+full\s+stop\b"#, "."),
            (#"(?i)\s+comma\b"#, ","),
            (#"(?i)\s+colon\b"#, ":"),
            (#"(?i)\s+semicolon\b"#, ";"),
            (#"(?i)\s+ellipsis\b"#, "..."),
            (#"(?i)\s+dot\s+dot\s+dot\b"#, "..."),
            (#"(?i)\s+dash\b"#, " — "),
            (#"(?i)\s+hyphen\b"#, "-"),
            (#"(?i)\s+open\s+quote\b"#, " \""),
            (#"(?i)\s+close\s+quote\b"#, "\""),
            (#"(?i)\s+apostrophe\b"#, "'"),
        ]
        for (pattern, replacement) in replacements {
            if let re = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: replacement)
            }
        }
        return s
    }

    // MARK: - Fillers (optional)

    private static func stripFillers(_ input: String) -> String {
        let pattern = #"(?i)\b(um|uh|erm|hmm|ah|like|you know)\b[,.]?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        var s = re.stringByReplacingMatches(in: input, range: range, withTemplate: " ")
        s = collapseWhitespace(s)
        return s
    }

    // MARK: - Spacing

    private static func collapseWhitespace(_ input: String) -> String {
        var s = input
        // Tabs → space
        s = s.replacingOccurrences(of: "\t", with: " ")
        // Multiple spaces → one (preserve newlines)
        if let re = try? NSRegularExpression(pattern: #"[^\S\n]+"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
        }
        // Space around newlines
        if let re = try? NSRegularExpression(pattern: #"[ \t]*\n[ \t]*"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "\n")
        }
        // Max 2 consecutive newlines
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixPunctuationSpacing(_ input: String) -> String {
        var s = input

        // No space BEFORE punctuation: "hello ," → "hello,"
        if let re = try? NSRegularExpression(pattern: #"\s+([,.;:!?…])"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }

        // Space AFTER punctuation when followed by a letter/number: "Hi.There" → "Hi. There"
        // Don't break decimals like 3.14 or times 10:30 or emails / paths
        if let re = try? NSRegularExpression(pattern: #"([.!?…])([A-Za-z])"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1 $2")
        }
        if let re = try? NSRegularExpression(pattern: #"([,;:])([A-Za-z0-9])"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1 $2")
        }

        // Fix "word ." leftovers again after spoken punctuation
        if let re = try? NSRegularExpression(pattern: #"\s+([,.;:!?])"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }

        // " ," style
        s = s.replacingOccurrences(of: " ,", with: ",")
        s = s.replacingOccurrences(of: " .", with: ".")
        s = s.replacingOccurrences(of: " ?", with: "?")
        s = s.replacingOccurrences(of: " !", with: "!")
        s = s.replacingOccurrences(of: " ;", with: ";")
        s = s.replacingOccurrences(of: " :", with: ":")

        // Multiple punctuation: "??" ok, ".." → "..." if exactly 2
        if let re = try? NSRegularExpression(pattern: #"\.{2}"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "...")
        }
        // "....." → "..."
        if let re = try? NSRegularExpression(pattern: #"\.{4,}"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "...")
        }

        // Opening paren/bracket spacing: "foo(" ok; ")foo" → ") foo" lightly
        if let re = try? NSRegularExpression(pattern: #"([)\]}])([A-Za-z])"#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1 $2")
        }

        // Quotes: ` "word" ` cleanup
        if let re = try? NSRegularExpression(pattern: #""\s+([^"]+?)\s+""#) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "\"$1\"")
        }

        // Collapse spaces again
        s = collapseWhitespace(s)
        return s
    }

    // MARK: - Capitalization

    private static func capitalizeFirst(_ input: String) -> String {
        guard let first = input.unicodeScalars.first else { return input }
        if CharacterSet.lowercaseLetters.contains(first) {
            let c = String(input[input.startIndex]).uppercased()
            return c + input.dropFirst()
        }
        return input
    }

    private static func capitalizeSentences(_ input: String) -> String {
        // Split on sentence-ending punctuation + whitespace
        var result = ""
        var capitalizeNext = true
        var i = input.startIndex

        while i < input.endIndex {
            let ch = input[i]
            if capitalizeNext, ch.isLetter {
                result.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
                if ch == "." || ch == "!" || ch == "?" || ch == "…" {
                    capitalizeNext = true
                } else if ch == "\n" {
                    capitalizeNext = true
                } else if !ch.isWhitespace && ch != "\"" && ch != "'" && ch != "(" {
                    // keep capitalizeNext if we only saw spaces after sentence end
                }
            }
            i = input.index(after: i)
        }

        // Fix common "i " → "I " (English pronoun)
        if let re = try? NSRegularExpression(pattern: #"\bi\b"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "I")
        }
        // "I'm" "I've" etc. already covered by capital I alone when isolated

        return result
    }

    /// If the text looks like a sentence and has no ending punctuation, add a period.
    private static func ensureTerminalPunctuation(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return input } // short phrases stay as-is
        guard let last = trimmed.last else { return input }

        // Already ends with punctuation or looks like a path/command/url
        if ".!?…\"')".contains(last) { return input }
        if trimmed.contains("://") || trimmed.hasPrefix("/") || trimmed.hasPrefix("~") { return input }
        if trimmed.split(separator: " ").count < 4 { return input } // short = maybe title or command

        // Looks like prose (has letters and spaces)
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters > 8 else { return input }

        return input + "."
    }
}
