import Foundation

func runNamingTests() {
    func name(_ path: String, product: String? = nil) -> String {
        Naming.friendlyName(for: URL(fileURLWithPath: path)) { _ in product }
    }
    check(name("/Games/Notepad++/notepad++.exe") == "Notepad++", "an all-lower-case name takes the folder")
    check(name("/Games/Terraria/Terraria.exe") == "Terraria", "a capitalised name is kept")
    check(name("/Games/Hollow Knight/hollow_knight.exe") == "Hollow Knight", "an all-lower-case name with spaces takes the folder")
    check(name("/Games/Stuff/Celeste.exe") == "Celeste", "a capitalised name is kept even if the folder differs")
    check(name("/Games/Hollow Knight/Launcher.exe") == "Hollow Knight", "a generic name takes the folder")
    check(name("/Games/Some Game/Binaries/Win64/Game.exe") == "Some Game", "a generic name walks up out of Binaries/Win64")
    check(name("/Games/CoD/Call of Duty 4 Modern Warfare/iw3sp.exe", product: "Call of Duty(R) 4 - Modern Warfare(TM)")
          == "Call of Duty 4 - Modern Warfare", "a code-like name takes the tidied product name")
    check(name("/Games/CoD/Call of Duty 4 Modern Warfare/iw3sp.exe") == "Call of Duty 4 Modern Warfare",
          "a code-like name without a product name takes the folder")
    check(name("/Games/Elden Ring/Game/eldenring.exe", product: "ELDEN RING™") == "ELDEN RING", "trademark signs are removed")
    check(name("/Games/X/bin/hl2.exe", product: "Unity") == "X", "an engine's product name is ignored")
    check(name("/Users/me/Downloads/iw4mp.exe") == "iw4mp", "a place folder like Downloads isn't used as a name")
    check(name("/Games/Tool/tool2.exe", product: "ab") == "Tool", "a product name too short to be a title is ignored")
    check(Naming.looksLikeCode("witcher3") && Naming.looksLikeCode("DOOM3") && !Naming.looksLikeCode("Notepad++")
          && !Naming.looksLikeCode("Call of Duty"), "what reads like a code")
}
