import Foundation

protocol ChatTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

extension URLSession: ChatTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

enum ChatEvent {
    case text(String)
    case activity(String)
    case toolFinished(name: String, isError: Bool)
    case failed(String)
    case stopped(String)
}

struct ChatLoop {
    let wire: ChatWire
    let base: URL
    let key: String
    let model: String
    let provider: String
    let system: String
    let tools: [ChatToolSpec]
    var maxRounds: Int = 20

    private func output(_ call: ChatToolCall, _ text: String) -> ChatToolOutput {
        ChatToolOutput(callID: call.id, text: text, isError: true, png: nil)
    }

    func run(messages: inout [[String: Any]],
             transport: ChatTransport,
             runTool: (ChatToolCall) async -> ChatToolOutput,
             activity: (ChatToolCall) -> String,
             events: (ChatEvent) -> Void) async {
        let startCount = messages.count
        func fail(_ text: String, _ messages: inout [[String: Any]]) {
            if messages.count == startCount, !messages.isEmpty { messages.removeLast() }
            events(.failed(text))
        }
        for round in 1...max(1, maxRounds) {
            if Task.isCancelled { return }
            let request: URLRequest
            do {
                request = try wire.request(base: base, key: key, model: model, system: system, tools: tools, messages: messages)
            } catch {
                fail("Ferry won't send chat to that address. Use an https address, or a server on this Mac.", &messages)
                return
            }
            let data: Data
            let status: Int
            do {
                (data, status) = try await transport.send(request)
            } catch {
                if Task.isCancelled { return }
                if (error as? URLError)?.code == .timedOut {
                    fail("\(provider) took too long to answer. Try again.", &messages)
                } else {
                    fail("Ferry couldn't reach \(provider). Check the internet connection.", &messages)
                }
                return
            }
            if Task.isCancelled { return }
            guard (200...299).contains(status) else {
                fail(ChatWireError.message(status: status, body: data, provider: provider, key: key), &messages)
                return
            }
            let reply: ChatReply
            do {
                reply = try wire.parse(data)
            } catch {
                fail("\(provider) sent an answer Ferry couldn't read.", &messages)
                return
            }
            messages.append(reply.rawAssistant)

            if reply.stop == .tooLong || reply.stop == .refused {
                let why = reply.stop == .tooLong ? "The answer was cut off before this ran." : "Not run."
                if !reply.toolCalls.isEmpty {
                    messages.append(contentsOf: wire.toolResultMessages(reply.toolCalls.map { output($0, why) }))
                }
            }
            switch reply.stop {
            case .refused:
                events(.text(reply.text.isEmpty ? "The model declined to answer that." : reply.text))
                return
            case .tooLong:
                if !reply.text.isEmpty { events(.text(reply.text)) }
                events(.stopped("The answer was cut off. Ask the assistant to go on."))
                return
            case .done, .toolCalls:
                break
            }
            if !reply.text.isEmpty { events(.text(reply.text)) }
            if reply.toolCalls.isEmpty { return }

            var outputs: [ChatToolOutput] = []
            for call in reply.toolCalls {
                if Task.isCancelled {
                    outputs.append(output(call, "Stopped by the person."))
                    continue
                }
                if !tools.contains(where: { $0.name == call.name }) {
                    outputs.append(output(call, "Ferry has no action called \(call.name)."))
                    events(.toolFinished(name: call.name, isError: true))
                    continue
                }
                if call.arguments == nil {
                    outputs.append(output(call, "The arguments weren't a JSON object: \(call.rawArguments)"))
                    events(.toolFinished(name: call.name, isError: true))
                    continue
                }
                events(.activity(activity(call)))
                let result = await runTool(call)
                outputs.append(result)
                events(.toolFinished(name: call.name, isError: result.isError))
            }
            messages.append(contentsOf: wire.toolResultMessages(outputs))
            if Task.isCancelled { return }
            if round == max(1, maxRounds) {
                events(.stopped("The assistant stopped after \(maxRounds) steps. Ask again to let it go on."))
                return
            }
        }
    }
}
