import Darwin
import Foundation
import IOKit

struct WindowsProcess: Identifiable, Equatable {
    let id: Int32
    let name: String
    let commandLine: String
    let prefix: String?
    let memory: UInt64
    let cpuNanoseconds: UInt64

    var isWineSystem: Bool { TaskList.isWineSystem(name: name, commandLine: commandLine) }
}

enum TaskList {
    enum Owner: Hashable {
        case game(UUID, kind: String)
        case setup(kind: String)
        case other(String)
    }

    private static let wineSystemPrograms: Set<String> = [
        "services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe", "rpcss.exe", "conhost.exe",
        "winemenubuilder.exe", "wineboot.exe", "tabtip.exe", "start.exe",
    ]

    static func isWineSystem(name: String, commandLine: String) -> Bool {
        let lower = name.lowercased()
        if lower == "explorer.exe" { return commandLine.lowercased().contains("/desktop") }
        return wineSystemPrograms.contains(lower)
    }

    static func programName(_ commandLine: String) -> String? {
        let line = commandLine.trimmingCharacters(in: .whitespaces)
        let path: Substring
        if line.hasPrefix("\"") {
            path = line.dropFirst().prefix { $0 != "\"" }
        } else if let exe = line.range(of: ".exe", options: .caseInsensitive) {
            path = line[..<exe.upperBound]
        } else if !line.hasPrefix("/"), let first = line.split(separator: " ").first {
            path = first
        } else {
            return nil
        }
        let name = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    static func owner(ofPrefix prefix: String, root: String) -> Owner {
        let base = root.hasSuffix("/") ? root : root + "/"
        guard prefix.hasPrefix(base) else { return .other(prefix) }
        let parts = prefix.dropFirst(base.count).split(separator: "/").map(String.init)
        func kind(_ folder: String) -> String? {
            guard folder.hasPrefix("windows-") else { return nil }
            let rest = folder.dropFirst("windows-".count)
            return String(rest.hasSuffix(".building") ? rest.dropLast(".building".count) : rest)
        }
        if parts.count >= 3, parts[0] == "Bottles", let id = UUID(uuidString: parts[1]), let k = kind(parts[2]) {
            return .game(id, kind: k)
        }
        if parts.count >= 2, parts[0] == "Templates", let k = kind(parts[1]) { return .setup(kind: k) }
        return .other(prefix)
    }

    static func parseProcArgs(_ bytes: [UInt8]) -> (args: [String], env: [String: String]) {
        guard bytes.count > 4 else { return ([], [:]) }
        let argc = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        var i = 4
        while i < bytes.count && bytes[i] != 0 { i += 1 }
        while i < bytes.count && bytes[i] == 0 { i += 1 }
        func next() -> String? {
            guard i < bytes.count else { return nil }
            let start = i
            while i < bytes.count && bytes[i] != 0 { i += 1 }
            let text = String(decoding: bytes[start..<i], as: UTF8.self)
            i += 1
            return text
        }
        var args: [String] = []
        while args.count < argc, let a = next() { args.append(a) }
        var env: [String: String] = [:]
        while let entry = next(), !entry.isEmpty {
            if let eq = entry.firstIndex(of: "=") { env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...]) }
        }
        return (args, env)
    }

    static func serverName(forPrefix path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return "server-" + String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16) + "-" + String(info.st_ino, radix: 16)
    }

    static func snapshot(root: String, prefixes: [String]) -> [WindowsProcess] {
        var byServer: [String: String] = [:]
        for prefix in prefixes { if let name = serverName(forPrefix: prefix) { byServer[name] = prefix } }
        let engines = (root.hasSuffix("/") ? root : root + "/") + "Runtimes/"
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let me = getuid()
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        var found: [WindowsProcess] = []
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0, bsd.pbi_uid == me,
                  executablePath(pid)?.hasPrefix(engines) == true, let bytes = procArgs(pid) else { continue }
            let line = parseProcArgs(bytes).args.joined(separator: " ")
            guard let name = programName(line) else { continue }
            var info = proc_taskinfo()
            _ = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            let ticks = info.pti_total_user + info.pti_total_system
            found.append(WindowsProcess(id: pid, name: name, commandLine: line,
                                        prefix: serverFolder(pid).flatMap { byServer[$0] } ?? currentFolder(pid).flatMap { environment(containing: $0, root: root) },
                                        memory: info.pti_resident_size,
                                        cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))))
        }
        return found
    }

    static func environment(containing folder: String, root: String) -> String? {
        let base = root.hasSuffix("/") ? root : root + "/"
        guard folder.hasPrefix(base) else { return nil }
        let parts = folder.dropFirst(base.count).split(separator: "/", omittingEmptySubsequences: true)
        let depth = parts.first == "Bottles" ? 3 : parts.first == "Templates" ? 2 : 0
        guard depth > 0, parts.count >= depth, parts[depth - 1].hasPrefix("windows-") else { return nil }
        return base + parts.prefix(depth).joined(separator: "/")
    }

    private static func currentFolder(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }

    private static func serverFolder(_ pid: Int32) -> String? {
        var address: UInt64 = 0
        var info = proc_regionwithpathinfo()
        while proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, Int32(MemoryLayout<proc_regionwithpathinfo>.size)) > 0 {
            let path = withUnsafeBytes(of: info.prp_vip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if let wine = path.range(of: "/.wine-"), let server = path.range(of: "/server-", range: wine.upperBound..<path.endIndex) {
                return "server-" + path[server.upperBound...].prefix { $0 != "/" }
            }
            let next = info.prp_prinfo.pri_address + info.prp_prinfo.pri_size
            guard next > address else { break }
            address = next
        }
        return nil
    }

    private static func procArgs(_ pid: Int32) -> [UInt8]? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }

    static func gpuSnapshot() -> (times: [Int32: UInt64], devicePercent: Int?) {
        var times: [Int32: UInt64] = [:]
        var device: Int?
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS
        else { return ([:], nil) }
        defer { IOObjectRelease(accelerators) }
        func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        var accelerator = IOIteratorNext(accelerators)
        while accelerator != 0 {
            if let stats = property(accelerator, "PerformanceStatistics") as? [String: Any],
               let percent = (stats["Device Utilization %"] as? NSNumber)?.intValue {
                device = max(device ?? 0, percent)
            }
            var clients: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS {
                var client = IOIteratorNext(clients)
                while client != 0 {
                    if let creator = property(client, "IOUserClientCreator") as? String, let pid = gpuClientPID(creator),
                       let usage = property(client, "AppUsage") as? [[String: Any]] {
                        for entry in usage {
                            if let ns = entry["accumulatedGPUTime"] as? NSNumber { times[pid, default: 0] += ns.uint64Value }
                        }
                    }
                    IOObjectRelease(client)
                    client = IOIteratorNext(clients)
                }
                IOObjectRelease(clients)
            }
            IOObjectRelease(accelerator)
            accelerator = IOIteratorNext(accelerators)
        }
        return (times, device)
    }

    static func gpuClientPID(_ creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        return Int32(creator.dropFirst(4).prefix { $0.isNumber })
    }
}
