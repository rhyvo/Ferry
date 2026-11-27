import Foundation

enum AssistantRuns {

    struct StartFacts {
        var engineTitle = ""
        var engineInstalled = true
        var mullion32 = false
        var metalSharpFullBuild = true
        var mullionTemplateCurrent = true
        var usesDXVK = false
        var dxvkInstalled = true
        var shared = false
        var buildsTemplateOnFirstUse = false
        var hasEnvironment = true
        var hasTemplate = true
        var librariesInstalled = true
        var autoLibraries = true
        var uncachedLibraries: [String] = []
        var x86 = false
        var dgVoodooOn = false, dgVoodooReady = true
        var cncDdrawOn = false, cncDdrawReady = true, cncDdrawZipCached = true, ddrawBesideGame = false
        var directMusicOrPlayOn = false, legacyDirectXReady = true, legacyPackageCached = false
        var dotNetProgram = false
        var dotNet48On = false
        var dotNetInEnvironment: Bool? = false
        var dotNetLoaderReady = true, dotNetPackageCached = false
        var managedDirectXInEnvironment: Bool? = true
        var managedDirectXReady = true, directXPackageCached = true
        var sevenZipInstalled = true
    }

    static func startDownloads(_ f: StartFacts) -> [String] {
        var out: [String] = []
        if !f.engineInstalled { out.append(f.engineTitle) }
        if f.usesDXVK && !f.dxvkInstalled { out.append("DXVK") }
        if f.mullion32 && f.engineInstalled && !f.metalSharpFullBuild { out.append("MetalSharp Wine's build for 32-bit games") }
        let rebuildsMullion = f.mullion32 && (!f.engineInstalled || !f.metalSharpFullBuild || !f.mullionTemplateCurrent)
        let buildsTemplate = rebuildsMullion || (!f.shared && f.buildsTemplateOnFirstUse && !f.hasEnvironment && !f.hasTemplate)
        let environment = f.hasEnvironment && !rebuildsMullion
        let copied = !environment && (f.hasTemplate || buildsTemplate)
        let installsLibraries = f.autoLibraries && !f.shared && !f.librariesInstalled && !copied
        if buildsTemplate || installsLibraries { out += f.uncachedLibraries }
        if f.dgVoodooOn && f.x86 && !f.dgVoodooReady { out.append("dgVoodoo2 (about 7 MB)") }
        if f.cncDdrawOn && !(f.dgVoodooOn && f.x86) && !f.cncDdrawReady && !f.ddrawBesideGame && !f.cncDdrawZipCached {
            out.append("cnc-ddraw (about 2 MB)")
        }
        var unpacks = false
        if f.x86 && f.directMusicOrPlayOn && !f.legacyDirectXReady {
            unpacks = true
            if !f.legacyPackageCached { out.append("DirectMusic and DirectPlay (about 105 MB)") }
        }
        let librariesThisStart = (buildsTemplate || installsLibraries) && f.dotNet48On
        let dotNetThere = librariesThisStart ? nil : f.dotNetInEnvironment
        let managedThere = librariesThisStart ? nil : f.managedDirectXInEnvironment
        if f.dotNetProgram && dotNetThere != false {
            if !f.dotNetLoaderReady {
                unpacks = true
                if !f.dotNetPackageCached { out.append(".NET loader (about 50 MB)") }
            }
            if managedThere != true && !f.managedDirectXReady {
                unpacks = true
                if !f.directXPackageCached { out.append("DirectX (June 2010) for Managed DirectX (about 100 MB)") }
            }
        }
        if unpacks && !f.sevenZipInstalled { out.append("7-Zip (under 1 MB)") }
        return out
    }

    struct WindowInfo: Equatable {
        let id: Int
        let pid: Int32
        let layer: Int
        let width: Double
        let height: Double
    }

    static func windows(from list: [[String: Any]]) -> [WindowInfo] {
        list.compactMap { w in
            guard let id = (w["kCGWindowNumber"] as? NSNumber)?.intValue,
                  let pid = (w["kCGWindowOwnerPID"] as? NSNumber)?.int32Value else { return nil }
            let bounds = w["kCGWindowBounds"] as? [String: Any]
            return WindowInfo(id: id, pid: pid, layer: (w["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0,
                              width: (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0,
                              height: (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    static func pickWindow(_ windows: [WindowInfo], pids: Set<Int32>) -> Int? {
        windows.filter { pids.contains($0.pid) && $0.layer == 0 && $0.width >= 64 && $0.height >= 64 }
            .max { $0.width * $0.height < $1.width * $1.height }?.id
    }

    static func scaledLongestSide(width: Int, height: Int, maxWidth: Int = 1280) -> Int? {
        guard width > maxWidth, width > 0 else { return nil }
        return Int(Double(max(width, height)) * Double(maxWidth) / Double(width))
    }

    enum Until: String, CaseIterable { case started, exited, crash }

    struct GameEnd: Equatable {
        let status: Int32
        let seconds: TimeInterval
        let stoppedByFerry: Bool
        let at: Date

        var crashed: Bool { !stoppedByFerry && status != 0 }
    }

    enum WaitOutcome: Equatable {
        case started, ended(GameEnd), crashedRunning, notStarting, notRunning, startFailed(String)
    }

    static func timeout(_ raw: Any?) -> Int {
        let asked: Double?
        switch raw {
        case let n as NSNumber: asked = n.doubleValue
        case let s as String: asked = Double(s.trimmingCharacters(in: .whitespaces))
        default: asked = nil
        }
        guard let a = asked, a.isFinite else { return 120 }
        return Int(min(600, max(1, a.rounded())))
    }

    static func waitOutcome(_ until: Until, running: Bool, preparing: Bool, ended: GameEnd?, crashInLog: Bool,
                            startFailure: String? = nil) -> WaitOutcome? {
        if let e = ended, !running { return .ended(e) }
        if let f = startFailure, !running, !preparing { return .startFailed(f) }
        switch until {
        case .started:
            if running { return .started }
            if !preparing { return .notStarting }
        case .exited:
            if !running && !preparing { return .notRunning }
        case .crash:
            if running && crashInLog { return .crashedRunning }
            if !running && !preparing { return .notRunning }
        }
        return nil
    }

    static func crashReported(_ log: String) -> Bool {
        log.contains("wine: Unhandled") || log.contains("Unhandled exception")
    }

    static func describe(_ e: GameEnd) -> String {
        let s = Int(e.seconds.rounded())
        let time = s < 120 ? "\(s) second\(s == 1 ? "" : "s")" : "\(s / 60) minutes"
        if e.stoppedByFerry { return "was stopped after \(time)" }
        return e.crashed ? "ended after \(time): it crashed (exit code \(e.status))" : "closed normally after \(time)"
    }

    static func settingsPane(_ name: String) -> (url: String, title: String)? {
        switch name.lowercased() {
        case "battery": return ("x-apple.systempreferences:com.apple.Battery-Settings.extension", "System Settings ▸ Battery")
        case "desktop-dock": return ("x-apple.systempreferences:com.apple.Desktop-Settings.extension", "System Settings ▸ Desktop & Dock")
        case "privacy": return ("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                                "System Settings ▸ Privacy & Security ▸ Screen Recording")
        default: return nil
        }
    }
}
