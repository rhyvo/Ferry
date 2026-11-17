import Foundation

struct LogFinding: Identifiable, Equatable {
    enum Fix: Equatable {
        case library(Component)
        case engine(EngineID)
        case webView2
        case none
    }
    let id: String
    let title: String
    let detail: String
    let fix: Fix
    let evidence: String

    var switchesEngine: Bool { if case .engine = fix { return true } else { return false } }
}

enum LogDoctor {
    static func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return "" }
        let part = 512 * 1024
        if data.count <= 2 * part { return String(decoding: data, as: UTF8.self) }
        return String(decoding: data.prefix(part), as: UTF8.self) + "\n" + String(decoding: data.suffix(part), as: UTF8.self)
    }

    static func diagnose(_ log: String, next: EngineID?) -> [LogFinding] {
        var findings: [LogFinding] = []
        var missing: [String: (dlls: [String], line: String)] = [:]
        var order: [String] = []
        func add(_ f: LogFinding) { if !findings.contains(where: { $0.id == f.id }) { findings.append(f) } }

        for raw in log.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let lower = line.lowercased()

            if lower.contains("err:module:import_dll"), lower.contains("not found"),
               let dll = capture(line, #"Library (\S+?\.dll)"#),
               !isWindowsTool(capture(line, #"needed by L?"([^"]+)""#)) {
                let key = missingKey(dll)
                if missing[key] == nil { missing[key] = ([], line); order.append(key) }
                if !missing[key]!.dlls.contains(where: { $0.caseInsensitiveCompare(dll) == .orderedSame }) { missing[key]!.dlls.append(dll) }
            }
            if lower.contains("err:module:import_dll"), lower.contains("c000007b"), let dll = capture(line, #"Loading library (\S+?\.dll)"#) {
                add(LogFinding(id: "arch", title: "\(dll) is the wrong kind for this game",
                               detail: "The game found a 32-bit copy of \(dll) where it needs a 64-bit one, or the other way round. It's usually a file that was copied into the game's folder by hand: remove it, or replace it with the right version.",
                               fix: .none, evidence: line))
            }
            if (lower.contains("you must install") && lower.contains(".net")) || (lower.contains("hostfxr.dll") && lower.contains("not found")) {
                add(library(.dotNetModern, "The game needs .NET 6 or 8", "It's built on Microsoft's newer .NET, which isn't in this game's Windows environment.", line))
            }
            if lower.contains("err:mscoree") && (lower.contains("mono is not installed") || lower.contains("getruntimehost")) {
                add(library(.dotNet48, "The game needs the .NET Framework", "It's a .NET program and this game's Windows environment has no .NET Framework.", line))
            }
            if lower.contains("could not load file or assembly 'microsoft.xna.framework") {
                add(library(.xna, "The game needs the XNA Framework", "It's an XNA game, and XNA isn't in this game's Windows environment.", line))
            }
            if lower.contains("unimplemented function"), let dll = capture(line, #"unimplemented function ([^\s,]+)"#) {
                if let c = component(for: dll.components(separatedBy: ".").first ?? "") {
                    add(library(c, "The game needs \(c.title)", "It called \(dll), which Wine only has a stand-in for.", line))
                } else if let next {
                    add(LogFinding(id: "unimplemented", title: "This engine is missing a Windows function the game uses",
                                   detail: "The game called \(dll), which this engine's Wine doesn't have. Another engine's Wine may.",
                                   fix: .engine(next), evidence: line))
                }
            }
            if lower.contains("webview2"), ["fail", "error", "not found", "0x8007", "0x8000"].contains(where: lower.contains) {
                add(LogFinding(id: "webview2", title: "The launcher couldn't start WebView2",
                               detail: "It shows its window or login page with WebView2, Microsoft's browser engine. Turn on WebView2 for launchers (Ferry installs WebView2 once, about 215 MB, and shares it between games). It doesn't work for every launcher under Wine.",
                               fix: .webView2, evidence: line))
            }
            if ["no adapters found", "vk_error_initialization_failed", "vk_error_incompatible_driver",
                "failed to create d3d device", "d3d11createdevice failed", "vkcreateinstance failed"].contains(where: lower.contains), let next {
                add(LogFinding(id: "graphics", title: "This engine's graphics couldn't start",
                               detail: "The engine couldn't set up DirectX for this game. Engines translate graphics in different ways, so another one may work.",
                               fix: .engine(next), evidence: line))
            }
            if lower.contains("steamapi_init") && (lower.contains("fail") || lower.contains("must be running")) {
                add(LogFinding(id: "steam", title: "The game wants Steam running",
                               detail: "It checks for Steam when it starts. Add Steam to Ferry, then add this game inside Steam's environment and start it from there.",
                               fix: .none, evidence: line))
            }
            if ["easyanticheat", "battleye", "beservice"].contains(where: lower.contains) {
                add(LogFinding(id: "anticheat", title: "The game uses anti-cheat",
                               detail: "Anti-cheat (EasyAntiCheat, BattlEye) doesn't run under Wine on a Mac, so online games that require it usually can't be played. Some let you play offline without it.",
                               fix: .none, evidence: line))
            }
        }

        let others = findings
        findings = []
        for key in order {
            guard let entry = missing[key] else { continue }
            let names = entry.dlls.joined(separator: ", ")
            if let c = Component(rawValue: key) {
                add(library(c, "The game needs \(c.title)", "It couldn't find \(names), which come with \(c.title).", entry.line))
            } else if key == "steam" {
                add(LogFinding(id: "missing-steam", title: "The game's Steam file is missing",
                               detail: "It couldn't find \(names), which normally comes with the game. Check that the whole game folder was copied or extracted.",
                               fix: .none, evidence: entry.line))
            } else {
                add(LogFinding(id: "missing-\(key)", title: "The game is missing \(names)",
                               detail: "This file isn't part of Windows or of a library Ferry installs, so it normally comes with the game. Check that the whole game folder was copied or extracted, or search for what \(names) belongs to.",
                               fix: .none, evidence: entry.line))
            }
        }

        for f in others { add(f) }

        if findings.isEmpty, let next,
           let line = log.split(whereSeparator: \.isNewline).first(where: { $0.contains("wine: Unhandled") }) {
            add(LogFinding(id: "crash", title: "The game crashed",
                           detail: "Windows reported a crash inside the game and the log names no missing file. That usually means this engine can't run it.",
                           fix: .engine(next), evidence: String(line)))
        }
        return findings
    }

    private static func library(_ c: Component, _ title: String, _ why: String, _ line: String) -> LogFinding {
        LogFinding(id: c.rawValue, title: title,
                   detail: "\(why) Ferry can install it into this game's Windows environment (this reinstalls its Windows libraries and can take a few minutes).",
                   fix: .library(c), evidence: line)
    }

    private static func isWindowsTool(_ path: String?) -> Bool {
        let p = (path ?? "").lowercased().replacingOccurrences(of: "\\", with: "/")
        return p.hasPrefix("c:/windows/") || p.hasPrefix("c://windows//")
    }

    private static func missingKey(_ dll: String) -> String {
        let name = dll.lowercased().replacingOccurrences(of: ".dll", with: "")
        if name.hasPrefix("steam_api") { return "steam" }
        return component(for: name)?.rawValue ?? name
    }

    static func component(for dll: String) -> Component? {
        let n = dll.lowercased()
        func starts(_ prefixes: [String]) -> Bool { prefixes.contains(where: n.hasPrefix) }
        if starts(["msvcp", "msvcr", "vcruntime", "mfc", "vcomp", "concrt", "vccorlib", "vcamp", "atl1"]) { return .visualCpp }
        if n == "d3dcompiler_47" { return .shaderCompiler }
        if starts(["d3dx9", "d3dx10", "d3dx11", "xinput1_", "xaudio2_", "x3daudio", "xapofx", "d3dcompiler_", "d3dcsx", "xactengine"]) { return .directX }
        if n == "openal32" || n == "wrap_oal" { return .openAL }
        if starts(["physxloader", "physxcore", "physxcooking", "physxextensions", "nxcooking"]) { return .physX }
        if n == "mscoree" { return .dotNet48 }
        if n == "hostfxr" || n == "hostpolicy" { return .dotNetModern }
        return nil
    }

    private static func capture(_ text: String, _ pattern: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
}

extension AppModel {
    func logFindings(_ g: Game) -> [LogFinding] {
        let current = resolvedEngine(g)
        let order = fallbackOrder(for: g)
        let next = order.firstIndex(of: current).flatMap { $0 + 1 < order.count ? order[$0 + 1] : nil }
            ?? order.first(where: { $0 != current })
        return LogDoctor.diagnose(LogDoctor.read(logURL(g.id, "game")), next: g.sharedWith == nil ? next : nil)
            .filter { !($0.fix == .webView2 && g.settings.webView2) }
    }

    func apply(_ fix: LogFinding.Fix, to id: UUID) {
        switch fix {
        case .library(let c):
            UserDefaults.standard.set(true, forKey: c.defaultsKey)
            reinstallLibraries(id)
        case .engine(let engine):
            guard var g = game(id) else { return }
            g.settings.engine = engine
            update(g)
        case .webView2:
            guard webView2Installed, var g = game(id) else { return }
            g.settings.webView2 = true
            update(g)
        case .none:
            break
        }
    }
}
