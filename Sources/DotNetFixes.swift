import Foundation

extension AppModel {
    private static let dotNetLoaderFiles = ["mscoree.dll", "mscorees.dll"]
    private var dotNetLoaderFolder: URL { Paths.cache.appendingPathComponent("dotnet-loader", isDirectory: true) }

    func cachedDotNetLoader() -> URL? {
        let all = ["x86", "x64"].allSatisfy { arch in
            Self.dotNetLoaderFiles.allSatisfy { fm.exists(dotNetLoaderFolder.appendingPathComponent("\(arch)/\($0)")) }
        }
        return all ? dotNetLoaderFolder : nil
    }

    func installDotNetLoader() async throws {
        if cachedDotNetLoader() != nil { return }
        guard let lib = Self.windowsLibraries.first(where: { $0.file == Self.dotNet40File }) else { return }
        if !runtimes.isCached(lib.file) { status = "Downloading Microsoft's .NET loader (about 50 MB)…" }
        guard let package = await cachedFile(for: lib) else {
            throw FerryError("Microsoft's .NET loader couldn't be downloaded. Check your connection and try again.")
        }
        if !runtimes.sevenZipInstalled { try await runtimes.installSevenZip() }
        status = "Unpacking Microsoft's .NET loader…"
        let work = Paths.cache.appendingPathComponent("dotnet-loader.new", isDirectory: true)
        fm.removeIfPresent(work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { fm.removeIfPresent(work) }
        let zip = RuntimeManager.sevenZip.path
        await Shell.run(zip, ["e", "-y", "-o" + work.path, package.path, "netfx_Core.mzz"])
        let inside = ["x86/mscoree.dll": "_003_mscoree_dll_x86", "x64/mscoree.dll": "_003_mscoree_dll_amd64",
                      "x86/mscorees.dll": "_017_mscorees_dll_x86", "x64/mscorees.dll": "_017_mscorees_dll_amd64"]
        await Shell.run(zip, ["e", "-y", "-o" + work.path, work.appendingPathComponent("netfx_Core.mzz").path] + inside.values.sorted())
        let ready = work.appendingPathComponent("ready", isDirectory: true)
        for (to, from) in inside {
            let dest = ready.appendingPathComponent(to)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.exists(work.appendingPathComponent(from)) else {
                throw FerryError("Microsoft's .NET package didn't have its loader. Try again.")
            }
            try fm.moveItem(at: work.appendingPathComponent(from), to: dest)
        }
        fm.removeIfPresent(dotNetLoaderFolder)
        try fm.moveItem(at: ready, to: dotNetLoaderFolder)
        fm.removeIfPresent(package)
    }

    private static let managedDirectX: [(file: String, name: String, version: String)] =
        ["", ".AudioVideoPlayback", ".Diagnostics", ".Direct3D", ".DirectDraw", ".DirectInput", ".DirectPlay", ".DirectSound"]
            .map { (file: "microsoft.directx\($0.lowercased()).dll", name: "Microsoft.DirectX\($0)", version: "1.0.2902.0") }
        + [(file: "microsoft.directx.direct3dx.dll", name: "Microsoft.DirectX.Direct3DX", version: "1.0.2911.0")]
    private static let olderDirect3DX = (2902...2910).map { "1.0.\($0).0" }
    private static let managedDirectXToken = "31bf3856ad364e35"

    private var managedDirectXFolder: URL { Paths.cache.appendingPathComponent("managed-directx", isDirectory: true) }

    func cachedManagedDirectX() -> URL? {
        let d3d = managedDirectXFolder.appendingPathComponent("GAC/Microsoft.DirectX.Direct3D/1.0.2902.0__\(Self.managedDirectXToken)/Microsoft.DirectX.Direct3D.dll")
        return fm.exists(d3d) ? managedDirectXFolder : nil
    }

    func installManagedDirectX() async throws {
        if cachedManagedDirectX() != nil { return }
        guard let lib = Self.windowsLibraries.first(where: { $0.component == .directX }) else { return }
        if !runtimes.isCached(lib.file) { status = "Downloading DirectX (June 2010)…" }
        guard let package = await cachedFile(for: lib) else {
            throw FerryError("DirectX (June 2010) couldn't be downloaded for Managed DirectX. Check your connection and try again.")
        }
        if !runtimes.sevenZipInstalled { try await runtimes.installSevenZip() }
        status = "Unpacking Managed DirectX…"
        let work = Paths.cache.appendingPathComponent("managed-directx.new", isDirectory: true)
        fm.removeIfPresent(work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { fm.removeIfPresent(work) }
        let zip = RuntimeManager.sevenZip.path
        await Shell.run(zip, ["e", "-y", "-o" + work.path, package.path, "Apr2006_MDX1_x86.cab", "Apr2006_MDX1_x86_Archive.cab"])
        let main = work.appendingPathComponent("main"), older = work.appendingPathComponent("older")
        await Shell.run(zip, ["e", "-y", "-o" + main.path, work.appendingPathComponent("Apr2006_MDX1_x86.cab").path])
        await Shell.run(zip, ["e", "-y", "-o" + older.path, work.appendingPathComponent("Apr2006_MDX1_x86_Archive.cab").path])
        let ready = work.appendingPathComponent("ready", isDirectory: true)
        func place(_ from: URL, name: String, version: String) throws {
            guard fm.exists(from) else { throw FerryError("Microsoft's DirectX package didn't have \(name) \(version).") }
            let dir = ready.appendingPathComponent("GAC/\(name)/\(version)__\(Self.managedDirectXToken)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: dir.appendingPathComponent(name + ".dll"))
        }
        for a in Self.managedDirectX { try place(main.appendingPathComponent(a.file), name: a.name, version: a.version) }
        for version in Self.olderDirect3DX {
            let cab = older.appendingPathComponent("mdx_\(version)_x86.cab"), out = work.appendingPathComponent(version)
            await Shell.run(zip, ["e", "-y", "-o" + out.path, cab.path, "microsoft.directx.direct3dx.dll"])
            try place(out.appendingPathComponent("microsoft.directx.direct3dx.dll"), name: "Microsoft.DirectX.Direct3DX", version: version)
        }
        fm.removeIfPresent(managedDirectXFolder)
        try fm.moveItem(at: ready, to: managedDirectXFolder)
    }

    func prepareDotNet(_ p: PreparedGame) async {
        guard PEParser.parse(URL(fileURLWithPath: p.game.exePath))?.isDotNet == true else { return }
        let windows = p.prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        guard fm.exists(windows.appendingPathComponent("Microsoft.NET/Framework/v4.0.30319/clr.dll"))
                || fm.exists(windows.appendingPathComponent("Microsoft.NET/Framework64/v4.0.30319/clr.dll")) else { return }
        let log = logURL(p.game.id, "setup")
        var places = [("x86", windows.appendingPathComponent("syswow64"))]
        if ![RuntimeKind.mach9, .arm64].contains(p.kind) { places.append(("x64", windows.appendingPathComponent("system32"))) }
        places = places.filter { fm.isDirectory($0.1) }
        let loaderMissing = places.contains { arch, dir in
            guard let source = cachedDotNetLoader() else { return true }
            return !fm.contentsEqual(atPath: dir.appendingPathComponent("mscoree.dll").path,
                                     andPath: source.appendingPathComponent("\(arch)/mscoree.dll").path)
        }
        if loaderMissing {
            do { try await installDotNetLoader() } catch {
                errorMessage = "\(error.localizedDescription) \(p.game.name) may not start."
                return
            }
            guard let source = cachedDotNetLoader() else { return }
            for (arch, dir) in places {
                for file in Self.dotNetLoaderFiles {
                    let to = dir.appendingPathComponent(file)
                    fm.removeIfPresent(to)
                    try? fm.copyItem(at: source.appendingPathComponent("\(arch)/\(file)"), to: to)
                }
            }
            await applyRegistry([
                "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\.NETFramework]",
                "\"InstallRoot\"=\"C:\\\\windows\\\\Microsoft.NET\\\\Framework64\\\\\"",
                "\"OnlyUseLatestCLR\"=dword:00000001",
                "",
                "[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\.NETFramework]",
                "\"InstallRoot\"=\"C:\\\\windows\\\\Microsoft.NET\\\\Framework\\\\\"",
                "\"OnlyUseLatestCLR\"=dword:00000001",
            ], name: "ferry-dotnet", wine: p.wine, env: p.env, prefix: p.prefix, log: log)
        }
        let gac = windows.appendingPathComponent("assembly/GAC", isDirectory: true)
        if !fm.exists(gac.appendingPathComponent("Microsoft.DirectX.Direct3D")) {
            do { try await installManagedDirectX() } catch {
                errorMessage = "\(error.localizedDescription) \(p.game.name) may not start if it uses Managed DirectX."
                return
            }
            guard let source = cachedManagedDirectX(),
                  let names = try? fm.contentsOfDirectory(atPath: source.appendingPathComponent("GAC").path) else { return }
            try? fm.createDirectory(at: gac, withIntermediateDirectories: true)
            for name in names {
                let to = gac.appendingPathComponent(name)
                fm.removeIfPresent(to)
                try? fm.copyItem(at: source.appendingPathComponent("GAC/\(name)"), to: to)
            }
        }
    }
}
