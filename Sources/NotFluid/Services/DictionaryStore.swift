import Foundation

/// User find→replace dictionary applied after STT.
@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NotFluid", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
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
        entries.append(DictionaryEntry(find: f, replace: r))
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func apply(_ text: String) -> String {
        var result = text
        // Longer finds first so "hello world" wins over "hello"
        let sorted = entries.sorted { $0.find.count > $1.find.count }
        for e in sorted {
            guard !e.find.isEmpty else { continue }
            result = result.replacingOccurrences(
                of: e.find,
                with: e.replace,
                options: [.caseInsensitive]
            )
        }
        return result
    }
}
