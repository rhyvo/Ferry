import Foundation

func runAssistantSetupTests() {
    let existing = Data(#"{"numStartups":42,"mcpServers":{"blender":{"command":"uvx","args":["blender-mcp"]}},"projects":{"/x":{"a":true}}}"#.utf8)
    let added = try? AssistantSetup.adding(to: existing, file: "f")
    let root = added.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let servers = root?["mcpServers"] as? [String: Any]
    check(servers?["blender"] != nil && root?["numStartups"] as? Int == 42 && root?["projects"] != nil, "everything else is kept")
    check(AssistantSetup.isAdded(added) && !AssistantSetup.isAdded(existing), "Ferry added, and seen as added")
    check(AssistantSetup.isAdded(try? AssistantSetup.adding(to: nil, file: "f")), "no file: a new one")
    check(AssistantSetup.isAdded(try? AssistantSetup.adding(to: Data(" \n".utf8), file: "f")), "an empty file: a new one")
    check((try? AssistantSetup.adding(to: Data("{oops".utf8), file: "f")) == nil, "unreadable file left alone")
    check((try? AssistantSetup.adding(to: Data(#"{"mcpServers":[1]}"#.utf8), file: "f")) == nil, "unknown mcpServers left alone")
    check(!AssistantSetup.isAdded(Data(#"{"mcpServers":{"ferry":{"command":"/elsewhere/ferry-mcp"}}}"#.utf8)), "another ferry-mcp isn't this one")
}
