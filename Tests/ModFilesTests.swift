import Foundation
import CryptoKit

func runFilesTests() {
    let anywhere = [URL(fileURLWithPath: "/")]
    let fm = FileManager.default
    let game = tempDir(); make(game, ["a.dll", "keep.txt"])
    let mod = tempDir(); make(mod, ["a.dll", "new/b.asi"])
    let plan = ModPlan(recipe: .dropIn, copies: [ModCopy(from: mod.appendingPathComponent("a.dll"), to: game.appendingPathComponent("a.dll")),
                                                ModCopy(from: mod.appendingPathComponent("new/b.asi"), to: game.appendingPathComponent("new/b.asi"))],
                       overrides: [], programExe: nil)
    try! "modded".write(to: mod.appendingPathComponent("a.dll"), atomically: true, encoding: .utf8)
    let originalA = ModFiles.sha256(game.appendingPathComponent("a.dll"))
    let recs = try! ModFiles.apply(plan, backups: tempDir(), within: anywhere)
    check(recs.count == 2 && recs[0].backup != nil && recs[1].backup == nil, "backup only for replaced file")
    check(ModFiles.sha256(game.appendingPathComponent("a.dll")) == recs[0].sha256 && recs[0].sha256 != originalA, "new file installed")
    try! "edited".write(to: game.appendingPathComponent("new/b.asi"), atomically: true, encoding: .utf8)
    let r = ModFiles.remove(recs, later: [])
    check(r.changed == [game.appendingPathComponent("new/b.asi").path], "edited file kept and listed")
    check(ModFiles.sha256(game.appendingPathComponent("a.dll")) == originalA, "original restored")
    check(fm.fileExists(atPath: game.appendingPathComponent("new/b.asi").path) && fm.fileExists(atPath: game.appendingPathComponent("new").path), "kept file keeps its folder")
    let recs2 = try! ModFiles.apply(ModPlan(recipe: .dropIn, copies: [plan.copies[0]], overrides: [], programExe: nil), backups: tempDir(), within: anywhere)
    let r2 = ModFiles.remove(recs2, later: [[ModFileRecord(path: game.appendingPathComponent("A.DLL").path, sha256: "", backup: nil)]])
    check(r2.restored == 0 && fm.fileExists(atPath: game.appendingPathComponent("a.dll").path), "later mod's file left alone")

    let g3 = tempDir(); make(g3, ["old/"])
    let m3 = tempDir(); make(m3, ["x.cfg"])
    let p3 = ModPlan(recipe: .mirror, copies: [ModCopy(from: m3.appendingPathComponent("x.cfg"), to: g3.appendingPathComponent("old/deep/er/x.cfg"))], overrides: [], programExe: nil)
    let rec3 = try! ModFiles.apply(p3, backups: tempDir(), within: anywhere)
    let r3 = ModFiles.remove(rec3, later: [])
    check(r3.restored == 1 && r3.changed.isEmpty, "file removed")
    check(!fm.fileExists(atPath: g3.appendingPathComponent("old/deep").path) && fm.fileExists(atPath: g3.appendingPathComponent("old").path), "created folders removed, existing kept")

    let g4 = tempDir(); make(g4, ["a.dll"])
    let m4 = tempDir(); make(m4, ["a.dll", "n/c.asi"])
    let before = ModFiles.sha256(g4.appendingPathComponent("a.dll"))
    let p4 = ModPlan(recipe: .dropIn, copies: [
        ModCopy(from: m4.appendingPathComponent("a.dll"), to: g4.appendingPathComponent("a.dll")),
        ModCopy(from: m4.appendingPathComponent("n/c.asi"), to: g4.appendingPathComponent("n/c.asi")),
        ModCopy(from: m4.appendingPathComponent("missing.dll"), to: g4.appendingPathComponent("z/missing.dll"))], overrides: [], programExe: nil)
    var threw = false
    do { _ = try ModFiles.apply(p4, backups: tempDir(), within: anywhere) } catch { threw = true }
    check(threw, "apply throws when a copy fails")
    check(ModFiles.sha256(g4.appendingPathComponent("a.dll")) == before, "failed apply restores replaced file")
    check(!fm.fileExists(atPath: g4.appendingPathComponent("n").path) && !fm.fileExists(atPath: g4.appendingPathComponent("z").path), "failed apply removes new files and folders")

    let g5 = tempDir(); let m5 = tempDir(); make(m5, ["p.asi", "q.asi"])
    let p5 = ModPlan(recipe: .dropIn, copies: [
        ModCopy(from: m5.appendingPathComponent("p.asi"), to: g5.appendingPathComponent("new/p.asi")),
        ModCopy(from: m5.appendingPathComponent("q.asi"), to: g5.appendingPathComponent("new/q.asi"))], overrides: [], programExe: nil)
    let rec5 = try! ModFiles.apply(p5, backups: tempDir(), within: anywhere)
    let r5 = ModFiles.remove(rec5, later: [])
    check(r5.restored == 2 && r5.changed.isEmpty && !fm.fileExists(atPath: g5.appendingPathComponent("new").path), "shared new folder removed")

    let g6 = tempDir(); make(g6, ["a.dll"])
    let m6 = tempDir(); make(m6, ["one/a.dll", "two/a.dll"])
    let orig6 = ModFiles.sha256(g6.appendingPathComponent("a.dll"))
    let p6 = ModPlan(recipe: .dropIn, copies: [
        ModCopy(from: m6.appendingPathComponent("one/a.dll"), to: g6.appendingPathComponent("a.dll")),
        ModCopy(from: m6.appendingPathComponent("two/a.dll"), to: g6.appendingPathComponent("a.dll"))], overrides: [], programExe: nil)
    let rec6 = try! ModFiles.apply(p6, backups: tempDir(), within: anywhere)
    let r6 = ModFiles.remove(rec6, later: [])
    check(r6.changed.isEmpty && ModFiles.sha256(g6.appendingPathComponent("a.dll")) == orig6, "duplicate destination restores original")

    let g7 = tempDir(); make(g7, ["sub/a.dll"])
    let m7 = tempDir(); make(m7, ["new.dll"])
    try! "mod".write(to: m7.appendingPathComponent("new.dll"), atomically: true, encoding: .utf8)
    let rec7 = try! ModFiles.apply(ModPlan(recipe: .dropIn, copies: [ModCopy(from: m7.appendingPathComponent("new.dll"), to: g7.appendingPathComponent("sub/a.dll"))], overrides: [], programExe: nil), backups: tempDir(), within: anywhere)
    chmod(g7.appendingPathComponent("sub").path, 0o555)
    let r7 = ModFiles.remove(rec7, later: [])
    chmod(g7.appendingPathComponent("sub").path, 0o755)
    check(r7.restored == 0 && r7.notDeleted == [g7.appendingPathComponent("sub/a.dll").path] && r7.changed.isEmpty, "failed delete is kept, not restored")

    let g8 = tempDir(); make(g8, ["d3d9.dll"])
    let m8a = tempDir(); make(m8a, ["d3d9.dll"]); try! "A".write(to: m8a.appendingPathComponent("d3d9.dll"), atomically: true, encoding: .utf8)
    let m8b = tempDir(); make(m8b, ["d3d9.dll"]); try! "B".write(to: m8b.appendingPathComponent("d3d9.dll"), atomically: true, encoding: .utf8)
    let orig8 = ModFiles.sha256(g8.appendingPathComponent("d3d9.dll"))
    func one(_ from: URL, _ to: URL) -> ModPlan { ModPlan(recipe: .dropIn, copies: [ModCopy(from: from, to: to)], overrides: [], programExe: nil) }
    let recA = try! ModFiles.apply(one(m8a.appendingPathComponent("d3d9.dll"), g8.appendingPathComponent("d3d9.dll")), backups: tempDir(), within: anywhere)
    let recB = try! ModFiles.apply(one(m8b.appendingPathComponent("d3d9.dll"), g8.appendingPathComponent("D3D9.DLL")), backups: tempDir(), within: anywhere)
    let bOwnBackup = recB[0].backup!
    let rA = ModFiles.remove(recA, later: [recB])
    check(rA.restored == 0 && ModFiles.sha256(g8.appendingPathComponent("d3d9.dll")) == recB[0].sha256, "removing A leaves B's file")
    check(rA.later.count == 1 && rA.later[0][0].backup == recA[0].backup, "B takes over A's original")
    check(!fm.fileExists(atPath: bOwnBackup), "B's backup of A's file is deleted")
    let rB = ModFiles.remove(rA.later[0], later: [])
    check(rB.restored == 1 && ModFiles.sha256(g8.appendingPathComponent("d3d9.dll")) == orig8, "removing B then puts the original back")

    let g9 = tempDir()
    let a9 = try! ModFiles.apply(one(m8a.appendingPathComponent("d3d9.dll"), g9.appendingPathComponent("new/deep/x.dll")), backups: tempDir(), within: anywhere)
    let b9 = try! ModFiles.apply(one(m8b.appendingPathComponent("d3d9.dll"), g9.appendingPathComponent("new/deep/x.dll")), backups: tempDir(), within: anywhere)
    let rA9 = ModFiles.remove(a9, later: [b9])
    check(fm.fileExists(atPath: g9.appendingPathComponent("new/deep/x.dll").path), "A's removal leaves B's file and its folders")
    check(rA9.later[0][0].backup == nil && !fm.fileExists(atPath: b9[0].backup!), "B gets no original, and its backup of A's file goes")
    check(rA9.later[0][0].createdFolders == a9[0].createdFolders, "B takes over A's created folders")
    let rB9 = ModFiles.remove(rA9.later[0], later: [])
    check(rB9.restored == 1 && !fm.fileExists(atPath: g9.appendingPathComponent("new").path), "removing B removes the file and A's folders")

    let g10 = tempDir(); make(g10, ["a.dll"])
    let r10rec = try! ModFiles.apply(one(m8a.appendingPathComponent("d3d9.dll"), g10.appendingPathComponent("a.dll")), backups: tempDir(), within: anywhere)
    try! fm.removeItem(atPath: r10rec[0].backup!)
    let r10 = ModFiles.remove(r10rec, later: [])
    check(r10.restored == 0 && r10.notRestored == [ModFiles.NotRestored(path: g10.appendingPathComponent("a.dll").path, backup: nil)], "missing backup reported")

    let g11 = tempDir(); make(g11, ["sub/a.dll"])
    let r11rec = try! ModFiles.apply(one(m8a.appendingPathComponent("d3d9.dll"), g11.appendingPathComponent("sub/a.dll")), backups: tempDir(), within: anywhere)
    try! fm.removeItem(at: g11.appendingPathComponent("sub/a.dll"))
    chmod(g11.appendingPathComponent("sub").path, 0o555)
    let r11 = ModFiles.remove(r11rec, later: [])
    chmod(g11.appendingPathComponent("sub").path, 0o755)
    check(r11.restored == 0 && r11.notRestored == [ModFiles.NotRestored(path: g11.appendingPathComponent("sub/a.dll").path, backup: r11rec[0].backup)]
          && fm.fileExists(atPath: r11rec[0].backup!), "failed restore reported with its backup")

    let big = tempDir().appendingPathComponent("big.bin")
    let bigData = Data((0..<(3 * 1_048_576 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    try! bigData.write(to: big)
    check(ModFiles.sha256(big) == SHA256.hash(data: bigData).map { String(format: "%02x", $0) }.joined(), "chunked hash matches")
    check(ModFiles.sha256(tempDir().appendingPathComponent("nope")) == "", "unreadable file hashes to empty")

    let g12 = tempDir(); make(g12, ["a.dll"])
    let m12 = tempDir(); make(m12, ["dir/inner.txt"])
    let orig12 = ModFiles.sha256(g12.appendingPathComponent("a.dll"))
    let p12 = ModPlan(recipe: .dropIn, copies: [
        ModCopy(from: m8a.appendingPathComponent("d3d9.dll"), to: g12.appendingPathComponent("a.dll")),
        ModCopy(from: m12.appendingPathComponent("dir"), to: g12.appendingPathComponent("made/odd"))], overrides: [], programExe: nil)
    var unreadable: String?
    do { _ = try ModFiles.apply(p12, backups: tempDir(), within: anywhere) } catch let e as ModFiles.UnreadableFile { unreadable = e.path } catch {}
    check(unreadable == g12.appendingPathComponent("made/odd").path, "unreadable copy fails the install, got \(unreadable ?? "nil")")
    check(ModFiles.sha256(g12.appendingPathComponent("a.dll")) == orig12 && !fm.fileExists(atPath: g12.appendingPathComponent("made").path), "unreadable copy undone: original back, nothing left")

    let g13 = tempDir(); make(g13, ["a.dll"])
    let orig13 = ModFiles.sha256(g13.appendingPathComponent("a.dll"))
    let backups13 = tempDir()
    var failed13 = false
    do { _ = try ModFiles.apply(one(m12.appendingPathComponent("missing.dll"), g13.appendingPathComponent("a.dll")), backups: backups13, within: anywhere) } catch { failed13 = true }
    check(failed13 && ModFiles.sha256(g13.appendingPathComponent("a.dll")) == orig13, "failed copy after backup restores the original")
    check((try? fm.contentsOfDirectory(atPath: backups13.path))?.isEmpty == true, "restored backup leaves nothing in the backups folder")

    let g14 = tempDir(); let m14 = tempDir(); make(m14, ["p.asi", "q.asi"])
    let rec14 = try! ModFiles.apply(ModPlan(recipe: .dropIn, copies: [
        ModCopy(from: m14.appendingPathComponent("p.asi"), to: g14.appendingPathComponent("gone/p.asi")),
        ModCopy(from: m14.appendingPathComponent("q.asi"), to: g14.appendingPathComponent("stays/q.asi"))], overrides: [], programExe: nil), backups: tempDir(), within: anywhere)
    make(g14, ["gone/.DS_Store", "stays/.DS_Store", "stays/user.txt"])
    let r14 = ModFiles.remove(rec14, later: [])
    check(r14.restored == 2 && !fm.fileExists(atPath: g14.appendingPathComponent("gone").path), "folder with only .DS_Store is removed")
    check(fm.fileExists(atPath: g14.appendingPathComponent("stays/user.txt").path), "folder with a user file stays")

    let g15 = tempDir()
    let a15 = try! ModFiles.apply(one(m8a.appendingPathComponent("d3d9.dll"), g15.appendingPathComponent("one/x.dll")), backups: tempDir(), within: anywhere)
    let b15 = try! ModFiles.apply(one(m8b.appendingPathComponent("d3d9.dll"), g15.appendingPathComponent("one/x.dll")), backups: tempDir(), within: anywhere)
    check(a15[0].createdFolders == [g15.appendingPathComponent("one").path] && b15[0].createdFolders == nil, "only A created the folder")
    var b15deep = b15[0]; b15deep.createdFolders = [g15.appendingPathComponent("one").path, g15.appendingPathComponent("one/two").path]
    var a15deep = a15[0]; a15deep.createdFolders = [g15.appendingPathComponent("one").path]
    let r15 = ModFiles.remove([a15deep], later: [[b15deep]])
    check(r15.later[0][0].createdFolders == [g15.appendingPathComponent("one").path, g15.appendingPathComponent("one/two").path], "created folders merged without repeats, got \(r15.later[0][0].createdFolders ?? [])")
    check(fm.fileExists(atPath: g15.appendingPathComponent("one").path), "folders stay while the later mod owns the file")
}
