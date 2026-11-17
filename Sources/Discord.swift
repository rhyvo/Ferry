import AppKit
import Darwin
import Foundation

private struct DetectableApp: Decodable {
    struct Executable: Decodable {
        let os: String?
        let name: String
    }
    let id: String
    let name: String
    let aliases: [String]?
    let executables: [Executable]?
}

actor DiscordCatalog {
    static let shared = DiscordCatalog()

    private var byPath: [String: String] = [:]
    private var byExe: [String: String] = [:]
    private var byTitle: [String: String] = [:]
    private var names: [String: String] = [:]
    private var loaded = false

    private let file = Paths.cache.appendingPathComponent("discord-games.json")
    private let source = URL(string: "https://discord.com/api/v9/applications/detectable")

    func match(exe: URL, title: String) async -> (id: String, name: String)? {
        await loadIfNeeded()
        let path = exe.path.lowercased()
        let parts = path.split(separator: "/")
        if parts.count >= 2 {
            let key = "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            if let id = byPath[key] { return (id, names[id] ?? title) }
        }
        if let file = parts.last, let id = byExe[String(file)] { return (id, names[id] ?? title) }
        if let id = byTitle[Self.normalize(title)] { return (id, names[id] ?? title) }
        return nil
    }

    private func loadIfNeeded() async {
        if loaded { return }
        let fm = FileManager.default
        let age = (try? fm.attributesOfItem(atPath: file.path)[.modificationDate] as? Date).map { Date().timeIntervalSince($0) }
        if age == nil || age! > 7 * 24 * 3600, let source,
           let fresh = try? await URLSession.shared.data(from: source).0, fresh.count > 1000 {
            try? fresh.write(to: file, options: .atomic)
        }
        guard let data = try? Data(contentsOf: file),
              let apps = try? JSONDecoder().decode([DetectableApp].self, from: data) else { return }
        index(apps)
        loaded = true
    }

    private func index(_ apps: [DetectableApp]) {
        var exeCount: [String: Int] = [:]
        var exeOwner: [String: String] = [:]
        for app in apps {
            names[app.id] = app.name
            byTitle[Self.normalize(app.name)] = app.id
            for alias in app.aliases ?? [] { byTitle[Self.normalize(alias)] = app.id }
            for exe in app.executables ?? [] where (exe.os ?? "win32") == "win32" {
                var name = exe.name.lowercased()
                while name.hasPrefix(">") { name.removeFirst() }
                let parts = name.split(separator: "/")
                if parts.count >= 2 {
                    byPath["\(parts[parts.count - 2])/\(parts[parts.count - 1])"] = app.id
                }
                if let last = parts.last {
                    exeCount[String(last), default: 0] += 1
                    exeOwner[String(last)] = app.id
                }
            }
        }
        for (exe, count) in exeCount where count == 1 { byExe[exe] = exeOwner[exe] }
    }

    static func normalize(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

actor DiscordRPC {
    static let shared = DiscordRPC()

    private var socket: Int32 = -1
    private var connectedID: String? = nil

    func setActivity(clientID: String, details: String?, state: String, start: Date,
                     largeImage: String? = nil, largeText: String? = nil) {
        if connectedID != clientID {
            disconnect()
            guard connect(clientID: clientID) else { return }
        }
        var activity: [String: Any] = [
            "state": state,
            "timestamps": ["start": Int(start.timeIntervalSince1970)],
        ]
        if let details { activity["details"] = details }
        if let largeImage { activity["assets"] = ["large_image": largeImage, "large_text": largeText ?? ""] }
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(getpid()), "activity": activity],
            "nonce": UUID().uuidString,
        ]
        if !send(op: 1, payload) {
            disconnect()
        } else {
            _ = receive()
        }
    }

    func clear() {
        guard socket >= 0 else { return }
        let payload: [String: Any] = ["cmd": "SET_ACTIVITY", "args": ["pid": Int(getpid())], "nonce": UUID().uuidString]
        _ = send(op: 1, payload)
        _ = receive()
        disconnect()
    }

    private func connect(clientID: String) -> Bool {
        for index in 0..<10 {
            let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("discord-ipc-\(index)")
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(fd); continue }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: bytes) }
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { Darwin.close(fd); continue }

            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            socket = fd
            guard send(op: 0, ["v": 1, "client_id": clientID]), receive() != nil else {
                disconnect()
                return false
            }
            connectedID = clientID
            return true
        }
        return false
    }

    private func disconnect() {
        if socket >= 0 { Darwin.close(socket) }
        socket = -1
        connectedID = nil
    }

    private func send(op: UInt32, _ object: [String: Any]) -> Bool {
        guard socket >= 0, let json = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var frame = Data()
        withUnsafeBytes(of: op.littleEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(json)
        return frame.withUnsafeBytes { raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(socket, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private func receive() -> Data? {
        guard socket >= 0 else { return nil }
        var header = [UInt8](repeating: 0, count: 8)
        guard Darwin.read(socket, &header, 8) == 8 else { return nil }
        let length = Int(header[4]) | Int(header[5]) << 8 | Int(header[6]) << 16 | Int(header[7]) << 24
        guard length > 0, length < 1_000_000 else { return Data() }
        var body = [UInt8](repeating: 0, count: length)
        var got = 0
        while got < length {
            let n = body.withUnsafeMutableBytes { Darwin.read(socket, $0.baseAddress!.advanced(by: got), length - got) }
            if n <= 0 { return nil }
            got += n
        }
        return Data(body)
    }
}

extension AppModel {
    func discordGameStarted(_ g: Game) {
        guard UserDefaults.standard.object(forKey: "discordPresence") as? Bool ?? true, g.settings.showOnDiscord else {
            discordCurrent = nil
            Task.detached { await DiscordRPC.shared.clear() }
            return
        }
        let exe = URL(fileURLWithPath: g.exePath)
        let fallbackID = (UserDefaults.standard.string(forKey: "discordFallbackID") ?? "").trimmingCharacters(in: .whitespaces)
        let start = Date()
        discordCurrent = g.id
        Task.detached {
            if let app = await DiscordCatalog.shared.match(exe: exe, title: g.name) {
                await DiscordRPC.shared.setActivity(clientID: app.id, details: nil, state: "Playing through Ferry on Mac", start: start)
            } else if !fallbackID.isEmpty {
                await DiscordRPC.shared.setActivity(clientID: fallbackID, details: g.name, state: "Playing through Ferry on Mac",
                                                    start: start, largeImage: "ferry", largeText: "Ferry")
            }
        }
    }

    func discordGameEnded(_ id: UUID) {
        guard discordCurrent == id else { return }
        discordCurrent = nil
        if let other = running.first(where: { $0 != id }), let g = game(other) {
            discordGameStarted(g)
        } else if !discordShowFerry() {
            Task.detached { await DiscordRPC.shared.clear() }
        }
    }

    static let launchedAt = Date()

    @discardableResult
    func discordShowFerry() -> Bool {
        let defaults = UserDefaults.standard
        let fallbackID = (defaults.string(forKey: "discordFallbackID") ?? "").trimmingCharacters(in: .whitespaces)
        guard defaults.object(forKey: "discordPresence") as? Bool ?? true,
              defaults.object(forKey: "discordShowFerry") as? Bool ?? true,
              !fallbackID.isEmpty, discordCurrent == nil, running.isEmpty else { return false }
        let count = games.count
        let start = Self.launchedAt
        Task.detached {
            await DiscordRPC.shared.setActivity(clientID: fallbackID, details: "Browsing the library",
                                                state: count == 1 ? "1 game" : "\(count) games",
                                                start: start, largeImage: "ferry", largeText: "Ferry")
        }
        return true
    }

    func startDiscordStatus() {
        Task {
            while true {
                if !discordShowFerry() && discordCurrent == nil && running.isEmpty {
                    await DiscordRPC.shared.clear()
                }
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func saveIconForDiscord() {
        guard let tiff = NSApp.applicationIconImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Ferry icon.png")
        do {
            try png.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = "Couldn't save the icon: \(error.localizedDescription)"
        }
    }
}
