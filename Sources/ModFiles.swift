import Foundation
import CryptoKit

enum ModFiles {
    static func sha256(_ file: URL) -> String { hash(file) ?? "" }

    private static func hash(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let more: Bool? = autoreleasepool {
                do {
                    guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
                    hasher.update(data: chunk)
                    return true
                } catch { return nil }
            }
            guard let more else { return nil }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    struct UnreadableFile: Error { let path: String }
    struct Outside: Error { let path: String }

    static func apply(_ plan: ModPlan, backups: URL, within allowed: [URL]) throws -> [ModFileRecord] {
        if let stray = plan.copies.first(where: { c in !allowed.contains { ModLayout.isInside(c.to, $0) } }) {
            throw Outside(path: stray.to.path)
        }
        let fm = FileManager.default
        var records: [ModFileRecord] = []
        var undo: [() -> Void] = []
        do {
            for (i, copy) in plan.copies.enumerated() {
                let dest = copy.to
                var backupPath: String?
                if fm.fileExists(atPath: dest.path) {
                    try fm.createDirectory(at: backups, withIntermediateDirectories: true)
                    let backup = backups.appendingPathComponent("\(i)-\(dest.lastPathComponent)")
                    try? fm.removeItem(at: backup)
                    try fm.moveItem(at: dest, to: backup)
                    undo.append { try? fm.moveItem(at: backup, to: dest) }
                    backupPath = backup.path
                }
                var missing: [URL] = []
                var dir = dest.deletingLastPathComponent()
                while !fm.fileExists(atPath: dir.path), dir.path != "/" {
                    missing.insert(dir, at: 0)
                    dir = dir.deletingLastPathComponent()
                }
                for folder in missing {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
                    undo.append { try? fm.removeItem(at: folder) }
                }
                try fm.copyItem(at: copy.from, to: dest)
                undo.append { try? fm.removeItem(at: dest) }
                guard let digest = hash(dest) else { throw UnreadableFile(path: dest.path) }
                records.append(ModFileRecord(path: dest.path, sha256: digest, backup: backupPath,
                                             createdFolders: missing.isEmpty ? nil : missing.map(\.path)))
            }
            return records
        } catch {
            for step in undo.reversed() { step() }
            throw error
        }
    }

    struct NotRestored: Equatable {
        let path: String
        let backup: String?
    }

    struct Removal {
        var restored = 0
        var changed: [String] = []
        var notDeleted: [String] = []
        var notRestored: [NotRestored] = []
        var later: [[ModFileRecord]] = []
    }

    static func pathKey(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path.lowercased() }

    static func remove(_ files: [ModFileRecord], later: [[ModFileRecord]]) -> Removal {
        let fm = FileManager.default
        var out = Removal(later: later)
        for rec in files.reversed() {
            let key = pathKey(rec.path)
            if let m = out.later.firstIndex(where: { $0.contains { pathKey($0.path) == key } }),
               let r = out.later[m].firstIndex(where: { pathKey($0.path) == key }) {
                var owner = out.later[m][r]
                if let own = owner.backup, own != rec.backup { try? fm.removeItem(atPath: own) }
                owner.backup = rec.backup
                var folders = owner.createdFolders ?? []
                for f in (rec.createdFolders ?? []).reversed() where !folders.contains(f) { folders.insert(f, at: 0) }
                owner.createdFolders = folders.isEmpty ? nil : folders
                out.later[m][r] = owner
                continue
            }
            let url = URL(fileURLWithPath: rec.path)
            if fm.fileExists(atPath: rec.path) {
                if sha256(url) != rec.sha256 { out.changed.append(rec.path); continue }
                do { try fm.removeItem(at: url) } catch { out.notDeleted.append(rec.path); continue }
            } else if rec.backup == nil {
                continue
            }
            guard let b = rec.backup else { out.restored += 1; continue }
            guard fm.fileExists(atPath: b) else { out.notRestored.append(NotRestored(path: rec.path, backup: nil)); continue }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: URL(fileURLWithPath: b), to: url)
            } catch { out.notRestored.append(NotRestored(path: rec.path, backup: b)); continue }
            out.restored += 1
            let backupFolder = (b as NSString).deletingLastPathComponent
            if (try? fm.contentsOfDirectory(atPath: backupFolder))?.isEmpty == true { try? fm.removeItem(atPath: backupFolder) }
        }
        let folders = Set(files.flatMap { $0.createdFolders ?? [] })
            .sorted { $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count }
        for folder in folders {
            let names = (try? fm.contentsOfDirectory(atPath: folder)) ?? ["?"]
            if names.allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(atPath: folder) }
        }
        return out
    }
}

enum ModSpace {
    static let margin: Int64 = 1_000_000_000

    static func enough(free: Int64, needed: Int64) -> Bool {
        let (total, overflow) = needed.addingReportingOverflow(margin)
        return !overflow && free >= total
    }

    static func downloadNeed(_ size: Int64) -> Int64 {
        let (n, overflow) = size.multipliedReportingOverflow(by: 3)
        return overflow ? .max : n
    }

    static func installBytes(_ plan: ModPlan) -> Int64 {
        func size(_ u: URL) -> Int64 { Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return plan.copies.reduce(0) { $0 + size($1.from) + size($1.to) }
    }
}
