import Foundation

enum AssistantSetup {
    static let command = "/Applications/Ferry.app/Contents/MacOS/ferry-mcp"

    static func isAdded(_ data: Data?) -> Bool {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ferry = (root["mcpServers"] as? [String: Any])?["ferry"] as? [String: Any] else { return false }
        return ferry["command"] as? String == command
    }

    static func adding(to data: Data?, file: String) throws -> Data {
        var root: [String: Any] = [:]
        if let data, !data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) {
            guard let r = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw FerryError("\(file) isn't a settings file Ferry can read, so it was left as it is.")
            }
            root = r
        }
        guard root["mcpServers"] == nil || root["mcpServers"] is [String: Any] else {
            throw FerryError("\(file) has its AI tools (mcpServers) in a form Ferry doesn't know, so it was left as it is.")
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["ferry"] = ["command": command, "args": [String]()]
        root["mcpServers"] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
    }
}
