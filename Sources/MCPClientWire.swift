import Foundation

struct MCPServerConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var command: String
    var arguments: [String]
    var enabled: Bool

    static let defaultsKey = "assistantMCPServers"

    static func load(_ defaults: UserDefaults) -> [MCPServerConfig] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([MCPServerConfig].self, from: data)) ?? []
    }

    static func save(_ servers: [MCPServerConfig], _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(servers) { defaults.set(data, forKey: defaultsKey) }
    }

    static func splitArguments(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inWord = false
        var quote: Character? = nil
        for c in line {
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
                inWord = true
            } else if c == " " || c == "\t" {
                if inWord { out.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(c)
                inWord = true
            }
        }
        if inWord { out.append(current) }
        return out
    }

    static func expandingHome(_ args: [String], home: String) -> [String] {
        args.map { a in
            if a == "~" { return home }
            if a.hasPrefix("~/") { return home + a.dropFirst() }
            return a
        }
    }

    static func joinArguments(_ args: [String]) -> String {
        args.map { a in
            if !a.isEmpty, !a.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" || $0 == "'" }) { return a }
            return a.contains("\"") ? "'\(a)'" : "\"\(a)\""
        }.joined(separator: " ")
    }
}

enum MCPClientWire {
    static func initialize(id: Int) -> [String: Any] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return request(id: id, method: "initialize", params: [
            "protocolVersion": MCPProtocol.versions[0],
            "capabilities": [String: Any](),
            "clientInfo": ["name": "Ferry", "version": version],
        ])
    }

    static func initialized() -> [String: Any] {
        ["jsonrpc": "2.0", "method": "notifications/initialized"]
    }

    static func toolsList(id: Int, cursor: String? = nil) -> [String: Any] {
        request(id: id, method: "tools/list", params: cursor.map { ["cursor": $0] } ?? [:])
    }

    static func call(id: Int, name: String, arguments: [String: Any]) -> [String: Any] {
        request(id: id, method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    private static func request(id: Int, method: String, params: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    static func tools(from result: [String: Any], server: String) -> [ChatToolSpec] {
        named(from: result, server: server).map(\.spec)
    }

    static func named(from result: [String: Any], server: String,
                      scrub: (String) -> String = { $0 }) -> [(spec: ChatToolSpec, tool: String)] {
        var seen: Set<String> = []
        var out: [(spec: ChatToolSpec, tool: String)] = []
        for t in result["tools"] as? [[String: Any]] ?? [] {
            guard let tool = t["name"] as? String else { continue }
            let name = toolName(server: server, tool: tool)
            guard split(name) != nil, seen.insert(name).inserted else { continue }
            let schema = t["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [String: Any]()]
            out.append((ChatToolSpec(name: name, description: scrub(t["description"] as? String ?? ""),
                                     schema: scrubStrings(schema, scrub) as? [String: Any] ?? schema), tool))
        }
        return out
    }

    static func scrubStrings(_ value: Any, _ f: (String) -> String) -> Any {
        if let s = value as? String { return f(s) }
        if let d = value as? [String: Any] { return d.mapValues { scrubStrings($0, f) } }
        if let a = value as? [Any] { return a.map { scrubStrings($0, f) } }
        return value
    }

    static let maxTools = 128

    static func capTools(_ servers: [(server: String, tools: [ChatToolSpec])], room: Int) -> (tools: [ChatToolSpec], notes: [String]) {
        var left = max(0, room)
        var tools: [ChatToolSpec] = []
        var notes: [String] = []
        for (server, list) in servers {
            let kept = list.prefix(left)
            tools += kept
            left -= kept.count
            if kept.count < list.count {
                notes.append(kept.isEmpty ? "\(server): none of its tools are used: the assistant can take only \(maxTools) tools."
                             : "\(server): only its first \(kept.count) tools are used.")
            }
        }
        return (tools, notes)
    }

    static func output(from result: [String: Any]) -> (text: String, isError: Bool) {
        let items = result["content"] as? [[String: Any]] ?? []
        let texts = items.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        let text = texts.isEmpty ? "The tool sent back no text." : texts.joined(separator: "\n")
        return (text, result["isError"] as? Bool ?? false)
    }

    static func toolName(server: String, tool: String) -> String {
        String((serverPart(server) + "__" + clean(tool)).prefix(64))
    }

    static func serverPart(_ server: String) -> String {
        var s = clean(server)
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        if let first = s.unicodeScalars.first, first != "_", !CharacterSet.letters.contains(first) { s = "s" + s }
        s = String(s.prefix(20))
        while s.hasSuffix("_") { s.removeLast() }
        return s.isEmpty ? "mcp" : s
    }

    static func split(_ name: String) -> (server: String, tool: String)? {
        guard let r = name.range(of: "__") else { return nil }
        let server = String(name[..<r.lowerBound]), tool = String(name[r.upperBound...])
        return server.isEmpty || tool.isEmpty ? nil : (server, tool)
    }

    private static func clean(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }.map(Character.init))
    }
}
