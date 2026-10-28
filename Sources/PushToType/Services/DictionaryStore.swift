import Foundation
import PushToTypeSupport

/// User find→replace dictionary applied after STT.
@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry] = []

    private var fileURL: URL {
        AppSupport.directory().appendingPathComponent("dictionary.json")
    }

    private init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(find: String, replace: String) {
        let f = find.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replace
        guard !f.isEmpty else { return }
        guard !DictionaryPairPolicy.isBlocked(find: f, replace: r) else { return }
        if let idx = entries.firstIndex(where: { $0.find.caseInsensitiveCompare(f) == .orderedSame }) {
            entries[idx].replace = r
        } else {
            entries.append(DictionaryEntry(find: f, replace: r))
        }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func apply(_ text: String, bundleID: String? = nil) -> String {
        let pairs = entries.map { ReplacementPair(find: $0.find, replace: $0.replace) }
        return DictationCorrections.apply(text, bundleID: bundleID, pairs: pairs)
    }
}
