import Foundation

func runProgramChoiceTests() {
    check(ProgramChoice.role(fileName: "iw4sp.exe", description: nil) == .singleplayer, "iw4sp")
    check(ProgramChoice.role(fileName: "iw4mp.exe", description: nil) == .multiplayer, "iw4mp")
    check(ProgramChoice.role(fileName: "CoD2MP_s.exe", description: nil) == .multiplayer, "CoD2MP_s")
    check(ProgramChoice.role(fileName: "CoDSP.exe", description: nil) == .singleplayer, "CoDSP")
    check(ProgramChoice.role(fileName: "Wasp.exe", description: nil) == .other, "a name merely ending in sp")
    check(ProgramChoice.role(fileName: "Game.exe", description: "Call of Duty Multiplayer") == .multiplayer, "from the description")
    check(ProgramChoice.role(fileName: "iw4m_ded.exe", description: nil) == .server, "dedicated server")
    check(ProgramChoice.role(fileName: "CoDWaWmp.exe", description: nil) == .multiplayer, "World at War")
    check(ProgramChoice.role(fileName: "Launcher.exe", description: nil) == .launcher, "launcher")
    check(ProgramChoice.role(fileName: "GraphicsConfig.exe", description: nil) == .settings, "settings tool")
    check(ProgramChoice.label(fileName: "iw4sp.exe", description: "Modern Warfare 2", role: .singleplayer) == "Single-player · Modern Warfare 2",
          "label with role and description")
    check(ProgramChoice.label(fileName: "x.exe", description: nil, role: .other) == "x.exe", "bare file name")
    check(ProgramChoice.isClose([(.singleplayer, 20), (.multiplayer, 12)]), "a single-player and multiplayer pair is always asked")
    check(!ProgramChoice.isClose([(.other, 25), (.other, 15)]), "a clear winner isn't asked")
    check(ProgramChoice.isClose([(.other, 20), (.launcher, 19)]), "two close programs are asked")
    check(!ProgramChoice.isClose([(.other, 20), (.server, 19.5)]), "a server doesn't count")

    func roles(_ names: String...) -> [ProgramRole] { ProgramChoice.roles(of: names.map { ($0, nil) }) }
    check(roles("jasp.exe", "jamp.exe") == [.singleplayer, .multiplayer], "Jedi Academy's pair")
    check(roles("WolfSP.exe", "WolfMP.exe") == [.singleplayer, .multiplayer], "Return to Castle Wolfenstein's pair")
    check(roles("SoF2SP.exe", "SoF2MP.exe", "SoF2Ded.exe") == [.singleplayer, .multiplayer, .server], "Soldier of Fortune II")
    check(roles("wasp.exe", "clamp.exe") == [.other, .other], "names that only end in sp/mp, with no pair")
    check(roles("hl.exe", "hlds.exe") == [.other, .server], "Half-Life and its server")
    check(roles("TESV.exe", "SkyrimLauncher.exe", "CreationKit.exe") == [.other, .launcher, .editor], "Skyrim's folder")
    check(roles("UT2004.exe", "UnrealEd.exe", "UCC.exe") == [.other, .editor, .editor], "Unreal Tournament 2004's folder")
    check(roles("Game.exe", "Game.exe") == [.other, .other], "nothing to go on stays neutral")
    check(roles("iw6sp64_ship.exe", "iw6mp64_ship.exe") == [.singleplayer, .multiplayer], "Ghosts' build endings")
    check(roles("BlackOps.exe", "BlackOpsMP.exe") == [.singleplayer, .multiplayer], "Black Ops: plain name plus MP")
    check(roles("Bump.exe") == [.other], "a lone name ending in mp")
    check(ProgramChoice.stem("Game-Win64-Shipping.exe") == "game-win", "Unreal's -Shipping ending")

    let mw2 = roles("iw4sp.exe", "iw4mp.exe", "iw4m_ded.exe")
    check(ProgramChoice.partner(of: 0, roles: mw2, inLibrary: [true, false, false]) == 1, "single-player added: offer multiplayer")
    check(ProgramChoice.partner(of: 1, roles: mw2, inLibrary: [false, true, false]) == 0, "multiplayer added: offer single-player")
    check(ProgramChoice.partner(of: 0, roles: mw2, inLibrary: [true, true, false]) == nil, "already in the library: no offer")
    check(ProgramChoice.partner(of: 0, roles: roles("TESV.exe", "SkyrimLauncher.exe"), inLibrary: [true, false]) == nil,
          "no single-player/multiplayer split: no offer")
    check(ProgramChoice.partner(of: 2, roles: mw2, inLibrary: [false, false, true]) == nil, "a server never gets an offer")
}
