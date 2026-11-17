import Foundation

func runSafetyTests() {
    let fm = FileManager.default

    let normal = tempDir(); make(normal, ["Fix/", "Fix/d3d9.dll", "Fix/scripts/a.asi", ".hidden/x.txt"])
    check(!ModLayout.escapes(normal), "normal tree doesn't escape")
    let out = tempDir(); make(out, ["secret.txt"])
    let linkOut = tempDir(); make(linkOut, ["Fix/a.dll"])
    try! fm.createSymbolicLink(atPath: linkOut.appendingPathComponent("Fix/evil").path, withDestinationPath: out.path)
    check(ModLayout.escapes(linkOut), "symlink pointing outside escapes")
    let linkIn = tempDir(); make(linkIn, ["Fix/a.dll"])
    try! fm.createSymbolicLink(atPath: linkIn.appendingPathComponent("Fix/b.dll").path, withDestinationPath: "a.dll")
    check(ModLayout.escapes(linkIn), "symlink pointing inside is still refused")
    let linkHidden = tempDir(); make(linkHidden, ["a.dll", "__MACOSX/"])
    try! fm.createSymbolicLink(atPath: linkHidden.appendingPathComponent("__MACOSX/l").path, withDestinationPath: "/etc")
    check(ModLayout.escapes(linkHidden), "a link hidden in __MACOSX is found too")
    let locked = tempDir(); make(locked, ["a.dll", "sub/b.dll"])
    chmod(locked.appendingPathComponent("sub").path, 0o000)
    check(ModLayout.escapes(locked), "a folder that can't be listed counts as escaping")
    chmod(locked.appendingPathComponent("sub").path, 0o755)
    let linkTop = tempDir()
    try! fm.createSymbolicLink(atPath: linkTop.appendingPathComponent("up").path, withDestinationPath: "..")
    check(ModLayout.escapes(linkTop), "a top-level link escapes")

    let g = URL(fileURLWithPath: "/Games/Doom 3")
    check(ModLayout.isInside(URL(fileURLWithPath: "/games/DOOM 3/base/x.pk4"), g), "inside ignores case")
    check(!ModLayout.isInside(URL(fileURLWithPath: "/Games/Doom 3/../evil.dll"), g), "\"..\" leaves the folder")
    check(!ModLayout.isInside(URL(fileURLWithPath: "/Games/Doom 3 (dhewm3)/dhewm3.exe"), g), "a sibling with a longer name is not inside")
    check(!ModLayout.isInside(g, g), "the folder itself is not inside itself")

    let game = tempDir(); make(game, ["game.exe", "base/pak000.pk4"])
    let folders = GameFolders(exeFolder: game, root: game, is64bit: true)
    let mod = tempDir(); make(mod, ["evil.dll", "ok.cfg"])
    let escaping = ModPlan(recipe: .mirror, copies: [
        ModCopy(from: mod.appendingPathComponent("ok.cfg"), to: game.appendingPathComponent("base/ok.cfg")),
        ModCopy(from: mod.appendingPathComponent("evil.dll"), to: game.appendingPathComponent("base/../../evil.dll"))],
                           overrides: [], programExe: nil)
    var refused = false
    do { _ = try ModFiles.apply(escaping, backups: tempDir(), within: ModLayout.allowedFolders(escaping, game: folders)) }
    catch is ModFiles.Outside { refused = true } catch {}
    check(refused, "a plan with \"..\" in a destination is refused")
    check(!fm.fileExists(atPath: game.appendingPathComponent("base/ok.cfg").path)
          && !fm.fileExists(atPath: game.deletingLastPathComponent().appendingPathComponent("evil.dll").path), "refused plan changes nothing")

    let clashGame = tempDir(); make(clashGame, ["Doom 3/base/pak000.pk4", "Doom 3/doom3.exe"])
    let d3 = clashGame.appendingPathComponent("Doom 3")
    let port = tempDir(); make(port, ["base/x.dll", "dhewm3.exe"])
    let pf = GameFolders(exeFolder: d3, root: d3, is64bit: true)
    let portPlan = ModLayout.plan(port, game: pf)
    check(portPlan?.recipe == .program && portPlan?.programExe?.path.contains("Doom 3 (dhewm3)") == true, "port with a clash goes beside the game")
    if let portPlan {
        check(ModLayout.allowedFolders(portPlan, game: pf).contains { ModLayout.samePath($0, clashGame.appendingPathComponent("Doom 3 (dhewm3)")) },
              "a port's own folder is allowed")
        let recs = try? ModFiles.apply(portPlan, backups: tempDir(), within: ModLayout.allowedFolders(portPlan, game: pf))
        check(recs?.count == 2, "a port beside the game installs")
        var stray = portPlan
        stray.copies.append(ModCopy(from: port.appendingPathComponent("dhewm3.exe"), to: clashGame.appendingPathComponent("Other/dhewm3.exe")))
        var strayRefused = false
        do { _ = try ModFiles.apply(stray, backups: tempDir(), within: ModLayout.allowedFolders(stray, game: pf)) }
        catch is ModFiles.Outside { strayRefused = true } catch {}
        check(strayRefused, "a program's file outside its own folder is refused")
    }

    let gb: Int64 = 1_000_000_000
    check(ModSpace.enough(free: 3 * gb, needed: 2 * gb), "exactly needed + 1 GB is enough")
    check(!ModSpace.enough(free: 3 * gb - 1, needed: 2 * gb), "a byte short is not enough")
    check(!ModSpace.enough(free: 0, needed: 0), "no free space is never enough")
    check(ModSpace.downloadNeed(100) == 300, "a download needs three times its size")
    check(!ModSpace.enough(free: Int64.max, needed: ModSpace.downloadNeed(Int64.max / 2)), "huge sizes don't overflow")
    let sized = tempDir(); make(sized, ["new.bin", "old.bin"])
    try! Data(count: 1000).write(to: sized.appendingPathComponent("new.bin"))
    try! Data(count: 300).write(to: sized.appendingPathComponent("old.bin"))
    let target = tempDir(); try! Data(count: 300).write(to: target.appendingPathComponent("old.bin"))
    let spacePlan = ModPlan(recipe: .mirror, copies: [
        ModCopy(from: sized.appendingPathComponent("new.bin"), to: target.appendingPathComponent("new.bin")),
        ModCopy(from: sized.appendingPathComponent("old.bin"), to: target.appendingPathComponent("old.bin"))], overrides: [], programExe: nil)
    check(ModSpace.installBytes(spacePlan) == 1600, "install needs the copies plus backups of replaced files")

    let doom = URL(fileURLWithPath: "/Games/Doom 3/Doom3.exe")
    check(ModLayout.sharesGameFolder(URL(fileURLWithPath: "/games/doom 3/dhewm3.exe"), with: doom), "a port in the game folder shares it")
    check(ModLayout.sharesGameFolder(URL(fileURLWithPath: "/Games/Doom 3/Binaries/Win64/x.exe"), with: doom), "an exe deeper in the game folder shares it")
    check(ModLayout.sharesGameFolder(doom, with: URL(fileURLWithPath: "/Games/Doom 3/dhewm3.exe")), "and the other way round")
    check(!ModLayout.sharesGameFolder(URL(fileURLWithPath: "/Games/Doom 3 (dhewm3)/dhewm3.exe"), with: doom), "a port beside the game doesn't")

    let doomID = UUID(), besideID = UUID(), otherID = UUID()
    let beside = URL(fileURLWithPath: "/Games/Doom 3 (dhewm3)/dhewm3.exe")
    check(ModLayout.blocksMods(entry: doomID, exe: doom, game: doomID, gameExe: doom, modPrograms: []), "the game itself blocks")
    check(ModLayout.blocksMods(entry: besideID, exe: beside, game: doomID, gameExe: doom, modPrograms: [besideID]),
          "a running beside port blocks Doom 3's mods")
    check(!ModLayout.blocksMods(entry: otherID, exe: beside, game: doomID, gameExe: doom, modPrograms: [besideID]),
          "an unrelated program beside the game doesn't block")
    check(ModLayout.blocksMods(entry: otherID, exe: URL(fileURLWithPath: "/Games/Doom 3/dhewm3.exe"), game: doomID, gameExe: doom, modPrograms: []),
          "a program in the game folder blocks")

    let upd = ModPlan(recipe: .mirror, copies: [ModCopy(from: port.appendingPathComponent("dhewm3.exe"), to: URL(fileURLWithPath: "/Games/Doom 3/DHEWM3.exe"))],
                      overrides: [], programExe: nil)
    check(ModLayout.replaces(upd, anyOf: [URL(fileURLWithPath: "/x/y.exe"), URL(fileURLWithPath: "/Games/Doom 3/dhewm3.exe")]) == 1, "update finds the port's exe")
    check(ModLayout.replaces(upd, anyOf: [URL(fileURLWithPath: "/x/y.exe")]) == nil, "no installed port, no update")
}
