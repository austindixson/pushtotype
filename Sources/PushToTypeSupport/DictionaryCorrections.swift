import Foundation

public enum DictationContext: String, Sendable {
    case prose
    case email
    case chat
    case code
    case shell

    public var isCode: Bool {
        switch self {
        case .code, .shell: return true
        case .prose, .email, .chat: return false
        }
    }

    public static func from(bundleID: String?) -> DictationContext {
        let id = (bundleID ?? "").lowercased()
        if id.isEmpty { return .prose }
        if matchesShell(id) { return .shell }
        if matchesChat(id) { return .chat }
        if matchesEmail(id) { return .email }
        if matchesCode(id) { return .code }
        return .prose
    }

    private static func matchesShell(_ id: String) -> Bool {
        let names = ["terminal", "iterm", "kitty", "alacritty", "warp", "ghostty", "wezterm", "cmux", "tabby"]
        if names.contains(where: { id.contains($0) }) { return true }
        return id == "com.apple.terminal"
    }

    private static func matchesChat(_ id: String) -> Bool {
        let names = ["slack", "discord", "telegram", "messages", "whatsapp", "signal", "imessage", "element"]
        return names.contains { id.contains($0) }
    }

    private static func matchesEmail(_ id: String) -> Bool {
        let names = ["mail", "outlook", "spark", "airmail", "mimestream", "superhuman"]
        return names.contains { id.contains($0) }
    }

    private static func matchesCode(_ id: String) -> Bool {
        let names = ["cursor", "code", "xcode", "sublime", "jetbrains", "zed", "nova", "textmate", "vim", "emacs"]
        return names.contains { id.contains($0) }
    }
}

public struct ReplacementPair: Equatable, Sendable {
    public var find: String
    public var replace: String

    public init(find: String, replace: String) {
        self.find = find
        self.replace = replace
    }
}

/// Blocks find→replace pairs that rewrite everyday English.
public enum DictionaryPairPolicy {
    public static let blockedFinds: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "i", "me", "my", "we", "you", "it", "its",
        "to", "of", "for", "in", "on", "at", "as", "or", "and",
        "is", "are", "was", "be", "do", "use", "so", "if",
        "idea", "continue",
    ]

    public static func isBlocked(find: String, replace: String) -> Bool {
        guard let pair = normalized(find, replace) else { return true }
        if blockedFinds.contains(pair.find) { return true }
        if isExpansionLoop(pair) { return true }
        if isTruncation(pair) { return true }
        if dropsPhraseToStopword(pair) { return true }
        return false
    }

    private struct Pair {
        var find: String
        var replace: String
        var findWords: [Substring]
        var replaceWords: [Substring]
        var originalFind: String
        var originalReplace: String
    }

    private static func normalized(_ find: String, _ replace: String) -> Pair? {
        let originalFind = find.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalReplace = replace
        if originalFind.isEmpty { return nil }
        let loweredFind = originalFind.lowercased()
        let loweredReplace = originalReplace.lowercased()
        return Pair(
            find: loweredFind,
            replace: loweredReplace,
            findWords: loweredFind.split(whereSeparator: { $0.isWhitespace }),
            replaceWords: loweredReplace.split(whereSeparator: { $0.isWhitespace }),
            originalFind: originalFind,
            originalReplace: originalReplace
        )
    }

    private static func isExpansionLoop(_ pair: Pair) -> Bool {
        guard pair.replace.hasPrefix(pair.find), pair.replace.count > pair.find.count + 2 else { return false }
        return pair.replace.contains("use this") || pair.replace.contains("i meant") || pair.replace.contains(". ")
    }

    private static func isTruncation(_ pair: Pair) -> Bool {
        // An empty replacement deletes the match. It is not a truncated word.
        guard !pair.replace.isEmpty else { return false }
        guard pair.findWords.count == 1, pair.find.hasPrefix(pair.replace), pair.replace.count < pair.find.count else {
            return false
        }
        let recasedName = pair.originalFind.first != pair.originalReplace.first
        return !recasedName
    }

    private static func dropsPhraseToStopword(_ pair: Pair) -> Bool {
        guard pair.findWords.count >= 2, pair.replaceWords.count == 1 else { return false }
        return blockedFinds.contains(String(pair.replaceWords[0]))
    }
}

public enum DictionaryReplacements {
    /// Trim a replacement the way `DictionaryStore.add` stores it.
    /// Whitespace-only text becomes empty, which deletes the matched word.
    public static func storedReplacement(_ replace: String) -> String {
        replace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func apply(_ text: String, pairs: [ReplacementPair]) -> String {
        var result = text
        let sorted = pairs.sorted { $0.find.count > $1.find.count }
        for pair in sorted {
            result = applyOne(result, pair: pair)
        }
        return result
    }

    private static func applyOne(_ text: String, pair: ReplacementPair) -> String {
        let find = pair.find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty, find != pair.replace else { return text }
        guard !DictionaryPairPolicy.isBlocked(find: find, replace: pair.replace) else { return text }
        let template = NSRegularExpression.escapedTemplate(for: pair.replace)
        return text.replacingOccurrences(of: pattern(for: find), with: template, options: .regularExpression)
    }

    private static func pattern(for find: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: find)
        if find.contains(where: { $0.isWhitespace }) {
            return "(?i)" + escaped
        }
        return "(?i)(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])"
    }
}

public enum DictationCorrections {
    public static func apply(_ text: String, bundleID: String?, pairs: [ReplacementPair]) -> String {
        let reserved = Set(pairs.map { $0.find.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let profile = DictationContext.from(bundleID: bundleID)
        let corrected = DevLexicon.correct(text, profile: profile, reservedFinds: reserved)
        return DictionaryReplacements.apply(corrected, pairs: pairs)
    }
}
