import Foundation

func runAssistantLookupTests() {
    let ac = UUID(), ak = UUID(), bio = UUID(), bio2 = UUID()
    let games: [(id: UUID, name: String)] = [(ac, "Batman: Arkham City"), (ak, "Batman: Arkham Knight"), (bio, "BioShock"), (bio2, "BioShock")]
    let lib = Array(games.prefix(3))
    check(AssistantLookup.matchGame(ac.uuidString, in: games) == .one(ac), "an id finds its game")
    check(AssistantLookup.matchGame("batman arkham city", in: games) == .one(ac), "exact name ignores case and punctuation")
    check(AssistantLookup.matchGame("city", in: games) == .one(ac), "a unique part of a name finds the game")
    check(AssistantLookup.matchGame("bioshock", in: lib) == .one(bio), "exact match wins")
    check(AssistantLookup.matchGame("arkham", in: games) == .ambiguous(["Batman: Arkham City", "Batman: Arkham Knight"]),
          "a part of several names lists them")
    if case .ambiguous(let names) = AssistantLookup.matchGame("bioshock", in: games) {
        check(names.count == 2 && names.allSatisfy { $0.contains("(id ") }, "same-named games are listed with their ids")
    } else { check(false, "two exact matches are ambiguous") }
    check(AssistantLookup.matchGame("Arkham Asylum", in: lib) == .none(["Batman: Arkham City", "Batman: Arkham Knight"]),
          "no match lists names sharing a word")
    check(AssistantLookup.matchGame("Half-Life", in: lib) == .none(["Batman: Arkham City", "Batman: Arkham Knight", "BioShock"]),
          "no close names lists the library")

    let home = "/Users/robin", game = "/Users/robin/Games/AC", driveC = "/Users/robin/F/Bottles/X/windows-mach9/drive_c"
    func req(_ p: String) -> String { AssistantLookup.requestedPath(p, gameFolder: game, driveC: driveC, home: home, user: "robin") }
    check(req("BmGame/Config/BmEngine.ini") == game + "/BmGame/Config/BmEngine.ini", "relative paths are in the game folder")
    check(req("C:/users/user/AppData/Local/x.ini") == driveC + "/users/robin/AppData/Local/x.ini", "C:/users/user is the real user folder")
    check(req(#"C:\users\Public\Documents\x.ini"#) == driveC + "/users/Public/Documents/x.ini", "Windows separators")
    check(req("~/F/Bottles/X/windows-mach9/drive_c/users/user/a.cfg") == driveC + "/users/robin/a.cfg", "scrubbed absolute paths come back")
    let real: Set<String> = [game + "/Profiles/robin/robin.ini", game + "/Profiles/robin", game + "/user/a.ini", game + "/user"]
    func reqFS(_ p: String) -> String {
        AssistantLookup.requestedPath(p, gameFolder: game, driveC: driveC, home: home, user: "robin", exists: real.contains)
    }
    check(reqFS("Profiles/user/user.ini") == game + "/Profiles/robin/robin.ini", "username folder and file come back")
    check(reqFS("user/a.ini") == game + "/user/a.ini", "a folder really called user stays")
    check(reqFS("Profiles/user/new.ini") == game + "/Profiles/robin/new.ini", "a new file in a username folder")
    check(reqFS("Nowhere/user/x.ini") == game + "/Nowhere/user/x.ini", "nothing to match: the path as given")
    check(AssistantLookup.unhidingUser("/a/user/b", user: "al", exists: { $0 == "/a/al/b" }) == "/a/user/b", "short usernames are never hidden, so never put back")

    let root = tempDir(), outside = tempDir()
    make(root, ["Game/Config/a.ini"])
    make(outside, ["secret.txt"])
    try? FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Game/escape"), withDestinationURL: outside)
    let roots = [root.appendingPathComponent("Game")]
    func plain(_ p: String) -> AssistantLookup.PathAccess {
        AssistantLookup.access(p, roots: roots, userFolders: root.appendingPathComponent("none"), home: "/nonexistent-home")
    }
    if case .inside = plain(root.path + "/Game/Config/a.ini") {} else { check(false, "a file inside a root is allowed") }
    if case .inside = plain(root.path + "/Game/Config/../../Game/Config/a.ini") {} else { check(false, "`..` that stays inside is allowed") }
    check(plain(root.path + "/Game/../Game2/a.ini") == .refused, "`..` out of the root is refused")
    check(plain(root.path + "/Game/escape/secret.txt") == .refused, "a symlink out of the root is refused")
    check(plain(root.path + "/GameX/a.ini") == .refused, "a folder that only starts like the root is outside")

    let base = tempDir(), fakeHome = base.appendingPathComponent("home"), elsewhere = base.appendingPathComponent("elsewhere")
    let users = fakeHome.appendingPathComponent("Bottles/X/drive_c/users"), gameDir = fakeHome.appendingPathComponent("Games/AC")
    make(base, ["home/Documents/WB/BmEngine.ini", "home/private.txt", "elsewhere/secret.ini", "home/Games/AC/a.ini", "home/Bottles/X/drive_c/users/robin/AppData/x.ini"])
    let fm = FileManager.default
    try? fm.createSymbolicLink(at: users.appendingPathComponent("robin/Documents"), withDestinationURL: fakeHome.appendingPathComponent("Documents"))
    try? fm.createSymbolicLink(at: users.appendingPathComponent("robin/Away"), withDestinationURL: elsewhere)
    func access(_ p: String) -> AssistantLookup.PathAccess {
        AssistantLookup.access(p, roots: [gameDir, users], userFolders: users, home: fakeHome.path)
    }
    if case .inside = access(gameDir.path + "/a.ini") {} else { check(false, "a game file is inside") }
    if case .inside = access(users.path + "/robin/AppData/x.ini") {} else { check(false, "a user-folder file is inside") }
    if case .linkedOutside(let u) = access(users.path + "/robin/Documents/WB/BmEngine.ini") {
        check(u.path.hasSuffix("/home/Documents/WB/BmEngine.ini"), "a linked folder gives the real file")
    } else { check(false, "Documents linked into the home folder asks first") }
    check(access(users.path + "/robin/Away/secret.ini") == .refused, "a link out of the home folder is refused")
    check(access(fakeHome.path + "/private.txt") == .refused, "a home file not reached through the user folders is refused")
    check(access(users.path + "/robin/../../../../../private.txt") == .refused, "`..` out of the user folders is refused")
    check(access(users.path + "/robin/Documents/../../../../private.txt") == .refused, "`..` through a linked folder is refused")
    check(access(gameDir.path + "/../../elsewhere/secret.ini") == .refused, "`..` out of the game folder is refused")
    make(base, ["home/Downloads/setup.ini", "home/.ssh/config", "home/Games/AC/.git/config"])
    func rooted(_ root: URL, _ p: String) -> AssistantLookup.PathAccess {
        AssistantLookup.access(p, roots: [root, users], userFolders: users, home: fakeHome.path)
    }
    if case .linkedOutside = rooted(fakeHome, fakeHome.path + "/private.txt") {} else { check(false, "a game folder that is home asks first") }
    if case .linkedOutside = rooted(fakeHome.appendingPathComponent("Downloads"), fakeHome.path + "/Downloads/setup.ini") {} else {
        check(false, "a game folder that is Downloads asks first")
    }
    if case .inside = rooted(gameDir, gameDir.path + "/a.ini") {} else { check(false, "a game folder deeper in home is the game's own") }
    if case .inside = rooted(fakeHome, users.path + "/robin/AppData/x.ini") {} else { check(false, "the user folders stay inside under a home game folder") }
    check(rooted(base, base.path + "/elsewhere/secret.ini") == .refused, "a game folder above home still refuses outside home")
    check(rooted(fakeHome, fakeHome.path + "/.ssh/config") == .refused, "hidden folders are refused in home")
    check(rooted(gameDir, gameDir.path + "/.git/config") == .refused, "hidden folders are refused in a game folder")
    check(access(users.path + "/robin/Documents/.hidden.ini") == .refused, "hidden files are refused in linked folders")
    make(base, ["home/Dropbox/ssh/config", "home/Games/AC/env.txt", "home/.wine/Game/a.ini"])
    try? fm.createSymbolicLink(at: fakeHome.appendingPathComponent(".sshlink"), withDestinationURL: fakeHome.appendingPathComponent("Dropbox/ssh"))
    try? fm.createSymbolicLink(at: gameDir.appendingPathComponent(".env"), withDestinationURL: gameDir.appendingPathComponent("env.txt"))
    check(rooted(fakeHome, fakeHome.path + "/.sshlink/config") == .refused, "a hidden link to a plain folder is refused in home")
    check(rooted(gameDir, gameDir.path + "/.env") == .refused, "a hidden link to a plain file is refused in a game folder")
    let hiddenGame = fakeHome.appendingPathComponent(".wine/Game")
    if case .inside = rooted(hiddenGame, hiddenGame.path + "/a.ini") {} else { check(false, "a game kept in a hidden folder still reads") }
    check(AssistantLookup.isPersonalFolder(fakeHome, home: fakeHome.path), "home is the Mac's own")
    check(AssistantLookup.isPersonalFolder(fakeHome.appendingPathComponent("Downloads"), home: fakeHome.path), "Downloads is the Mac's own")
    check(AssistantLookup.isPersonalFolder(base, home: fakeHome.path), "a folder home is in is the Mac's own")
    check(!AssistantLookup.isPersonalFolder(gameDir, home: fakeHome.path), "a game's folder deeper in home is the game's")
    check(AssistantLookup.walksInto(folderLevel: 5), "listings reach Documents/<publisher>/<game>/<engine>/Config")
    check(!AssistantLookup.walksInto(folderLevel: 6), "listings stop below 5 folders down")

    let b = ["/Users/robin/Games/Steam/Portal", "/P/drive_c", "/Users/robin"]
    for ok in ["/Users/robin/Games/Steam/Portal/cfg/config.cfg", "/P/drive_c/users/robin/AppData/Local/Game/Settings.ini",
               "/P/drive_c/users/robin/Documents/x.log", "/P/drive_c/a.YAML", "/Users/robin/Documents/Origins/a.toml"] {
        check(AssistantLookup.plainReadCovers(ok, bases: b), "plain read covers \(ok)")
    }
    for ask in ["/P/drive_c/users/robin/AppData/Local/EpicGamesLauncher/Saved/Config/Windows/GameUserSettings.ini",
                "/P/drive_c/Program Files (x86)/Steam/config/config.json", "/P/drive_c/users/robin/AppData/Roaming/Origin/local.xml",
                "/P/drive_c/ProgramData/Battle.net/Agent/agent.json", "/P/drive_c/Program Files/EA Desktop/x.ini",
                "/P/drive_c/users/robin/AppData/Local/Electronic Arts/EA Desktop/user.ini",
                "/P/drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/settings.yml", "/P/drive_c/GOG.com/a.ini",
                "/P/drive_c/ProgramData/GOG Galaxy/config.json", "/P/drive_c/users/robin/Documents/Rockstar Games/Launcher/settings.json",
                "/P/drive_c/Program Files/Epic Games/Launcher/a.ini", "/Users/robin/Games/Steam/Portal/loginusers.VDF",
                "/Users/robin/Games/Steam/Portal/save.dat", "/Users/robin/Games/Steam/Portal/ssfn123", "/P/drive_c/STEAM/a.txt"] {
        check(!AssistantLookup.plainReadCovers(ask, bases: b), "asks every time for \(ask)")
    }
    check(!AssistantLookup.isLauncherFile("/P/drive_c/users/robin/Documents/Rockstar Games/GTA V/settings.xml", bases: b),
          "Rockstar Games alone isn't the launcher")
    check(AssistantLookup.isLauncherFile("/Volumes/Steam/x.ini", bases: b), "outside every base the whole path counts")

    check(AssistantLookup.text(of: Data("[Engine]\nA=1".utf8)) == "[Engine]\nA=1", "UTF-8 text reads")
    check(AssistantLookup.text(of: Data([0x4D, 0x5A, 0x00, 0x01])) == nil, "binaries are refused")
    var utf16 = Data([0xFF, 0xFE]); utf16.append("A=1".data(using: .utf16LittleEndian)!)
    check(AssistantLookup.text(of: utf16) == "A=1", "UTF-16 config files read")
    check(AssistantLookup.text(of: Data([0x63, 0x61, 0x66, 0xE9])) == "café", "Windows Latin text reads")

    check(AssistantLookup.capped(["a", "b", "c"], max: 2) == ["a", "b", "… and 1 more"], "lists are capped")
    check(AssistantLookup.clipped("abcdef", maxChars: 4) == "abcd\n… (2 more characters cut)", "text is clipped")
    check(AssistantLookup.clipped("abc", maxChars: 4) == "abc", "short text is kept")
}
