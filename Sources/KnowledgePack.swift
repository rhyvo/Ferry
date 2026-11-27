import Foundation

struct KnowledgeDoc {
    let id: String
    let title: String
    let tags: [String]
    let body: String
}

struct KnowledgePack {
    struct Invalid: Error { let why: String }

    private let docs: [KnowledgeDoc]

    init(docs: [KnowledgeDoc]) { self.docs = docs }

    init(folder: URL) throws {
        let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = root["files"] as? [String] else { throw Invalid(why: "manifest.json has no files list") }
        docs = try files.map { path in
            let text = try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
            return Self.parse(text, id: path.hasSuffix(".md") ? String(path.dropLast(3)) : path)
        }
    }

    func adding(_ more: [KnowledgeDoc]) -> KnowledgePack { KnowledgePack(docs: docs + more) }

    func doc(_ id: String) -> KnowledgeDoc? { docs.first { $0.id == id } }

    private static let stopWords: Set<String> = ["a", "an", "the", "of", "and", "or", "to", "in", "on", "at", "is", "it", "my", "i", "for",
                                                 "with", "this", "that", "are", "was", "be", "do", "does", "how", "why", "what", "when", "me", "but"]

    private static func words(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { !stopWords.contains($0) && seen.insert($0).inserted }
    }

    func search(_ query: String, limit: Int) -> [KnowledgeDoc] {
        let ws = Self.words(query)
        guard !ws.isEmpty else { return [] }
        let scored: [(doc: KnowledgeDoc, score: Int)] = docs.map { d in
            let title = d.title.lowercased(), tags = d.tags.map { $0.lowercased() }, body = d.body.lowercased()
            let score = ws.reduce(0) { sum, w in
                sum + (title.contains(w) ? 3 : 0) + (tags.contains { $0.contains(w) } ? 2 : 0) + (body.contains(w) ? 1 : 0)
            }
            return (d, score)
        }
        return scored.filter { $0.score > 0 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.doc.id < $1.doc.id }
            .prefix(limit).map(\.doc)
    }

    private static func parse(_ text: String, id: String) -> KnowledgeDoc {
        var title = id, tags: [String] = [], body = text
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if key == "title" { title = value }
                else if key == "tags" { tags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            }
            body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return KnowledgeDoc(id: id, title: title, tags: tags, body: body)
    }

    static func generated(settings: [SettingEntry], symptoms: [(title: String, guide: String)]) -> [KnowledgeDoc] {
        func fill(_ t: String) -> String {
            t.replacingOccurrences(of: "{noun}", with: "game")
                .replacingOccurrences(of: "{hz}", with: "the display's")
                .replacingOccurrences(of: "{dxvkVersion}", with: "3.x")
                .replacingOccurrences(of: "{dxmtVersion}", with: "")
                .replacingOccurrences(of: "{owner}", with: "the program it shares an environment with")
        }
        var out = settings.map { e -> KnowledgeDoc in
            var body = fill(e.info) + "\n\nWhere: \(e.section) in the game's settings."
            if !e.needsTexts.isEmpty { body += "\n\nWhen it's greyed out: " + e.needsTexts.map(fill).joined(separator: " ") }
            return KnowledgeDoc(id: "settings/" + e.key, title: fill(e.title), tags: ["setting", e.key], body: body)
        }
        out += symptoms.map { s in
            let slug = s.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            return KnowledgeDoc(id: "troubleshoot/" + slug, title: s.title, tags: ["troubleshoot", "symptom"], body: s.guide)
        }
        return out
    }
}
