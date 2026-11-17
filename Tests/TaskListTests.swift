import Foundation

func runTaskListTests() {
    check(TaskList.programName("C:\\windows\\system32\\services.exe ") == "services.exe", "system program")
    check(TaskList.programName("/Users/me/Library/Application Support/Ferry/Cache/windows/vcredist_2005.x86.exe /q") == "vcredist_2005.x86.exe",
          "Mac path with spaces and arguments")
    check(TaskList.programName("\"C:\\Program Files (x86)\\Minecraft Launcher\\MinecraftLauncher.exe\" --type=gpu-process") == "MinecraftLauncher.exe",
          "quoted path")
    check(TaskList.programName("Z:\\Users\\me\\Games\\Game.EXE") == "Game.EXE", "upper-case extension")
    check(TaskList.programName("msiexec /i vcredist.msi") == "msiexec", "Windows command without .exe")
    check(TaskList.programName("ping -n 20 127.0.0.1") == "ping", "ping")
    check(TaskList.programName("/Applications/Ferry.app/Contents/MacOS/wineserver") == nil, "wineserver isn't a Windows program")

    check(TaskList.isWineSystem(name: "services.exe", commandLine: "C:\\windows\\system32\\services.exe"), "services is Wine's")
    check(TaskList.isWineSystem(name: "explorer.exe", commandLine: "C:\\windows\\system32\\explorer.exe /desktop"), "desktop shell is Wine's")
    check(!TaskList.isWineSystem(name: "explorer.exe", commandLine: "C:\\windows\\explorer.exe C:\\"), "a File Explorer window isn't")
    check(!TaskList.isWineSystem(name: "Game.exe", commandLine: "Game.exe"), "a game isn't")

    let root = "/Users/me/Library/Application Support/Ferry"
    let id = UUID()
    check(TaskList.owner(ofPrefix: root + "/Bottles/\(id.uuidString)/windows-mach9", root: root) == .game(id, kind: "mach9"), "game")
    check(TaskList.owner(ofPrefix: root + "/Templates/windows-arm64.building", root: root) == .setup(kind: "arm64"), "setup being built")
    check(TaskList.owner(ofPrefix: root + "/Templates/windows-staging", root: root) == .setup(kind: "staging"), "setup")
    check(TaskList.owner(ofPrefix: root + "/Runtimes/webview2.building", root: root) == .other(root + "/Runtimes/webview2.building"), "other")
    check(TaskList.owner(ofPrefix: root + "/Bottles/not-an-id/windows-mach9", root: root) == .other(root + "/Bottles/not-an-id/windows-mach9"),
          "folder that isn't a game id")

    var bytes: [UInt8] = [2, 0, 0, 0]
    bytes += Array("/path/wine-preloader".utf8) + [0, 0, 0, 0]
    bytes += Array("C:\\a b\\Game.exe".utf8) + [0] + Array("-x".utf8) + [0]
    bytes += Array("WINEPREFIX=/p/windows-mach9".utf8) + [0] + Array("A=b=c".utf8) + [0, 0]
    let parsed = TaskList.parseProcArgs(bytes)
    check(parsed.args == ["C:\\a b\\Game.exe", "-x"], "argv")
    check(parsed.env["WINEPREFIX"] == "/p/windows-mach9" && parsed.env["A"] == "b=c", "environment")
    check(TaskList.parseProcArgs([1, 0]).args.isEmpty, "short buffer")

    let folder = tempDir()
    var info = stat()
    _ = stat(folder.path, &info)
    let expected = "server-" + String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16) + "-" + String(info.st_ino, radix: 16)
    check(TaskList.serverName(forPrefix: folder.path) == expected, "server folder name")
    check(TaskList.serverName(forPrefix: folder.path + "/missing") == nil, "missing folder")

    let ferry = "/F"
    check(TaskList.environment(containing: "/F/Bottles/A/windows-arm64/drive_c/windows/system32", root: ferry) == "/F/Bottles/A/windows-arm64",
          "folder inside a game's environment")
    check(TaskList.environment(containing: "/F/Templates/windows-mach9/drive_c", root: ferry) == "/F/Templates/windows-mach9",
          "folder inside a ready-made environment")
    check(TaskList.environment(containing: "/F/Bottles/A/saves", root: ferry) == nil, "game folder that isn't an environment")
    check(TaskList.environment(containing: "/Users/me/Games", root: ferry) == nil, "folder outside Ferry")
    check(TaskList.gpuClientPID("pid 413, WindowServer") == 413, "GPU client pid")
    check(TaskList.gpuClientPID("WindowServer") == nil, "GPU client without pid")
    check(TaskList.gpuSnapshot().devicePercent != nil, "reads the GPU's use")
}
