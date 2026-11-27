import Foundation

struct ChatToolSpec {
    let name: String
    let description: String
    let schema: [String: Any]
}

struct ChatToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]?
    let rawArguments: String
}

enum ChatStop: Equatable { case done, toolCalls, tooLong, refused }

struct ChatReply {
    let text: String
    let toolCalls: [ChatToolCall]
    let stop: ChatStop
    let rawAssistant: [String: Any]
}

struct ChatToolOutput {
    let callID: String
    let text: String
    let isError: Bool
    let png: Data?
}

enum ChatWireError: Error {
    case badAddress
    case badReply

    static func message(status: Int, body: Data, provider: String, key: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        func scrub(_ s: String) -> String {
            trimmedKey.isEmpty ? s : s.replacingOccurrences(of: trimmedKey, with: "(key)")
        }
        let raw: String = {
            if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if let e = root["error"] as? [String: Any], let m = e["message"] as? String { return m }
                if let m = root["error"] as? String { return m }
                if let m = root["message"] as? String { return m }
            }
            return String(data: body, encoding: .utf8) ?? ""
        }()
        let lower = raw.lowercased()
        let tooLong = !lower.contains("max_tokens") && ["context", "too long", "maximum"].contains(where: { lower.contains($0) })
        switch status {
        case 401, 403:
            return "\(provider) refused the key. Check it in Settings ▸ AI."
        case 429:
            return "\(provider) says you've hit your limit or are out of credit. Try again later, or check your account."
        case 400 where tooLong:
            return "This chat is too long for the model. Start a new chat."
        case 500...599:
            return "\(provider) is having trouble right now. Try again in a minute."
        default:
            return "\(provider) answered with an error (\(status)): \(scrub(raw).prefix(300))"
        }
    }
}

enum ChatBase {
    static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return url.host?.isEmpty == false
        case "http": return ["localhost", "127.0.0.1", "::1"].contains((url.host ?? "").lowercased())
        default: return false
        }
    }

    static let refusedRequest = URLRequest(url: URL(string: "ferry-refused:")!)

    static func join(_ base: URL, _ path: String) throws -> URL {
        guard isAllowed(base) else { throw ChatWireError.badAddress }
        var s = base.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/" + path) else { throw ChatWireError.badAddress }
        return url
    }
}

protocol ChatWire {
    func request(base: URL, key: String, model: String, system: String, tools: [ChatToolSpec], messages: [[String: Any]]) throws -> URLRequest
    func parse(_ data: Data) throws -> ChatReply
    func userMessage(_ text: String) -> [String: Any]
    func toolResultMessages(_ outputs: [ChatToolOutput]) -> [[String: Any]]
    func modelsRequest(base: URL, key: String) -> URLRequest
    func parseModels(_ data: Data) -> [String]
}

private func trimmed(_ key: String) -> String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

private func decodeArguments(_ raw: String) -> [String: Any]? {
    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
    guard let d = raw.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

let chatRequestTimeout: TimeInterval = 600
let modelsRequestTimeout: TimeInterval = 30

private func modelIDs(_ data: Data) -> [String] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = root["data"] as? [[String: Any]] else { return [] }
    return list.compactMap { $0["id"] as? String }.sorted()
}

struct ClaudeWire: ChatWire {
    private func headers(_ r: inout URLRequest, key: String) {
        r.setValue(trimmed(key), forHTTPHeaderField: "x-api-key")
        r.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
    }

    func request(base: URL, key: String, model: String, system: String, tools: [ChatToolSpec], messages: [[String: Any]]) throws -> URLRequest {
        var r = URLRequest(url: try ChatBase.join(base, "messages"), timeoutInterval: chatRequestTimeout)
        r.httpMethod = "POST"
        headers(&r, key: key)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "system": system,
            "tools": tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] as [String: Any] },
            "messages": messages,
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    func parse(_ data: Data) throws -> ChatReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else { throw ChatWireError.badReply }
        var text = ""
        var calls: [ChatToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "tool_use":
                let input = block["input"] as? [String: Any]
                let raw = input.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                calls.append(ChatToolCall(id: block["id"] as? String ?? "", name: block["name"] as? String ?? "", arguments: input, rawArguments: raw))
            default:
                break
            }
        }
        let stop: ChatStop
        switch root["stop_reason"] as? String {
        case "tool_use": stop = .toolCalls
        case "max_tokens": stop = .tooLong
        case "refusal": stop = .refused
        default: stop = .done
        }
        return ChatReply(text: text, toolCalls: calls, stop: stop, rawAssistant: ["role": "assistant", "content": content])
    }

    func userMessage(_ text: String) -> [String: Any] { ["role": "user", "content": text] }

    func toolResultMessages(_ outputs: [ChatToolOutput]) -> [[String: Any]] {
        let blocks: [[String: Any]] = outputs.map { o in
            var inner: [[String: Any]] = [["type": "text", "text": o.text]]
            if let png = o.png {
                inner.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]])
            }
            var block: [String: Any] = ["type": "tool_result", "tool_use_id": o.callID, "content": inner]
            if o.isError { block["is_error"] = true }
            return block
        }
        return [["role": "user", "content": blocks]]
    }

    func modelsRequest(base: URL, key: String) -> URLRequest {
        guard let url = try? ChatBase.join(base, "models") else { return ChatBase.refusedRequest }
        var r = URLRequest(url: url, timeoutInterval: modelsRequestTimeout)
        headers(&r, key: key)
        return r
    }

    func parseModels(_ data: Data) -> [String] { modelIDs(data) }
}

struct OpenAIWire: ChatWire {
    func request(base: URL, key: String, model: String, system: String, tools: [ChatToolSpec], messages: [[String: Any]]) throws -> URLRequest {
        var r = URLRequest(url: try ChatBase.join(base, "chat/completions"), timeoutInterval: chatRequestTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let k = trimmed(key)
        if !k.isEmpty { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system] as [String: Any]] + messages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema] as [String: Any]] as [String: Any]
            }
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    func parse(_ data: Data) throws -> ChatReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw ChatWireError.badReply }
        let calls: [ChatToolCall] = (message["tool_calls"] as? [[String: Any]] ?? []).map { c in
            let fn = c["function"] as? [String: Any] ?? [:]
            let raw = fn["arguments"] as? String ?? ""
            return ChatToolCall(id: c["id"] as? String ?? "", name: fn["name"] as? String ?? "", arguments: decodeArguments(raw), rawArguments: raw)
        }
        let stop: ChatStop
        switch choice["finish_reason"] as? String {
        case "tool_calls": stop = .toolCalls
        case "length": stop = .tooLong
        case "content_filter": stop = .refused
        default: stop = calls.isEmpty ? .done : .toolCalls
        }
        return ChatReply(text: message["content"] as? String ?? "", toolCalls: calls, stop: stop, rawAssistant: message)
    }

    func userMessage(_ text: String) -> [String: Any] { ["role": "user", "content": text] }

    func toolResultMessages(_ outputs: [ChatToolOutput]) -> [[String: Any]] {
        outputs.map { o in
            let note = o.png == nil ? "" : " (Ferry took a picture, but this model's connection can't take pictures.)"
            return ["role": "tool", "tool_call_id": o.callID, "content": o.text + note]
        }
    }

    func modelsRequest(base: URL, key: String) -> URLRequest {
        guard let url = try? ChatBase.join(base, "models") else { return ChatBase.refusedRequest }
        var r = URLRequest(url: url, timeoutInterval: modelsRequestTimeout)
        let k = trimmed(key)
        if !k.isEmpty { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        return r
    }

    func parseModels(_ data: Data) -> [String] { modelIDs(data) }
}

struct ResponsesWire: ChatWire {
    func request(base: URL, key: String, model: String, system: String, tools: [ChatToolSpec], messages: [[String: Any]]) throws -> URLRequest {
        var r = URLRequest(url: try ChatBase.join(base, "responses"), timeoutInterval: chatRequestTimeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let k = trimmed(key)
        if !k.isEmpty { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        var input: [[String: Any]] = []
        for m in messages {
            if let items = m["responseItems"] as? [[String: Any]] { input.append(contentsOf: items) } else { input.append(m) }
        }
        var body: [String: Any] = [
            "model": model,
            "instructions": system,
            "input": input,
            "store": false,
            "include": ["reasoning.encrypted_content"],
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                ["type": "function", "name": $0.name, "description": $0.description, "parameters": $0.schema, "strict": false] as [String: Any]
            }
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    func parse(_ data: Data) throws -> ChatReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]] else { throw ChatWireError.badReply }
        var texts: [String] = []
        var refusals: [String] = []
        var calls: [ChatToolCall] = []
        for item in output {
            switch item["type"] as? String {
            case "message":
                for part in item["content"] as? [[String: Any]] ?? [] {
                    switch part["type"] as? String {
                    case "output_text": texts.append(part["text"] as? String ?? "")
                    case "refusal": refusals.append(part["refusal"] as? String ?? "")
                    default: break
                    }
                }
            case "function_call":
                let raw = item["arguments"] as? String ?? ""
                calls.append(ChatToolCall(id: item["call_id"] as? String ?? "", name: item["name"] as? String ?? "", arguments: decodeArguments(raw), rawArguments: raw))
            default:
                break
            }
        }
        var text = texts.joined(separator: "\n")
        let reason = (root["incomplete_details"] as? [String: Any])?["reason"] as? String
        let incomplete = root["status"] as? String == "incomplete"
        let stop: ChatStop
        if incomplete && reason == "max_output_tokens" {
            stop = .tooLong
        } else if incomplete && reason == "content_filter" {
            stop = .refused
        } else if !refusals.isEmpty {
            stop = .refused
            if text.isEmpty { text = refusals.joined(separator: "\n") }
        } else {
            stop = calls.isEmpty ? .done : .toolCalls
        }
        return ChatReply(text: text, toolCalls: calls, stop: stop, rawAssistant: ["responseItems": output])
    }

    func userMessage(_ text: String) -> [String: Any] { ["role": "user", "content": text] }

    func toolResultMessages(_ outputs: [ChatToolOutput]) -> [[String: Any]] {
        outputs.map { o in
            var item: [String: Any] = ["type": "function_call_output", "call_id": o.callID]
            if let png = o.png {
                item["output"] = [
                    ["type": "input_text", "text": o.text] as [String: Any],
                    ["type": "input_image", "image_url": "data:image/png;base64," + png.base64EncodedString()] as [String: Any],
                ]
            } else {
                item["output"] = o.text
            }
            return item
        }
    }

    func modelsRequest(base: URL, key: String) -> URLRequest { OpenAIWire().modelsRequest(base: base, key: key) }

    func parseModels(_ data: Data) -> [String] { modelIDs(data) }
}
