import Foundation

/// Shared guards so LLM “cleanup” never pastes chatty meta-replies.
public enum PolishSanitizer {
    /// Drop model output that looks like a conversation / meta-description instead of cleaned dictation.
    public static func sanitize(output: String, original: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return original }

        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.contains("```") {
            s = s.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lower = s.lowercased()

        let metaPhrases = [
            "grammatically correct", "punctuationally", "filler words",
            "unnecessary punctuation", "free of any imperfections",
            "the text is now", "the text has been", "has been spaced",
            "spaced properly", "meaning and language are clear",
            "no filler", "cleaned up version", "here is the cleaned",
            "i have cleaned", "i've cleaned", "revised version",
            "the corrected text", "as requested", "without changing the meaning",
            "the following text", "output only the", "return only the"
        ]
        let metaHits = metaPhrases.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
        if metaHits >= 2 { return original }
        if lower.hasPrefix("the text is") || lower.hasPrefix("the text has")
            || lower.hasPrefix("your text") || lower.hasPrefix("this text is") {
            return original
        }

        let chattyPrefixes = [
            "sure", "of course", "certainly", "absolutely", "here is", "here's",
            "i think you", "i believe you", "it seems like", "it looks like you",
            "as an ai", "as a language", "happy to help", "let me know",
            "the cleaned", "cleaned version", "corrected version", "i've corrected",
            "i have corrected", "you said", "you meant", "did you mean",
            "i've fixed", "i have fixed", "fixed version"
        ]
        for p in chattyPrefixes {
            if lower.hasPrefix(p) { return original }
        }

        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "are",
            "was", "were", "be", "been", "it", "this", "that", "with", "as", "at",
            "by", "from", "has", "have", "had", "not", "no", "any", "now"
        ]
        func tokens(_ str: String) -> Set<String> {
            str.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stop.contains($0) }
                .reduce(into: Set<String>()) { $0.insert($1) }
        }
        let origTok = tokens(original)
        let outTok = tokens(s)
        if !origTok.isEmpty {
            let overlap = origTok.intersection(outTok).count
            let ratio = Double(overlap) / Double(origTok.count)
            if ratio < 0.25 && origTok.count >= 3 {
                return original
            }
        }

        if s.count > max(100, original.count * 2) {
            return original
        }

        if s.contains("?") && !original.contains("?") && s.count > original.count + 20 {
            let qCount = s.filter { $0 == "?" }.count
            if qCount >= 1 && s.split(separator: " ").count > original.split(separator: " ").count + 8 {
                return original
            }
        }

        return s.isEmpty ? original : s
    }

    /// True if sanitizer would discard `output` in favor of `original`.
    public static func wouldFallback(output: String, original: String) -> Bool {
        sanitize(output: output, original: original) == original
            && output.trimmingCharacters(in: .whitespacesAndNewlines) != original
    }
}
