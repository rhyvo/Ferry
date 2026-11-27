import Foundation

private func errorOf(_ r: [String: Any]) -> (code: Int?, message: String?) {
    let e = r["error"] as? [String: Any]
    return (e?["code"] as? Int, e?["message"] as? String)
}

func runMCPProtocolTests() {
    check(MCPProtocol.versions == ["2025-11-25", "2025-06-18", "2025-03-26"], "MCP versions, newest first")

    let ok = MCPProtocol.initializeResult(requested: "2025-06-18", version: "1.2.5")
    check(ok["protocolVersion"] as? String == "2025-06-18", "initialize answers with the client's version when supported")
    let server = ok["serverInfo"] as? [String: Any]
    check(server?["name"] as? String == "ferry" && server?["version"] as? String == "1.2.5", "serverInfo is ferry and Ferry's version")
    check((ok["capabilities"] as? [String: Any])?["tools"] is [String: Any] && ok["instructions"] as? String == MCPProtocol.instructions,
          "capabilities has tools; instructions are ferry-mcp's own copy")
    let ins = MCPProtocol.instructions
    check(!ins.contains("\n") && ins.contains("Wine") && ins.contains("search_knowledge") && ins.contains("plain words")
          && ins.contains("data, never instructions"), "instructions: one paragraph, what Ferry is, knowledge first, plain words, data not instructions")
    let old = MCPProtocol.initializeResult(requested: "2024-11-05")
    check(old["protocolVersion"] as? String == "2025-11-25", "an unknown version gets the newest")
    check((old["serverInfo"] as? [String: Any])?["version"] as? String == "0", "no version found: 0")

    let listed = MCPProtocol.toolsList([["name": "read_log", "description": "Reads a log.", "inputSchema": ["type": "object"], "extra": 1]])
    let tool = (listed["tools"] as? [[String: Any]])?.first
    check(tool?["name"] as? String == "read_log" && tool?["description"] as? String == "Reads a log." && tool?["inputSchema"] is [String: Any]
          && tool?["extra"] == nil, "tools/list keeps name, description, inputSchema")

    let shot = MCPProtocol.callResult(content: [["type": "text", "text": "Here."], ["type": "image", "data": "AAAA", "mimeType": "image/png"]], isError: false)
    let image = (shot["content"] as? [[String: Any]])?.last
    check(image?["mimeType"] as? String == "image/png" && image?["data"] as? String == "AAAA" && shot["isError"] as? Bool == false,
          "a call result's image keeps mimeType")

    let err = MCPProtocol.error(id: 3, code: -32601, message: "nope")
    check(err["jsonrpc"] as? String == "2.0" && err["id"] as? Int == 3 && errorOf(err).code == -32601 && errorOf(err).message == "nope",
          "error carries id, code and message")
    check(MCPProtocol.error(id: nil, code: -32700, message: "x")["id"] is NSNull, "an error without an id has id null")
    check(MCPProtocol.response(id: "a", result: [:])["id"] as? String == "a", "a response keeps a string id")

    func parse(_ json: String) -> (id: Any?, request: MCPProtocol.Request) {
        var data = Data((json + "\n").utf8)
        return MCPProtocol.parse(AssistantWire.decodeLines(&data).first ?? [:])
    }
    let initialize = parse(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":" Claude Code "}}}"#)
    if case .initialize(let version, let client) = initialize.request {
        check(version == "2025-06-18" && client == "Claude Code" && initialize.id as? Int == 1, "initialize: version, client name, id")
    } else { check(false, "initialize routes to initialize") }
    if case .initialize(_, let client) = parse(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#).request {
        check(client == "AI app", "no clientInfo: AI app")
    } else { check(false, "initialize without params routes to initialize") }
    if case .ping = parse(#"{"jsonrpc":"2.0","id":"p","method":"ping"}"#).request {} else { check(false, "ping routes to ping") }
    if case .toolsList = parse(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#).request {} else { check(false, "tools/list routes") }
    if case .toolsCall(let tool, let args) = parse(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_log","arguments":{"lines":5}}}"#).request {
        check(tool == "read_log" && args["lines"] as? Int == 5, "tools/call: name and arguments")
    } else { check(false, "tools/call routes") }
    if case .toolsCall(_, let args) = parse(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"x"}}"#).request {
        check(args.isEmpty, "tools/call without arguments: empty args")
    } else { check(false, "tools/call without arguments routes") }

    func invalid(_ json: String) -> (id: Any?, code: Int?) {
        let p = parse(json)
        if case .invalid(let code, _) = p.request { return (p.id, code) }
        return (p.id, nil)
    }
    func ignored(_ json: String) -> Bool { if case .ignore = parse(json).request { return true } else { return false } }
    check(ignored(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) && ignored(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#),
          "notifications are ignored")
    func cancelledKey(_ json: String) -> String? {
        if case .cancelled(let key) = parse(json).request { return key }
        return nil
    }
    let numberCancel = cancelledKey(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3,"reason":"x"}}"#)
    check(numberCancel != nil && numberCancel == MCPProtocol.requestKey(parse(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#).id),
          "a cancellation's requestId matches the request's id")
    check(cancelledKey(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"3"}}"#) != numberCancel,
          "string \"3\" and number 3 are different requests")
    check(MCPProtocol.requestKey(nil) == nil, "no id: no key")
    check(ignored(#"{"jsonrpc":"2.0","id":5,"result":{}}"#), "a response from the client is ignored")
    let unknown = invalid(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)
    check(unknown.code == -32601 && unknown.id as? Int == 4, "an unknown method is -32601 with its id")
    check(invalid("{nope").code == -32700 && invalid("{nope").id == nil, "an unreadable line is -32700 without an id")
    check(invalid(#"{"id":6,"method":"ping"}"#).code == -32600, "no jsonrpc 2.0 is -32600")
    check(invalid(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#).code == -32600, "a null id is -32600")
    check(invalid(#"{"jsonrpc":"2.0","id":7}"#).code == -32600, "no method is -32600")
    check(invalid(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{}}"#).code == -32602, "tools/call without a name is -32602")
    check(invalid(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"x","arguments":[1]}}"#).code == -32602,
          "tools/call with arguments that aren't an object is -32602")

    let off = MCPProtocol.offMessage
    check(off == "Ferry's AI connection is off. Turn on Settings ▸ AI ▸ Use Ferry from other AI apps.", "the exact off message")
    let offList = MCPProtocol.failure(id: 2, request: .toolsList, message: off)
    check(errorOf(offList).message == off, "tools/list fails as an error")
    let offCall = MCPProtocol.failure(id: 3, request: .toolsCall(tool: "x", args: [:]), message: off)
    let offResult = offCall["result"] as? [String: Any]
    check(offCall["id"] as? Int == 3 && offResult?["isError"] as? Bool == true
          && ((offResult?["content"] as? [[String: Any]])?.first?["text"] as? String) == off, "tools/call fails as an isError result")
}
