import Foundation

func runAssistantTextTests() {
    let s = AssistantText.scrub("""
        /Users/robin/Games/AC/BatmanAC.exe
        Z:\\Users\\robin\\Games\\AC\\x.dll
        C:\\users\\robin\\Documents\\My Games\\a.ini
        """, home: "/Users/robin", user: "robin", gameFolder: "/Users/robin/Games/AC")
    check(!s.contains("robin"), "scrub removes the username in every form")
    check(s.contains("BatmanAC.exe") && s.contains("x.dll") && !s.contains("Games/AC"), "game folder shown relative")
    check(s.contains("C:\\users\\user\\Documents"), "Windows user folder becomes users\\user")
    check(AssistantText.scrub("/Users/robinson/a /Users/robin/b", home: "/Users/robin", user: "robin", gameFolder: nil) == "/Users/robinson/a ~/b",
          "scrub leaves longer names alone")
    check(AssistantText.scrub("Saved to /Users/robin. Also /Users/robin- and /Users/robin", home: "/Users/robin", user: "robin", gameFolder: nil) == "Saved to ~. Also ~- and ~",
          "scrub handles a path ending a sentence")
    check(AssistantText.scrub("/Users/robin/.wine/drive_c/users/robin/AppData C:/Users/robin/x", home: "/Users/robin", user: "robin", gameFolder: nil) == "~/.wine/drive_c/users/user/AppData C:/users/user/x",
          "scrub handles forward-slash Wine users paths")
    let esc = AssistantText.scrub(#"L"C:\\users\\robin\\Desktop\\game.exe" L"Z:\\Users\\robin\\Games\\AC\\x.dll" L"Z:\\Users\\robin\\Games\\AC""#,
                                  home: "/Users/robin", user: "robin", gameFolder: "/Users/robin/Games/AC")
    check(esc == #"L"C:\\users\\user\\Desktop\\game.exe" L"x.dll" L".""#, "scrub handles Wine's escaped paths: \(esc)")
    check(AssistantText.scrub(#"Z:\\Users\\robin\\Desktop Z:\Users\robin\Desktop"#, home: "/Users/robin", user: "robin", gameFolder: nil)
          == #"Z:\\users\\user\\Desktop Z:\users\user\Desktop"#, "scrub handles the home folder in Windows forms")
    check(AssistantText.scrub("USERNAME=robin /Users/robin.Next robin_x", home: "/Users/robin", user: "robin", gameFolder: nil)
          == "USERNAME=user /Users/user.Next robin_x", "scrub replaces the bare username as a whole word")
    check(AssistantText.scrub("Robin wrote this", home: "/Users/robin", user: "robin", gameFolder: nil) == "Robin wrote this",
          "whole-word pass is case-sensitive")
    check(AssistantText.scrub("also al ok, C:\\users\\al\\x", home: "/Users/al", user: "al", gameFolder: nil) == "also al ok, C:\\users\\user\\x",
          "short usernames are left alone outside paths")

    check(AssistantText.isSaveFile("Documents/My Games/AC/Saves/slot1.sgd"), "Saves folder is a save")
    check(AssistantText.isSaveFile("AppData/Roaming/Game/SaveGames/a.dat"), "SaveGames folder is a save")
    check(AssistantText.isSaveFile("profile.sav"), "sav extension is a save")
    check(AssistantText.isSaveFile("Program Files/Steam/userdata/123/remote/x.bin"), "Steam cloud folder is a save")
    check(!AssistantText.isSaveFile("Documents/My Games/AC/settings.ini"), "settings.ini is not a save")
    check(!AssistantText.isSaveFile("BmGame/Config/UserEngine.ini"), "engine config is not a save")

    let log = (1...500).map { "info: line \($0)" }.joined(separator: "\n") + "\nerr: Failed to create PSO\nwarn: x"
    let f = AssistantText.focusLog(log, search: nil, maxLines: 40)
    check(f.contains("err: Failed to create PSO"), "focusLog keeps errors")
    check(f.split(separator: "\n").count <= 40, "focusLog respects maxLines")
    check(AssistantText.focusLog(log, search: "line 250", maxLines: 40).contains("info: line 250"), "focusLog keeps search hits")
    let rep = AssistantText.focusLog("err: a\nerr: a\nerr: a", search: nil, maxLines: 40)
    check(rep == "err: a", "focusLog drops repeats")
}
