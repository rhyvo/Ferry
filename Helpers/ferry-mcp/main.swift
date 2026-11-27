import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

let realSocket = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Ferry/assistant.sock").path
#if FERRY_RELEASE
let socketPath = realSocket
let defaultsSuite = "app.ferry.Ferry"
let openCommand: String? = nil
#else
let env = ProcessInfo.processInfo.environment
let socketPath = env["FERRY_MCP_SOCKET"] ?? realSocket
let defaultsSuite = env["FERRY_MCP_DEFAULTS_SUITE"] ?? "app.ferry.Ferry"
let openCommand = env["FERRY_MCP_OPEN"]
#endif

let enclosingApp: URL? = {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size) + 1)
    guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }
    let app = URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}()
let ferryVersion = enclosingApp.flatMap {
    NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
} ?? "0"

func log(_ text: String) {
    FileHandle.standardError.write(Data("ferry-mcp: \(text)\n".utf8))
}

let stdoutLock = NSLock()

func reply(_ obj: [String: Any]) {
    let data = AssistantWire.encode(obj)
    stdoutLock.lock()
    defer { stdoutLock.unlock() }
    var sent = 0
    while sent < data.count {
        let n = data.withUnsafeBytes { write(1, $0.baseAddress! + sent, $0.count - sent) }
        if n > 0 {
            sent += n
        } else if n < 0, errno == EINTR {
            continue
        } else {
            exit(0)
        }
    }
}

func switchOn() -> Bool {
    let defaults = defaultsSuite == Bundle.main.bundleIdentifier ? UserDefaults.standard : UserDefaults(suiteName: defaultsSuite)
    return defaults?.bool(forKey: "assistantMCPEnabled") ?? false
}

struct Failed: Error { let message: String }

final class Ferry: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.ferry.mcp")
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var pending = Set<String>()
    private var current: String?
    private var cancelled = Set<String>()
    private var input = Data()
    private var lines: [[String: Any]] = []
    private var lastId = 0
    private var clientName = "AI app"

    func received(_ key: String?) {
        guard let key else { return }
        lock.withLock { _ = pending.insert(key) }
    }

    func cancel(_ key: String) {
        lock.withLock {
            guard pending.contains(key) else { return }
            cancelled.insert(key)
            if current == key, fd >= 0 { shutdown(fd, SHUT_RDWR) }
        }
    }

    func setClient(_ name: String) {
        queue.async { self.clientName = name }
    }

    func handle(id: Any?, request: MCPProtocol.Request) {
        let key = MCPProtocol.requestKey(id)
        lock.withLock { current = key }
        defer {
            lock.withLock {
                current = nil
                if let key {
                    pending.remove(key)
                    cancelled.remove(key)
                }
            }
        }
        do {
            try checkCancelled(key)
            switch request {
            case .toolsList:
                try connect()
                try checkCancelled(key)
                try send(["op": "tools"])
                let tools = try next(within: 30) { $0["op"] as? String == "tools" }
                reply(MCPProtocol.response(id: id, result: MCPProtocol.toolsList(tools["tools"] as? [[String: Any]] ?? [])))
            case .toolsCall(let tool, let args):
                try connect()
                try checkCancelled(key)
                lastId += 1
                let wireId = lastId
                let r: [String: Any]
                do {
                    try send(["op": "call", "id": wireId, "tool": tool, "args": args])
                    r = try next(within: 15 * 60) { $0["op"] as? String == "result" && $0["id"] as? Int == wireId }
                } catch {
                    disconnect()
                    throw error
                }
                reply(MCPProtocol.response(id: id, result: MCPProtocol.callResult(content: r["content"] as? [[String: Any]] ?? [],
                                                                                  isError: r["isError"] as? Bool ?? false)))
            case .initialize, .ping, .ignore, .invalid, .cancelled:
                break
            }
        } catch {
            let wasCancelled = key.map { k in lock.withLock { cancelled.contains(k) } } ?? false
            let message = wasCancelled ? "The AI app cancelled this request." : (error as? Failed)?.message ?? "\(error)"
            reply(MCPProtocol.failure(id: id, request: request, message: message))
        }
    }

    private func checkCancelled(_ key: String?) throws {
        guard let key, lock.withLock({ cancelled.contains(key) }) else { return }
        throw Failed(message: "The AI app cancelled this request.")
    }

    private func connect() throws {
        guard fd < 0 else { return }
        var socket = connectOnce()
        if socket == nil {
            log("Ferry isn't listening; opening it")
            openFerry()
            let deadline = Date().addingTimeInterval(20)
            while socket == nil, Date() < deadline {
                usleep(500_000)
                socket = connectOnce()
            }
        }
        guard let socket else { throw Failed(message: "Ferry didn't start. Open Ferry and try again.") }
        lock.withLock { fd = socket }
        input = Data()
        lines = []
        try send(["op": "hello", "client": clientName])
        do {
            _ = try next(within: 30) { $0["op"] as? String == "hello" }
        } catch {
            disconnect()
            throw error
        }
    }

    private func connectOnce() -> Int32? {
        var addr = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let s = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else {
            close(s)
            return nil
        }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return s
    }

    private func openFerry() {
        let p = Process()
        if let openCommand {
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", openCommand]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = enclosingApp.map { ["-g", "-a", $0.path] } ?? ["-g", "-b", "app.ferry.Ferry"]
        }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            log("couldn't open Ferry: \(error.localizedDescription)")
        }
    }

    private func disconnect() {
        lock.withLock {
            if fd >= 0 { close(fd) }
            fd = -1
        }
    }

    private func lost() -> Failed {
        disconnect()
        return Failed(message: "Ferry closed the connection (it quit, or Settings ▸ AI ▸ Use Ferry from other AI apps was turned off). Try again.")
    }

    private func send(_ obj: [String: Any]) throws {
        let data = AssistantWire.encode(obj)
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + sent, $0.count - sent) }
            if n > 0 {
                sent += n
            } else if n < 0, errno == EINTR {
                continue
            } else {
                throw lost()
            }
        }
    }

    private func next(within seconds: TimeInterval, _ matches: ([String: Any]) -> Bool) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(seconds)
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            while !lines.isEmpty {
                let line = lines.removeFirst()
                if matches(line) { return line }
                if line.isEmpty { throw Failed(message: "Ferry's answer couldn't be read (over 8 MB, or not JSON).") }
                if line["op"] as? String == "result", line["id"] == nil {
                    log("Ferry: \(((line["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "an error without an id")")
                }
            }
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { throw Failed(message: "Ferry didn't answer in time. Try again.") }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, Int32(min(left, 60) * 1000) + 1)
            if ready < 0, errno == EINTR { continue }
            if ready == 0 { continue }
            let n = read(fd, &chunk, chunk.count)
            if n < 0, errno == EINTR || errno == EAGAIN { continue }
            guard n > 0 else { throw lost() }
            input.append(contentsOf: chunk[..<n])
            if chunk[..<n].contains(10) || input.count > AssistantWire.maxLine { lines += AssistantWire.decodeLines(&input) }
        }
    }
}

let ferry = Ferry()
let outstanding = DispatchGroup()

func handle(_ msg: [String: Any]) {
    let (id, request) = MCPProtocol.parse(msg)
    switch request {
    case .ignore:
        return
    case .invalid(let code, let message):
        reply(MCPProtocol.error(id: id, code: code, message: message))
    case .cancelled(let key):
        ferry.cancel(key)
    case .initialize(let version, let client):
        ferry.setClient(client)
        reply(MCPProtocol.response(id: id, result: MCPProtocol.initializeResult(requested: version, version: ferryVersion)))
    case _ where !switchOn():
        reply(MCPProtocol.failure(id: id, request: request, message: MCPProtocol.offMessage))
    case .ping:
        reply(MCPProtocol.response(id: id, result: [:]))
    default:
        ferry.received(MCPProtocol.requestKey(id))
        outstanding.enter()
        ferry.queue.async {
            ferry.handle(id: id, request: request)
            outstanding.leave()
        }
    }
}

var pendingInput = Data()
var chunk = [UInt8](repeating: 0, count: 64 << 10)
while true {
    let n = read(0, &chunk, chunk.count)
    if n < 0, errno == EINTR { continue }
    guard n > 0 else { break }
    pendingInput.append(contentsOf: chunk[..<n])
    if chunk[..<n].contains(10) || pendingInput.count > AssistantWire.maxLine { AssistantWire.decodeLines(&pendingInput).forEach(handle) }
}
if !pendingInput.isEmpty {
    pendingInput.append(10)
    AssistantWire.decodeLines(&pendingInput).forEach(handle)
}
_ = outstanding.wait(timeout: .now() + 30)
exit(0)
