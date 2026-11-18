import AppKit
import SwiftUI

struct TroubleshootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let gameID: UUID

    enum Symptom: String, CaseIterable, Identifiable {
        case blackScreen, blackObjects, crashes, slow, sound, blankLauncher, mouseStuck, pointerShows
        var id: String { rawValue }
        var title: String {
            switch self {
            case .blackScreen: return "The screen is black, but there's sound"
            case .blackObjects: return "Objects or effects are black, or take ages to appear"
            case .crashes: return "It crashes or closes"
            case .slow: return "It's slow or stutters"
            case .sound: return "The sound crackles"
            case .blankLauncher: return "A launcher's window or login page is blank"
            case .mouseStuck: return "The mouse is stuck inside the window"
            case .pointerShows: return "The Mac's mouse pointer shows while I play"
            }
        }
        var icon: String {
            switch self {
            case .blackScreen: return "rectangle.fill"
            case .blackObjects: return "cube.transparent"
            case .crashes: return "xmark.octagon"
            case .slow: return "tortoise"
            case .sound: return "speaker.wave.2"
            case .blankLauncher: return "macwindow"
            case .mouseStuck: return "cursorarrow.rays"
            case .pointerShows: return "cursorarrow"
            }
        }
    }

    @State private var symptom: Symptom? = nil
    @State private var done: Set<String> = []
    @State private var findings: [LogFinding] = []

    private var game: Game? { model.game(gameID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(symptom == nil ? "What's happening?" : symptom!.title).font(.title3.weight(.semibold))
                Spacer()
                if symptom != nil { Button("Back") { symptom = nil; done = [] } }
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let g = game {
                        if !findings.isEmpty { logSection(g) }
                        if let symptom { steps(for: symptom, g) } else { symptomList }
                    }
                }
                .padding(20)
            }
            .onAppear { if let g = game { findings = model.logFindings(g) } }
            Divider()
            HStack {
                if let g = game { Text("\(g.name) · \(model.resolvedEngine(g).short)").foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }

    private var symptomList: some View {
        ForEach(Symptom.allCases) { s in
            Button { symptom = s } label: {
                HStack(spacing: 12) {
                    Image(systemName: s.icon).frame(width: 24).foregroundStyle(.tint)
                    Text(s.title)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func steps(for symptom: Symptom, _ g: Game) -> some View {
        let engine = model.resolvedEngine(g)
        switch symptom {
        case .blackScreen:
            if engine == .d3dmetal { hideROVStep(g, first: true); nvidiaStep(g) }
            switchEngineStep(g)
            note("Still black? Show the log from its settings and check for errors, or ask for help with the log.")
        case .blackObjects:
            note("The first time a game needs a material or effect, its shader has to be translated for Metal and built. Until it's ready, many games draw nothing there. It gets faster every session: quit from the game's own menu so the built shaders are saved.")
            if engine == .d3dmetal { hideROVStep(g, first: false) }
            if engine == .mach9 && g.arch != .x86 && [.dx11, .dx12].contains(g.graphics) && model.runtimes.rosetta {
                engineStep(g, to: .d3dmetal, why: "D3DMetal turns DirectX 11 and 12 shaders straight into Metal with Apple's own converter, much faster than Mach9's route through Vulkan.")
            }
            frameLimitStep(g, why: "Leaves the processor and graphics room to build shaders while you play.")
        case .crashes:
            if engine == .d3dmetal { nvidiaStep(g) }
            switchEngineStep(g)
            action("Show the log", detail: "The last lines usually say what went wrong.", key: "log", label: "Show Log") {
                model.showLog(g.id, "game")
            }
        case .slow:
            lowPowerStep()
            frameLimitStep(g, why: "Steadier frame pacing, and less heat and battery use.")
            if engine == .mach9 && g.graphics == .dx9 {
                toggleStep(g, title: "MetalFX upscaling", detail: "Renders at 75% resolution and upscales with MetalFX.", key: "metalfx",
                           isOn: g.settings.metalFX) { $0.settings.metalFX.toggle() }
            }
            note("Close other apps while playing, especially on a Mac with 8 GB of memory: when memory runs short, macOS moves data to disk and games stutter.")
        case .sound:
            frameLimitStep(g, why: "Crackling usually means the processor is fully busy and the sound misses its deadline. A frame limit gives it room.")
            lowPowerStep()
            note("Close other apps while playing. In our testing, crackling lined up with the processor being fully loaded and memory being moved to disk.")
        case .mouseStuck:
            note("To get out now: press Esc, or click once. While you drag a Windows program's window, Windows keeps the mouse inside it until the button is released; if the Mac snaps the window into place mid-drag, Wine can miss the release.")
            action("Turn off window tiling", detail: "Stops the Mac snapping windows when they're dragged to a screen edge, which is what usually causes this. It affects every app; you can still tile from the green button's menu.", key: "tiling", label: "Desktop & Dock") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            if g.settings.captureFullscreen {
                toggleStep(g, title: "Exclusive full-screen mode", detail: "It's on for this program. It lets Wine take over the display and hold the mouse whenever a window covers the screen, which suits games but traps the mouse in apps.",
                           key: "exclusive", isOn: g.settings.captureFullscreen, suggest: false) { $0.settings.captureFullscreen.toggle() }
            }
        case .pointerShows:
            if engine == .mach9 {
                toggleStep(g, title: "Exclusive full-screen mode",
                           detail: g.settings.captureFullscreen
                               ? "It's on for this \(g.noun), which lets it hide the Mac's pointer. If the pointer still shows, try the steps below."
                               : "Mach9 normally shows full-screen games at a scaled, virtual resolution. In that mode it keeps the mouse in the game but can leave the Mac's pointer on screen. Exclusive full-screen lets the game hide it; the screen switches resolution when the game starts and quits.",
                           key: "exclusive", isOn: g.settings.captureFullscreen) { $0.settings.captureFullscreen.toggle() }
            }
            if engine != .mach9 || g.settings.captureFullscreen {
                note("Click once inside its window so it's the active app: macOS only lets the app in front hide the pointer. If its own menus use the mouse, the pointer comes back while they're open.")
                switchEngineStep(g)
            }
        case .blankLauncher:
            if model.webView2Installed {
                toggleStep(g, title: "WebView2 for launchers",
                           detail: "Many newer launchers draw their window or login page as a web page with Microsoft's WebView2. This points it at Ferry's shared copy.",
                           key: "webview2", isOn: g.settings.webView2) { $0.settings.webView2.toggle() }
            } else {
                webView2InstallStep()
            }
            switchEngineStep(g)
            note("WebView2 doesn't work for every launcher under Wine. If it stays blank, look for the launcher's offline mode, or add the game's own .exe to Ferry to start it without the launcher.")
        }
    }

    @ViewBuilder
    private func logSection(_ g: Game) -> some View {
        Label("Found in the log", systemImage: "doc.text.magnifyingglass").font(.headline)
        ForEach(findings) { f in
            stepCard(title: f.title, detail: f.detail) {
                switch f.fix {
                case .library:
                    Button("Install") { model.apply(f.fix, to: g.id); done.insert("log-" + f.id) }
                        .disabled(done.contains("log-" + f.id))
                    if done.contains("log-" + f.id) { Text("Installing…").font(.caption).foregroundStyle(.secondary) }
                case .engine(let engine):
                    Button(model.resolvedEngine(g) == engine ? "Switched" : "Try \(engine.short)") {
                        model.apply(f.fix, to: g.id); done.insert("log-" + f.id)
                    }
                    .disabled(model.resolvedEngine(g) == engine)
                case .webView2:
                    if model.webView2Installed {
                        Button("Turn On") { model.apply(f.fix, to: g.id); done.insert("log-" + f.id) }
                            .disabled(g.settings.webView2)
                        if g.settings.webView2 { Text("Already on").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Button(model.installingComponent == .webView2 ? "Installing…" : "Install WebView2") { model.installComponentNow(.webView2) }
                            .disabled(model.installingComponent != nil || model.setupRunning || model.updating)
                    }
                case .none:
                    EmptyView()
                }
            }
            Text(f.evidence.trimmingCharacters(in: .whitespaces).prefix(180))
                .font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(2).textSelection(.enabled)
                .padding(.leading, 12).padding(.top, -6)
        }
        if symptom == nil { Divider().padding(.vertical, 4) }
    }

    private func hideROVStep(_ g: Game, first: Bool) -> some View {
        toggleStep(g, title: "Hide ROV support",
                   detail: "\(g.rovSeen ? "Ferry saw this game draw with ROV. " : "")Some DirectX 12 games use a drawing method called ROV, which D3DMetal says it supports but can show as black. This tells the game it isn't available (and reports an NVIDIA card), so it uses its ordinary method.\(first ? " Fixed a black screen in testing." : "")",
                   key: "rov", isOn: g.settings.hideROV) { $0.settings.hideROV.toggle() }
    }

    private func webView2InstallStep() -> some View {
        stepCard(title: "Install WebView2",
                 detail: "Many newer launchers draw their window or login page as a web page with Microsoft's WebView2. Ferry installs it once (about 215 MB) and shares it between games; afterwards, turn on WebView2 for launchers here or in the game's settings.") {
            Button(model.installingComponent == .webView2 ? "Installing…" : "Install") { model.installComponentNow(.webView2) }
                .disabled(model.installingComponent != nil || model.setupRunning || model.updating)
        }
    }

    private func nvidiaStep(_ g: Game) -> some View {
        toggleStep(g, title: "Report graphics card as NVIDIA",
                   detail: "D3DMetal tells games the Mac has an AMD card. Some games take AMD-only paths or workarounds that crash or draw wrong on a Mac; this makes them see an NVIDIA card instead.\(g.settings.hideROV ? " Hide ROV support needs it, so turning it off turns that off too." : "")",
                   key: "nvidia", isOn: g.settings.reportNVIDIA) { $0.settings.reportNVIDIA.toggle() }
    }

    @ViewBuilder
    private func switchEngineStep(_ g: Game) -> some View {
        let current = model.resolvedEngine(g)
        let order = model.fallbackOrder(for: g)
        if let i = order.firstIndex(of: current), i + 1 < order.count {
            engineStep(g, to: order[i + 1], why: "Each engine translates graphics differently; a program that fails on one often works on another.")
        } else if let other = order.first(where: { $0 != current }) {
            engineStep(g, to: other, why: "Each engine translates graphics differently; a program that fails on one often works on another.")
        }
    }

    private func engineStep(_ g: Game, to engine: EngineID, why: String) -> some View {
        action("Try \(engine.short)", detail: why, key: "engine-\(engine.rawValue)", label: "Switch") {
            change(g) { $0.settings.engine = engine }
        }
    }

    @ViewBuilder
    private func frameLimitStep(_ g: Game, why: String) -> some View {
        let engine = model.resolvedEngine(g)
        let supported = engine == .dxvk || (engine == .mach9 && g.settings.mach9Direct3D != "wined3d")
            || (g.settings.dxvkD3D9 && engine != .mach9)
        if supported {
            action("Limit the frame rate to 30", detail: why, key: "fps", label: "Set", alreadyOn: g.settings.fpsLimit == 30) {
                change(g) { $0.settings.fpsLimit = 30 }
            }
        } else {
            note("Limit the frame rate to 30 in the \(g.noun)'s own graphics settings. \(why) (\(engine.short) has no limiter Ferry can set.)")
        }
    }

    @ViewBuilder
    private func lowPowerStep() -> some View {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            action("Turn off Low Power Mode", detail: "It slows the processor and graphics a lot.", key: "lpm", label: "Battery Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func toggleStep(_ g: Game, title: String, detail: String, key: String, isOn: Bool, suggest: Bool = true,
                            flip: @escaping (inout Game) -> Void) -> some View {
        stepCard(title: title, detail: detail) {
            Button(suggest ? "Turn On" : "Turn Off") { change(g, flip); done.insert(key) }
                .disabled(isOn == suggest)
            if done.contains(key) { Text("Start the \(g.noun) to try it").font(.caption).foregroundStyle(.secondary) }
            else if isOn == suggest { Text(suggest ? "Already on" : "Already off").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func action(_ title: String, detail: String, key: String, label: String, alreadyOn: Bool = false,
                        run: @escaping () -> Void) -> some View {
        stepCard(title: title, detail: detail) {
            Button(label) { run(); done.insert(key) }
                .disabled(alreadyOn && !done.contains(key))
            if done.contains(key) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else if alreadyOn { Text("Already on").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func stepCard<Buttons: View>(title: String, detail: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) { buttons() }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func change(_ g: Game, _ edit: (inout Game) -> Void) {
        guard var current = model.game(g.id) else { return }
        edit(&current)
        model.update(current)
    }
}
