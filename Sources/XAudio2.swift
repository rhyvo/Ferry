import Foundation

@MainActor
enum XAudio2Usage {
    private nonisolated static let classIDs: [(version: Int, id: String)] = [
        (0, "fac23f48-31f5-45a8-b49b-5225d61401aa"), (1, "e21a7345-eb21-468e-be50-804db97cf708"),
        (2, "b802058a-464a-42db-bc10-b650d6f2586a"), (3, "4c5e637a-16c7-4de3-9c46-5ed22181962d"),
        (4, "03219e78-5bc3-44d1-b92e-f63d89cc6526"), (5, "4c9b6dde-6809-46e6-a278-9b6a97588670"),
        (6, "3eda9b49-2085-498b-9bb2-39a6778493de"), (7, "5a508685-a254-4fba-9b82-9a24b00306af"),
    ]
    private static var cache: [String: [Int]] = [:]
    private static var reading: Set<String> = []

    static func versions(in exe: URL) -> [Int] {
        let files = files(of: exe)
        for f in files where cache[f.key] == nil { cache[f.key] = versions(inFile: f.url) }
        return merged(files)
    }

    static func knownVersions(in exe: URL, whenRead: @escaping @MainActor () -> Void) -> [Int]? {
        let files = files(of: exe)
        let missing = files.filter { cache[$0.key] == nil }
        if missing.isEmpty { return merged(files) }
        let keys = Set(missing.map(\.key))
        guard reading.isDisjoint(with: keys) else { return nil }
        reading.formUnion(keys)
        let urls = missing.map(\.url)
        Task.detached {
            let found = urls.map { versions(inFile: $0) }
            await MainActor.run {
                for (f, versions) in zip(missing, found) { cache[f.key] = versions }
                reading.subtract(keys)
                whenRead()
            }
        }
        return nil
    }

    private static func merged(_ files: [(url: URL, key: String)]) -> [Int] {
        Array(Set(files.flatMap { cache[$0.key] ?? [] })).sorted()
    }

    private static func files(of exe: URL) -> [(url: URL, key: String)] {
        let dlls = ((try? FileManager.default.contentsOfDirectory(at: exe.deletingLastPathComponent(),
                                                                  includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "dll" }
            .sorted { $0.path < $1.path }
        return ([exe] + dlls.prefix(300)).map { url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (url, url.path + "|" + String(modified?.timeIntervalSince1970 ?? 0))
        }
    }

    private nonisolated static func versions(inFile url: URL) -> [Int] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let program = 0..<programEnd(data)
        return classIDs.filter { data.range(of: guidBytes($0.id), in: program) != nil }.map(\.version)
    }

    nonisolated static func programEnd(_ data: Data) -> Int {
        func u16(_ at: Int) -> Int? { at + 2 <= data.count ? Int(data[at]) | Int(data[at + 1]) << 8 : nil }
        func u32(_ at: Int) -> Int? { guard let lo = u16(at), let hi = u16(at + 2) else { return nil }; return lo | hi << 16 }
        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x0000_4550,
              let count = u16(pe + 6), let optional = u16(pe + 20) else { return data.count }
        let table = pe + 24 + optional
        var end = 0
        for i in 0..<count {
            guard let size = u32(table + i * 40 + 16), let start = u32(table + i * 40 + 20) else { return data.count }
            end = max(end, start + size)
        }
        return end > 0 ? min(end, data.count) : data.count
    }

    private nonisolated static func guidBytes(_ text: String) -> Data {
        guard let u = UUID(uuidString: text) else { return Data() }
        let b = withUnsafeBytes(of: u.uuid) { Array($0) }
        return Data([b[3], b[2], b[1], b[0], b[5], b[4], b[7], b[6]] + b[8...])
    }
}

extension AppModel {
    func nativeXAudio2Overrides(_ g: Game, engine: EngineID, prefix: URL) -> [String] {
        guard g.settings.nativeXAudio2, engine.runtime != .gptk else { return [] }
        let folder = "drive_c/windows/" + (g.arch == .x86 ? "syswow64" : "system32")
        return XAudio2Usage.versions(in: URL(fileURLWithPath: g.exePath)).compactMap { version in
            let name = "\(folder)/xaudio2_\(version).dll"
            let target = prefix.appendingPathComponent(name)
            if !isMicrosoftDLL(target) {
                let source = templateURL(.staging).appendingPathComponent(name)
                guard isMicrosoftDLL(source) else { return nil }
                fm.removeIfPresent(target)
                guard (try? fm.copyItem(at: source, to: target)) != nil else { return nil }
            }
            return "xaudio2_\(version)=n,b"
        }
    }

    private func isMicrosoftDLL(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return false }
        return data.range(of: Data("Wine builtin DLL".utf8)) == nil && data.range(of: Data("Wine placeholder DLL".utf8)) == nil
            && data.range(of: "Microsoft Corporation".data(using: .utf16LittleEndian)!) != nil
    }

    func usesSDKXAudio2(_ g: Game) -> Bool {
        guard runtimeKind(g) != .gptk else { return false }
        let versions = XAudio2Usage.knownVersions(in: URL(fileURLWithPath: g.exePath)) { [weak self] in self?.objectWillChange.send() }
        return !(versions ?? []).isEmpty
    }
}
