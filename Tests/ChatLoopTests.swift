import Foundation

private final class FakeTransport: ChatTransport {
    var queue: [Result<(Data, Int), Error>]
    var sent: [URLRequest] = []
    let repeating: (Data, Int)?
    init(_ q: [Result<(Data, Int), Error>], repeating: (Data, Int)? = nil) { queue = q; self.repeating = repeating }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        sent.append(request)
        if queue.isEmpty, let r = repeating { return r }
        return try queue.removeFirst().get()
    }
}

private func ok(_ s: String) -> Result<(Data, Int), Error> { .success((Data(s.utf8), 200)) }
private let claudeCall = #"{"content":[{"type":"tool_use","id":"t1","name":"read_log","input":{"game":"G"}}],"stop_reason":"tool_use"}"#
private func claudeText(_ t: String, _ stop: String = "end_turn") -> String { #"{"content":[{"type":"text","text":"\#(t)"}],"stop_reason":"\#(stop)"}"# }

private func describe(_ e: ChatEvent) -> String {
    switch e {
    case .text(let s): return "text:\(s)"
    case .activity(let s): return "activity:\(s)"
    case .toolFinished(let n, let err): return "done:\(n):\(err)"
    case .failed(let s): return "failed:\(s)"
    case .stopped(let s): return "stopped:\(s)"
    }
}

private func loop(_ wire: ChatWire = ClaudeWire(), tools: [String] = ["read_log"]) -> ChatLoop {
    ChatLoop(wire: wire, base: URL(string: "https://api.anthropic.com/v1")!, key: "sk-secret", model: "m", provider: "Claude", system: "s",
             tools: tools.map { ChatToolSpec(name: $0, description: "d", schema: ["type": "object"]) })
}

private func drive(_ l: ChatLoop, _ messages: inout [[String: Any]], _ t: FakeTransport,
                   runner: @escaping (ChatToolCall) async -> ChatToolOutput = { ChatToolOutput(callID: $0.id, text: "ran", isError: false, png: nil) }) async -> [String] {
    var events: [String] = []
    await l.run(messages: &messages, transport: t, runTool: runner, activity: { "Reading \($0.name)" }, events: { events.append(describe($0)) })
    return events
}

func runChatLoopTests() async {
    let wire = ClaudeWire()

    do {
        let rw = ResponsesWire()
        var m = [rw.userMessage("hi")]
        let first = #"{"status":"completed","output":[{"type":"reasoning","id":"rs_1","encrypted_content":"e"},{"type":"function_call","id":"fc_1","call_id":"call_1","name":"read_log","arguments":"{}"}]}"#
        let second = #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}]}"#
        let t = FakeTransport([ok(first), ok(second)])
        var ran = 0
        let ev = await drive(loop(rw), &m, t, runner: { ran += 1; return ChatToolOutput(callID: $0.id, text: "ran", isError: false, png: nil) })
        let input = (try? JSONSerialization.jsonObject(with: t.sent[1].httpBody!) as? [String: Any])?["input"] as? [[String: Any]] ?? []
        let kinds = input.map { ($0["type"] as? String) ?? ($0["role"] as? String) ?? "" }
        check(ran == 1 && ev.last == "text:Done." && kinds == ["user", "reasoning", "function_call", "function_call_output"], "Responses loop flattens items across rounds: \(kinds)")
    }

    do {
        var m = [wire.userMessage("hi")]
        let t = FakeTransport([ok(claudeCall), ok(claudeText("Turn it on."))])
        let ev = await drive(loop(), &m, t)
        check(ev == ["activity:Reading read_log", "done:read_log:false", "text:Turn it on."], "tool round then answer: events \(ev)")
        check(m.count == 4 && m[1]["role"] as? String == "assistant" && m[2]["role"] as? String == "user" && m[3]["role"] as? String == "assistant", "messages: user, assistant, results, assistant")
        check(t.sent.count == 2, "two requests")
    }

    do {
        var m = [wire.userMessage("hi")]
        let t = FakeTransport([ok(#"{"content":[{"type":"tool_use","id":"t1","name":"x","input":{}}],"stop_reason":"tool_use"}"#), ok(claudeText("ok"))])
        var asked = 0
        let ev = await drive(loop(), &m, t, runner: { asked += 1; return ChatToolOutput(callID: $0.id, text: "", isError: false, png: nil) })
        let block = ((m[2]["content"] as? [[String: Any]])?.first)
        let inner = (block?["content"] as? [[String: Any]])?.first?["text"] as? String
        check(asked == 0 && inner == "Ferry has no action called x." && block?["is_error"] as? Bool == true, "unknown tool gets an error result, runner not asked")
        check(ev.last == "text:ok", "loop continues after unknown tool")
    }

    do {
        var m = [wire.userMessage("hi")]
        let oai = OpenAIWire()
        m = [oai.userMessage("hi")]
        let bad = #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"read_log","arguments":"oops"}}]},"finish_reason":"tool_calls"}]}"#
        let fin = #"{"choices":[{"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}]}"#
        let t = FakeTransport([ok(bad), ok(fin)])
        var asked = 0
        _ = await drive(loop(oai), &m, t, runner: { asked += 1; return ChatToolOutput(callID: $0.id, text: "", isError: false, png: nil) })
        check(asked == 0 && m[2]["content"] as? String == "The arguments weren't a JSON object: oops", "bad arguments become an error result")
    }

    do {
        var m = [wire.userMessage("hi")]
        let t = FakeTransport([], repeating: (Data(claudeCall.utf8), 200))
        let ev = await drive(loop(), &m, t)
        check(t.sent.count == 20, "exactly 20 requests, got \(t.sent.count)")
        check(ev.last == "stopped:The assistant stopped after 20 steps. Ask again to let it go on.", "20 rounds stop message")
        check(ev.filter { $0.hasPrefix("failed") }.isEmpty, "no failure at the limit")
        check(m.last?["role"] as? String == "user", "history still valid (ends with results)")
    }

    do {
        let before = [wire.userMessage("earlier"), ["role": "assistant", "content": "ok"] as [String: Any]]
        var m = before + [wire.userMessage("hi")]
        let t = FakeTransport([.success((Data(#"{"error":{"message":"bad"}}"#.utf8), 401))])
        let ev = await drive(loop(), &m, t)
        check(ev == ["failed:" + ChatWireError.message(status: 401, body: Data(), provider: "Claude", key: "sk-secret")] && m.count == 2, "HTTP failure: one failed event, this turn's user message removed, earlier history kept")
        var m3 = before + [wire.userMessage("hi")]
        _ = await drive(loop(), &m3, FakeTransport([ok(claudeCall), .success((Data(), 500))]))
        check(m3.count == 5, "failure after a kept reply keeps the history")
    }

    do {
        var m = [wire.userMessage("hi")]
        let t = FakeTransport([.failure(URLError(.notConnectedToInternet))])
        let ev = await drive(loop(), &m, t)
        check(ev == ["failed:Ferry couldn't reach Claude. Check the internet connection."], "network error")
        let t2 = FakeTransport([.failure(URLError(.timedOut))])
        let ev2 = await drive(loop(), &m, t2)
        check(ev2 == ["failed:Claude took too long to answer. Try again."], "timeout")
    }

    do {
        var m = [wire.userMessage("hi")]
        let t = FakeTransport([ok("not json")])
        let ev = await drive(loop(), &m, t)
        check(ev == ["failed:Claude sent an answer Ferry couldn't read."], "unreadable reply")
        var m2 = [wire.userMessage("hi")]
        var events: [String] = []
        let l = ChatLoop(wire: wire, base: URL(string: "http://example.com")!, key: "k", model: "m", provider: "Claude", system: "s", tools: [])
        await l.run(messages: &m2, transport: FakeTransport([]), runTool: { ChatToolOutput(callID: $0.id, text: "", isError: false, png: nil) }, activity: { $0.name }, events: { events.append(describe($0)) })
        check(events.count == 1 && events[0].hasPrefix("failed:"), "disallowed base becomes one failed event")
    }

    do {
        var m = [wire.userMessage("hi")]
        let ev = await drive(loop(), &m, FakeTransport([ok(claudeText("Partial", "max_tokens"))]))
        check(ev == ["text:Partial", "stopped:The answer was cut off. Ask the assistant to go on."], "cut off")
    }

    do {
        var m = [wire.userMessage("hi")]
        let cut = #"{"content":[{"type":"tool_use","id":"z","name":"read_log","input":{}}],"stop_reason":"max_tokens"}"#
        var asked = 0
        _ = await drive(loop(), &m, FakeTransport([ok(cut)]), runner: { asked += 1; return ChatToolOutput(callID: $0.id, text: "", isError: false, png: nil) })
        let r = (m.last?["content"] as? [[String: Any]]) ?? []
        check(asked == 0 && r.count == 1 && r[0]["tool_use_id"] as? String == "z" && r[0]["is_error"] as? Bool == true, "cut-off reply with a tool call: history ends with its result")
        var m2 = [wire.userMessage("hi")]
        let ref = #"{"content":[{"type":"tool_use","id":"y","name":"read_log","input":{}}],"stop_reason":"refusal"}"#
        _ = await drive(loop(), &m2, FakeTransport([ok(ref)]))
        check(((m2.last?["content"] as? [[String: Any]])?.first?["tool_use_id"]) as? String == "y", "refused reply with a tool call: history ends with its result")
    }

    do {
        var m = [wire.userMessage("hi")]
        let ev1 = await drive(loop(), &m, FakeTransport([ok(claudeText("No.", "refusal"))]))
        check(ev1 == ["text:No."], "refused with text shows it: \(ev1)")
        var m2 = [wire.userMessage("hi")]
        let ev2 = await drive(loop(), &m2, FakeTransport([ok(#"{"content":[],"stop_reason":"refusal"}"#)]))
        check(ev2.contains("text:The model declined to answer that."), "refused without text uses the default: \(ev2)")
    }

    do {
        var m = [wire.userMessage("hi")]
        let two = #"{"content":[{"type":"tool_use","id":"a","name":"read_log","input":{}},{"type":"tool_use","id":"b","name":"read_log","input":{}}],"stop_reason":"tool_use"}"#
        let t = FakeTransport([ok(two), ok(claudeText("never"))])
        var ev: [String] = []
        let l = loop()
        let task = Task { () -> [[String: Any]] in
            var mm = m
            await l.run(messages: &mm, transport: t, runTool: { c in
                withUnsafeCurrentTask { $0?.cancel() }
                return ChatToolOutput(callID: c.id, text: "ran", isError: false, png: nil)
            }, activity: { $0.name }, events: { ev.append(describe($0)) })
            return mm
        }
        m = await task.value
        let results = (m.last?["content"] as? [[String: Any]]) ?? []
        let second = ((results.last?["content"] as? [[String: Any]])?.first?["text"]) as? String
        check(results.count == 2 && second == "Stopped by the person." && results.last?["tool_use_id"] as? String == "b", "cancelled mid-tools: results for both calls")
        check(t.sent.count == 1 && !ev.contains { $0.hasPrefix("failed") || $0.hasPrefix("text") }, "no more requests or events after cancel")
    }
}
