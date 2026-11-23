import AppKit
import SwiftUI

@main
struct FerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Ferry", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.runtimes)
                .frame(minWidth: 600, minHeight: 600)
                .onOpenURL { model.handle($0) }
                .ferryTheme()
        }
        .defaultSize(width: 680, height: 780)
        .commands { FerryCommands(model: model) }

        Window("Compatibility Check", id: "analyzer") {
            AnalyzerView()
                .environmentObject(model)
                .environmentObject(model.runtimes)
                .ferryTheme()
        }
        .defaultSize(width: 640, height: 760)

        Window("Task Manager", id: "taskManager") {
            TaskManagerView()
                .environmentObject(model)
                .environmentObject(model.runtimes)
                .ferryTheme()
        }
        .defaultSize(width: 600, height: 460)
        .keyboardShortcut("t", modifiers: [.command, .option])

        Window("Controller", id: "controller") {
            ControllerView()
                .ferryTheme()
        }
        .defaultSize(width: 1100, height: 520)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.runtimes)
                .ferryTheme()
        }
    }
}

struct FerryCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedGame) private var selected
    @AppStorage(LibrarySort.key) private var sort = LibrarySort.added

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { model.checkForUpdatesNow() }
            Button("Support Ferry…") { NSWorkspace.shared.open(URL(string: "https://ko-fi.com/rhyvo")!) }
        }
        CommandGroup(after: .newItem) {
            Button("Add Windows Program…") { model.chooseFile() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Check Compatibility…") { openWindow(id: "analyzer") }
                .keyboardShortcut("k", modifiers: [.command])
        }
        CommandGroup(before: .toolbar) {
            Picker("Sort Library By", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
            }
            Divider()
        }
        CommandMenu("Game") {
            let id = selected
            Button(id.map { model.running.contains($0) } == true ? "Stop" : "Play") {
                guard let id else { return }
                if model.running.contains(id) { model.stop(id) } else { model.play(id) }
            }
            .disabled(id == nil)
            Button("Settings…") { model.settingsGame = id }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(id == nil)
            Button("Troubleshoot…") { model.troubleshootGame = id }
                .disabled(id == nil)
            Button("Mods…") { model.modsGame = id }
                .disabled(id == nil)
            Divider()
            Button("Show Log") { if let id { model.showLog(id, "game") } }
                .disabled(id == nil)
            Button("Show Files in Finder") { if let id { model.showGameInFinder(id) } }
                .disabled(id == nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])
        MainActor.assumeIsolated { SystemAccent.install() }
        registerURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) { registerURLHandler() }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: 0x4755_524C,
            andEventID: 0x4755_524C
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: 0x2D2D_2D2D)?.stringValue,
              let url = URL(string: text) else { return }
        Task { @MainActor in AppModel.shared.handle(url) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        Task { @MainActor in for file in files { AppModel.shared.add(file) } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSApp.windows.filter { $0.styleMask.contains(.titled) && !$0.title.isEmpty && ($0.isVisible || $0.isMiniaturized) }
        for window in open.sorted(by: { dockTitle($0) < dockTitle($1) }) {
            let item = NSMenuItem(title: dockTitle(window), action: #selector(showWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = window
            item.state = window.isMiniaturized ? .mixed : window.isKeyWindow ? .on : .off
            menu.addItem(item)
        }
        let windowMenu = NSApp.windowsMenu ?? NSApp.mainMenu?.item(withTitle: "Window")?.submenu
        var closed: [NSMenuItem] = []
        for title in ["Ferry", "Task Manager", "Compatibility Check"] where !open.contains(where: { $0.title == title }) {
            guard let opener = windowMenu?.items.first(where: { $0.title == title && $0.action != nil }) else { continue }
            let item = NSMenuItem(title: title, action: #selector(openFromWindowMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opener
            closed.append(item)
        }
        if !open.contains(where: isSettings) {
            let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
            item.target = self
            closed.append(item)
        }
        if !closed.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            closed.forEach(menu.addItem)
        }
        return menu
    }

    private func isSettings(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
    }

    private func dockTitle(_ window: NSWindow) -> String {
        isSettings(window) ? "Settings – \(window.title)" : window.title
    }

    @objc private func showWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openFromWindowMenu(_ sender: NSMenuItem) {
        guard let opener = sender.representedObject as? NSMenuItem, let menu = opener.menu else { return }
        NSApp.activate()
        menu.performActionForItem(at: menu.index(of: opener))
    }

    @objc private func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
