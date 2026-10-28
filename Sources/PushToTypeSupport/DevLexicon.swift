import Foundation
import os.log

/// Developer vocabulary for dictation.
///
/// `DevLexicon.tsv` is the full list. Apple documents a cap of 100 phrases on
/// `SFSpeechRecognitionRequest.contextualStrings`, so hints stay inside that cap.
/// Corrections use every spoken variant.
public enum DevLexicon {
    public static let contextualStringLimit = 100

    public struct Entry: Equatable, Sendable {
        public var term: String
        public var spoken: [String]
        public var category: String
        /// Spoken variants apply only in code and shell. Example: jason → JSON.
        public var codeOnly: Bool
    }

    public static var entries: [Entry] { cache.entries }
    public static var termCount: Int { cache.entries.count }
    public static var correctionCount: Int { cache.rules.count }

    public static var categories: Set<String> {
        Set(cache.entries.map(\.category))
    }

    public static func contextualStrings(limit: Int = contextualStringLimit) -> [String] {
        prioritize(entries: cache.entries, limit: max(0, limit))
    }

    /// Whole-word fixes. Longer spoken phrases win. Code-only rows stay put in prose.
    /// `reservedFinds` are user-dictionary phrases, and those rules are skipped.
    public static func correct(
        _ text: String,
        profile: DictationContext,
        reservedFinds: Set<String> = []
    ) -> String {
        let reserved = Set(reservedFinds.map { $0.lowercased() })
        var result = text
        for rule in cache.rules where rule.applies(inCodeContext: profile.isCode) {
            if reserved.contains(rule.spoken.lowercased()) { continue }
            result = rule.apply(to: result)
        }
        return result
    }

    static func entries(parsing text: String) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { parseRow(String($0)) }
    }

    private struct Cache {
        var entries: [Entry]
        var rules: [Rule]
    }

    private struct Rule {
        var spoken: String
        var codeOnly: Bool
        var expression: NSRegularExpression
        var template: String

        func applies(inCodeContext code: Bool) -> Bool {
            !codeOnly || code
        }

        func apply(to text: String) -> String {
            let range = NSRange(text.startIndex..., in: text)
            return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        }
    }

    private static let logger = Logger(subsystem: "dev.pushtotype.app", category: "DevLexicon")
    private static let cache = load()

    private static func load() -> Cache {
        let text = readResource()
        if text.isEmpty {
            logger.error("Developer lexicon is empty")
        }
        var entries: [Entry] = []
        var rules: [Rule] = []
        var seenSpoken = Set<String>()
        for entry in Self.entries(parsing: text) {
            entries.append(entry)
            appendRules(for: entry, into: &rules, seen: &seenSpoken)
        }
        rules.sort { lhs, rhs in
            if lhs.spoken.count != rhs.spoken.count { return lhs.spoken.count > rhs.spoken.count }
            return lhs.spoken > rhs.spoken
        }
        return Cache(entries: entries, rules: rules)
    }

    private static func appendRules(for entry: Entry, into rules: inout [Rule], seen: inout Set<String>) {
        for spoken in entry.spoken {
            let key = spoken.lowercased()
            guard spoken != entry.term else { continue }
            guard seen.insert(key).inserted else { continue }
            if let rule = makeRule(spoken: spoken, term: entry.term, codeOnly: entry.codeOnly) {
                rules.append(rule)
            }
        }
    }

    private static func parseRow(_ line: String) -> Entry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 4 else { return nil }
        let term = parts[0]
        let category = parts[2]
        guard !term.isEmpty, !category.isEmpty, term != "term" else { return nil }
        let spoken = parts[1]
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Entry(
            term: term,
            spoken: spoken.map { String($0) },
            category: category,
            codeOnly: parts[3].lowercased() == "code"
        )
    }

    private static func makeRule(spoken: String, term: String, codeOnly: Bool) -> Rule? {
        let escaped = NSRegularExpression.escapedPattern(for: spoken)
        let pattern = "(?i)(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Rule(
            spoken: spoken,
            codeOnly: codeOnly,
            expression: expression,
            template: replacementTemplate(term)
        )
    }

    private static func replacementTemplate(_ term: String) -> String {
        term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    private static func readResource() -> String {
        let urls = resourceURLs()
        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("\t") {
                return text
            }
        }
        return ""
    }

    private static func resourceURLs() -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.module.url(forResource: "DevLexicon", withExtension: "tsv") {
            urls.append(url)
        }
        if let url = Bundle.main.url(forResource: "DevLexicon", withExtension: "tsv") {
            urls.append(url)
        }
        urls.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("DevLexicon.tsv")
        )
        return urls
    }

    private static let categoryQuota: [(name: String, quota: Int)] = [
        ("hosting", 32),
        ("ai", 12),
        ("framework", 12),
        ("language", 8),
        ("cli", 10),
        ("format", 6),
        ("database", 6),
        ("git", 4),
        ("casing", 5),
        ("env", 5),
    ]

    private static func prioritize(entries: [Entry], limit: Int) -> [String] {
        let grouped = groupEligible(entries)
        var picker = Picker(limit: limit)
        picker.takeQuotas(grouped, quotas: categoryQuota)
        picker.fillRemainder(grouped, order: categoryQuota.map(\.name))
        return picker.result
    }

    private static func groupEligible(_ entries: [Entry]) -> [String: [String]] {
        var grouped: [String: [String]] = [:]
        for entry in entries where phraseWordCount(entry.term) <= 2 {
            grouped[entry.category, default: []].append(entry.term)
        }
        return grouped
    }

    private static func phraseWordCount(_ term: String) -> Int {
        term.split(whereSeparator: { $0.isWhitespace }).count
    }

    private struct Picker {
        var limit: Int
        var result: [String] = []
        var seen = Set<String>()
        var cursors: [String: Int] = [:]

        mutating func takeQuotas(_ grouped: [String: [String]], quotas: [(name: String, quota: Int)]) {
            for item in quotas {
                take(item.quota, from: grouped[item.name] ?? [], category: item.name)
            }
        }

        mutating func fillRemainder(_ grouped: [String: [String]], order: [String]) {
            var progressed = true
            while result.count < limit, progressed {
                progressed = false
                for name in order {
                    if appendNext(grouped[name] ?? [], category: name) {
                        progressed = true
                    }
                    if result.count >= limit { return }
                }
            }
        }

        mutating func take(_ quota: Int, from list: [String], category: String) {
            var taken = 0
            var index = cursors[category] ?? 0
            while taken < quota, index < list.count, result.count < limit {
                if insert(list[index]) { taken += 1 }
                index += 1
            }
            cursors[category] = index
        }

        mutating func appendNext(_ list: [String], category: String) -> Bool {
            var index = cursors[category] ?? 0
            while index < list.count {
                let term = list[index]
                index += 1
                cursors[category] = index
                if insert(term) { return true }
            }
            cursors[category] = index
            return false
        }

        mutating func insert(_ term: String) -> Bool {
            let key = term.lowercased()
            guard result.count < limit, seen.insert(key).inserted else { return false }
            result.append(term)
            return true
        }
    }
}
