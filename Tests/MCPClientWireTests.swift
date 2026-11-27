import Foundation

func runMCPClientWireTests() {
    let initialize = MCPClientWire.initialize(id: 1)
    let params = initialize["params"] as? [String: Any]
    check(initialize["jsonrpc"] as? String == "2.0" && initialize["id"] as? Int == 1 && initialize["method"] as? String == "initialize",
          "initialize is a JSON-RPC request")
    check(params?["protocolVersion"] as? String == MCPProtocol.versions[0], "initialize asks for the newest MCP version")
    check((params?["clientInfo"] as? [String: Any])?["name"] as? String == "Ferry", "clientInfo.name is Ferry")
    check(params?["capabilities"] is [String: Any], "initialize sends capabilities")
    let initialized = MCPClientWire.initialized()
    check(initialized["method"] as? String == "notifications/initialized" && initialized["id"] == nil, "initialized is a notification")
    check(MCPClientWire.toolsList(id: 2)["method"] as? String == "tools/list", "tools/list")
    check((MCPClientWire.toolsList(id: 3, cursor: "abc")["params"] as? [String: Any])?["cursor"] as? String == "abc", "tools/list sends the cursor")
    let call = MCPClientWire.call(id: 4, name: "read", arguments: ["path": "a"])
    let callParams = call["params"] as? [String: Any]
    check(call["method"] as? String == "tools/call" && callParams?["name"] as? String == "read"
          && (callParams?["arguments"] as? [String: Any])?["path"] as? String == "a", "tools/call carries name and arguments")
    check(JSONSerialization.isValidJSONObject(call) && JSONSerialization.isValidJSONObject(initialize), "requests are valid JSON")

    let listed: [String: Any] = ["tools": [
        ["name": "read", "description": "Reads.", "inputSchema": ["type": "object", "properties": ["path": ["type": "string"]]]],
        ["name": "no.schema"],
        ["name": "read"],
        ["description": "no name"],
    ]]
    let tools = MCPClientWire.tools(from: listed, server: "My Server!")
    check(tools.map(\.name) == ["MyServer__read", "MyServer__noschema"], "tools are named <server>__<tool>, cleaned; duplicates skipped")
    check(tools.first?.description == "Reads." && (tools.first?.schema["properties"] as? [String: Any])?["path"] != nil,
          "inputSchema becomes schema")
    check(tools.last?.schema["type"] as? String == "object", "no inputSchema: an empty object schema")
    check(MCPClientWire.named(from: listed, server: "My Server!").last?.tool == "no.schema", "the tool's own name is kept for calls")

    check(MCPClientWire.toolName(server: "My Server!", tool: "read") == "MyServer__read", "server reduced to [A-Za-z0-9_-]")
    check(MCPClientWire.toolName(server: String(repeating: "a", count: 30), tool: "x") == String(repeating: "a", count: 20) + "__x",
          "server cut to 20 characters")
    let long = MCPClientWire.toolName(server: "s", tool: String(repeating: "t", count: 100))
    check(long.count == 64 && long.hasPrefix("s__t"), "a name longer than 64 characters is cut to 64")
    check(MCPClientWire.toolName(server: "a_", tool: "b") == "a__b" && MCPClientWire.split("a__b")! == ("a", "b"),
          "a trailing underscore never moves the split")
    check(MCPClientWire.toolName(server: "!!!", tool: "b") == "mcp__b", "a server name with nothing left is mcp")

    check(MCPClientWire.split("MyServer__read")! == ("MyServer", "read"), "split")
    check(MCPClientWire.split("srv__get__thing")! == ("srv", "get__thing"), "split at the first __")
    check(MCPClientWire.split("read_log") == nil && MCPClientWire.split("__x") == nil && MCPClientWire.split("x__") == nil,
          "names without both parts don't split")

    let out = MCPClientWire.output(from: ["content": [["type": "text", "text": "one"], ["type": "image", "data": "AA"],
                                                      ["type": "text", "text": "two"]], "isError": true])
    check(out.text == "one\ntwo" && out.isError, "output joins the text items and reads isError")
    check(MCPClientWire.output(from: ["content": [["type": "text", "text": "x"]]]).isError == false, "no isError: not an error")
    check(!MCPClientWire.output(from: ["content": [["type": "image", "data": "AA"]]]).text.isEmpty, "no text: says so")

    check(MCPServerConfig.splitArguments(#"-y "@scope/my pkg" 'a b' c  "" d"#) == ["-y", "@scope/my pkg", "a b", "c", "", "d"],
          "arguments split on spaces, quotes respected")
    check(MCPServerConfig.splitArguments("  ") == [], "no arguments")
    check(MCPServerConfig.expandingHome(["-y", "~/Documents", "~", "~bob/x", "a~/b", "--dir=~/x"], home: "/Users/me")
          == ["-y", "/Users/me/Documents", "/Users/me", "~bob/x", "a~/b", "--dir=~/x"], "leading ~ in an argument is the home folder")
    check(MCPServerConfig.joinArguments(["-y", "a b", ""]) == #"-y "a b" """#, "arguments shown on one line, quoted where needed")

    let defaults = UserDefaults(suiteName: "mcp-client-wire-tests")!
    defaults.removePersistentDomain(forName: "mcp-client-wire-tests")
    check(MCPServerConfig.load(defaults) == [], "no servers saved")
    let saved = [MCPServerConfig(id: UUID(), name: "Files", command: "npx", arguments: ["-y", "server"], enabled: true)]
    MCPServerConfig.save(saved, defaults)
    check(MCPServerConfig.load(defaults) == saved && defaults.data(forKey: "assistantMCPServers") != nil, "servers saved as JSON")
    defaults.removePersistentDomain(forName: "mcp-client-wire-tests")

    check(MCPClientWire.serverPart("9lives") == "s9lives" && MCPClientWire.serverPart("-x") == "s-x"
          && MCPClientWire.serverPart("_x") == "_x" && MCPClientWire.serverPart("Files") == "Files", "a server part starts with a letter or _")
    check(MCPClientWire.serverPart(String(repeating: "1", count: 30)).count == 20, "the prefixed part is still cut to 20")
    check(MCPClientWire.toolName(server: "1", tool: "read") == "s1__read", "a digit server name gets a letter in front")
    let scrubbedTools = MCPClientWire.named(from: ["tools": [["name": "read", "description": "Reads /Users/me/notes",
        "inputSchema": ["type": "object", "properties": ["path": ["type": "string", "description": "Under /Users/me", "enum": ["/Users/me/a"]]]]]]],
        server: "s", scrub: { $0.replacingOccurrences(of: "/Users/me", with: "~") })
    let scrubbedProps = scrubbedTools.first?.spec.schema["properties"] as? [String: Any]
    let pathProp = scrubbedProps?["path"] as? [String: Any]
    check(scrubbedTools.first?.spec.description == "Reads ~/notes" && pathProp?["description"] as? String == "Under ~"
          && pathProp?["enum"] as? [String] == ["~/a"] && pathProp?["type"] as? String == "string" && scrubbedTools.first?.tool == "read",
          "descriptions and the schema's strings are scrubbed; keys and the tool's own name aren't")
    check(MCPClientWire.scrubStrings(["a": [1, "x", ["b": "x"]] as [Any]], { $0 + "!" }) as? NSDictionary
          == ["a": [1, "x!", ["b": "x!"]]] as NSDictionary, "scrubStrings reaches nested arrays and objects")
    func specs(_ n: Int, _ s: String) -> [ChatToolSpec] { (0..<n).map { ChatToolSpec(name: "\(s)__t\($0)", description: "", schema: [:]) } }
    let capped = MCPClientWire.capTools([("A", specs(3, "A")), ("B", specs(4, "B")), ("C", specs(2, "C"))], room: 5)
    check(capped.tools.map(\.name) == ["A__t0", "A__t1", "A__t2", "B__t0", "B__t1"], "tools kept in server order up to the room")
    check(capped.notes == ["B: only its first 2 tools are used.", "C: none of its tools are used: the assistant can take only 128 tools."],
          "a server cut short gets a note")
    check(MCPClientWire.capTools([("A", specs(2, "A"))], room: 5).notes.isEmpty, "room enough: no note")
    check(MCPClientWire.maxTools == 128, "128 tools at most")

    let prompt = AssistantPrompts.serverPrompt(chat: UUID(), server: "Files")
    check(prompt.title == "Let the assistant use Files's tools for this chat?" && prompt.allow == "Allow for this chat"
          && prompt.deny == "Not now" && !prompt.always && prompt.key == "mcp Files", "server prompt")
}
