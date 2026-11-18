import Foundation

struct PEInfo {
    var arch: PEArch
    var imports: Set<String>
    var isDotNet: Bool
    var is16bit: Bool
}

enum PEParser {
    static func parse(_ url: URL) -> PEInfo? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let bytes = [UInt8](data.prefix(64))
        guard bytes.count >= 64, bytes[0] == 0x4D, bytes[1] == 0x5A else { return nil }

        func u16(_ o: Int) -> Int? {
            guard o >= 0, o + 2 <= data.count else { return nil }
            return Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8
        }
        func u32(_ o: Int) -> Int? {
            guard let lo = u16(o), let hi = u16(o + 2) else { return nil }
            return lo | hi << 16
        }

        guard let pe = u32(0x3C), pe > 0, pe + 24 <= data.count,
              u32(pe) == 0x0000_4550 else {
            return PEInfo(arch: .unknown, imports: [], isDotNet: false, is16bit: true)
        }
        let machine = u16(pe + 4) ?? 0
        let sectionCount = u16(pe + 6) ?? 0
        let optionalSize = u16(pe + 20) ?? 0
        let opt = pe + 24
        let magic = u16(opt) ?? 0
        let arch: PEArch
        switch machine {
        case 0x014C: arch = .x86
        case 0x8664: arch = .x64
        case 0xAA64: arch = .arm64
        default: arch = .unknown
        }

        let is64 = magic == 0x20B
        let dirCount = u32(opt + (is64 ? 108 : 92)) ?? 0
        let dirs = opt + (is64 ? 112 : 96)
        func directory(_ index: Int) -> (rva: Int, size: Int)? {
            guard index < dirCount, let rva = u32(dirs + index * 8), let size = u32(dirs + index * 8 + 4),
                  rva != 0 else { return nil }
            return (rva, size)
        }

        var sections: [(va: Int, size: Int, raw: Int)] = []
        let table = opt + optionalSize
        for i in 0..<min(sectionCount, 96) {
            let s = table + i * 40
            guard let vsize = u32(s + 8), let va = u32(s + 12), let rawSize = u32(s + 16), let raw = u32(s + 20) else { break }
            sections.append((va, vsize > 0 ? vsize : rawSize, raw))
        }
        func offset(_ rva: Int) -> Int? {
            for s in sections where rva >= s.va && rva < s.va + s.size { return rva - s.va + s.raw }
            return nil
        }
        func cString(_ rva: Int) -> String? {
            guard let start = offset(rva), start < data.count else { return nil }
            var end = start
            while end < data.count, end - start < 256, data[data.startIndex + end] != 0 { end += 1 }
            return String(decoding: data[(data.startIndex + start)..<(data.startIndex + end)], as: UTF8.self)
        }

        var imports = Set<String>()
        if let dir = directory(1), var at = offset(dir.rva) {
            for _ in 0..<512 {
                guard let nameRVA = u32(at + 12), let thunk = u32(at) else { break }
                if nameRVA == 0 && thunk == 0 { break }
                if let name = cString(nameRVA) { imports.insert(name.lowercased()) }
                at += 20
            }
        }
        if let dir = directory(13), var at = offset(dir.rva) {
            for _ in 0..<512 {
                guard let nameRVA = u32(at + 4), nameRVA != 0 else { break }
                if let name = cString(nameRVA) { imports.insert(name.lowercased()) }
                at += 32
            }
        }
        let isDotNet = directory(14) != nil
        return PEInfo(arch: arch, imports: imports, isDotNet: isDotNet, is16bit: false)
    }
}

struct Finding: Identifiable, Hashable {
    enum Level: Int { case info, warning, blocker }
    let id = UUID()
    let level: Level
    let text: String
}

struct AnalysisReport {
    enum Verdict { case shouldWork, mightWork, wontWork }

    var exe: URL
    var root: URL
    var name: String
    var arch: PEArch
    var graphics: GraphicsAPI
    var framework: String?
    var isInstaller: Bool
    var libraries: [String]
    var findings: [Finding]
    var engine: EngineID
    var settings: GameSettings
    var reasons: [String]
    var candidates: [URL]
    var candidateLabels: [URL: String] = [:]
    var asksWhichProgram = false

    var verdict: Verdict {
        if findings.contains(where: { $0.level == .blocker }) { return .wontWork }
        if findings.contains(where: { $0.level == .warning }) { return .mightWork }
        return .shouldWork
    }
}

enum Analyzer {

    private static let helperNames = [
        "unins", "uninst", "crashhandler", "crashreport", "crashpad", "unitycrashhandler", "vc_redist", "vcredist",
        "dxsetup", "dxwebsetup", "dotnet", "ndp4", "oalinst", "physx", "ue4prereq", "ueprereq", "prereq",
        "easyanticheat", "beservice", "redist", "update", "updater", "notification_helper", "cefsharp", "quicksfv",
    ]

    struct ProgramCandidate {
        let url: URL
        let role: ProgramRole
        let label: String
        let score: Double
    }

    static func candidates(in root: URL) -> [URL] { rankedPrograms(in: root).map(\.url) }

    static func rankedPrograms(in root: URL) -> [ProgramCandidate] {
        describe(scoredPrograms(in: root), root: root)
    }

    static func describe(_ urls: [URL], root: URL) -> [ProgramCandidate] {
        describe(urls.map { ($0, baseScore($0, root: root)) }, root: root)
    }

    private static func describe(_ scored: [(url: URL, score: Double)], root: URL) -> [ProgramCandidate] {
        let descriptions = scored.map { $0.url.pathExtension.lowercased() == "exe" ? PEVersionInfo.string("FileDescription", in: $0.url) : nil }
        let roles = ProgramChoice.roles(of: zip(scored, descriptions).map { ($0.url.lastPathComponent, $1) })
        return zip(scored, zip(descriptions, roles)).map { program, info in
            ProgramCandidate(url: program.url, role: info.1, label: ProgramChoice.label(fileName: program.url.lastPathComponent,
                             description: info.0, role: info.1), score: program.score + info.1.weight)
        }
        .sorted { $0.score > $1.score }
    }

    private static func baseScore(_ url: URL, root: URL) -> Double {
        let level = max(0, url.pathComponents.count - root.pathComponents.count - 1)
        let folderName = root.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
        return score(url, level: level, folderName: folderName)
    }

    private static func score(_ url: URL, level: Int, folderName: String) -> Double {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let size = Double(FileManager.default.byteSize(url))
        var score = log2(max(size, 1))
        score -= Double(level) * 1.5
        let compact = name.filter { $0.isLetter || $0.isNumber }
        if !folderName.isEmpty, compact.contains(folderName) || folderName.contains(compact) { score += 6 }
        if name.hasSuffix("-shipping") { score += 8 }
        if name.contains("launcher") { score -= 2 }
        if name.contains("setup") || name.contains("install") || ext == "msi" { score -= 1 }
        if ext == "bat" { score -= 6 }
        return score
    }

    private static func scoredPrograms(in root: URL) -> [(url: URL, score: Double)] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(url: URL, score: Double)] = []
        let folderName = root.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > 20_000 { break }
            if walker.level > 5 { walker.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased()
            guard ["exe", "msi", "bat"].contains(ext) else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            if helperNames.contains(where: { name.contains($0) }) { continue }
            found.append((url, score(url, level: walker.level - 1, folderName: folderName)))
        }
        return found
    }

    static func analyze(exe: URL, root: URL, candidates: [URL], rosetta: Bool, knownGraphics: GraphicsAPI? = nil) -> AnalysisReport {
        let fm = FileManager.default
        let dir = exe.deletingLastPathComponent()
        let ext = exe.pathExtension.lowercased()
        let info = ext == "exe" ? PEParser.parse(exe) : nil
        var findings: [Finding] = []
        var reasons: [String] = []
        var libraries: [String] = []
        var settings = GameSettings.defaults()

        let arch = info?.arch ?? (ext == "exe" ? .unknown : .x86)
        let detected = ext == "exe" ? PEInspector.graphicsAPI(for: exe) : .unknown
        var graphics = detected == .unknown ? (knownGraphics ?? .unknown) : detected
        let imports = info?.imports ?? []
        func loads(_ prefix: String) -> Bool { imports.contains { $0.hasPrefix(prefix) } }
        func exists(_ relative: String) -> Bool { fm.exists(dir.appendingPathComponent(relative)) }
        func anyFile(_ test: (String) -> Bool) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).contains { test($0.lowercased()) }
        }
        let exeData = (try? Data(contentsOf: exe, options: .alwaysMapped)).map { fm.byteSize(exe) < 200_000_000 ? $0 : $0.prefix(32_000_000) }
        func exeContains(_ text: String) -> Bool { exeData?.range(of: Data(text.utf8)) != nil }

        let lowerName = exe.deletingPathExtension().lastPathComponent.lowercased()
        let isInstaller = ModLayout.looksLikeInstaller(exe)
        if isInstaller {
            findings.append(Finding(level: .info, text: "This is an installer. Run it, then use Change Executable in its settings to point Ferry at the installed program inside its C: drive."))
        }

        if info?.is16bit == true {
            findings.append(Finding(level: .blocker, text: "This is a 16-bit DOS or Windows 3.x program. Modern Wine can't run those; DOSBox can."))
        }
        if ["msix", "appx", "msixbundle", "appxbundle"].contains(ext) {
            findings.append(Finding(level: .blocker, text: "Microsoft Store packages need the Store and Xbox services, which don't exist outside Windows."))
        }

        let antiCheat: [(String, String)] = [
            ("easyanticheat", "Easy Anti-Cheat"), ("battleye", "BattlEye"), ("beservice", "BattlEye"),
            ("vgk", "Riot Vanguard"), ("xigncode", "XIGNCODE"), ("gameguard", "nProtect GameGuard"),
            ("mhyprot", "miHoYo anti-cheat"), ("eaanticheat", "EA Anti-Cheat"), ("ace-base", "ACE anti-cheat"),
        ]
        let rootItems = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).map { $0.lowercased() }
        let parentItems = ((try? fm.contentsOfDirectory(atPath: dir.deletingLastPathComponent().path)) ?? []).map { $0.lowercased() }
        for (needle, label) in antiCheat where (rootItems + parentItems).contains(where: { $0.contains(needle) }) {
            findings.append(Finding(level: .warning, text: "\(label) found. Anti-cheat usually blocks online play under Wine on Mac; single-player or offline modes may still work."))
            break
        }
        if exeContains("Denuvo") || anyFile({ $0.contains("denuvo") }) {
            findings.append(Finding(level: .info, text: "Denuvo copy protection found. It often works under Wine but can be slow to start the first time."))
        }

        var framework: String? = nil
        if exists("UnityPlayer.dll") || anyFile({ $0.hasSuffix("_data") }) {
            framework = exists("GameAssembly.dll") ? "Unity (IL2CPP)" : "Unity"
        } else if exe.path.contains("/Binaries/Win64/") || lowerName.hasSuffix("-shipping") || anyFile({ $0 == "engine" }) && fm.exists(dir.appendingPathComponent("Engine/Binaries")) {
            framework = "Unreal Engine"
        } else if exists("data.win") {
            framework = "GameMaker"
        } else if anyFile({ $0.hasPrefix("rgss") && $0.hasSuffix(".dll") }) || anyFile({ $0.hasPrefix("game.rgss") }) {
            framework = "RPG Maker XP/VX/VX Ace"
        } else if exists("www/js/rpg_core.js") || exists("js/rmmz_core.js") {
            framework = "RPG Maker MV/MZ"
        } else if exists("resources/app.asar") {
            framework = "Electron"
        } else if exists("nw.dll") || exists("nw_elf.dll") {
            framework = "NW.js"
        } else if anyFile({ $0.hasSuffix(".pck") }) || exeContains("Godot Engine") {
            framework = "Godot"
        } else if exists("renpy") || anyFile({ $0.hasSuffix(".rpa") }) {
            framework = "Ren'Py"
        } else if exists("bin/engine.dll") {
            framework = "Source engine"
        } else if exeContains("Clickteam") || exeContains("mmfs2") || (exeContains("MMF2") && (exeContains("PAMU") || exeContains("PAME"))) {
            framework = "Clickteam Fusion"
            if exeContains("mmf2d3d9") { graphics = .dx9 }
        } else if exeContains("Microsoft.Xna.Framework") || anyFile({ $0.hasPrefix("microsoft.xna.framework") }) {
            framework = "XNA"
        } else if exists("FNA.dll") {
            framework = "FNA"
        } else if exists("MonoGame.Framework.dll") {
            framework = "MonoGame"
        } else if info?.isDotNet == true {
            framework = ".NET"
        }
        if exeContains("launch4j") {
            findings.append(Finding(level: .warning, text: "This .exe is a wrapper around a Java program. It needs Java for Windows installed inside its environment, or run the .jar with Java for Mac instead."))
        }

        let vcVersions: [(String, String)] = [
            ("msvcr71", "Visual C++ 2003"), ("msvcp71", "Visual C++ 2003"),
            ("msvcr80", "Visual C++ 2005"), ("msvcp80", "Visual C++ 2005"),
            ("msvcr90", "Visual C++ 2008"), ("msvcp90", "Visual C++ 2008"),
            ("msvcr100", "Visual C++ 2010"), ("msvcp100", "Visual C++ 2010"),
            ("msvcr110", "Visual C++ 2012"), ("msvcp110", "Visual C++ 2012"),
            ("msvcr120", "Visual C++ 2013"), ("msvcp120", "Visual C++ 2013"),
            ("vcruntime140", "Visual C++ 2015–2022"), ("msvcp140", "Visual C++ 2015–2022"),
        ]
        for (dll, label) in vcVersions where loads(dll) && !libraries.contains(label) { libraries.append(label) }
        if libraries.contains("Visual C++ 2003") {
            findings.append(Finding(level: .warning, text: "Needs Visual C++ 2003, which Ferry doesn't install. Many games ship its DLL themselves, so it may still work."))
        }
        if loads("d3dx9") || loads("d3dx10") || loads("d3dx11") || loads("xinput1_3") || loads("xaudio2_7") || loads("x3daudio") || loads("d3dcompiler_43") {
            libraries.append("DirectX June 2010 extras")
        }
        if info?.isDotNet == true || loads("mscoree") { libraries.append(".NET Framework") }
        if framework == "XNA" { libraries.append("XNA Framework 4.0") }
        if loads("openal32") || exists("OpenAL32.dll") { libraries.append("OpenAL") }
        if loads("physxloader") || loads("physx3") || anyFile({ $0.hasPrefix("physxloader") }) {
            libraries.append("PhysX")
            reasons.append("Uses NVIDIA PhysX: Ferry installs the legacy PhysX runtime that older games expect.")
        }
        if loads("steam_api") || exists("steam_api.dll") || exists("steam_api64.dll") {
            libraries.append("Steam")
            findings.append(Finding(level: .info, text: "Uses Steam. If it was bought on Steam, install Steam in Ferry and run the game through it (or add it to Steam's environment)."))
        }
        if loads("eossdk") { libraries.append("Epic Online Services") }

        var missing: Set<String> = ["Steam", "Epic Online Services", "Visual C++ 2003"]
        if let configName = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).first(where: { $0.lowercased().hasSuffix(".runtimeconfig.json") }) {
            if exists("coreclr.dll") {
                libraries.append(".NET (included with the program)")
            } else if let data = try? Data(contentsOf: dir.appendingPathComponent(configName)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let options = json["runtimeOptions"] as? [String: Any] {
                let frameworks = (options["frameworks"] as? [[String: Any]]) ?? [options["framework"] as? [String: Any]].compactMap { $0 }
                let majors = frameworks.compactMap { ($0["version"] as? String)?.split(separator: ".").first.flatMap { Int($0) } }
                if let major = majors.max() {
                    let label = ".NET \(major)"
                    libraries.append(label)
                    if ![6, 8].contains(major) {
                        missing.insert(label)
                        findings.append(Finding(level: .warning, text: "Needs the \(label) Desktop Runtime. Ferry installs .NET 6 and 8; for \(label), download the Windows x64 Desktop Runtime installer from Microsoft's .NET site and run it inside its Windows environment."))
                    }
                }
            }
        }
        if exists("WebView2Loader.dll") || loads("webview2loader") {
            libraries.append("WebView2")
            findings.append(Finding(level: .info, text: "Uses WebView2 for built-in web pages (often a login screen). If its window or login page is blank, turn on WebView2 for launchers in its settings. It doesn't always work under Wine."))
        }
        if loads("quartz") || loads("mfplat") || anyFile({ [".wmv", ".avi", ".mpg", ".mpeg", ".asf"].contains(where: $0.hasSuffix) }) {
            libraries.append("Windows video playback")
        }

        let pick = EngineAdvisor.pick(arch: arch, graphics: graphics, framework: framework, isExe: ext == "exe", rosetta: rosetta)
        let engine = pick.engine
        reasons.append(pick.reason)
        settings = EngineAdvisor.tune(settings, engine: engine, arch: arch, graphics: graphics, reasons: &reasons)
        settings.engine = .auto
        let drawsWithSomethingNewer = ["d3d8", "d3d9", "d3d10", "d3d11", "d3d12", "opengl32", "vulkan-1"].contains(where: loads)
        if loads("ddraw") && arch == .x86 && !drawsWithSomethingNewer {
            settings.cncDdraw = true
            reasons.append("Uses DirectDraw, the old 2D graphics system: turned on the old 2D game fix (cnc-ddraw), which fixes most slow, flickering or broken DirectDraw games.")
        }

        switch framework ?? "" {
        case "Unreal Engine" where graphics == .dx12:
            reasons.append("Unreal Engine DX12 game: if it crashes on start, add \"-dx11\" as a launch argument.")
        case "Unity" where graphics == .dx12:
            reasons.append("Unity DX12 game: if it crashes or looks wrong, add \"-force-d3d11\" as a launch argument.")
        case "Electron", "NW.js":
            findings.append(Finding(level: .info, text: "\(framework ?? "") apps are built on a web browser engine. If the window stays blank, add \"--disable-gpu\" as a launch argument."))
        case "XNA":
            reasons.append("XNA game: Ferry's Wine Staging environment already has XNA 4.0 and .NET installed.")
        case "RPG Maker MV/MZ":
            findings.append(Finding(level: .info, text: "RPG Maker MV/MZ games are web-based; many also run natively on Mac with NW.js for Mac."))
        default:
            break
        }

        if graphics == .dx8 || libraries.contains("Visual C++ 2003") {
            settings.windowsVersion = "win7"
            reasons.append("Older game (DirectX 8 era): reports Windows 7, which older games accept more readily than Windows 10.")
        }
        if framework == "Clickteam Fusion" || framework == "GameMaker" || framework?.hasPrefix("RPG Maker") == true {
            reasons.append("\(framework ?? "") games are lightweight 2D games and usually run well.")
        }
        let provided = libraries.filter { !missing.contains($0) }
        if !provided.isEmpty {
            reasons.append("Already in Ferry's Windows environments: \(provided.joined(separator: ", ")).")
        }

        let name = Naming.friendlyName(for: exe)
        let described = candidates.count > 1 ? describe(candidates, root: root) : []
        let labels = Dictionary(described.map { ($0.url, $0.label) }, uniquingKeysWith: { first, _ in first })
        let asks = ProgramChoice.isClose(described.map { ($0.role, $0.score) })
        return AnalysisReport(exe: exe, root: root, name: name, arch: arch, graphics: graphics, framework: framework,
                              isInstaller: isInstaller, libraries: libraries, findings: findings, engine: engine,
                              settings: settings, reasons: reasons, candidates: candidates,
                              candidateLabels: labels, asksWhichProgram: asks)
    }
}

enum EngineAdvisor {
    struct Pick {
        var engine: EngineID
        var reason: String
    }

    static func pick(arch: PEArch, graphics: GraphicsAPI, framework: String?, isExe: Bool, rosetta: Bool) -> Pick {
        let mach9 = Platform.mach9Available
        let mullion32 = Platform.metalSharpRuns32bit
        if arch == .arm64 {
            return Pick(engine: .mullion, reason: "It's an ARM64 Windows program, which MetalSharp Wine runs natively, with no translation.")
        }
        if !rosetta {
            if graphics == .opengl || (arch == .x86 && framework == "Clickteam Fusion"), arch != .x86 || mullion32 {
                return Pick(engine: .mullion, reason: "Rosetta isn't available, so this runs on an Apple-silicon engine. Mullion (MetalSharp Wine) suits it best: it draws OpenGL up to 4.6 through Metal, and runs Clickteam games well.")
            }
            if mach9 {
                return Pick(engine: .mach9, reason: "Rosetta isn't available, so Mach9 runs it: DirectX 9 through mtld3d, 10 and 11 through DXMT, 12 through vkd3d-proton and Vulkan through KosmicKrisp, all on Metal.")
            }
            return Pick(engine: .mullion, reason: arch == .x86 && !mullion32
                ? "Rosetta isn't available, and running 32-bit programs without it needs macOS 26.4 or later. Update macOS, or install Rosetta."
                : "Rosetta isn't available, so Mullion (MetalSharp Wine) runs it.")
        }
        if !isExe {
            return Pick(engine: .wined3d, reason: "Installers and scripts run on Wine Staging.")
        }
        if graphics == .opengl && (arch != .x86 || mullion32) {
            return Pick(engine: .mullion, reason: "OpenGL game: Mullion (MetalSharp Wine) draws OpenGL through Metal and supports up to OpenGL 4.6. Apple's own OpenGL, which the other engines use, stops at 4.1 and hasn't been updated since 2018.")
        }
        if arch == .x86 && framework == "Clickteam Fusion" && mullion32 {
            return Pick(engine: .mullion, reason: "32-bit Clickteam game: Mullion (MetalSharp Wine) runs these without Rosetta. In Ferry's testing, a Clickteam game that crashed on Wine Staging ran fully on Mullion.")
        }
        if graphics == .dx9 && mach9 {
            return Pick(engine: .mach9, reason: "DirectX 9 game: Mach9 draws it with mtld3d, which turns DirectX 9 straight into Metal, with no Rosetta and no OpenGL in between. Videos, effects and frame rate hold up much better than on WineD3D. If something draws wrong, set \"Mach9 draws Direct3D with\" to WineD3D.")
        }
        if graphics == .vulkan && mach9 {
            return Pick(engine: .mach9, reason: "Vulkan game: Mach9 includes KosmicKrisp, which runs all of Vulkan 1.4 on Metal and is certified by Khronos. Wine Staging, with MoltenVK, is the backup.")
        }
        if arch == .x86 {
            if graphics == .dx10 || graphics == .dx11 {
                let version = graphics == .dx10 ? "10" : "11"
                if mach9 {
                    return Pick(engine: .mach9, reason: "32-bit DirectX \(version) game: Mach9's DXMT turns it straight into Metal, without Rosetta or Vulkan in between. DXVK on Wine Staging is the backup.")
                }
                return Pick(engine: .dxvk, reason: "32-bit DirectX \(version): DXVK on Wine Staging." + (mullion32 ? " If it stutters or crashes, try Mullion, which turns DirectX 11 straight into Metal." : ""))
            }
            if graphics == .unknown && mach9 {
                return Pick(engine: .mach9, reason: "32-bit program whose graphics Ferry can't see in the file (launchers like Steam load them later): Mach9 runs these best, and picks DirectX 9 or 10–12 → Metal itself once the program starts. Wine Staging is the backup.")
            }
            return Pick(engine: .wined3d, reason: "32-bit program using \(graphics == .unknown ? "older graphics" : graphics.label): Wine Staging's WineD3D, the most tested route for these."
                + (mach9 ? " If it crashes or runs slowly, try Mach9." : mullion32 ? " If it crashes or runs slowly, try Mullion." : ""))
        }
        switch graphics {
        case .dx12, .dx11, .unknown:
            return Pick(engine: .d3dmetal, reason: "64-bit \(graphics == .unknown ? "program" : graphics.label + " game"): D3DMetal, Apple's own translator, is the fastest and most compatible for these. \(mach9 ? "Mach9" : "Mullion") is the backup.")
        case .dx10:
            if mach9 {
                return Pick(engine: .mach9, reason: "DirectX 10: Mach9's DXMT turns it straight into Metal. DXVK is the backup.")
            }
            return Pick(engine: .dxvk, reason: "DirectX 10: DXVK handles it best.")
        case .vulkan:
            return Pick(engine: .wined3d, reason: "Vulkan game: Wine Staging runs it through MoltenVK (Vulkan → Metal). If it crashes or draws wrong, try Mullion.")
        case .dx9, .dx8, .opengl:
            return Pick(engine: .wined3d, reason: "\(graphics.label): Wine's built-in WineD3D handles it. If it runs poorly, try Mullion.")
        }
    }

    static func fallbacks(after best: EngineID, arch: PEArch, graphics: GraphicsAPI, rosetta: Bool) -> [EngineID] {
        let rest: [EngineID]
        switch arch {
        case .x86: rest = graphics == .dx10 || graphics == .dx11 ? [.mach9, .dxvk, .wined3d, .mullion] : [.mach9, .wined3d, .mullion, .dxvk]
        case .arm64: rest = [.mullion, .mach9]
        case _ where graphics == .vulkan: rest = [.mach9, .wined3d, .mullion]
        default: rest = graphics == .dx9 ? [.mach9, .d3dmetal, .wined3d, .mullion, .dxvk] : [.d3dmetal, .mach9, .mullion, .dxvk, .wined3d]
        }
        var order: [EngineID] = []
        for engine in [best] + rest where engine != .auto && !order.contains(engine) {
            let kind = engine.runtime
            guard kind.availableHere, !kind.needsRosetta || rosetta else { continue }
            if engine == .d3dmetal && arch == .x86 { continue }
            if engine == .mullion && arch == .x86 && !Platform.metalSharpRuns32bit { continue }
            order.append(engine)
        }
        return order
    }

    static func tune(_ base: GameSettings, engine: EngineID, arch: PEArch, graphics: GraphicsAPI, reasons: inout [String]) -> GameSettings {
        var s = base
        switch engine {
        case .mach9:
            if !s.fastSync {
                s.fastSync = true
                reasons.append("Fast synchronization (MSync) on: Mach9 is built around it, and it cuts the time the program waits on itself.")
            }
            if arch == .x86 && s.fullMemory32 {
                reasons.append("4 GB of memory for this 32-bit program instead of 2 GB, like the well-known 4GB patch but without changing its files. It prevents out-of-memory crashes on big levels.")
            }
            if graphics == .dx9 {
                reasons.append("mtld3d keeps a shader cache next to the game, so the first minutes may hitch once; later launches don't.")
            }
        case .d3dmetal where graphics == .dx11 || graphics == .dx12:
            if !s.metalFX {
                s.metalFX = true
                reasons.append("DLSS → MetalFX on: if the game offers DLSS in its graphics settings, choosing it upscales with Apple's MetalFX for a large frame-rate gain. It does nothing otherwise.")
            }
        default:
            break
        }
        if s.retina && Platform.memoryGB <= 8 && [GraphicsAPI.dx11, .dx12].contains(graphics) {
            s.retina = false
            reasons.append("Retina resolution off: this Mac has \(Platform.memoryGB) GB of memory, and drawing a modern 3D game at full Retina resolution costs far more frame rate than it's worth here.")
        }
        return s
    }
}
