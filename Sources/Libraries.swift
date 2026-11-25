import Foundation

struct WinLibrary {
    enum Method {
        case exe([String])
        case msi
        case zip(inner: String, args: [String])
        case directX
        case dotNet
        case systemDLL(is64bit: Bool)
        case cacheOnly
        case directShowZip(folder: String)
        case extractThenRun(inner: String, args: [String])
    }

    let name: String
    let url: String
    let file: String
    let method: Method
    let needs32bitWine: Bool
    var slow = false
    var githubRepo: String? = nil
    var githubAsset: ((String) -> Bool)? = nil
    var component: Component = .visualCpp
    var sha256: String? = nil
}

extension AppModel {
    static let dotNet40File = "dotNetFx40_Full_x86_x64.exe"

    static let librarySetVersion = 2

    private static let vcArgs = ["/install", "/quiet", "/norestart"]

    static let windowsLibraries: [WinLibrary] = [
        WinLibrary(name: "Visual C++ 2005 (32-bit)",
                   url: "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE",
                   file: "vcredist_2005.x86.exe", method: .exe(["/q"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2005 (64-bit)",
                   url: "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.EXE",
                   file: "vcredist_2005.x64.exe", method: .exe(["/q"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2008 (32-bit)",
                   url: "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe",
                   file: "vcredist_2008.x86.exe", method: .exe(["/q"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2008 (64-bit)",
                   url: "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe",
                   file: "vcredist_2008.x64.exe", method: .exe(["/q"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2010 (32-bit)",
                   url: "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe",
                   file: "vcredist_2010.x86.exe", method: .exe(["/q", "/norestart"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2010 (64-bit)",
                   url: "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe",
                   file: "vcredist_2010.x64.exe", method: .exe(["/q", "/norestart"]), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2012 (32-bit)",
                   url: "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe",
                   file: "vcredist_2012.x86.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2012 (64-bit)",
                   url: "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe",
                   file: "vcredist_2012.x64.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2013 (32-bit)", url: "https://aka.ms/highdpimfc2013x86enu",
                   file: "vcredist_2013.x86.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2013 (64-bit)", url: "https://aka.ms/highdpimfc2013x64enu",
                   file: "vcredist_2013.x64.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2015–2022 (32-bit)", url: "https://aka.ms/vs/17/release/vc_redist.x86.exe",
                   file: "vc_redist_2015-2022.x86.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "Visual C++ 2015–2022 (64-bit)", url: "https://aka.ms/vs/17/release/vc_redist.x64.exe",
                   file: "vc_redist_2015-2022.x64.exe", method: .exe(vcArgs), needs32bitWine: true),
        WinLibrary(name: "DirectX (June 2010)",
                   url: "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe",
                   file: "directx_Jun2010_redist.exe", method: .directX, needs32bitWine: true, component: .directX),
        WinLibrary(name: "DirectX shader compiler (64-bit)",
                   url: "https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47.dll",
                   file: "d3dcompiler_47.x64.dll", method: .systemDLL(is64bit: true), needs32bitWine: false, component: .shaderCompiler),
        WinLibrary(name: "DirectX shader compiler (32-bit)",
                   url: "https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47_32.dll",
                   file: "d3dcompiler_47.x86.dll", method: .systemDLL(is64bit: false), needs32bitWine: true, component: .shaderCompiler),
        WinLibrary(name: ".NET Framework 4.8",
                   url: "https://download.visualstudio.microsoft.com/download/pr/2d6bb6b2-226a-4baa-bdec-798822606ff1/8494001c276a4b96804cde7829c04d7f/ndp48-x86-x64-allos-enu.exe",
                   file: "ndp48-x86-x64-allos-enu.exe", method: .dotNet, needs32bitWine: true, slow: true, component: .dotNet48),
        WinLibrary(name: ".NET 4.0 (for Microsoft's .NET loader)",
                   url: "https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe",
                   file: AppModel.dotNet40File, method: .cacheOnly, needs32bitWine: true, component: .dotNet48,
                   sha256: "65e064258f2e418816b304f646ff9e87af101e4c9552ab064bb74d281c38659f"),
        WinLibrary(name: ".NET 6 Desktop Runtime (64-bit)", url: "https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x64.exe",
                   file: "windowsdesktop-runtime-6.x64.exe", method: .exe(vcArgs), needs32bitWine: true, component: .dotNetModern),
        WinLibrary(name: ".NET 6 Desktop Runtime (32-bit)", url: "https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x86.exe",
                   file: "windowsdesktop-runtime-6.x86.exe", method: .exe(vcArgs), needs32bitWine: true, component: .dotNetModern),
        WinLibrary(name: ".NET 8 Desktop Runtime (64-bit)", url: "https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe",
                   file: "windowsdesktop-runtime-8.x64.exe", method: .exe(vcArgs), needs32bitWine: true, component: .dotNetModern),
        WinLibrary(name: ".NET 8 Desktop Runtime (32-bit)", url: "https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x86.exe",
                   file: "windowsdesktop-runtime-8.x86.exe", method: .exe(vcArgs), needs32bitWine: true, component: .dotNetModern),
        WinLibrary(name: "XNA Framework 4.0",
                   url: "https://download.microsoft.com/download/A/C/2/AC2C903B-E6E8-42C2-9FD7-BEBAC362A930/xnafx40_redist.msi",
                   file: "xnafx40_redist.msi", method: .msi, needs32bitWine: true, component: .xna),
        WinLibrary(name: "Visual Basic 6 runtime",
                   url: "https://web.archive.org/web/20070204154430id_/https://download.microsoft.com/download/5/a/d/5ad868a0-8ecd-4bb0-a882-fe53eb7ef348/VB6.0-KB290887-X86.exe",
                   file: "VB6.0-KB290887-X86.exe", method: .extractThenRun(inner: "vbrun60sp6.exe", args: ["/Q"]),
                   needs32bitWine: true, component: .vb6,
                   sha256: "467b5a10c369865f2021d379fc0933cb382146b702bbca4bcb703fc86f4322bb"),
        WinLibrary(name: "OpenAL", url: "https://www.openal.org/downloads/oalinst.zip",
                   file: "oalinst.zip", method: .zip(inner: "oalinst.exe", args: ["/s"]), needs32bitWine: true, component: .openAL),
        WinLibrary(name: "PhysX (legacy games)",
                   url: "https://us.download.nvidia.com/Windows/9.13.0604/PhysX-9.13.0604-SystemSoftware-Legacy.msi",
                   file: "PhysX-9.13.0604-Legacy.msi", method: .msi, needs32bitWine: true, component: .physX),
        WinLibrary(name: "LAV Filters (video codecs, 64-bit)", url: "", file: "LAVFilters-x64.zip",
                   method: .directShowZip(folder: "LAV Filters\\x64"), needs32bitWine: false,
                   githubRepo: "Nevcairiel/LAVFilters",
                   githubAsset: { $0.hasPrefix("LAVFilters-") && $0.hasSuffix("-x64.zip") }, component: .lav),
        WinLibrary(name: "LAV Filters (video codecs, 32-bit)", url: "", file: "LAVFilters-x86.zip",
                   method: .directShowZip(folder: "LAV Filters\\x86"), needs32bitWine: true,
                   githubRepo: "Nevcairiel/LAVFilters",
                   githubAsset: { $0.hasPrefix("LAVFilters-") && $0.hasSuffix("-x86.zip") }, component: .lav),
        WinLibrary(name: "cnc-ddraw (old 2D game fix)", url: "", file: "cnc-ddraw.zip",
                   method: .cacheOnly, needs32bitWine: false,
                   githubRepo: "FunkyFr3sh/cnc-ddraw", githubAsset: { $0 == "cnc-ddraw.zip" }, component: .cncDdraw),
        WinLibrary(name: "DirectX (February 2010) for DirectMusic and DirectPlay",
                   url: "https://web.archive.org/web/20100205000000id_/https://download.microsoft.com/download/E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe",
                   file: "directx_feb2010_redist.exe", method: .cacheOnly, needs32bitWine: true, component: .legacyDirectX,
                   sha256: "f6d191e89a963d7cca34f169d30f49eab99c1ed3bb92da73ec43617caaa1e93f"),
        WinLibrary(name: "dgVoodoo2 (old 3D game fix)", url: "", file: "dgVoodoo2.zip", method: .cacheOnly, needs32bitWine: false,
                   githubRepo: "dege-diosg/dgVoodoo2",
                   githubAsset: { $0.hasPrefix("dgVoodoo2_") && $0.hasSuffix(".zip") && !$0.contains("_dbg") && !$0.contains("_dev") },
                   component: .dgVoodoo),
        WinLibrary(name: "WebView2", url: "https://go.microsoft.com/fwlink/?linkid=2124701",
                   file: "MicrosoftEdgeWebView2RuntimeInstallerX64.exe", method: .cacheOnly, needs32bitWine: true,
                   component: .webView2),
    ]

    static let visualCppDLLs = [
        "msvcp100", "msvcr100", "mfc100", "mfc100u", "vcomp100",
        "msvcp110", "msvcr110", "mfc110", "mfc110u", "vcomp110",
        "msvcp120", "msvcr120", "mfc120", "mfc120u", "vcomp120",
        "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait", "msvcp140_codecvt_ids",
        "vcruntime140", "vcruntime140_1", "vcruntime140_threads", "concrt140", "vccorlib140",
        "vcomp140", "vcamp140", "mfc140", "mfc140u",
    ]

    private static func isEnabled(_ lib: WinLibrary) -> Bool { Component.isOn(lib.component) }

    private func downloadURL(for lib: WinLibrary) async -> URL? {
        if !lib.url.isEmpty { return URL(string: lib.url) }
        guard let repo = lib.githubRepo, let match = lib.githubAsset,
              let found = try? await GitHub.latestAsset(repo: repo, matching: match) else { return nil }
        return URL(string: found.asset.browserDownloadUrl)
    }

    func cachedFile(for lib: WinLibrary) async -> URL? {
        guard let url = await downloadURL(for: lib),
              let file = try? await runtimes.cachedInstaller(url, name: lib.file) else { return nil }
        if let expected = lib.sha256, ModFiles.sha256(file) != expected {
            fm.removeIfPresent(file)
            return nil
        }
        return file
    }

    func cachedCncDdrawDLL() -> URL? {
        let unpacked = Paths.cache.appendingPathComponent("cnc-ddraw", isDirectory: true)
        return fm.firstItem(under: unpacked, where: { $0.lastPathComponent.lowercased() == "ddraw.dll" })
    }

    func cncDdrawDLL() async -> URL? {
        let unpacked = Paths.cache.appendingPathComponent("cnc-ddraw", isDirectory: true)
        if let existing = cachedCncDdrawDLL() { return existing }
        guard let lib = Self.windowsLibraries.first(where: { $0.file == "cnc-ddraw.zip" }),
              let zip = await cachedFile(for: lib) else { return nil }
        fm.removeIfPresent(unpacked)
        await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        return fm.firstItem(under: unpacked, where: { $0.lastPathComponent.lowercased() == "ddraw.dll" })
    }

    func webView2Installer() async -> URL? {
        guard let lib = Self.windowsLibraries.first(where: { $0.component == .webView2 }) else { return nil }
        return await cachedFile(for: lib)
    }

    func downloadWindowsLibraries() async -> [String] {
        var skipped: [String] = []
        for lib in Self.windowsLibraries where Self.isEnabled(lib) {
            if lib.component == .legacyDirectX && cachedLegacyDirectX() != nil { continue }
            if lib.component == .dgVoodoo && dgVoodooFiles() != nil { continue }
            if lib.file == Self.dotNet40File && cachedDotNetLoader() != nil { continue }
            if !runtimes.isCached(lib.file) { status = "Downloading \(lib.name)…" }
            if await cachedFile(for: lib) == nil { skipped.append(lib.name) }
        }
        return skipped
    }

    @discardableResult
    func installWindowsLibraries(wine: URL, env: [String: String], prefix: URL, kind: RuntimeKind, log: URL,
                                 only: Component? = nil) async -> [String] {
        var skipped: [String] = []
        let server = runtimes.wineserver(for: kind)
        func waitForWine() async {
            if let server { await Shell.run(server.path, ["-w"], env: env, log: log) }
        }
        let windows = prefix.appendingPathComponent("drive_c/windows")

        for lib in Self.windowsLibraries where (only.map { lib.component == $0 } ?? Self.isEnabled(lib))
                                                && !(lib.needs32bitWine && !kind.supports32bit) {
            if case .cacheOnly = lib.method { continue }
            if !runtimes.isCached(lib.file) { report("Downloading \(lib.name)…", for: kind) }
            guard let file = await cachedFile(for: lib) else {
                skipped.append(lib.name)
                continue
            }
            report(lib.slow ? "Installing \(lib.name). This one takes several minutes…" : "Installing \(lib.name)…", for: kind)

            let limit: UInt64 = lib.slow ? 30 * 60 : 10 * 60
            let watchdog = Task { () -> Bool in
                try? await Task.sleep(nanoseconds: limit * 1_000_000_000)
                if Task.isCancelled { return false }
                if let server { await Shell.run(server.path, ["-k"], env: env, log: log) }
                return true
            }
            defer { watchdog.cancel() }

            switch lib.method {
            case .exe(let args):
                await Shell.run(wine.path, [file.path] + args, env: env, log: log)

            case .msi:
                await Shell.run(wine.path, ["msiexec", "/i", file.path, "/qn"], env: env, log: log)

            case .zip(let inner, let args):
                let unpack = prefix.appendingPathComponent("drive_c/ferry-unpack")
                fm.removeIfPresent(unpack)
                await Shell.run("/usr/bin/ditto", ["-x", "-k", file.path, unpack.path], log: log)
                if let installer = fm.firstItem(under: unpack, where: { $0.lastPathComponent.lowercased() == inner.lowercased() }) {
                    await Shell.run(wine.path, [installer.path] + args, env: env, log: log)
                    await waitForWine()
                } else {
                    skipped.append(lib.name)
                }
                fm.removeIfPresent(unpack)

            case .directX:
                let unpack = prefix.appendingPathComponent("drive_c/ferry-directx")
                fm.removeIfPresent(unpack)
                try? fm.createDirectory(at: unpack, withIntermediateDirectories: true)
                await Shell.run(wine.path, [file.path, "/Q", "/T:C:\\ferry-directx"], env: env, log: log)
                await waitForWine()
                await Shell.run(wine.path, [unpack.appendingPathComponent("DXSETUP.exe").path, "/silent"], env: env, log: log)
                await waitForWine()
                fm.removeIfPresent(unpack)

            case .extractThenRun(let inner, let args):
                let unpack = prefix.appendingPathComponent("drive_c/ferry-unpack")
                fm.removeIfPresent(unpack)
                try? fm.createDirectory(at: unpack, withIntermediateDirectories: true)
                await Shell.run(wine.path, [file.path, "/Q", "/C", "/T:C:\\ferry-unpack"], env: env, log: log)
                await waitForWine()
                if let installer = fm.firstItem(under: unpack, where: { $0.lastPathComponent.lowercased() == inner.lowercased() }) {
                    await Shell.run(wine.path, [installer.path] + args, env: env, log: log)
                } else {
                    skipped.append(lib.name)
                }
                await waitForWine()
                fm.removeIfPresent(unpack)

            case .directShowZip(let folder):
                let dest = prefix.appendingPathComponent("drive_c/Program Files (x86)/" + folder.replacingOccurrences(of: "\\", with: "/"))
                fm.removeIfPresent(dest)
                await Shell.run("/usr/bin/ditto", ["-x", "-k", file.path, dest.path], log: log)
                let filters = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []).filter { $0.lowercased().hasSuffix(".ax") }
                if filters.isEmpty { skipped.append(lib.name); continue }
                for ax in filters {
                    await Shell.run(wine.path, ["regsvr32", "/s", "C:\\Program Files (x86)\\\(folder)\\\(ax)"], env: env, log: log)
                }

            case .dotNet:
                let (_, listing) = await Shell.capture(wine.path, ["uninstaller", "--list"], env: env)
                for line in listing.split(whereSeparator: \.isNewline) where line.lowercased().contains("mono") {
                    if let id = line.components(separatedBy: "|||").first, id.hasPrefix("{") {
                        await Shell.run(wine.path, ["uninstaller", "--remove", id], env: env, log: log)
                    }
                }
                await waitForWine()
                for view in ["", "Wow6432Node\\"] {
                    await Shell.run(wine.path, ["reg", "delete", "HKLM\\Software\\\(view)Microsoft\\NET Framework Setup\\NDP\\v4", "/f"],
                                    env: env, log: log)
                }
                await waitForWine()
                await Shell.run(wine.path, ["winecfg", "-v", "win7"], env: env, log: log)
                await Shell.run(wine.path, [file.path, "/q", "/norestart"], env: env, log: log)
                await waitForWine()
                await Shell.run(wine.path, ["reg", "add", "HKCU\\Software\\Wine\\DllOverrides", "/v", "mscoree",
                                            "/t", "REG_SZ", "/d", "native", "/f"], env: env, log: log)
                await Shell.run(wine.path, ["winecfg", "-v", "win10"], env: env, log: log)

            case .systemDLL(let is64bit):
                let dest = windows.appendingPathComponent(is64bit ? "system32" : "syswow64")
                guard fm.isDirectory(dest) else { continue }
                let out = dest.appendingPathComponent("d3dcompiler_47.dll")
                fm.removeIfPresent(out)
                if (try? fm.copyItem(at: file, to: out)) == nil { skipped.append(lib.name) }

            case .cacheOnly:
                break
            }
            await waitForWine()
            watchdog.cancel()
            if await watchdog.value {
                skipped.append("\(lib.name) (it stopped responding, so Ferry skipped it)")
            }
        }

        if !kind.supports32bit {
            copyVisualCpp(into: prefix)
        }

        await applyRegistry(
            ["[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]"]
                + (Self.visualCppDLLs + ["d3dcompiler_47"]).map { "\"\($0)\"=\"native,builtin\"" },
            name: "ferry-dlls", wine: wine, env: env, prefix: prefix, log: log)
        report(nil, for: kind)
        return skipped
    }

    func copyVisualCpp(into prefix: URL) {
        let source = templateURL(.staging).appendingPathComponent("drive_c/windows/system32")
        let dest = prefix.appendingPathComponent("drive_c/windows/system32")
        guard fm.isDirectory(source), fm.isDirectory(dest),
              let files = try? fm.contentsOfDirectory(atPath: source.path) else { return }
        let wanted = Set(Self.visualCppDLLs)
        for file in files {
            let lower = file.lowercased()
            guard lower.hasSuffix(".dll"), wanted.contains(String(lower.dropLast(4))) else { continue }
            let out = dest.appendingPathComponent(file)
            fm.removeIfPresent(out)
            try? fm.copyItem(at: source.appendingPathComponent(file), to: out)
        }
    }

    func installLibraries(_ p: PreparedGame) async -> [String] {
        let skipped = await installWindowsLibraries(wine: p.wine, env: p.env, prefix: p.prefix, kind: p.kind,
                                                    log: logURL(p.game.id, "setup"))
        if var g = game(p.game.id), !g.runtimesInstalled.contains(p.kind.rawValue) {
            g.runtimesInstalled.append(p.kind.rawValue)
            update(g)
        }
        return skipped
    }

    func reinstallLibraries(_ id: UUID) {
        guard !preparing.contains(id) else { return }
        preparing.insert(id)
        Task {
            defer { preparing.remove(id); status = nil }
            do {
                let prepared = try await prepare(id)
                let skipped = await installLibraries(prepared)
                if !skipped.isEmpty {
                    errorMessage = "These couldn't be downloaded: \(skipped.joined(separator: ", ")). Check your connection and try again."
                } else {
                    noticeMessage = "Windows libraries reinstalled."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
