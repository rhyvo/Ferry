import Darwin
import Foundation

final class AssistantServer: @unchecked Sendable {
    struct Handler {
        let instructions: String
        let tools: [[String: Any]]
        let open: @MainActor (_ chat: UUID, _ client: String) -> Void
        let call: @MainActor (_ chat: UUID, _ tool: String, _ args: [String: Any]) async -> (content: [[String: Any]], isError: Bool)
        let end: @MainActor (_ chat: UUID) -> Void
    }

    let path: String
    fileprivate let handler: Handler
    private let uid: uid_t
    fileprivate let queue = DispatchQueue(label: "app.ferry.assistant-server")
    private var listener: DispatchSourceRead?
    fileprivate var connections: [ObjectIdentifier: Connection] = [:]
    fileprivate var readBuffer = [UInt8](repeating: 0, count: 64 << 10)

    init(path: String, handler: Handler, uid: uid_t = getuid()) {
        self.path = path
        self.handler = handler
        self.uid = uid
    }

    static func clientName(_ raw: Any?) -> String {
        let name = ((raw as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed app" : String(name.prefix(60))
    }

    @discardableResult
    func start() -> Bool {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            NSLog("Ferry: AI apps can't connect: the socket path is longer than macOS allows (%d bytes): %@", bytes.count, path)
            return false
        }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("Ferry: AI apps can't connect: no socket (%@)", String(cString: strerror(errno)))
            return false
        }
        unlink(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            NSLog("Ferry: AI apps can't connect: couldn't listen at %@ (%@)", path, String(cString: strerror(errno)))
            close(fd)
            unlink(path)
            return false
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { close(fd) }
        queue.sync { listener = source }
        source.resume()
        return true
    }

    func stop() {
        let wasListening: Bool = queue.sync {
            let was = listener != nil
            listener?.cancel()
            listener = nil
            for c in connections.values { c.close() }
            return was
        }
        if wasListening { unlink(path) }
    }

    func disconnect(chat: UUID) {
        queue.async { self.connections.values.first { $0.chat == chat }?.close() }
    }

    private func acceptAll(_ listening: Int32) {
        while true {
            let fd = accept(listening, nil, nil)
            guard fd >= 0 else { return }
            var peer = uid_t(0), group = gid_t(0)
            guard getpeereid(fd, &peer, &group) == 0, peer == uid else {
                close(fd)
                continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                close(fd)
                continue
            }
            let c = Connection(fd: fd, server: self)
            connections[ObjectIdentifier(c)] = c
            c.begin()
        }
    }
}

private final class Connection: @unchecked Sendable {
    let fd: Int32
    let server: AssistantServer
    private(set) var chat: UUID?
    private var reader: DispatchSourceRead
    private var writer: DispatchSourceWrite
    private var writerRunning = false
    private var sourcesOpen = 2
    private var input = Data()
    private var output = Data()
    private var sent = 0
    private var pending: [[String: Any]] = []
    private var busy = false
    private var closed = false

    init(fd: Int32, server: AssistantServer) {
        self.fd = fd
        self.server = server
        reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: server.queue)
        writer = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: server.queue)
    }

    func begin() {
        let done = { [self] in
            sourcesOpen -= 1
            if sourcesOpen == 0 { Darwin.close(fd) }
        }
        reader.setEventHandler { [self] in read() }
        reader.setCancelHandler(handler: done)
        writer.setEventHandler { [self] in flush() }
        writer.setCancelHandler(handler: done)
        reader.resume()
    }

    func close() {
        guard !closed else { return }
        closed = true
        if !writerRunning { writer.resume() }
        reader.cancel()
        writer.cancel()
        server.connections[ObjectIdentifier(self)] = nil
        if let chat {
            let server = server
            Task { @MainActor in server.handler.end(chat) }
        }
    }

    private func read() {
        let n = server.readBuffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n < 0, errno == EAGAIN || errno == EINTR { return }
        guard n > 0 else { return close() }
        let chunk = server.readBuffer[..<n]
        input.append(contentsOf: chunk)
        guard chunk.contains(10) || input.count > AssistantWire.maxLine else { return }
        pending += AssistantWire.decodeLines(&input)
        next()
    }

    private func next() {
        while !busy, !closed, !pending.isEmpty { handle(pending.removeFirst()) }
    }

    private func handle(_ msg: [String: Any]) {
        let id = msg["id"]
        if chat == nil, msg.isEmpty { return close() }
        switch msg["op"] as? String {
        case "hello":
            guard chat == nil else { return send(Self.failure(id, "This connection already said hello; one connection is one chat.")) }
            let chat = UUID(), client = AssistantServer.clientName(msg["client"])
            self.chat = chat
            busy = true
            let server = server
            Task { @MainActor in
                server.handler.open(chat, client)
                server.queue.async { [self] in
                    busy = false
                    send(["op": "hello", "instructions": server.handler.instructions])
                    next()
                }
            }
        case "tools":
            send(["op": "tools", "tools": server.handler.tools])
        case "call":
            guard let chat else { return send(Self.failure(id, "Say hello first: {\"op\":\"hello\",\"client\":\"<app name>\"}.")) }
            guard let tool = msg["tool"] as? String else { return send(Self.failure(id, "A call needs \"tool\", the action's name.")) }
            guard let args = (msg["args"] ?? [String: Any]()) as? [String: Any] else {
                return send(Self.failure(id, "\"args\" must be a JSON object."))
            }
            busy = true
            let server = server
            Task { @MainActor in
                let r = await server.handler.call(chat, tool, args)
                server.queue.async { [self] in
                    busy = false
                    var reply: [String: Any] = ["op": "result", "isError": r.isError, "content": r.content]
                    if let id { reply["id"] = id }
                    send(reply)
                    next()
                }
            }
        case let op:
            send(Self.failure(id, msg.isEmpty
                ? "Ferry couldn't read that line. Send one JSON object per line, under 8 MB."
                : "Ferry has no op “\(op ?? "")”. Ops: hello, tools, call."))
        }
    }

    private static func failure(_ id: Any?, _ text: String) -> [String: Any] {
        var r: [String: Any] = ["op": "result", "isError": true, "content": [["type": "text", "text": text]]]
        if let id { r["id"] = id }
        return r
    }

    private func send(_ obj: [String: Any]) {
        guard !closed else { return }
        output.append(AssistantWire.encode(obj))
        flush()
    }

    private func flush() {
        while sent < output.count {
            let n = output.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, $0.count - sent) }
            if n > 0 {
                sent += n
            } else if n < 0, errno == EINTR {
                continue
            } else if n < 0, errno == EAGAIN {
                if !writerRunning { writer.resume(); writerRunning = true }
                return
            } else {
                return close()
            }
        }
        output = Data()
        sent = 0
        if writerRunning { writer.suspend(); writerRunning = false }
    }
}
