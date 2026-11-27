import Darwin
import Foundation

@discardableResult
private func pump(until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while !done() {
        if Date() > deadline { return false }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return true
}

private final class Client {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    private var input = Data()
    private var lines: [[String: Any]] = []

    init(_ path: String) {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        check(ok == 0, "client connects to \(path)")
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
    }

    func send(_ text: String) {
        let data = Array(text.utf8)
        check(data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == data.count, "client sends \(text.prefix(40))")
    }

    func line() -> [String: Any]? {
        var eof = false
        pump {
            var chunk = [UInt8](repeating: 0, count: 65536)
            while lines.isEmpty, !eof {
                let n = read(fd, &chunk, chunk.count)
                guard n >= 0 else { break }
                if n == 0 { eof = true }
                input.append(contentsOf: chunk[..<n])
                if chunk[..<n].contains(10) { lines += AssistantWire.decodeLines(&input) }
            }
            return !lines.isEmpty || eof
        }
        return lines.isEmpty ? nil : lines.removeFirst()
    }

    func closedByFerry() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        return pump { read(fd, &chunk, chunk.count) == 0 }
    }

    func close() { Darwin.close(fd) }
}

private final class Seen {
    var opened: [(chat: UUID, client: String)] = []
    var calls: [(chat: UUID, tool: String, args: [String: Any])] = []
    var ended: [UUID] = []
}

private func text(_ r: [String: Any]?) -> String {
    ((r?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
}

func runAssistantServerTests() {
    check(AssistantServer.clientName("  Claude Code \n") == "Claude Code", "client name trimmed")
    check(AssistantServer.clientName(" ") == "Unnamed app" && AssistantServer.clientName(nil) == "Unnamed app"
          && AssistantServer.clientName(3) == "Unnamed app", "no name: Unnamed app")
    check(AssistantServer.clientName(String(repeating: "a", count: 80)).count == 60, "client name at most 60 characters")

    let seen = Seen()
    let handler = AssistantServer.Handler(
        instructions: "Use Ferry.",
        tools: [["name": "read_log", "description": "Reads a log.", "inputSchema": ["type": "object", "properties": [:]]]],
        open: { seen.opened.append(($0, $1)) },
        call: { chat, tool, args in
            seen.calls.append((chat, tool, args))
            if tool == "slow" { try? await Task.sleep(nanoseconds: 300_000_000) }
            var content: [[String: Any]] = [["type": "text", "text": "\(tool) ran"]]
            if tool == "big" { content.append(["type": "image", "data": String(repeating: "A", count: 3 << 20), "mimeType": "image/png"]) }
            return (content, tool == "bad")
        },
        end: { seen.ended.append($0) })

    let long = tempDir().path + "/" + String(repeating: "x", count: 120) + ".sock"
    check(!AssistantServer(path: long, handler: handler).start(), "a path too long for sun_path fails instead of crashing")

    let path = NSTemporaryDirectory() + "ferry-test-\(getpid()).sock"
    try? Data("left behind".utf8).write(to: URL(fileURLWithPath: path))
    let server = AssistantServer(path: path, handler: handler)
    check(server.start(), "starts over a stale file")
    var st = stat()
    check(stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFSOCK && (st.st_mode & 0o777) == 0o600, "socket with mode 0600")

    let junk = Client(path)
    junk.send("GET / HTTP/1.1\n")
    check(junk.closedByFerry() && seen.opened.isEmpty, "garbage before hello closes the connection")
    junk.close()

    let a = Client(path)
    a.send(#"{"op":"call","id":1,"tool":"read_log"}"# + "\n")
    let early = a.line()
    check(early?["op"] as? String == "result" && early?["id"] as? Int == 1 && early?["isError"] as? Bool == true
          && text(early).contains("hello") && seen.calls.isEmpty, "a call before hello is an error result")

    a.send(#"{"op":"hello","client":"  Claude Code  "}"# + "\n" + #"{"op":"tools"}"# + "\n")
    let hello = a.line(), tools = a.line()
    check(hello?["op"] as? String == "hello" && hello?["instructions"] as? String == "Use Ferry.", "hello answers the instructions")
    let list = tools?["tools"] as? [[String: Any]]
    check(tools?["op"] as? String == "tools" && list?.first?["name"] as? String == "read_log"
          && list?.first?["description"] as? String == "Reads a log." && list?.first?["inputSchema"] is [String: Any], "tools lists name, description, inputSchema")
    check(seen.opened.count == 1 && seen.opened[0].client == "Claude Code", "hello opens a chat named by the client")
    let chatA = seen.opened.first?.chat

    a.send(#"{"op":"call","id":"s","tool":"slow","args":{"x":1}}"# + "\n" + #"{"op":"call","id":7,"tool":"big"}"# + "\n")
    let slow = a.line(), big = a.line()
    check(slow?["id"] as? String == "s" && slow?["isError"] as? Bool == false && text(slow) == "slow ran", "first call answers first")
    let image = (big?["content"] as? [[String: Any]])?.last
    check(big?["id"] as? Int == 7 && (image?["data"] as? String)?.count == 3 << 20 && image?["mimeType"] as? String == "image/png",
          "a 3 MB result arrives whole")
    check(seen.calls.count == 2 && seen.calls.allSatisfy { $0.chat == chatA } && seen.calls[0].args["x"] as? Int == 1,
          "calls run in the connection's chat with their args")

    a.send("{nope\n")
    let unreadable = a.line()
    check(unreadable?["isError"] as? Bool == true && unreadable?["id"] == nil && text(unreadable).contains("couldn't read"), "a bad line is an error result")
    a.send(#"{"op":"dance","id":9}"# + "\n" + #"{"op":"call","id":10,"tool":"x","args":[1]}"# + "\n" + #"{"op":"hello","client":"again"}"# + "\n")
    let dance = a.line(), badArgs = a.line(), again = a.line()
    check(dance?["id"] as? Int == 9 && dance?["isError"] as? Bool == true && text(dance).contains("dance"), "an unknown op is an error result")
    check(badArgs?["id"] as? Int == 10 && badArgs?["isError"] as? Bool == true, "args that aren't an object are an error result")
    check(again?["isError"] as? Bool == true && seen.opened.count == 1, "a second hello doesn't open another chat")

    a.close()
    check(pump { seen.ended == [chatA].compactMap { $0 } }, "the app closing ends its chat")

    let b = Client(path)
    b.send(#"{"op":"hello"}"# + "\n")
    _ = b.line()
    check(seen.opened.count == 2 && seen.opened[1].client == "Unnamed app" && seen.opened[1].chat != chatA, "each hello is a fresh chat")
    let chatB = seen.opened[1].chat
    server.disconnect(chat: chatB)
    check(b.closedByFerry() && pump { seen.ended.contains(chatB) }, "Disconnect closes the connection and ends the chat")
    b.close()

    let c = Client(path)
    c.send(#"{"op":"hello","client":"C"}"# + "\n")
    _ = c.line()
    let chatC = seen.opened.last?.chat
    server.stop()
    check(c.closedByFerry() && pump { seen.ended.last == chatC }, "stop closes connections and ends their chats")
    check(!FileManager.default.fileExists(atPath: path), "stop removes the socket file")
    c.close()

    let otherPath = NSTemporaryDirectory() + "ferry-test-uid-\(getpid()).sock"
    let strict = AssistantServer(path: otherPath, handler: handler, uid: getuid() + 1)
    check(strict.start(), "starts for another uid")
    let stranger = Client(otherPath)
    stranger.send(#"{"op":"hello","client":"x"}"# + "\n")
    check(stranger.closedByFerry() && seen.opened.count == 3, "a peer with another uid is closed without a chat")
    stranger.close()
    strict.stop()
}
