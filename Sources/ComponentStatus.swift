import AppKit
import UniformTypeIdentifiers

struct ComponentStatus: Equatable {
    var installed: Bool
    var missingFrom: [RuntimeKind] = []
}

extension AppModel {
    func environments(for c: Component) -> [RuntimeKind] {
        let libs = Self.windowsLibraries.filter { $0.component == c }
        return [RuntimeKind.staging, .gptk, .mach9, .arm64, .x64].filter { kind in
            fm.isDirectory(templateURL(kind)) && libs.contains { !($0.needs32bitWine && !kind.supports32bit) }
        }
    }

    func libraryInstalled(_ c: Component, in kind: RuntimeKind) -> Bool {
        let c_ = templateURL(kind).appendingPathComponent("drive_c", isDirectory: true)
        func has(_ path: String) -> Bool { fm.exists(c_.appendingPathComponent(path)) }
        switch c {
        case .dotNet48: return has("windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll") || has("windows/Microsoft.NET/Framework/v4.0.30319/clr.dll")
        case .dotNetModern: return has("Program Files/dotnet/shared/Microsoft.WindowsDesktop.App") || has("Program Files (x86)/dotnet/shared/Microsoft.WindowsDesktop.App")
        case .xna: return has("Program Files (x86)/Common Files/Microsoft Shared/XNA/Framework")
        case .openAL: return has("windows/syswow64/OpenAL32.dll") || has("windows/system32/OpenAL32.dll")
        case .physX: return has("Program Files (x86)/NVIDIA Corporation/PhysX")
        case .lav: return has("Program Files (x86)/LAV Filters/x64/LAVVideo.ax") && (!kind.supports32bit || has("Program Files (x86)/LAV Filters/x86/LAVVideo.ax"))
        case .shaderCompiler:
            return fm.byteSize(c_.appendingPathComponent("windows/system32/d3dcompiler_47.dll")) > 1_000_000
        default: return false
        }
    }

    func computeComponentStatus(_ c: Component) -> ComponentStatus {
        switch c {
        case .metalSharp: return ComponentStatus(installed: runtimes.info[.arm64] != nil)
        case .mach9: return ComponentStatus(installed: runtimes.info[.mach9] != nil)
        case .dxvk: return ComponentStatus(installed: runtimes.info[.dxvk] != nil)
        case .gstreamer: return ComponentStatus(installed: runtimes.gstreamerInstalled)
        case .sevenZip: return ComponentStatus(installed: runtimes.sevenZipInstalled)
        case .cncDdraw: return ComponentStatus(installed: fm.firstItem(under: Paths.cache.appendingPathComponent("cnc-ddraw"),
                                                                      where: { $0.lastPathComponent.lowercased() == "ddraw.dll" }) != nil)
        case .webView2: return ComponentStatus(installed: webView2Folder() != nil)
        case .dxvk3: return ComponentStatus(installed: betaDXVK32() != nil)
        case .d3dmetal4: return ComponentStatus(installed: runtimes.info[.x64] != nil)
        case .dotNet48, .dotNetModern, .xna, .openAL, .physX, .lav, .shaderCompiler:
            let kinds = environments(for: c)
            let missing = kinds.filter { !libraryInstalled(c, in: $0) }
            return ComponentStatus(installed: !kinds.isEmpty && missing.isEmpty, missingFrom: missing.count < kinds.count ? missing : [])
        default: return ComponentStatus(installed: true)
        }
    }

    static let checkableLibraries: [Component] = [.dotNet48, .dotNetModern, .xna, .openAL, .physX, .lav, .shaderCompiler]

    func missingLibraries(in kind: RuntimeKind) -> [Component] {
        guard fm.exists(templateURL(kind).appendingPathComponent("system.reg")) else { return [] }
        let kept = ((try? String(contentsOf: templateURL(kind).appendingPathComponent(".ferry-keep"), encoding: .utf8)) ?? "")
            .split(separator: " ").map(String.init)
        return Self.checkableLibraries.filter { c in
            let places = environments(for: c)
            guard places.contains(kind), !libraryInstalled(c, in: kind) else { return false }
            return Component.isOn(c) || kept.contains(c.rawValue) || places.contains { $0 != kind && libraryInstalled(c, in: $0) }
        }
    }

    func needsFilling(_ kind: RuntimeKind) -> Bool {
        !fm.exists(templateURL(kind).appendingPathComponent(".ferry-filled")) && !missingLibraries(in: kind).isEmpty
    }

    func fillMissingLibraries(_ kind: RuntimeKind) async {
        guard needsFilling(kind), let wine = runtimes.wine(for: kind, arch: .x64) else { return }
        let prefix = templateURL(kind)
        let log = Paths.logs.appendingPathComponent("fill-\(kind.rawValue).log")
        _ = Shell.openLog(log, truncate: true).map { try? $0.close() }
        for c in missingLibraries(in: kind) {
            installingComponent = c
            _ = await installWindowsLibraries(wine: wine, env: baseEnvironment(prefix: prefix), prefix: prefix,
                                              kind: kind, log: log, only: c)
            installingComponent = nil
            refreshComponentStatus()
        }
        if let server = runtimes.wineserver(for: kind) {
            await Shell.run(server.path, ["-w"], env: baseEnvironment(prefix: prefix), log: log)
        }
        try? Data().write(to: prefix.appendingPathComponent(".ferry-filled"))
        report(nil, for: kind)
    }

    func refreshComponentStatus() {
        var all: [Component: ComponentStatus] = [:]
        for c in Component.allCases where c.tier != .required { all[c] = computeComponentStatus(c) }
        componentStatus = all
        webView2Installed = all[.webView2]?.installed ?? false
    }

    func installComponentNow(_ c: Component) {
        guard installingComponent == nil, !setupRunning, !updating else { return }
        installingComponent = c
        if c.tier != .beta { UserDefaults.standard.set(true, forKey: c.defaultsKey) }
        Task {
            defer { installingComponent = nil; status = nil; refreshComponentStatus() }
            do {
                try await install(c)
                refreshComponentStatus()
                if componentStatus[c]?.installed == false {
                    errorMessage = "\(c.title) didn't install completely. Details are in Ferry's Logs folder (\(Paths.logs.path))."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func install(_ c: Component) async throws {
        switch c {
        case .metalSharp: try await runtimes.ensure(.arm64)
        case .mach9: try await runtimes.ensure(.mach9)
        case .dxvk:
            try await runtimes.ensure(.dxvk)
            if fm.isDirectory(templateURL(.staging)) { installDXVK(into: templateURL(.staging)) }
        case .gstreamer: try await runtimes.installGStreamer()
        case .sevenZip: try await runtimes.installSevenZip()
        case .cncDdraw:
            if await cncDdrawDLL() == nil { throw FerryError("cnc-ddraw couldn't be downloaded. Check your connection and try again.") }
        case .webView2: try await installWebView2()
        case .dxvk3: try await installBetaDXVK()
        case .d3dmetal4: try await runtimes.ensure(.x64)
        default:
            let log = Paths.logs.appendingPathComponent("install-\(c.rawValue).log")
            _ = Shell.openLog(log, truncate: true).map { try? $0.close() }
            for kind in environments(for: c) where !libraryInstalled(c, in: kind) {
                guard let wine = runtimes.wine(for: kind, arch: .x64) else { continue }
                let prefix = templateURL(kind)
                let skipped = await installWindowsLibraries(wine: wine, env: baseEnvironment(prefix: prefix), prefix: prefix,
                                                            kind: kind, log: log, only: c)
                if !skipped.isEmpty {
                    throw FerryError("\(skipped.joined(separator: ", ")) couldn't be downloaded. Check your connection and try again.")
                }
            }
        }
    }
}
