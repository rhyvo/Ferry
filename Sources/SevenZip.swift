import Foundation

extension RuntimeManager {
    static var sevenZipFolder: URL { Paths.runtimes.appendingPathComponent("7zip", isDirectory: true) }
    static var sevenZip: URL { sevenZipFolder.appendingPathComponent("7zz") }

    var sevenZipInstalled: Bool { FileManager.default.isExecutableFile(atPath: Self.sevenZip.path) }

    var sevenZipVersion: String? {
        (try? String(contentsOf: Self.sevenZipFolder.appendingPathComponent("version"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let knownSevenZip = (tag: "26.06", url: "https://github.com/ip7z/7zip/releases/download/26.06/7z2606-mac.tar.xz")

    func installSevenZip() async throws {
        if sevenZipInstalled { return }
        let fm = FileManager.default
        var tag = Self.knownSevenZip.tag
        var link = Self.knownSevenZip.url
        var size = 0
        if let found = try? await GitHub.latestAsset(repo: "ip7z/7zip", matching: { $0.hasSuffix("-mac.tar.xz") }) {
            tag = found.tag
            link = found.asset.browserDownloadUrl
            size = found.asset.size
        }
        guard let url = URL(string: link) else { throw FerryError("Bad download link for 7-Zip.") }

        task = "Downloading 7-Zip \(tag)…"
        defer { task = nil; progress = nil }
        let archive = Paths.cache.appendingPathComponent(url.lastPathComponent)
        try await download(url, to: archive, expectedBytes: size)
        defer { fm.removeIfPresent(archive) }

        let staging = Paths.runtimes.appendingPathComponent("7zip.new", isDirectory: true)
        fm.removeIfPresent(staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        guard await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path]) == 0,
              let tool = fm.firstItem(under: staging, where: { $0.lastPathComponent == "7zz" }) else {
            fm.removeIfPresent(staging)
            throw FerryError("The 7-Zip download didn't contain the 7zz tool.")
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        if await Shell.run(tool.path, ["i"]) != 0 {
            await Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", tool.path])
            guard await Shell.run(tool.path, ["i"]) == 0 else {
                fm.removeIfPresent(staging)
                throw FerryError("7-Zip downloaded but wouldn't run on this Mac.")
            }
        }

        let dest = Self.sevenZipFolder
        fm.removeIfPresent(dest)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.moveItem(at: tool, to: Self.sevenZip)
        if let license = fm.firstItem(under: staging, where: { $0.lastPathComponent == "License.txt" }) {
            try? fm.moveItem(at: license, to: dest.appendingPathComponent("License.txt"))
        }
        try? tag.write(to: dest.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        fm.removeIfPresent(staging)
        objectWillChange.send()
    }
}
