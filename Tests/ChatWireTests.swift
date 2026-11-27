import Foundation

func runChatWireTests() {
    let tools = [ChatToolSpec(name: "game_details", description: "d", schema: ["type": "object", "properties": [:], "required": []])]
    let claude = ClaudeWire(), oai = OpenAIWire()
    let creq = try! claude.request(base: URL(string: "https://api.anthropic.com/v1")!, key: " sk-ant \n", model: "claude-opus-5-5", system: "sys", tools: tools, messages: [claude.userMessage("hi")])
    check(creq.url?.absoluteString == "https://api.anthropic.com/v1/messages", "Claude URL")
    check(creq.value(forHTTPHeaderField: "x-api-key") == "sk-ant" && creq.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21", "Claude headers, key trimmed")
    let cbody = try! JSONSerialization.jsonObject(with: creq.httpBody!) as! [String: Any]
    check(cbody["max_tokens"] as? Int == 16000 && (cbody["thinking"] as? [String: String])?["type"] == "adaptive", "Claude limits and thinking")
    check(cbody["temperature"] == nil && cbody["top_p"] == nil && cbody["top_k"] == nil, "no sampling fields")
    check(((cbody["tools"] as? [[String: Any]])?.first?["input_schema"]) != nil, "Claude tool schema key")

    let ctool = Data(#"{"content":[{"type":"thinking","thinking":"x","signature":"s"},{"type":"text","text":"Looking."},{"type":"tool_use","id":"toolu_1","name":"read_log","input":{"game":"MW2"}}],"stop_reason":"tool_use"}"#.utf8)
    let cr = try! claude.parse(ctool)
    check(cr.stop == .toolCalls && cr.text == "Looking." && cr.toolCalls.first?.name == "read_log" && cr.toolCalls.first?.arguments?["game"] as? String == "MW2", "Claude tool call")
    check((cr.rawAssistant["content"] as? [[String: Any]])?.count == 3 && cr.rawAssistant["role"] as? String == "assistant", "raw assistant kept whole, thinking included")
    let cres = claude.toolResultMessages([ChatToolOutput(callID: "toolu_1", text: "log", isError: true, png: nil)])
    check(cres.count == 1 && cres[0]["role"] as? String == "user", "Claude results are one user message")
    check(((cres[0]["content"] as? [[String: Any]])?.first?["is_error"]) as? Bool == true, "Claude error result")
    let cpng = claude.toolResultMessages([ChatToolOutput(callID: "t", text: "shot", isError: false, png: Data([1, 2]))])
    let cpngInner = ((cpng[0]["content"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]]
    check(cpngInner?.contains { $0["type"] as? String == "image" && ($0["source"] as? [String: Any])?["media_type"] as? String == "image/png" } == true, "Claude picture goes in as an image block")
    check(try! claude.parse(Data(#"{"content":[{"type":"text","text":"a"}],"stop_reason":"max_tokens"}"#.utf8)).stop == .tooLong, "max_tokens is tooLong")
    check(try! claude.parse(Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)).stop == .refused, "refusal is refused")
    check(try! claude.parse(Data(#"{"content":[{"type":"text","text":"a"}],"stop_reason":"end_turn"}"#.utf8)).stop == .done, "end_turn is done")

    let oreq = try! oai.request(base: URL(string: "http://localhost:11434/v1")!, key: "", model: "llama", system: "sys", tools: tools, messages: [oai.userMessage("hi")])
    check(oreq.url?.absoluteString == "http://localhost:11434/v1/chat/completions" && oreq.value(forHTTPHeaderField: "Authorization") == nil, "no key, no Authorization")
    let obody = try! JSONSerialization.jsonObject(with: oreq.httpBody!) as! [String: Any]
    check((obody["messages"] as? [[String: Any]])?.first?["role"] as? String == "system", "system message first")
    check(((obody["tools"] as? [[String: Any]])?.first?["type"]) as? String == "function", "function tools")
    check((try? oai.request(base: URL(string: "http://example.com/v1")!, key: "k", model: "m", system: "", tools: [], messages: [])) == nil, "plain http refused off this Mac")
    let okey = try! oai.request(base: URL(string: "https://api.openai.com/v1")!, key: " k \n", model: "m", system: "", tools: [], messages: [])
    check(okey.value(forHTTPHeaderField: "Authorization") == "Bearer k", "Bearer key, trimmed")
    check(ChatBase.isAllowed(URL(string: "http://[::1]:8080/v1")!) && ChatBase.isAllowed(URL(string: "http://127.0.0.1/v1")!) && !ChatBase.isAllowed(URL(string: "ftp://localhost")!), "local http and ::1 allowed")

    let otool = Data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"read_log","arguments":"{\"game\":\"MW2\"}"}},{"id":"c2","type":"function","function":{"name":"x","arguments":"not json"}}],"extra_content":{"google":{"thought_signature":"t"}}},"finish_reason":"tool_calls"}]}"#.utf8)
    let orr = try! oai.parse(otool)
    check(orr.stop == .toolCalls && orr.toolCalls.count == 2 && orr.toolCalls[1].arguments == nil && orr.toolCalls[1].rawArguments == "not json", "bad arguments kept as text")
    check(orr.rawAssistant["extra_content"] != nil, "OpenAI-style raw message kept whole")
    check(try! oai.parse(Data(#"{"choices":[{"message":{"role":"assistant","content":"Hi"},"finish_reason":"length"}]}"#.utf8)).stop == .tooLong, "length is tooLong")
    let ores = oai.toolResultMessages([ChatToolOutput(callID: "c1", text: "ok", isError: false, png: Data([1]))])
    check(ores.count == 1 && ores[0]["role"] as? String == "tool" && (ores[0]["content"] as? String)?.contains("picture") == true, "OpenAI-style results say a picture was left out")

    check(oai.parseModels(Data(#"{"data":[{"id":"b"},{"id":"a"}]}"#.utf8)) == ["a", "b"], "models sorted")
    let m = ChatWireError.message(status: 401, body: Data(#"{"error":{"message":"invalid x-api-key sk-secret"}}"#.utf8), provider: "Claude", key: "sk-secret")
    check(m.contains("Claude") && m.contains("Settings ▸ AI") && !m.contains("sk-secret"), "401 in plain words, key never shown: \(m)")
    check(ChatWireError.message(status: 429, body: Data(), provider: "ChatGPT", key: "k").contains("ChatGPT"), "429 names the provider")
    check(ChatWireError.message(status: 400, body: Data(#"{"error":{"message":"prompt is too long"}}"#.utf8), provider: "Claude", key: "k").contains("too long for the model"), "400 too long")
    check(ChatWireError.message(status: 503, body: Data(), provider: "Claude", key: "k").contains("having trouble"), "5xx")
    let other = ChatWireError.message(status: 418, body: Data(#"{"error":{"message":"bad sk-secret thing"}}"#.utf8), provider: "Claude", key: "sk-secret")
    check(other.contains("(418)") && other.contains("(key)") && !other.contains("sk-secret"), "other errors scrub the key: \(other)")

    for w in [claude as ChatWire, oai as ChatWire] {
        let bad = w.modelsRequest(base: URL(string: "http://example.com/v1")!, key: "sk-x")
        check(bad.value(forHTTPHeaderField: "x-api-key") == nil && bad.value(forHTTPHeaderField: "Authorization") == nil && bad.url?.scheme != "http", "models request off-Mac http carries no key")
        let good = w.modelsRequest(base: URL(string: "https://example.com/v1/")!, key: " sk-x ")
        check(good.url?.absoluteString == "https://example.com/v1/models" && (good.httpMethod ?? "GET") == "GET" && (good.value(forHTTPHeaderField: "x-api-key") == "sk-x" || good.value(forHTTPHeaderField: "Authorization") == "Bearer sk-x"), "models request is GET <base>/models with the key")
    }
    check(ChatWireError.message(status: 418, body: Data(String(repeating: "a", count: 1000).utf8), provider: "Claude", key: "k").count < 400, "long error body capped")

    check(creq.timeoutInterval == 600 && oreq.timeoutInterval == 600, "chat requests wait 600 s")
    for w in [claude as ChatWire, oai as ChatWire] {
        check(w.modelsRequest(base: URL(string: "https://example.com/v1")!, key: "k").timeoutInterval == 30, "models request waits 30 s")
    }

    let key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let straddle = String(repeating: "x", count: 290) + key + String(repeating: "y", count: 200)
    for body in [Data(straddle.utf8), Data(#"{"error":{"message":"\#(straddle)"}}"#.utf8)] {
        let m = ChatWireError.message(status: 418, body: body, provider: "Claude", key: key)
        let leaked = (8...key.count).contains { m.contains(String(key.prefix($0))) }
        check(!leaked && m.contains("(key)"), "key straddling the cap scrubbed before cutting: \(m.suffix(40))")
    }
    let lateTooLong = #"{"error":{"message":"\#(String(repeating: "z", count: 400)) prompt is too long"}}"#
    check(ChatWireError.message(status: 400, body: Data(lateTooLong.utf8), provider: "Claude", key: "k").contains("too long for the model"), "too long checked on the whole text")
    let maxTokens = ChatWireError.message(status: 400, body: Data(#"{"error":{"message":"max_tokens: 16000 > 8192, which is the maximum allowed"}}"#.utf8), provider: "Claude", key: "sk-test-key")
    check(maxTokens.contains("(400)") && maxTokens.contains("max_tokens") && !maxTokens.contains("too long for the model"), "max_tokens 400 shows the detail: \(maxTokens)")

    let blank = Data(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"list_games","arguments":""}},{"id":"c2","type":"function","function":{"name":"list_games","arguments":" \n"}}]},"finish_reason":"tool_calls"}]}"#.utf8)
    let blankCalls = try! oai.parse(blank).toolCalls
    check(blankCalls.count == 2 && blankCalls.allSatisfy { $0.arguments != nil && $0.arguments!.isEmpty }, "blank arguments are {}")

    runResponsesWireTests(tools: tools)
}

private func jsonObject(_ d: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: d) as! [String: Any] }

private func runResponsesWireTests(tools: [ChatToolSpec]) {
    let rw = ResponsesWire()
    let reasoning: [String: Any] = ["type": "reasoning", "id": "rs_1", "encrypted_content": "enc"]
    let fcall: [String: Any] = ["type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "game_details", "arguments": "{}"]
    let results = rw.toolResultMessages([ChatToolOutput(callID: "call_1", text: "ok", isError: false, png: nil)])
    let req = try! rw.request(base: URL(string: "https://api.openai.com/v1")!, key: " sk-o \n", model: "gpt-6.2-astra", system: "sys", tools: tools,
                              messages: [rw.userMessage("hi"), ["responseItems": [reasoning, fcall]]] + results)
    let body = jsonObject(req.httpBody!)
    let input = body["input"] as? [[String: Any]] ?? []
    check(req.url?.absoluteString == "https://api.openai.com/v1/responses" && req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-o", "responses_request: URL and Bearer")
    check(body["instructions"] as? String == "sys" && body["store"] as? Bool == false && body["include"] as? [String] == ["reasoning.encrypted_content"] && body["max_output_tokens"] == nil, "responses_request: instructions, store, include, no max_output_tokens")
    let t0 = (body["tools"] as? [[String: Any]])?.first
    check(t0?["type"] as? String == "function" && t0?["name"] as? String == "game_details" && t0?["strict"] as? Bool == false && t0?["parameters"] != nil && t0?["function"] == nil, "responses_request: flat tools, strict false")
    check(input.count == 4 && input[0]["role"] as? String == "user" && input[1]["type"] as? String == "reasoning" && input[2]["type"] as? String == "function_call" && input[3]["type"] as? String == "function_call_output" && input[3]["call_id"] as? String == "call_1" && input[3]["output"] as? String == "ok", "responses_request: items flatten in order")

    let text = Data(#"{"status":"completed","incomplete_details":null,"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"A"},{"type":"output_text","text":"B"}]}]}"#.utf8)
    let tr = try! rw.parse(text)
    check(tr.text == "A\nB" && tr.stop == .done && tr.toolCalls.isEmpty && (tr.rawAssistant["responseItems"] as? [[String: Any]])?.count == 1 && tr.rawAssistant.count == 1, "responses_parse_text")

    let tools1 = Data(#"{"status":"completed","output":[{"type":"reasoning","id":"rs","encrypted_content":"e"},{"type":"function_call","id":"fc_1","call_id":"call_1","name":"read_log","arguments":"{\"game\":\"x\"}"},{"type":"function_call","id":"fc_2","call_id":"call_2","name":"list_games","arguments":""}]}"#.utf8)
    let pr = try! rw.parse(tools1)
    check(pr.stop == .toolCalls && pr.toolCalls.count == 2 && pr.toolCalls[0].id == "call_1" && pr.toolCalls[0].arguments?["game"] as? String == "x" && pr.toolCalls[1].arguments?.isEmpty == true, "responses_parse_tools")
    check((pr.rawAssistant["responseItems"] as? [[String: Any]])?.count == 3, "responses_parse_tools: all items kept")

    let cut = try! rw.parse(Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8))
    let filtered = try! rw.parse(Data(#"{"status":"incomplete","incomplete_details":{"reason":"content_filter"},"output":[]}"#.utf8))
    let refusal = try! rw.parse(Data(#"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"No."}]}]}"#.utf8))
    check(cut.stop == .tooLong && filtered.stop == .refused && refusal.stop == .refused && refusal.text == "No.", "responses_parse_incomplete")

    var threw = false
    do { _ = try rw.parse(Data("{}".utf8)) } catch { threw = true }
    check(threw, "responses_parse_bad")

    let png = rw.toolResultMessages([ChatToolOutput(callID: "c", text: "shot", isError: false, png: Data([1, 2]))])
    let out = png.first?["output"] as? [[String: Any]]
    check(png.count == 1 && out?.count == 2 && out?[0]["type"] as? String == "input_text" && out?[0]["text"] as? String == "shot" && out?[1]["type"] as? String == "input_image" && (out?[1]["image_url"] as? String)?.hasPrefix("data:image/png;base64,") == true, "responses_tool_output_png")
    check(rw.parseModels(Data(#"{"data":[{"id":"b"},{"id":"a"}]}"#.utf8)) == ["a", "b"] && rw.modelsRequest(base: URL(string: "https://api.openai.com/v1")!, key: "k").value(forHTTPHeaderField: "Authorization") == "Bearer k", "responses models")
}
