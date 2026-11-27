import Foundation

func runAssistantRunsTests() {
    typealias F = AssistantRuns.StartFacts
    func downloads(_ change: (inout F) -> Void) -> [String] {
        var f = F()
        f.engineTitle = "Mach9 Wine"
        f.uncachedLibraries = ["PhysX (legacy games)"]
        change(&f)
        return AssistantRuns.startDownloads(f)
    }
    check(downloads { _ in } == [], "a game with everything in place downloads nothing")
    check(downloads { $0.engineInstalled = false } == ["Mach9 Wine"], "a missing engine is named")
    check(downloads { $0.usesDXVK = true; $0.dxvkInstalled = false } == ["DXVK"], "DXVK when it draws and is missing")
    check(downloads { $0.dxvkInstalled = false } == [], "DXVK missing but unused downloads nothing")
    check(downloads { $0.buildsTemplateOnFirstUse = true; $0.hasEnvironment = false; $0.hasTemplate = false }
          == ["PhysX (legacy games)"], "building the ready-made environment downloads uncached libraries")
    check(downloads { $0.buildsTemplateOnFirstUse = true; $0.hasEnvironment = false; $0.hasTemplate = false; $0.shared = true } == [],
          "a game in another's environment builds nothing")
    check(downloads { $0.librariesInstalled = false; $0.hasEnvironment = false } == [],
          "a new environment copied from the ready-made one already has its libraries")
    check(downloads { $0.librariesInstalled = false; $0.hasEnvironment = false; $0.hasTemplate = false } == ["PhysX (legacy games)"],
          "an environment built from scratch gets libraries installed")
    check(downloads { $0.librariesInstalled = false } == ["PhysX (legacy games)"], "an existing environment without libraries gets them")
    check(downloads { $0.librariesInstalled = false; $0.autoLibraries = false } == [], "libraries off in settings: none")
    check(downloads { $0.mullion32 = true; $0.metalSharpFullBuild = false } == ["MetalSharp Wine's build for 32-bit games", "PhysX (legacy games)"],
          "a 32-bit game on the 64-bit-only MetalSharp: the full build and a rebuilt environment")
    check(downloads { $0.mullion32 = true; $0.mullionTemplateCurrent = false } == ["PhysX (legacy games)"], "an outdated Mullion environment is rebuilt")
    check(downloads { $0.mullion32 = true; $0.engineInstalled = false; $0.engineTitle = "MetalSharp" } == ["MetalSharp", "PhysX (legacy games)"],
          "a fresh MetalSharp is the full build already")
    check(downloads { $0.dgVoodooOn = true; $0.dgVoodooReady = false } == [], "dgVoodoo2 only for 32-bit games")
    check(downloads { $0.dgVoodooOn = true; $0.dgVoodooReady = false; $0.x86 = true } == ["dgVoodoo2 (about 7 MB)"], "dgVoodoo2")
    check(downloads { $0.cncDdrawOn = true; $0.cncDdrawReady = false; $0.cncDdrawZipCached = false } == ["cnc-ddraw (about 2 MB)"], "cnc-ddraw")
    check(downloads { $0.cncDdrawOn = true; $0.cncDdrawReady = false; $0.cncDdrawZipCached = false; $0.ddrawBesideGame = true } == [],
          "a game with its own ddraw.dll gets no cnc-ddraw")
    check(downloads { $0.cncDdrawOn = true; $0.cncDdrawReady = false; $0.cncDdrawZipCached = false; $0.dgVoodooOn = true; $0.dgVoodooReady = false; $0.x86 = true }
          == ["dgVoodoo2 (about 7 MB)"], "dgVoodoo2 takes cnc-ddraw's place")
    check(downloads { $0.x86 = true; $0.directMusicOrPlayOn = true; $0.legacyDirectXReady = false; $0.sevenZipInstalled = false }
          == ["DirectMusic and DirectPlay (about 105 MB)", "7-Zip (under 1 MB)"], "DirectMusic needs its package and 7-Zip")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = true; $0.dotNetLoaderReady = false } == [".NET loader (about 50 MB)"],
          ".NET loader for a .NET program")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = nil; $0.dotNetLoaderReady = false } == [".NET loader (about 50 MB)"],
          "when Ferry can't tell whether .NET is there, it counts")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = false; $0.dotNetLoaderReady = false } == [], "no .NET in the environment: nothing")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = false; $0.dotNetLoaderReady = false; $0.dotNet48On = true
                      $0.librariesInstalled = false; $0.uncachedLibraries = []; $0.managedDirectXInEnvironment = false
                      $0.managedDirectXReady = false; $0.directXPackageCached = false; $0.sevenZipInstalled = false }
          == [".NET loader (about 50 MB)", "DirectX (June 2010) for Managed DirectX (about 100 MB)", "7-Zip (under 1 MB)"],
          "libraries installed during the start bring .NET, so its parts count even though the environment lacks it now")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = false; $0.dotNetLoaderReady = false; $0.dotNet48On = true
                      $0.mullion32 = true; $0.mullionTemplateCurrent = false; $0.uncachedLibraries = [] } == [".NET loader (about 50 MB)"],
          "a rebuilt environment may bring .NET too")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = false; $0.dotNetLoaderReady = false
                      $0.librariesInstalled = false; $0.uncachedLibraries = [] } == [], ".NET 4.8 not ticked: libraries don't bring it")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = true; $0.managedDirectXInEnvironment = false; $0.managedDirectXReady = false }
          == [], "Managed DirectX from the cached DirectX package downloads nothing")
    check(downloads { $0.dotNetProgram = true; $0.dotNetInEnvironment = true; $0.managedDirectXInEnvironment = nil
                      $0.managedDirectXReady = false; $0.directXPackageCached = false; $0.sevenZipInstalled = false }
          == ["DirectX (June 2010) for Managed DirectX (about 100 MB)", "7-Zip (under 1 MB)"], "Managed DirectX's package")

    let list: [[String: Any]] = [
        ["kCGWindowNumber": 10, "kCGWindowOwnerPID": 50, "kCGWindowLayer": 0, "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 800, "Height": 600]],
        ["kCGWindowNumber": 11, "kCGWindowOwnerPID": 50, "kCGWindowLayer": 0, "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 1920, "Height": 1080]],
        ["kCGWindowNumber": 12, "kCGWindowOwnerPID": 50, "kCGWindowLayer": 3, "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 4000, "Height": 4000]],
        ["kCGWindowNumber": 13, "kCGWindowOwnerPID": 51, "kCGWindowLayer": 0, "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 32, "Height": 32]],
        ["kCGWindowNumber": 14, "kCGWindowOwnerPID": 99, "kCGWindowLayer": 0, "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 3000, "Height": 2000]],
        ["kCGWindowOwnerPID": 50],
    ]
    let windows = AssistantRuns.windows(from: list)
    check(windows.count == 5, "window entries without a number are skipped")
    check(AssistantRuns.pickWindow(windows, pids: [50, 51]) == 11, "the biggest ordinary window of the game's processes")
    check(AssistantRuns.pickWindow(windows, pids: [51]) == nil, "tiny windows don't count")
    check(AssistantRuns.pickWindow(windows, pids: []) == nil, "no processes, no window")

    check(AssistantRuns.scaledLongestSide(width: 1280, height: 800) == nil, "1280 wide stays")
    check(AssistantRuns.scaledLongestSide(width: 2560, height: 1440) == 1280, "wide pictures scale to 1280 wide")
    check(AssistantRuns.scaledLongestSide(width: 2000, height: 4000) == 2560, "tall pictures keep the width at 1280")

    check(AssistantRuns.timeout(nil) == 120, "default timeout")
    check(AssistantRuns.timeout(30) == 30 && AssistantRuns.timeout("45") == 45, "numbers and number strings")
    check(AssistantRuns.timeout(5000) == 600 && AssistantRuns.timeout(-3) == 1, "timeout is clamped to 1...600")
    check(AssistantRuns.timeout("soon") == 120 && AssistantRuns.timeout(Double.infinity) == 120, "nonsense gets the default")

    let crash = AssistantRuns.GameEnd(status: 3, seconds: 12, stoppedByFerry: false, at: Date())
    let stopped = AssistantRuns.GameEnd(status: 15, seconds: 200, stoppedByFerry: true, at: Date())
    func wait(_ u: AssistantRuns.Until, running: Bool = false, preparing: Bool = false, ended: AssistantRuns.GameEnd? = nil,
              crashInLog: Bool = false, failure: String? = nil) -> AssistantRuns.WaitOutcome? {
        AssistantRuns.waitOutcome(u, running: running, preparing: preparing, ended: ended, crashInLog: crashInLog, startFailure: failure)
    }
    check(wait(.started, failure: "no wine") == .startFailed("no wine"), "a failed start ends the wait with its reason")
    check(wait(.exited, failure: "no wine") == .startFailed("no wine") && wait(.crash, failure: "x") == .startFailed("x"),
          "every wait reports a failed start")
    check(wait(.started, preparing: true, failure: "old") == nil, "a start under way keeps waiting")
    check(wait(.started, running: true, failure: "old") == .started, "running wins over a failure")
    check(wait(.exited, ended: crash, failure: "x") == .ended(crash), "an end seen during the wait comes first")
    check(wait(.started, preparing: true) == nil, "still getting ready: keep waiting")
    check(wait(.started, running: true) == .started, "running counts as started")
    check(wait(.started) == .notStarting, "neither running nor starting")
    check(wait(.started, ended: crash) == .ended(crash), "started and already ended")
    check(wait(.exited, running: true) == nil && wait(.exited, ended: crash) == .ended(crash), "exited waits for the end")
    check(wait(.exited) == .notRunning, "exited when it isn't running")
    check(wait(.crash, running: true) == nil, "crash keeps waiting while it runs")
    check(wait(.crash, running: true, crashInLog: true) == .crashedRunning, "a crash in the log while it's open")
    check(wait(.crash, ended: stopped) == .ended(stopped), "crash wait ends with any end")
    check(wait(.exited, running: true, ended: crash) == nil, "started again after an end: keep waiting")
    check(crash.crashed && !stopped.crashed, "a stop isn't a crash")
    check(AssistantRuns.crashReported("0024:err\nwine: Unhandled page fault on read access") && !AssistantRuns.crashReported("err:d3d:x"),
          "Wine's crash report is seen in the log")
    check(AssistantRuns.describe(crash) == "ended after 12 seconds: it crashed (exit code 3)", "crash text")
    check(AssistantRuns.describe(stopped) == "was stopped after 3 minutes", "stop text")
    check(AssistantRuns.describe(.init(status: 0, seconds: 1, stoppedByFerry: false, at: Date())) == "closed normally after 1 second", "normal end")

    check(AssistantRuns.settingsPane("Battery")?.url == "x-apple.systempreferences:com.apple.Battery-Settings.extension", "battery pane")
    check(AssistantRuns.settingsPane("privacy")?.url.hasSuffix("Privacy_ScreenCapture") == true, "privacy is Screen Recording")
    check(AssistantRuns.settingsPane("network") == nil, "other panes aren't opened")
}
