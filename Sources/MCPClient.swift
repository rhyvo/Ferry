import Foundation

struct MCPClientError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

final class MCPClient: @unchecked Sendable {
    let config: MCPServerConfig
    static let startTimeout: TimeInterval = 20
    static let callTimeout: TimeInterval = 120

    private let process = Process()
    private let stdin: Pipe, stdout = Pipe(), stderr = Pipe()
    private let lock = NSLock()
    private let input: Input
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var buffer = Data()
    private var errorTail = Data()
    private var gone: String? = nil
    private var toolNames: [String: String] = [:]

    init(config: MCPServerConfig) {
        self.config = config
        let pipe = Pipe()
        stdin = pipe
        input = Input(pipe.fileHandleForWriting)
    }

    deinit { stop() }

    func start() async throws -> [ChatToolSpec] {
        let command = (config.command.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !command.isEmpty else { throw MCPClientError("it has no command.") }
        let arguments = MCPServerConfig.expandingHome(config.arguments, home: NSHomeDirectory())
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin") + ":/opt/homebrew/bin:/usr/local/bin"
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in self?.readError(h.availableData) }
        process.terminationHandler = { [weak self] p in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { self?.fail("it stopped (exit code \(p.terminationStatus))") }
        }
        do { try process.run() } catch {
            stop()
            throw MCPClientError("Ferry couldn't run \(config.command): \(error.localizedDescription)")
        }
        let deadline = Date(timeIntervalSinceNow: Self.startTimeout)
        func left() -> TimeInterval { max(0.1, deadline.timeIntervalSinceNow) }
        _ = try await request({ MCPClientWire.initialize(id: $0) }, timeout: left())
        send(MCPClientWire.initialized())
        var specs: [ChatToolSpec] = []
        var names: [String: String] = [:]
        var cursor: String? = nil
        for _ in 0..<20 {
            let result = try await request({ MCPClientWire.toolsList(id: $0, cursor: cursor) }, timeout: left())
            let scrub = { AssistantText.scrub($0, home: NSHomeDirectory(), user: NSUserName(), gameFolder: nil) }
            for t in MCPClientWire.named(from: result, server: config.name, scrub: scrub) where names[MCPClientWire.split(t.spec.name)!.tool] == nil {
                names[MCPClientWire.split(t.spec.name)!.tool] = t.tool
                specs.append(t.spec)
            }
            cursor = result["nextCursor"] as? String
            if cursor?.isEmpty ?? true { break }
        }
        lock.withLock { toolNames = names }
        return specs
    }

    func call(_ tool: String, arguments: [String: Any]) async throws -> (text: String, isError: Bool) {
        guard let own = lock.withLock({ toolNames[tool] }) else {
            return ("\(config.name) has no tool called \(tool).", true)
        }
        do {
            let result = try await request({ MCPClientWire.call(id: $0, name: own, arguments: arguments) }, timeout: Self.callTimeout)
            return MCPClientWire.output(from: result)
        } catch let e as MCPClientError {
            return ("\(config.name)'s \(tool) failed: \(e.message)", true)
        }
    }

    func stop() {
        fail("it was stopped")
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        let input = self.input
        DispatchQueue.global().async { input.close() }
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func request(_ make: (Int) -> [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let id: Int = lock.withLock { defer { nextID += 1 }; return nextID }
        let message = make(id)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: Any], Error>) in
                let why: String? = lock.withLock {
                    if let gone { return gone }
                    pending[id] = c
                    return nil
                }
                if let why { c.resume(throwing: MCPClientError(reason(why))); return }
                if Task.isCancelled { resolve(id, .failure(CancellationError())); return }
                send(message)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.resolve(id, .failure(MCPClientError("it took longer than \(Int(timeout)) seconds to answer.")))
                }
            }
        } onCancel: {
            resolve(id, .failure(CancellationError()))
        }
    }

    private func resolve(_ id: Int, _ r: Result<[String: Any], Error>) {
        lock.withLock { pending.removeValue(forKey: id) }?.resume(with: r)
    }

    private func send(_ obj: [String: Any]) {
        input.write(AssistantWire.encode(obj))
    }

    private func read(_ data: Data) {
        guard !data.isEmpty else { stdout.fileHandleForReading.readabilityHandler = nil; return }
        let lines: [[String: Any]] = lock.withLock {
            buffer.append(data)
            return AssistantWire.decodeLines(&buffer)
        }
        for msg in lines {
            if let method = msg["method"] as? String {
                guard let id = msg["id"] else { continue }
                send(method == "ping" ? MCPProtocol.response(id: id, result: [:])
                     : MCPProtocol.error(id: id, code: -32601, message: "Ferry doesn't offer \(method)."))
            } else if let id = (msg["id"] as? NSNumber)?.intValue {
                if let result = msg["result"] as? [String: Any] {
                    resolve(id, .success(result))
                } else {
                    let message = (msg["error"] as? [String: Any])?["message"] as? String ?? "it sent an answer Ferry couldn't read."
                    resolve(id, .failure(MCPClientError(message)))
                }
            }
        }
    }

    private func readError(_ data: Data) {
        lock.withLock {
            errorTail.append(data)
            if errorTail.count > 2048 { errorTail = errorTail.suffix(2048) }
        }
        if data.isEmpty { stderr.fileHandleForReading.readabilityHandler = nil }
    }

    private func fail(_ why: String) {
        let waiting: [CheckedContinuation<[String: Any], Error>] = lock.withLock {
            if gone == nil { gone = why }
            defer { pending = [:] }
            return Array(pending.values)
        }
        if waiting.isEmpty { return }
        let error = MCPClientError(reason(why))
        for c in waiting { c.resume(throwing: error) }
    }

    private func reason(_ why: String) -> String {
        let tail = lock.withLock { String(decoding: errorTail, as: UTF8.self) }
        let said = tail.split(whereSeparator: \.isNewline).suffix(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return said.isEmpty ? why + "." : "\(why): \(String(said.suffix(300)))"
    }
}

private final class Input: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var closed = false

    init(_ handle: FileHandle) { self.handle = handle }

    func write(_ data: Data) {
        lock.withLock { if !closed { try? handle.write(contentsOf: data) } }
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            try? handle.close()
        }
    }
}

#if !FERRY_RELEASE
extension AssistantDebug {
    @MainActor static func runMCPClientCheck(_ args: [String]) -> Never {
        guard let command = args.first else {
            print("Usage: Ferry --mcp-client-check <command> [args…]")
            exit(1)
        }
        let config = MCPServerConfig(id: UUID(), name: (command as NSString).lastPathComponent, command: command,
                                     arguments: Array(args.dropFirst()), enabled: true)
        let client = MCPClient(config: config)
        final class Box { var out: String?; var code: Int32 = 0 }
        let box = Box()
        Task {
            do {
                let tools = try await client.start()
                box.out = (["\(tools.count) tools"] + tools.prefix(5).map(\.name)).joined(separator: "\n")
            } catch {
                box.out = "\(config.name) didn't start: \((error as? MCPClientError)?.message ?? error.localizedDescription)"
                box.code = 1
            }
        }
        while box.out == nil { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) }
        client.stop()
        print(box.out!)
        exit(box.code)
    }
}
#endif
