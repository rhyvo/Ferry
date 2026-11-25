import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var targeted = false
    @State private var selection: UUID? = nil
    @State private var search = ""
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool
    @AppStorage(LibrarySort.key) private var sort = LibrarySort.added

    var body: some View {
        if model.setupComplete && !model.setupRunning {
            library
        } else {
            SetupView()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search games and apps", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { search = ""; searchFocused = false; listFocused = true }
                .onSubmit { searchFocused = false; listFocused = true }
            if !search.isEmpty {
                Button { search = ""; listFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.1)))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var shownGames: [Game] {
        var list = model.games
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .added: break
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent: list.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
        return list
    }

    private var library: some View {
        VStack(spacing: 0) {
            if !runtimes.availableUpdates.isEmpty && !model.updating {
                UpdateBanner()
                    .padding([.horizontal, .top], 16)
            }
            if model.ferryUpdate != nil && !model.ferryUpdateHidden {
                FerryUpdateBanner()
                    .padding([.horizontal, .top], 16)
            }
            if model.librariesOutdated {
                LibraryUpdateBanner()
                    .padding([.horizontal, .top], 16)
            }
            DropZone(targeted: targeted, compact: !model.games.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, model.games.isEmpty ? 16 : 12)
            if !model.games.isEmpty { searchField }
            if model.games.isEmpty {
                Spacer()
                Text("Games and programs you add show up here.")
                    .foregroundStyle(.secondary)
                Button {
                    model.installSteam()
                } label: {
                    Label("Install Steam", systemImage: "arrow.down.circle")
                }
                .padding(.top, 6)
                Spacer()
            } else if shownGames.isEmpty {
                Spacer()
                Text("No games or apps match \u{201C}\(search)\u{201D}.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(shownGames) { game in
                        GameRow(game: game).tag(game.id)
                    }
                }
                .listStyle(.inset)
                .focused($listFocused)
                .onExitCommand { selection = nil }
                .onAppear { listFocused = true }
                .onChange(of: selection) { _, new in if new != nil { listFocused = true } }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let g = model.game(id) { GameActions(game: g) }
                } primaryAction: { ids in
                    if let id = ids.first, !model.running.contains(id), !model.preparing.contains(id) { model.play(id) }
                }
            }
        }
        .focusedSceneValue(\.selectedGame, selection)
        .animation(.easeOut(duration: 0.18), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            var checking = false
            for url in urls {
                if FileManager.default.isDirectory(url) || AnalyzerModel.isArchive(url) {
                    if !checking { AnalyzerModel.shared.analyze(url) }
                    checking = true
                    openWindow(id: "analyzer")
                } else {
                    model.add(url)
                }
            }
            return !urls.isEmpty
        } isTargeted: { targeted = $0 }
        .sheet(item: Binding(
            get: { model.settingsGame.map { TroubleshootTarget(id: $0) } },
            set: { model.settingsGame = $0?.id }
        )) { target in
            GameSettingsView(gameID: target.id)
                .environmentObject(model)
                .environmentObject(runtimes)
        }
        .sheet(isPresented: $model.showStorage) {
            StorageView()
                .environmentObject(model)
        }
        .sheet(item: Binding(
            get: { model.troubleshootGame.map { TroubleshootTarget(id: $0) } },
            set: { model.troubleshootGame = $0?.id }
        )) { target in
            TroubleshootView(gameID: target.id)
                .environmentObject(model)
        }
        .sheet(item: Binding(
            get: { model.modsGame.map { TroubleshootTarget(id: $0) } },
            set: { model.modsGame = $0?.id }
        )) { target in
            ModsView(gameID: target.id)
                .environmentObject(model)
        }
        .modifier(ErrorAlert())
        .toolbar(id: "library") {
            ToolbarItem(id: "add") {
                Menu {
                    Button("Add Windows Program…") { model.chooseFile() }
                        .keyboardShortcut("o", modifiers: [.command])
                    Button("Install Steam") { model.installSteam() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add a Windows game or program (⌘O), or install Steam")
                .accessibilityLabel("Add")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "compatibility") {
                Button { openWindow(id: "analyzer") } label: { Label("Check Compatibility", systemImage: "stethoscope") }
                    .help("Check a program, folder or archive before adding it (⌘K)")
            }
            ToolbarItem(id: "taskManager") {
                Button { openWindow(id: "taskManager") } label: { Label("Task Manager", systemImage: "list.bullet.rectangle") }
                    .help("See every Windows program Ferry is running, and end stuck ones")
            }
            ToolbarItem(id: "controller") {
                Button { openWindow(id: "controller") } label: { Label("Controller", systemImage: "gamecontroller") }
                    .help("Remap controller buttons for every game and app, and save keybinds")
            }
            ToolbarItem(id: "storage") {
                settingsShortcut("Storage", "internaldrive", tab: "storage", help: "See what Ferry keeps on disk and free up space")
            }
            ToolbarItem(id: "settings") {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Engines, defaults and system setup")
            }
            ToolbarShortcuts(model: model) { tab in
                UserDefaults.standard.set(tab, forKey: SettingsView.tabKey)
                openSettings()
            }
        }
    }
}

struct ToolbarShortcuts: CustomizableToolbarContent {
    let model: AppModel
    let openTab: (String) -> Void

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "engines", showsByDefault: false) {
            tabButton("Engines", "cpu", "engines", "Settings ▸ Engines: update, reinstall or remove engines")
        }
        ToolbarItem(id: "components", showsByDefault: false) {
            tabButton("Components", "shippingbox", "components", "Settings ▸ Components: Windows libraries and optional downloads")
        }
        ToolbarItem(id: "general", showsByDefault: false) {
            tabButton("General", "switch.2", "general", "Settings ▸ General: theme, archives, Compatibility Check and Discord")
        }
        ToolbarItem(id: "newGames", showsByDefault: false) {
            tabButton("New Games", "plus.app", "newGames", "Settings ▸ New Games: what newly added games and apps start with")
        }
        ToolbarItem(id: "system", showsByDefault: false) {
            tabButton("System", "lock.shield", "system", "Settings ▸ System: Rosetta, folder access and repair")
        }
        ToolbarItem(id: "checkUpdates", showsByDefault: false) {
            Button { model.checkForUpdatesNow() } label: { Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath") }
                .help("Check for a new Ferry and new engines now")
        }
        ToolbarItem(id: "reportBug", showsByDefault: false) {
            Button { NSWorkspace.shared.open(URL(string: "https://github.com/rhyvo/Ferry/issues/new/choose")!) } label: {
                Label("Report a Bug", systemImage: "ladybug")
            }
            .help("Open a bug report on Ferry's GitHub")
        }
    }

    private func tabButton(_ title: String, _ icon: String, _ tab: String, _ help: String) -> some View {
        Button { openTab(tab) } label: { Label(title, systemImage: icon) }
            .help(help)
    }
}

extension ContentView {
    func settingsShortcut(_ title: String, _ icon: String, tab: String, help: String) -> some View {
        Button {
            UserDefaults.standard.set(tab, forKey: SettingsView.tabKey)
            openSettings()
        } label: { Label(title, systemImage: icon) }
        .help(help.isEmpty ? "Settings ▸ \(title)" : help)
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case added, name, recent
    static let key = "librarySort"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .added: return "Date Added"
        case .name: return "Name"
        case .recent: return "Recently Played"
        }
    }
}

struct SelectedGameKey: FocusedValueKey { typealias Value = UUID }

extension FocusedValues {
    var selectedGame: UUID? {
        get { self[SelectedGameKey.self] }
        set { self[SelectedGameKey.self] = newValue }
    }
}

struct ErrorAlert: ViewModifier {
    @EnvironmentObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Something went wrong", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Ferry", isPresented: Binding(
                get: { model.noticeMessage != nil },
                set: { if !$0 { model.noticeMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.noticeMessage ?? "")
            }
            .alert("\(model.launchFailure?.name ?? "The program") closed right after starting",
                   isPresented: Binding(get: { model.launchFailure != nil }, set: { if !$0 { model.launchFailure = nil } }),
                   presenting: model.launchFailure) { failure in
                let logFix = failure.findings.first.map { !$0.switchesEngine } ?? false
                if let next = failure.next {
                    Button("Try \(next.short)") { model.retry(failure) }.keyboardShortcut(logFix ? nil : .defaultAction)
                }
                Button("Troubleshoot…") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.troubleshootGame = failure.gameID }
                }
                .keyboardShortcut(logFix || failure.next == nil ? .defaultAction : nil)
                Button("I Closed It", role: .cancel) {}
            } message: { failure in
                Text(launchFailureMessage(failure))
            }
            .alert("Free up \(DiskUsage.text(model.storageSuggestion ?? 0))?", isPresented: Binding(
                get: { model.storageSuggestion != nil },
                set: { if !$0 { model.storageSuggestion = nil } }
            )) {
                Button("Review") { model.showStorage = true }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Some programs have Windows environments from engines they no longer use, or there are leftovers from removed programs. They aren't needed and can be deleted without losing saves.")
            }
            .alert("Low Power Mode is on", isPresented: Binding(
                get: { model.lowPowerPrompt != nil },
                set: { if !$0 { model.lowPowerPrompt = nil } }
            ), presenting: model.lowPowerPrompt) { id in
                Button("Play Anyway") {
                    model.lowPowerAcknowledged = true
                    model.play(id)
                }
                Button("Open Battery Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("macOS slows the processor and graphics in Low Power Mode, so games run noticeably slower and their sound can crackle. Turn it off in System Settings ▸ Battery, or Control Center, for the best performance.")
            }
            .alert("\(model.rovPrompt.flatMap { model.game($0)?.name } ?? "This game") draws with ROV", isPresented: Binding(
                get: { model.rovPrompt != nil },
                set: { if !$0 { model.rovPrompt = nil } }
            ), presenting: model.rovPrompt) { id in
                Button("Turn On Hide ROV Support") {
                    if var g = model.game(id) { g.settings.hideROV = true; model.update(g) }
                }
                Button("Not Now", role: .cancel) {}
            } message: { _ in
                Text("Ferry noticed it uses rasterizer-ordered views (ROV), a drawing method D3DMetal says it supports but can show as a black screen or black objects. Hide ROV support makes the game use its ordinary method. If the game already looks right, you can leave it off.")
            }
            .alert("\(model.stallPrompt.flatMap { model.game($0)?.name } ?? "This game") got stuck waiting", isPresented: Binding(
                get: { model.stallPrompt != nil },
                set: { if !$0 { model.stallPrompt = nil } }
            ), presenting: model.stallPrompt) { id in
                Button("Turn Off Fast Sync") { model.apply(.fastSyncOff, to: id) }
                    .keyboardShortcut(.defaultAction)
                Button("Not Now", role: .cancel) {}
            } message: { _ in
                Text("Part of it waited more than a minute for another part. With Fast Sync on, that can leave textures blurry, loading screens stuck or sounds missing. Turning Fast Sync off for this game usually fixes it; you can turn it back on in its settings, and Troubleshoot keeps this suggestion.")
            }
            .alert("Also add \(model.pairOffer?.role.label?.lowercased() ?? "the other program")?",
                   isPresented: Binding(get: { model.pairOffer != nil }, set: { if !$0 { model.pairOffer = nil } }),
                   presenting: model.pairOffer) { offer in
                Button("Add \(offer.role.label ?? "It")") { model.addPartnerProgram(offer) }
                    .keyboardShortcut(.defaultAction)
                Button("Not Now", role: .cancel) {}
            } message: { offer in
                Text("\(offer.gameName) has a separate \(offer.role.label?.lowercased() ?? "") program, \(offer.program.lastPathComponent). Ferry can add it as its own entry, sharing this game's Windows environment and saves, so you can start either one directly instead of switching inside the game.")
            }
            .alert("\(model.installedOffer?.installer ?? "The installer") installed \(model.installedOffer?.programs.first?.name ?? "a program")",
                   isPresented: Binding(get: { model.installedOffer?.programs.count == 1 }, set: { if !$0 { model.installedOffer = nil } }),
                   presenting: model.installedOffer) { offer in
                Button("Use \(offer.programs[0].name) for This Entry") { model.useInstalledProgram(offer.programs[0], from: offer) }
                    .keyboardShortcut(.defaultAction)
                Button("Not Now", role: .cancel) {}
            } message: { offer in
                Text("Play still runs the installer. Ferry can start \(offer.programs[0].name) instead, with the engine the installer used. You can also choose a program later with Change Executable.")
            }
            .confirmationDialog("\(model.installedOffer?.installer ?? "The installer") installed \(model.installedOffer?.programs.count ?? 0) programs",
                                isPresented: Binding(get: { (model.installedOffer?.programs.count ?? 0) > 1 }, set: { if !$0 { model.installedOffer = nil } }),
                                titleVisibility: .visible, presenting: model.installedOffer) { offer in
                ForEach(offer.programs, id: \.exe) { program in
                    Button("Use \(program.name)") { model.useInstalledProgram(program, from: offer) }
                }
                Button("Not Now", role: .cancel) {}
            } message: { _ in
                Text("Play still runs the installer. Choose the program this entry should start instead; it keeps the engine the installer used. You can also choose later with Change Executable.")
            }
            .alert("Updates available", isPresented: $model.showUpdatePrompt) {
                Button("Update Now") { model.installUpdates() }
                Button("Later", role: .cancel) {}
            } message: {
                Text(model.updateSummary)
            }
    }

    private func launchFailureMessage(_ f: LaunchFailure) -> String {
        var text = "If you closed it yourself, you can ignore this.\n\nIf it closed on its own, or you closed it because it wasn't working (a black screen, an error, a freeze), \(f.failed.short) probably can't run it."
        if let next = f.next {
            text += " Try \(next.short): it becomes its engine if it works."
        } else {
            text += " There's no other engine left to try automatically."
        }
        if let found = f.findings.first {
            text += "\n\nFerry read the log and found a likely cause: \(found.title.prefix(1).lowercased() + found.title.dropFirst()). Troubleshoot shows it and the fix."
        } else {
            text += " Troubleshoot walks you through fixes for what you saw, including the log."
            if !f.logTail.isEmpty { text += "\n\nEnd of the log:\n" + f.logTail }
        }
        return text
    }
}

struct LibraryUpdateBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("New Windows libraries").font(.callout.weight(.semibold))
                Text("Includes a Visual C++ fix for D3DMetal games, plus .NET 6 and 8, PhysX and video codecs. New games and apps get them automatically after installing; for ones already in Ferry, use Reinstall Windows Libraries in their settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Install") { model.runSetup() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
    }
}

struct UpdateBanner: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Updates available").font(.callout.weight(.semibold))
                Text(runtimes.availableUpdates.map { "\($0.title) \(runtimes.latest[$0] ?? "")" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Update") { model.installUpdates() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
    }
}

struct FerryUpdateBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ferry \(model.ferryUpdate ?? "") is available").font(.callout.weight(.semibold))
                Text("You have \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "an older version"). Download it and drag it into Applications; your games and settings are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Not Now") { model.ferryUpdateHidden = true }
                .help("Hide this until Ferry next opens")
            Button("Download") { NSWorkspace.shared.open(AppModel.releasesPage) }
                .buttonStyle(.borderedProminent)
                .help("Open the new version's page on GitHub")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager
    @State private var measured: [Component: Int]? = nil
    @State private var selectionVersion = 0

    private var showingProgress: Bool {
        model.setupRunning || model.setupSteps.values.contains { $0 != .pending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 84, height: 84)
                    VStack(spacing: 6) {
                        Text("Set up Ferry")
                            .font(.largeTitle.weight(.bold))
                        Text("Install everything Windows games and programs need, once. After this, dropping in a game or app just works.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 460)
                    }

                    if !showingProgress {
                        ComponentChecklist { selectionVersion += 1 }
                            .padding(16)
                            .frame(maxWidth: 520, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.07)))
                    } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(SetupStep.allCases.filter { Platform.mach9Available || ![.mach9, .mach9Template].contains($0) }) { step in
                            HStack(alignment: .top, spacing: 10) {
                                stateIcon(model.setupSteps[step] ?? .pending)
                                    .frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(step.title)
                                        .font(.callout.weight(.medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(step.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 480, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.07)))
                    }

                    Text("Engines come from the free, open-source Wine, Game Porting Toolkit, DXVK and MetalSharp builds on GitHub; Visual C++, DirectX and .NET come from Microsoft. You can keep using your Mac while it installs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }

            Divider()

            VStack(spacing: 10) {
                if model.setupRunning {
                    TaskProgressBar(value: runtimes.progress)
                        .frame(maxWidth: 360)
                    Text(runtimes.task ?? model.status ?? "Working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = model.setupError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    model.runSetup()
                } label: {
                    Text(buttonTitle).frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.setupRunning)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .modifier(ErrorAlert())
        .task { measured = await model.downloadEstimates() }
    }

    private var buttonTitle: String {
        if model.setupRunning { return "Installing…" }
        if model.setupError != nil { return "Try Again" }
        _ = selectionVersion
        guard let measured else { return "Install" }
        let bytes = AppModel.plannedBytes(measured: measured)
        return "Install (about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
    }

    @ViewBuilder
    private func stateIcon(_ state: StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
        case .off:
            Image(systemName: "minus.circle").foregroundStyle(.tertiary).help("Not selected")
        }
    }
}

struct ComponentChecklist: View {
    var onChange: () -> Void = {}
    var showsStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(showsStatus ? [ComponentTier.required, .recommended, .optional, .beta] : [.required, .recommended, .optional],
                    id: \.self) { tier in
                let components = Component.allCases.filter { $0.tier == tier && ($0 != .mach9 || Platform.mach9Available) }
                VStack(alignment: .leading, spacing: 10) {
                    Text(tier.label)
                        .font(.headline)
                    if tier == .required {
                        Text("Ferry needs these to run Windows games and programs, so they can't be turned off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if tier == .beta {
                        Text("Experimental downloads, not part of setup. Each is installed only when you click its button, and used only where you turn it on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(components) { component in
                        ComponentRow(component: component, onChange: onChange, showsStatus: showsStatus)
                        if component != components.last { Divider() }
                    }
                }
            }
        }
    }
}

struct ComponentInstallStatus: View {
    @EnvironmentObject var model: AppModel
    let component: Component

    var body: some View {
        let status = model.componentStatus[component]
        VStack(alignment: .trailing, spacing: 4) {
            if model.installingComponent == component {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Installing…").font(.caption).foregroundStyle(.secondary)
                }
            } else if status?.installed == true {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Install Now") { model.installComponentNow(component) }
                    .controlSize(.small)
                    .disabled(model.installingComponent != nil || model.setupRunning || model.updating || !model.setupComplete)
                if let missing = status?.missingFrom, !missing.isEmpty {
                    Text("Missing from \(missing.map(\.engineName).joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("Not installed").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 110, alignment: .trailing)
    }
}

struct ComponentRow: View {
    @EnvironmentObject var model: AppModel
    let component: Component
    let onChange: () -> Void
    let showsStatus: Bool
    @AppStorage private var isOn: Bool

    init(component: Component, onChange: @escaping () -> Void, showsStatus: Bool = false) {
        self.component = component
        self.onChange = onChange
        self.showsStatus = showsStatus
        _isOn = AppStorage(wrappedValue: component.tier == .recommended, component.defaultsKey)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if component.tier == .required {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help("Required")
            } else if component.tier == .beta {
                Image(systemName: "flask")
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                    .help("Optional beta download")
            } else {
                Toggle("", isOn: $isOn)
                    .toggleStyle(.themedCheckbox)
                    .labelsHidden()
                    .onChange(of: isOn) { _, _ in onChange() }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(component.title).font(.callout.weight(.medium))
                    TierBadge(tier: component.tier)
                }
                Text(component.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if component.tier != .required, !isOn, model.componentStatus[component]?.installed != true,
                   let without = component.withoutIt {
                    Text(without)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsStatus && component.tier != .required { ComponentInstallStatus(component: component) }
        }
    }
}

struct TierBadge: View {
    let tier: ComponentTier

    var body: some View {
        let tint: AnyShapeStyle = {
            switch tier {
            case .required: return AnyShapeStyle(Color.secondary)
            case .recommended: return AnyShapeStyle(.tint)
            case .optional: return AnyShapeStyle(Color.gray)
            case .beta: return AnyShapeStyle(Color.orange)
            }
        }()
        Text(tier.badge)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }
}

struct ComponentSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ComponentChecklist(showsStatus: true)
                Divider()
                Text("Install Now adds one component right away. The ticks decide what Run Setup Again installs; unticking doesn't remove anything. Games already in Ferry get new Windows libraries from Reinstall Windows Libraries in their settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Run Setup Again") { model.runSetup() }
                    .disabled(model.setupRunning || model.updating || model.installingComponent != nil)
            }
            .padding(20)
        }
        .onAppear { model.refreshComponentStatus() }
        .onChange(of: model.updating) { _, _ in model.refreshComponentStatus() }
        .onChange(of: model.setupRunning) { _, _ in model.refreshComponentStatus() }
    }
}

struct TaskProgressBar: View {
    let value: Double?

    var body: some View {
        if let value {
            ProgressView(value: value)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }
}

struct DropZone: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager
    let targeted: Bool
    let compact: Bool

    var body: some View {
        let slim = compact && !targeted
        let shape = RoundedRectangle(cornerRadius: slim ? 12 : 18, style: .continuous)
        let message = runtimes.task ?? model.status
        Button {
            if runtimes.task == nil { model.chooseFile() }
        } label: {
            ZStack {
                shape.fill(targeted ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(Color.secondary.opacity(0.06)))
                shape.strokeBorder(style: StrokeStyle(lineWidth: slim ? 1.5 : 2, dash: slim ? [6, 5] : [8, 6]))
                    .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.45)))
                if let message {
                    if slim {
                        HStack(spacing: 12) {
                            TaskProgressBar(value: runtimes.progress)
                                .frame(width: 140)
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 10) {
                            TaskProgressBar(value: runtimes.progress)
                                .frame(maxWidth: 300)
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                    }
                } else if slim {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.app")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Drop a Windows game or app here, or click to add one")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.app")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                        Text("Drop a Windows game or app here")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(".exe, .msi or .bat to add it, or a folder or .zip/.rar/.7z to check it first")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
            }
            .frame(minHeight: slim ? 48 : 190)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(message == nil ? "Add a Windows game or app (⌘O)" : "")
        .accessibilityLabel(message ?? "Add a Windows game or app")
        .accessibilityHint(message == nil ? "Opens a file picker. You can also drop a program, folder or archive onto Ferry's window." : "")
    }
}

@ViewBuilder
func settingLabel(_ title: String, needs: String?) -> some View {
    Text(title).foregroundStyle(needs == nil ? .primary : .tertiary)
    if let needs { Text(needs) }
}

struct FrameLimitPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var game: Game

    var body: some View {
        let vsync = game.settings.vsync
        let hz = Platform.displayHz
        let current = game.settings.fpsLimit
        let limits = [30, 40, 45, 60, 90, 120].filter { !vsync || $0 < hz || $0 == current }
        if model.hasFrameLimiter(game) {
            Picker("Frame rate limit", selection: $game.settings.fpsLimit) {
                Text(vsync ? "Display rate (\(hz) FPS)" : "Off").tag(0)
                ForEach(limits, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            .info(vsync
                  ? "With VSync on, the \(game.noun) runs at the display's rate (\(hz) FPS), or at a lower limit picked here, with every frame still shown on a refresh. A limit a little below what the \(game.noun) can hold keeps frame times even when it can't reach \(hz)."
                  : "Caps the frame rate. Lower limits keep frame pacing even, leave the processor room for sound, and run cooler on battery.")
        } else {
            LabeledContent("Frame rate limit") {
                Text("Use the \(game.noun)'s own setting (Ferry can't limit it on \(model.resolvedEngine(game).short))")
                    .foregroundStyle(.secondary)
            }
            .info("Ferry can't limit the frame rate of this \(game.noun)'s graphics on this engine, or the \(game.noun) has anti-cheat. Use the \(game.noun)'s own setting instead.")
        }
        Toggle("VSync", isOn: $game.settings.vsync)
            .info("Shows each frame in step with the display's refresh, so the picture doesn't tear (a frame showing partway through another), and keeps the \(game.noun) from drawing more frames than the display can show: \(hz) a second on this Mac's display. The time it would spend on frames you never see goes to the \(game.noun) and macOS instead, and the Mac runs cooler. Use the frame rate limit with it to cap lower. Mullion's DirectX 10–12 can still tear. Turn it off for the highest frame rate and lowest input delay.")
    }
}

struct TroubleshootTarget: Identifiable { let id: UUID }

struct GameIconView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let side: CGFloat

    var body: some View {
        if let image = model.icon(for: game) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
        } else {
            Image(systemName: "gamecontroller.fill")
                .font(side > 40 ? .title : .title3)
                .foregroundStyle(.tint)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(.tint.opacity(0.14)))
        }
    }
}

struct GameRow: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            GameIconView(game: game, side: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.headline).lineLimit(1)
                details.font(.caption).lineLimit(1)
            }
            .help(game.name)
            .accessibilityElement(children: .combine)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            if model.preparing.contains(game.id) {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Starting \(game.name)")
            } else if model.running.contains(game.id) {
                Button { model.stop(game.id) } label: { Label("Stop", systemImage: "stop.fill") }
                    .accessibilityLabel("Stop \(game.name)")
            } else {
                Button { model.play(game.id) } label: { Label("Play", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Play \(game.name)")
            }
            Button { model.settingsGame = game.id } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings for \(game.name) (⌘I)")
            .accessibilityLabel("Settings for \(game.name)")
            Menu {
                GameActions(game: game)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More for \(game.name): Troubleshoot, Mods, Show Log and more")
            .accessibilityLabel("More for \(game.name)")
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.05 : 0))
            .padding(.horizontal, -6))
        .onHover { hovering = $0 }
        .accessibilityActions {
            Button("Settings") { model.settingsGame = game.id }
            Button("Troubleshoot") { model.troubleshootGame = game.id }
            Button("Mods") { model.modsGame = game.id }
            Button("Show Log") { model.showLog(game.id, "game") }
            Button("Show Files in Finder") { model.showGameInFinder(game.id) }
        }
    }

    @ViewBuilder private var details: some View {
        let line = Text(model.subtitle(for: game)).foregroundStyle(.secondary)
        if model.running.contains(game.id), let start = model.startedAt[game.id] {
            TimelineView(.periodic(from: start, by: 30)) { context in
                line + Text(" · ").foregroundStyle(.secondary)
                    + Text("Running · \(Self.duration(from: start, to: context.date))").foregroundStyle(.tint)
            }
        } else if let last = game.lastPlayed {
            line + Text(" · Played \(last, format: .relative(presentation: .named))").foregroundStyle(.secondary)
        } else {
            line
        }
    }

    static func duration(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "just started" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

struct GameActions: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if model.running.contains(game.id) {
            Button("Stop") { model.stop(game.id) }
        } else {
            Button("Play") { model.play(game.id) }
        }
        Button("Settings…") { model.settingsGame = game.id }
        Divider()
        Button("Open C: Drive") { model.openDriveC(game.id) }
        Button("Show Files in Finder") { model.showGameInFinder(game.id) }
        Button("Make Mac Shortcut") { model.makeShortcut(game.id) }
        Button("Show Log") { model.showLog(game.id, "game") }
        Button("Troubleshoot…") { model.troubleshootGame = game.id }
        Button("Mods…") { model.modsGame = game.id }
        Divider()
        Button("Add Program to This Environment…") { model.addProgram(toEnvironmentOf: game.id) }
    }
}

extension View {
    func info(_ text: String) -> some View { modifier(SettingInfo(text: text)) }
}

struct SettingInfo: ViewModifier {
    let text: String
    @State private var shown = false

    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            content
                .help(text)
                .accessibilityHint(text)
            Button { shown.toggle() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("What this does")
            .accessibilityLabel("About this setting")
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 300, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

struct GameSettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let gameID: UUID
    @State private var draft: Game? = nil
    @State private var programs: [Analyzer.ProgramCandidate] = []
    @State private var confirmRemove = false
    @State private var tab = SettingsTab.general
    @State private var showAdvanced = false
    @Environment(\.openWindow) private var openWindow

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, graphics, compatibility, tools
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .graphics: return "Graphics"
            case .compatibility: return "Compatibility"
            case .tools: return "Tools & Saves"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let game = Binding($draft) {
                Picker("Page", selection: $tab) {
                    ForEach(SettingsTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 4)
                Form {
                    if tab == .general {
                        Section(game.wrappedValue.noun.capitalized) {
                            TextField("Name", text: game.name)
                            LabeledContent("Icon") {
                                HStack(spacing: 10) {
                                    GameIconView(game: game.wrappedValue, side: 32)
                                    Picker("Icon", selection: game.iconMode) {
                                        ForEach(IconMode.allCases) { Text($0.title(game.wrappedValue.noun)).tag($0) }
                                    }
                                    .info("Where its icon comes from, in the library and in Mac shortcuts.")
                                    .labelsHidden()
                                    .fixedSize()
                                    Button("Choose Image…") {
                                        if model.chooseCustomIcon(for: gameID) { game.wrappedValue.iconMode = .custom }
                                    }
                                }
                            }
                            .onChange(of: game.wrappedValue.iconMode) { _, mode in
                                if mode == .auto { model.refreshAutoIcon(game.wrappedValue) }
                            }
                            LabeledContent("File") {
                                Text(game.wrappedValue.exePath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            LabeledContent("Detected") {
                                Text("\(game.wrappedValue.graphics.label), \(game.wrappedValue.arch.label)")
                            }
                            Menu("Change Executable") {
                                let others = programs.filter { $0.url.path != game.wrappedValue.exePath }
                                ForEach(others.prefix(12), id: \.url) { program in
                                    Button("\(program.label) — \(program.url.lastPathComponent)") {
                                        let current = game.wrappedValue
                                        Task { draft = await model.retarget(current, to: program.url) }
                                    }
                                }
                                if !others.isEmpty { Divider() }
                                if let partner = model.partnerProgram(of: game.wrappedValue, among: programs) {
                                    Button("Add \(partner.role.label ?? "It") as Its Own Entry") {
                                        model.addPartnerProgram(PairOffer(gameID: gameID, gameName: game.wrappedValue.name,
                                                                          program: partner.url, role: partner.role))
                                    }
                                    Divider()
                                }
                                Button("Choose Another File…") {
                                    let current = game.wrappedValue
                                    Task { if let changed = await model.pickExecutable(for: current) { draft = changed } }
                                }
                            }
                            .info("The program Ferry starts. Lists the other programs in its folder, best guess first: single-player before multiplayer and launchers, servers and tools last.")
                            .task(id: game.wrappedValue.exePath) {
                                let exe = URL(fileURLWithPath: game.wrappedValue.exePath)
                                guard !ModLayout.looksLikeInstaller(exe) else { programs = []; return }
                                let folder = model.programFolder(for: exe)
                                programs = await Task.detached { Analyzer.rankedPrograms(in: folder) }.value
                            }
                        }
                        Section {
                            Picker("Graphics engine", selection: game.settings.engine) {
                                ForEach(EngineID.allCases.filter { $0.runtime.availableHere || $0 == .auto || $0 == game.wrappedValue.settings.engine }) {
                                    Text($0 == .auto ? "Automatic (\(model.recommendedEngine(game.wrappedValue).short))" : $0.title).tag($0)
                                }
                            }
                            .info("Which translator runs this \(game.wrappedValue.noun). Automatic picks the best one for its graphics and architecture; the compatibility check shows why.")
                            let engine = game.wrappedValue.settings.engine
                            let recommended = model.recommendedEngine(game.wrappedValue)
                            let autoNeeds: String? = engine == .auto ? "Already on Automatic, which uses it."
                                : engine == recommended ? "Already using it."
                                : game.wrappedValue.sharedWith != nil ? "Set in \(model.environmentOwner(of: game.wrappedValue).name)'s settings, whose Windows environment this uses."
                                : nil
                            LabeledContent {
                                Button("Use Auto") { game.wrappedValue.settings.engine = .auto }
                                    .disabled(autoNeeds != nil)
                            } label: {
                                settingLabel("Recommended: \(recommended.short)", needs: autoNeeds)
                            }
                        } header: {
                            Text("Engine")
                        } footer: {
                            Text("Using \(model.resolvedEngine(game.wrappedValue).short). Each engine keeps its own Windows environment; saves are shared between them.")
                        }
                    }
                    if tab == .graphics {
                        let g = game.wrappedValue
                        let engine = model.resolvedEngine(g)
                        let owner: String? = g.sharedWith == nil ? nil
                            : "Set in \(model.environmentOwner(of: g).name)'s settings, whose Windows environment this uses."
                        Section {
                            if g.graphics.hasDX9Fallback {
                                Toggle("Use DirectX 9", isOn: game.settings.useDX9)
                                    .info("Makes a DirectX 10 or 11 \(g.noun) use its older DirectX 9 renderer, for games with no setting of their own to switch. Ferry hides DirectX 10 and 11 from it and starts it with -dx9. Try it if the \(g.noun) crashes or draws wrong; turn it off if it won't start, since not every game still has a DirectX 9 renderer.")
                            }
                            Toggle(engine == .mach9 ? "MetalFX upscaling" : "DLSS via MetalFX", isOn: game.settings.metalFX)
                                .info(engine == .mach9
                                      ? "Renders at 75% resolution and upscales with MetalFX for a higher frame rate."
                                      : "When DLSS is selected in the \(g.noun)'s graphics options, D3DMetal upscales with Apple's MetalFX instead.")
                            Toggle(isOn: game.settings.retina) { settingLabel("Retina resolution", needs: owner) }
                                .disabled(owner != nil)
                                .info("Renders at the display's full pixel resolution. Sharper, but slower.")
                            if engine == .d3dmetal {
                                Picker(selection: game.settings.gameMode) {
                                    Text(g.usesGameMode && g.settings.gameMode == 0 ? "Automatic (on: it's a game)"
                                         : g.settings.gameMode == 0 ? "Automatic (off: it's an app)" : "Automatic").tag(0)
                                    Text("On").tag(1)
                                    Text("Off").tag(2)
                                } label: {
                                    settingLabel("macOS Game Mode", needs: owner)
                                }
                                .disabled(owner != nil)
                                .info("Game Mode gives a game more of the processor and graphics and lowers controller and AirPods latency. Automatic turns it on for programs where Ferry found game graphics or a game engine, and off for apps.")
                            }
                            Picker(selection: game.settings.uiScale) {
                                Text("Automatic").tag(0)
                                Text("Normal (100%)").tag(100)
                                Text("Large (200%)").tag(200)
                            } label: {
                                settingLabel("Interface size", needs: owner)
                            }
                            .disabled(owner != nil)
                            .info("Windows' scaling for menus, text and buttons. Automatic uses 200% with Retina for apps (so they're sharp at their usual size) and 100% for games, which handle their own resolution.")
                            Toggle("Performance HUD", isOn: game.settings.metalHUD)
                                .info("Shows the frame rate and GPU statistics (Metal HUD) over the \(g.noun).")
                            FrameLimitPicker(game: game)
                            Toggle("Native full-screen button", isOn: game.settings.macFullScreenButton)
                                .info("Enables the green window button for a windowed \(g.noun), opening it in a macOS full-screen space.")
                        } header: {
                            Text("Graphics")
                        } footer: {
                            Text("Click ⓘ beside a setting to see what it does.")
                        }
                        Section {
                            if showAdvanced {
                                if engine == .d3dmetal {
                                    Toggle("Report graphics card as NVIDIA", isOn: game.settings.reportNVIDIA)
                                        .info("D3DMetal tells games the Mac has an AMD card. Some games take AMD-only paths or workarounds that break on a Mac; this makes them see an NVIDIA GeForce RTX 3060 instead.")
                                    let nvidia = g.settings.reportNVIDIA
                                    Toggle(isOn: game.settings.hideROV) {
                                        settingLabel("Hide ROV support", needs: nvidia ? nil : "Needs Report graphics card as NVIDIA on.")
                                    }
                                        .disabled(!nvidia)
                                        .padding(.leading, 18)
                                        .info("Fixes some DirectX 12 games that show a black screen on D3DMetal. Tells the \(g.noun) the graphics card has no rasterizer-ordered views, so it uses its ordinary drawing path. Needs Report graphics card as NVIDIA: some games use ROV on an AMD card whatever they're told.")
                                    if g.rovSeen && !g.settings.hideROV {
                                        Text("Ferry saw this \(g.noun) draw with ROV, which D3DMetal can show as black. Hide ROV support is recommended.")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                if model.usesSDKXAudio2(g) {
                                    Toggle("Microsoft XAudio2", isOn: game.settings.nativeXAudio2)
                                        .info("This \(g.noun) plays sound with an older XAudio2 from the DirectX SDK. Wine's own version can hold back or drop sounds such as dialogue, so Ferry loads Microsoft's copy instead. Turn off if the game's sound breaks.")
                                }
                                let intelBuild = model.runtimes.info[.x64] != nil
                                let onRosetta = g.settings.mullionRosetta && intelBuild && model.runtimes.rosetta
                                if engine == .mullion {
                                    Picker(selection: game.settings.mullionRosetta) {
                                        Text("FEX").tag(false)
                                        Text("Rosetta 2").tag(true)
                                    } label: {
                                        settingLabel("CPU translation", needs: intelBuild ? nil
                                                     : "Rosetta 2 needs D3DMetal 4 (beta) from Settings ▸ Components, which includes MetalSharp's Intel build.")
                                    }
                                    .disabled(!intelBuild && !g.settings.mullionRosetta)
                                    .info("How the \(g.noun)'s Intel code runs on Apple silicon. FEX works without Rosetta, so it keeps working once macOS drops Rosetta. Rosetta 2 is usually faster, and uses MetalSharp's Intel build of the same Wine (it comes with D3DMetal 4 in Settings ▸ Components) in a Windows environment of its own. Without Rosetta or that build, Mullion uses FEX.")
                                    if intelBuild && g.settings.mullionRosetta && !model.runtimes.rosetta {
                                        Text("Rosetta 2 isn't available on this Mac, so Mullion uses FEX.")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    Picker("MetalSharp renderer", selection: game.settings.metalSharpBackend) {
                                        Text("Automatic (Mullion)").tag("")
                                        Text(g.arch == .x86 ? "DXVK (64-bit only)" : "DXVK").tag("dxvk")
                                        Text("WineD3D").tag("wine")
                                        Text("VKD3D-Proton (DirectX 12)").tag("vkd3d")
                                    }
                                    .info("How Mullion draws DirectX. Automatic uses Mullion for DirectX 10–12 and WineD3D for DirectX 9 and older. DXVK goes through Vulkan (64-bit only), WineD3D uses Wine's own DirectX for every version, and VKD3D-Proton is for DirectX 12 games that draw incorrectly on Mullion.")
                                    Picker("OpenGL implementation", selection: game.settings.metalSharpOpenGL) {
                                        Text("WineMetalGL (default)").tag("")
                                        Text("Apple's OpenGL").tag("wine")
                                    }
                                    .info("Which OpenGL draws OpenGL games, and DirectX 9 and older through WineD3D. WineMetalGL supports OpenGL 4.6 on Metal; Apple's OpenGL stops at 4.1 but is long-tested. Try Apple's if the \(g.noun) draws incorrectly.")
                                    let hasKosmicKrisp = model.runtimes.kosmicKrispDriver() != nil
                                    Picker(selection: Binding(
                                        get: { onRosetta ? "" : game.wrappedValue.settings.mullionVulkan },
                                        set: { if !onRosetta { game.wrappedValue.settings.mullionVulkan = $0 } })) {
                                        Text("MoltenVK (default)").tag("")
                                        Text("KosmicKrisp (from Mach9)").tag("kosmickrisp")
                                    } label: {
                                        settingLabel("Vulkan driver", needs: onRosetta ? "Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2, which uses MoltenVK."
                                                     : hasKosmicKrisp ? nil : "Install Mach9 in Settings ▸ Components first.")
                                    }
                                    .disabled(!hasKosmicKrisp || onRosetta)
                                    .info("What Vulkan games, and the DXVK and VKD3D-Proton renderers, draw through. KosmicKrisp runs all of Vulkan 1.4 on Metal; MoltenVK is the long-tested default. Try the other one if the \(g.noun) crashes or draws wrong.")
                                }
                                if engine == .mach9 {
                                    Picker("Mach9 renderer", selection: game.settings.mach9Direct3D) {
                                        Text("Metal: mtld3d, DXMT (default)").tag("")
                                        Text("WineD3D").tag("wined3d")
                                    }
                                    .info("How Mach9 draws DirectX. Metal uses mtld3d for DirectX 9 and DXMT for DirectX 10 and 11, straight to Metal. WineD3D uses Wine's own DirectX through OpenGL: slower, but worth trying if the \(g.noun) draws incorrectly.")
                                    if g.arch == .x86 {
                                        Toggle("Large address aware (4 GB)", isOn: game.settings.fullMemory32)
                                            .info("Gives this 32-bit \(g.noun) 4 GB of address space instead of 2 GB, preventing out-of-memory crashes. Turn off if the \(g.noun) won't start.")
                                    }
                                }
                                let dx9Capable = [GraphicsAPI.dx9, .unknown].contains(g.graphics) || g.graphics.hasDX9Fallback
                                let dx9Needs: String? = [GraphicsAPI.dx9, .unknown].contains(g.drawsWith) ? nil : "Needs Use DirectX 9 on."
                                if dx9Capable && engine != .mach9 {
                                    Toggle(isOn: game.settings.dxvkD3D9) { settingLabel("DirectX 9 via DXVK", needs: dx9Needs) }
                                        .disabled(dx9Needs != nil && !g.settings.dxvkD3D9)
                                        .info("Renders DirectX 9 through DXVK (Vulkan → Metal) instead of WineD3D. On Mullion, 64-bit programs use MetalSharp's newer DXVK, which runs natively on Apple silicon (needs Mach9 installed for its KosmicKrisp driver); 32-bit games use DXVK 1.10.3, the newest 32-bit build for macOS.")
                                    let dxvkNeeds: String? = dx9Needs ?? (g.settings.dxvkD3D9 ? nil : "Needs DirectX 9 via DXVK on.")
                                    if engine == .mullion && g.arch == .x86 {
                                        let betaNeeds: String? = dxvkNeeds
                                            ?? (onRosetta ? "Only with CPU translation set to FEX: KosmicKrisp doesn't run through Rosetta 2. DXVK 1.10.3 is used instead."
                                                : model.betaDXVK32() == nil ? "Optional beta download: install it in Settings ▸ Components ▸ Optional beta downloads."
                                                : model.runtimes.kosmicKrispDriver() == nil ? "Needs Mach9 installed, for its KosmicKrisp driver." : nil)
                                        Toggle(isOn: Binding(
                                            get: { betaNeeds == nil && game.wrappedValue.settings.dxvkBeta },
                                            set: { if betaNeeds == nil { game.wrappedValue.settings.dxvkBeta = $0 } })) {
                                            settingLabel("DXVK 3 on KosmicKrisp (beta)", needs: betaNeeds)
                                        }
                                        .disabled(betaNeeds != nil)
                                        .padding(.leading, 18)
                                        .info("Uses the newest official DXVK (\(model.betaDXVKVersion ?? "3.x")) through KosmicKrisp instead of DXVK 1.10.3 from 2023 through MoltenVK. Experimental: turn it off if the \(g.noun) draws incorrectly or won't start.")
                                    }
                                    Picker(selection: game.settings.dxvkVideoMemory) {
                                        Text(Platform.memoryGB <= 8 ? "Automatic (1 GB on this Mac)" : "Automatic (DXVK's own)").tag(0)
                                        Text("512 MB").tag(512)
                                        Text("1 GB").tag(1024)
                                        Text("2 GB").tag(2048)
                                        Text("4 GB").tag(4096)
                                        Text("DXVK's own").tag(-1)
                                    } label: {
                                        settingLabel("Video memory (DXVK)", needs: dxvkNeeds)
                                    }
                                    .disabled(dxvkNeeds != nil)
                                    .padding(.leading, 18)
                                    .info("How much video memory the \(g.noun) is told it has. On Macs with 8 GB or less, games told they have lots keep every texture loaded until macOS runs out of memory, which makes them stutter or play in slow motion. Raise it if a game hides graphics options or won't start.")
                                }
                                if dx9Capable {
                                    Picker(selection: game.settings.drawCopies) {
                                        Text(model.drawsCopies(g) ? "Automatic (on)" : "Automatic (off)").tag(Bool?.none)
                                        Text("On").tag(Bool?.some(true))
                                        Text("Off").tag(Bool?.some(false))
                                    } label: {
                                        settingLabel("Faster screen copies", needs: dx9Needs)
                                    }
                                    .disabled(dx9Needs != nil)
                                    .info("Performs DirectX 9 copies into the frame being drawn as draws, which Apple GPUs handle several times faster. Games with screen effects such as panoramas, blur or glow can make hundreds of these copies per frame. On automatically for DirectX 9 games. Turn it off if a game draws incorrectly or won't start.")
                                }
                                if g.arch == .x86 {
                                    Toggle("DirectDraw compatibility (cnc-ddraw)", isOn: Binding(
                                        get: { game.wrappedValue.settings.cncDdraw },
                                        set: { game.wrappedValue.settings.cncDdraw = $0; if $0 { game.wrappedValue.settings.dgVoodoo = false } }))
                                        .info("Fixes slow, flickering or broken DirectDraw games from the 1990s and 2000s.")
                                    let dgVoodooReady = model.componentStatus[.dgVoodoo]?.installed ?? false
                                    Toggle(isOn: Binding(
                                        get: { game.wrappedValue.settings.dgVoodoo },
                                        set: { game.wrappedValue.settings.dgVoodoo = $0; if $0 { game.wrappedValue.settings.cncDdraw = false } })) {
                                        settingLabel("Old 3D game fix (dgVoodoo2)", needs: dgVoodooReady ? nil : "Install it in Settings ▸ Components first.")
                                    }
                                    .disabled(!dgVoodooReady && !g.settings.dgVoodoo)
                                    .info("For 3D games from the late 1990s that use 3dfx Glide or DirectX 1–7, and draw wrong, crash or won't start. dgVoodoo2 draws them through DirectX 11 instead. Experimental under Wine: turn it off if the \(g.noun) gets worse. Turns cnc-ddraw off, since both replace the same file.")
                                }
                                if g.graphics.hasDX9Fallback && [EngineID.dxvk, .wined3d].contains(engine) {
                                    let dxmtReady = model.componentStatus[.dxmt]?.installed ?? false
                                    let dxmtNeeds: String? = g.settings.useDX9 ? "Turn off Use DirectX 9 first."
                                        : dxmtReady ? nil : "Install DXMT (beta) in Settings ▸ Components first."
                                    Toggle(isOn: game.settings.dxmtUpstream) { settingLabel("DirectX 10/11 via DXMT (beta)", needs: dxmtNeeds) }
                                        .disabled(dxmtNeeds != nil && !g.settings.dxmtUpstream)
                                        .info("Draws DirectX 10 and 11 with the newest official DXMT\(model.upstreamDXMTVersion.map { " (\($0))" } ?? "") straight to Metal, instead of \(engine == .wined3d ? "WineD3D through OpenGL" : "DXVK through Vulkan"). Often much faster. Experimental: turn it off if the \(g.noun) crashes or draws wrong.")
                                }
                                if [EngineID.wined3d, .dxvk, .mach9].contains(engine) {
                                    let wined3dNeeds: String? = engine == .mach9 && g.settings.mach9Direct3D != "wined3d"
                                        ? "Needs Mach9 renderer set to WineD3D." : nil
                                    Picker(selection: game.settings.wined3dVulkan) {
                                        Text("OpenGL (default)").tag(false)
                                        Text("Vulkan").tag(true)
                                    } label: {
                                        settingLabel("WineD3D renderer", needs: wined3dNeeds)
                                    }
                                    .disabled(wined3dNeeds != nil)
                                    .info("What WineD3D draws DirectX 9 and older with. OpenGL is the most tested on the Mac. Vulkan goes through MoltenVK and can crash some games.")
                                    Toggle(isOn: game.settings.wined3dSingleThread) { settingLabel("Single-threaded rendering", needs: wined3dNeeds) }
                                        .disabled(wined3dNeeds != nil)
                                        .info("Turns off WineD3D's command-stream threading (CSMT). Fixes parts of models lagging a frame behind; slightly slower.")
                                    Toggle(isOn: game.settings.openGLBackingStore) { settingLabel("OpenGL backing store", needs: wined3dNeeds ?? owner) }
                                        .disabled(wined3dNeeds != nil || owner != nil)
                                        .info("Fixes windows that freeze, stay blank or flicker.")
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { showAdvanced.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                                        .font(.caption.weight(.semibold))
                                    Text("Advanced")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showAdvanced ? "Hide advanced settings" : "Show advanced settings")
                        } footer: {
                            Text("For when a \(g.noun) won't start or doesn't draw right. Change one setting at a time. Greyed-out settings say what they need.")
                        }
                    }
                    if tab == .compatibility {
                        let g = game.wrappedValue
                        let owner: String? = g.sharedWith == nil ? nil
                            : "Set in \(model.environmentOwner(of: g).name)'s settings, whose Windows environment this uses."
                        Section("Compatibility") {
                            Picker(selection: game.settings.windowsVersion) {
                                Text("Windows 11").tag("win11")
                                Text("Windows 10").tag("win10")
                                Text("Windows 8.1").tag("win81")
                                Text("Windows 7").tag("win7")
                                Text("Windows XP").tag("winxp64")
                            } label: {
                                settingLabel("Windows version", needs: owner)
                            }
                            .disabled(owner != nil)
                            .info("The Windows version the \(g.noun) sees. Some older programs refuse to start, or behave differently, on newer versions.")
                            Picker("Windows language", selection: game.settings.windowsLanguage) {
                                Text("Same as this Mac").tag("")
                                Divider()
                                ForEach(GameSettings.windowsLanguages, id: \.code) { Text($0.name).tag($0.code) }
                            }
                            .info("The language and region Windows tells the \(g.noun) it has. Many games made for Japan, China, Korea or Russia show garbled text, crash or won't start unless Windows is set to their language, because they write text in that language's old character set. This changes only what the \(g.noun) sees, not the \(g.noun)'s own language setting.")
                            Toggle(isOn: game.settings.commandIsCtrl) { settingLabel("⌘ Command as Ctrl", needs: owner) }
                                .disabled(owner != nil)
                                .info("Command works as Ctrl in the \(g.noun), so ⌘C and ⌘S act as Ctrl+C and Ctrl+S.")
                            Toggle(isOn: game.settings.optionIsAlt) { settingLabel("⌥ Option as Alt", needs: owner) }
                                .disabled(owner != nil)
                                .info("Option works as Alt in the \(g.noun), for shortcuts such as Alt+Enter.")
                            Toggle(isOn: game.settings.captureFullscreen) { settingLabel("Exclusive full-screen mode", needs: owner) }
                                .disabled(owner != nil)
                                .info("Lets the \(g.noun) change the display's resolution. When off, full screen is virtual: it's scaled to fit the display.")
                            if owner == nil && g.settings.captureFullscreen && g.graphics == .unknown {
                                Text("Meant for games. In an app like this one, a maximized window can trap the mouse and stop resizing, so it's best left off.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Toggle("Fast synchronization (MSync)", isOn: game.settings.fastSync)
                                .info("Handles Windows synchronization with Mach semaphores instead of Wine's server. Faster; rarely incompatible.")
                            Toggle("Advertise AVX (Rosetta)", isOn: game.settings.advertiseAVX)
                                .info("Reports AVX support to programs that require it. Applies to engines that run through Rosetta.")
                            if g.arch == .x86 {
                                let legacyReady = model.componentStatus[.legacyDirectX]?.installed ?? false
                                let legacyNeeds: String? = legacyReady ? nil : "Install DirectMusic and DirectPlay in Settings ▸ Components first."
                                Toggle(isOn: game.settings.nativeDirectMusic) { settingLabel("Microsoft's DirectMusic", needs: legacyNeeds) }
                                    .disabled(!legacyReady && !g.settings.nativeDirectMusic)
                                    .info("Plays the \(g.noun)'s music with Microsoft's DirectMusic instead of Wine's, which is incomplete. Try it if a game from around 1998–2005 has no music, or crashes when music starts. Turn it off if sound gets worse.")
                                Toggle(isOn: game.settings.nativeDirectPlay) { settingLabel("Microsoft's DirectPlay", needs: legacyNeeds) }
                                    .disabled(!legacyReady && !g.settings.nativeDirectPlay)
                                    .info("Uses Microsoft's DirectPlay instead of Wine's for the \(g.noun)'s LAN or online multiplayer. Try it if an older game's multiplayer menu fails, crashes or finds no games.")
                            }
                            Toggle("Show on Discord", isOn: game.settings.showOnDiscord)
                                .info("Shows this \(g.noun) on your Discord profile while it runs.")
                            ArgsEditor(text: game.settings.arguments)
                                .id("args-\(gameID)")
                            EnvEditor(text: game.settings.extraEnv)
                                .id(gameID)
                            Toggle(isOn: game.settings.webView2) {
                                Text("WebView2 for launchers").foregroundStyle(model.webView2Installed ? .primary : .tertiary)
                                if !model.webView2Installed { Text("Install WebView2 in Settings ▸ Components first.") }
                            }
                                .disabled(!model.webView2Installed)
                                .info("For launchers whose window or login page is blank. Lets them show built-in web pages with Microsoft's WebView2, installed once in Settings ▸ Components and shared between games and apps. It doesn't work for every launcher under Wine.")
                        }
                    }
                    if tab == .tools {
                        Section("Windows") {
                            HStack {
                                Button("Open C: Drive") { model.openDriveC(gameID) }
                                Button("Wine Configuration") { model.runTool(gameID, ["winecfg"]) }
                                Button("Windows Controller Panel") { model.runTool(gameID, ["control", "joy.cpl"]) }
                                    .help("Wine's own game controller panel, to check that Windows sees the controller")
                            }
                            Button("Add Program to This Environment…") { model.addProgram(toEnvironmentOf: gameID) }
                                .help("Add a game or app this launcher installed, so it can start straight from Ferry")
                        }
                        Section("Fix Problems") {
                            HStack {
                                Button("Troubleshoot…") {
                                    if let draft { model.saveSettings(draft) }
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.troubleshootGame = gameID }
                                }
                                Button("Reinstall Windows Libraries") { model.reinstallLibraries(gameID) }
                                    .help("Visual C++, DirectX, .NET, XNA and OpenAL")
                            }
                            HStack {
                                Button("Show Log") { model.showLog(gameID, "game") }
                                Button("Show Setup Log") { model.showLog(gameID, "setup") }
                            }
                        }
                        Section("Mac") {
                            HStack {
                                Button("Make Mac Shortcut") { model.makeShortcut(gameID) }
                                Button("Controller Settings…") { openWindow(id: "controller") }
                                    .help("Ferry's Controller window: rebind buttons for every game and app, or play with the controller as a keyboard and mouse")
                            }
                        }
                        Section {
                            HStack {
                                Button("Back Up Saves") { model.backupSaves(gameID) }
                                Button("Open Saves Folder") { model.openSavesFolder(gameID) }
                                Button("Clear Shader Cache") { model.clearShaderCache(gameID) }
                                    .help("Clear it if a game flickers or glitches after an update. It stutters briefly while the cache rebuilds.")
                            }
                        } header: {
                            Text("Saves and Caches")
                        } footer: {
                            Text("Saves are shared by every engine, so switching engines never hides them. Backups go to Documents ▸ Ferry Backups.")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollBounceBehavior(.basedOnSize)
            }

            HStack {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Text("Remove from Ferry…").foregroundStyle(.red)
                }
                if model.preparing.contains(gameID), let status = model.status {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let draft { model.saveSettings(draft) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 560, idealHeight: 720)
        .onAppear {
            draft = model.game(gameID)
            if let d = draft, d.rovSeen && !d.settings.hideROV { showAdvanced = true }
        }
        .confirmationDialog("Remove \(draft?.name ?? "this program") from Ferry?", isPresented: $confirmRemove) {
            if draft?.sharedWith != nil {
                Button("Remove") {
                    model.remove(gameID, deleteWindowsFiles: false)
                    dismiss()
                }
            } else {
                Button("Remove but Keep Its Environment") {
                    model.remove(gameID, deleteWindowsFiles: false)
                    dismiss()
                }
                Button("Remove and Delete Its Environment and Saves", role: .destructive) {
                    model.remove(gameID, deleteWindowsFiles: true)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeMessage)
        }
    }

    private var removeMessage: String {
        guard let g = draft else { return "" }
        if g.sharedWith != nil {
            return "Only the Ferry entry goes away. \(model.environmentOwner(of: g).name)'s Windows environment, and the \(g.noun) inside it, stay."
        }
        let sharing = model.sharers(of: g.id).count
        var text = "The \(g.noun)'s own files on your Mac are never touched."
        if sharing > 0 {
            text += " The \(sharing) program\(sharing == 1 ? "" : "s") added to its environment will be removed from Ferry too."
        }
        return text
    }
}

struct SettingsView: View {
    @AppStorage(SettingsView.tabKey) private var tab = "engines"
    static let tabKey = "settingsTab"

    var body: some View {
        TabView(selection: $tab) {
            EngineSettings().tabItem { Label("Engines", systemImage: "cpu") }.tag("engines")
            ComponentSettings().tabItem { Label("Components", systemImage: "shippingbox") }.tag("components")
            DefaultSettings().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            NewGameSettings().tabItem { Label("New Games", systemImage: "plus.app") }.tag("newGames")
            SystemSettings().tabItem { Label("System", systemImage: "lock.shield") }.tag("system")
            StorageView(showsDone: false).tabItem { Label("Storage", systemImage: "internaldrive") }.tag("storage")
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 560, idealHeight: 640)
    }
}

struct EngineSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager
    @State private var error: String? = nil
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("checkOnLaunch") private var checkOnLaunch = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(updateStatus).font(.callout)
                            Text(lastCheckedText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if runtimes.checkingForUpdates {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check for Updates") { model.checkForUpdatesNow() }
                            .disabled(runtimes.checkingForUpdates || busy)
                        if !runtimes.availableUpdates.isEmpty {
                            Button("Update All") { model.installUpdates() }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                        }
                    }
                    Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                        .help("Checks for new versions of Ferry and its engines and components once a day, and tells you when updates are available.")
                    Toggle("Check for updates when Ferry opens", isOn: $checkOnLaunch)
                        .help("Checks for new versions of Ferry and its engines and components each time Ferry opens, so updates show up as soon as they're out.")
                } header: {
                    Text("Updates")
                }

                ForEach([RuntimeKind.gptk, .x64, .staging, .dxvk, .arm64, .mach9].filter { $0.availableHere && ($0 != .x64 || runtimes.info[.x64] != nil) }) { kind in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(kind.title).font(.headline)
                                    .info(kind.blurb)
                                Spacer()
                                if runtimes.updateAvailable(kind) {
                                    Text("\(runtimes.info[kind]?.version ?? "") → \(runtimes.latest[kind] ?? "") available")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tint)
                                } else {
                                    Text(versionText(kind)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(Self.firstSentence(kind.blurb)).font(.caption).foregroundStyle(.secondary)
                            let users = model.games.filter { model.runtimeKind($0) == kind }.map(\.name)
                            if runtimes.info[kind] != nil {
                                Text(users.isEmpty ? "Not used by any game or app right now"
                                     : "Used by " + ListFormatter.localizedString(byJoining: users))
                                    .font(.caption)
                                    .foregroundStyle(users.isEmpty ? .tertiary : .secondary)
                                    .lineLimit(2)
                            }
                            if kind == .gptk, runtimes.info[.x64] != nil {
                                Label("D3DMetal games run on D3DMetal 4 (beta) below. Remove that to use this one again.", systemImage: "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                            HStack {
                                if runtimes.updateAvailable(kind) {
                                    Button(actionTitle(kind)) { perform { try await model.updateEngine(kind) } }
                                        .buttonStyle(.borderedProminent)
                                } else {
                                    Button(actionTitle(kind)) { perform { try await model.updateEngine(kind) } }
                                }
                                Button("Remove", role: .destructive) { model.removeEngine(kind) }
                                    .disabled(runtimes.info[kind] == nil)
                                    .help(runtimes.info[kind] == nil ? "It isn't installed." : "Deletes this engine; Ferry downloads it again if a game needs it.")
                                if kind == .gptk {
                                    let d3dmetal4 = runtimes.info[.x64] != nil
                                    Button("Import Newer D3DMetal…") { importD3DMetal() }
                                        .disabled(d3dmetal4)
                                        .help(d3dmetal4 ? "D3DMetal games run on D3DMetal 4 (beta) while it's installed. Remove it to use an imported D3DMetal."
                                              : "Use the D3DMetal from Apple's \"Evaluation environment for Windows games\" .dmg")
                                    Button("Restore Bundled Version") { runtimes.restoreBundledD3DMetal() }
                                        .disabled(d3dmetal4 || !runtimes.hasD3DMetalBackup)
                                        .help(runtimes.hasD3DMetalBackup ? "Goes back to the D3DMetal the Game Porting Toolkit came with."
                                              : "Only after importing a newer D3DMetal: it goes back to the one the Game Porting Toolkit came with.")
                                }
                            }
                            .disabled(busy)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let task = runtimes.task ?? model.status {
                HStack {
                    TaskProgressBar(value: runtimes.progress).frame(width: 160)
                    Text(task).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .alert("Couldn't finish", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var busy: Bool { runtimes.task != nil || model.setupRunning || model.updating }

    static func firstSentence(_ text: String) -> String {
        guard let end = text.range(of: ". ") else { return text }
        return String(text[..<end.lowerBound]) + "."
    }

    private var updateStatus: String {
        let count = runtimes.availableUpdates.count
        if count == 0 { return "Everything is up to date" }
        return count == 1 ? "1 update available" : "\(count) updates available"
    }

    private var lastCheckedText: String {
        guard let date = runtimes.lastUpdateCheck else { return "Not checked yet" }
        let formatter = RelativeDateTimeFormatter()
        return "Last checked \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func actionTitle(_ kind: RuntimeKind) -> String {
        if runtimes.info[kind] == nil { return "Install" }
        return runtimes.updateAvailable(kind) ? "Update" : "Reinstall"
    }

    private func versionText(_ kind: RuntimeKind) -> String {
        guard let info = runtimes.info[kind] else { return "Not installed — downloads automatically when a game or app needs it" }
        if let imported = info.d3dmetalImported { return "\(info.version) · D3DMetal \(imported)" }
        if kind == .x64, let d3dmetal = runtimes.x64D3DMetalVersion { return "\(info.version) · D3DMetal \(d3dmetal) · Wine 11 · In use" }
        if kind == .gptk, runtimes.info[.x64] != nil { return "\(info.version) · Not in use" }
        return info.version
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }

    private func importD3DMetal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dmg") ?? .diskImage]
        panel.message = "Choose Apple's Game Porting Toolkit .dmg (Evaluation environment for Windows games)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try await runtimes.importD3DMetal(from: url) }
    }
}

struct DefaultSettings: View {
    @AppStorage("discordPresence") private var discordPresence = true
    @AppStorage("discordFallbackID") private var discordFallbackID = ""
    @AppStorage("discordShowFerry") private var discordShowFerry = true
    @AppStorage(UnpackDestination.defaultsKey) private var unpackDestination = UnpackDestination.games.rawValue
    @AppStorage(UnpackDestination.customFolderKey) private var unpackCustomFolder = ""
    @AppStorage("deleteArchiveAfterAdd") private var deleteArchiveAfterAdd = false
    @AppStorage(GameWiki.defaultsKey) private var onlineLookup = true
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                ThemeColorSetting()
            }
            Section {
                Picker("Unpack to", selection: $unpackDestination) {
                    ForEach(UnpackDestination.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .info("Where games and apps that come as .zip, .rar or .7z archives (including multi-part ones like .part1.rar or .7z.001) are unpacked, so adding them is instant. Ferry checks there's enough free space first. \"Next to the archive\" keeps the game on the same drive as the archive, e.g. a big external drive.")
                let customFolder = unpackDestination == UnpackDestination.custom.rawValue
                LabeledContent {
                    HStack {
                        Text(unpackCustomFolder.isEmpty ? "None chosen yet" : (unpackCustomFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseUnpackFolder() }
                    }
                } label: {
                    settingLabel("Folder", needs: customFolder ? nil : "Only with Unpack to set to \"\(UnpackDestination.custom.title)\".")
                }
                .disabled(!customFolder)
                Toggle("Permanently delete archives after adding what's in them", isOn: $deleteArchiveAfterAdd)
                    .info("Deletes an archive for good, not to the Trash, and only once the game or app in it is unpacked and safely in place.")
            } header: {
                Text("Games and Apps from Archives")
            } footer: {
                Text(".zip, .rar and .7z games and apps are unpacked straight into this folder.")
            }
            Section {
                Toggle("Look up games online when needed", isOn: $onlineLookup)
                    .info("When Ferry can't tell from a program's files which graphics it uses (DirectX 9, 11, Vulkan…), it looks the game up on PCGamingWiki, a community database of PC games, and checks it for anti-cheat. Each game is looked up once, and Ferry ignores a page unless its title matches the game.")
            } header: {
                Text("Compatibility Check")
            } footer: {
                Text("Only the game's name is sent, to PCGamingWiki.")
            }
            Section {
                Toggle("Show the current game on Discord", isOn: $discordPresence)
                    .info("Sets your Discord status to the game you're playing, through the Discord app on this Mac. Games Discord recognizes, like Call of Duty: Black Ops II, show with their real name and icon, plus \"Playing through Ferry on Mac\". Each game's settings can hide it from Discord.")
                TextField("Ferry's Discord Application ID (optional)", text: $discordFallbackID,
                          prompt: Text("For example, 1234567890123456789"))
                    .disabled(!discordPresence)
                Toggle("Show \"Playing Ferry\" while Ferry is open", isOn: $discordShowFerry)
                    .info("Shows Ferry itself on Discord while it's open. Needs a Ferry application ID.")
                    .disabled(!discordPresence || discordFallbackID.isEmpty)
                DisclosureGroup("Setting up a Ferry application ID") {
                    Text("With a Ferry application ID, games Discord doesn't know (most fan games) show as \"Playing Ferry\" with the game's name, and Ferry itself can show while it's open.\n\n1. Create an application named \"Ferry\" at discord.com/developers/applications and paste its Application ID above.\n2. Click Save Ferry's Icon for Discord.\n3. Upload the icon as the App Icon (General Information) and as an art asset named exactly \"ferry\" (Rich Presence ▸ Art Assets).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                    Button("Save Ferry's Icon for Discord…") { model.saveIconForDiscord() }
                }
            } header: {
                Text("Discord")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseUnpackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where games from archives are unpacked"
        if panel.runModal() == .OK, let url = panel.url { unpackCustomFolder = url.path }
    }
}

struct NewGameSettings: View {
    @AppStorage("autoRuntimes") private var autoRuntimes = true
    @AppStorage("defaultFastSync") private var fastSync = true
    @AppStorage("defaultAVX") private var avx = true
    @AppStorage("defaultRetina") private var retina = false
    @AppStorage("defaultMetalFX") private var metalFX = false
    @AppStorage("defaultVSync") private var vsync = true
    @AppStorage("defaultCommandIsCtrl") private var commandIsCtrl = false

    var body: some View {
        Form {
            Section {
                Toggle("Install Windows libraries for games and apps outside the ready-made environments", isOn: $autoRuntimes)
                    .info("Installs Visual C++, DirectX, .NET and other libraries the first time a game or app runs, if it didn't get a copy of a ready-made environment.")
            } footer: {
                Text("New games and apps normally start from a ready-made environment that already has these.")
            }
            Section {
                Toggle("Fast synchronization (MSync)", isOn: $fastSync)
                    .info("Handles Windows synchronization with Mach semaphores instead of Wine's server. Faster; rarely incompatible.")
                Toggle("Advertise AVX (Rosetta)", isOn: $avx)
                    .info("Reports AVX support to programs that require it. Applies to engines that run through Rosetta.")
                Toggle("Retina resolution", isOn: $retina)
                    .info("Renders at the display's full pixel resolution. Sharper, but slower.")
                Toggle("DLSS → MetalFX upscaling", isOn: $metalFX)
                    .info("Lets games that offer NVIDIA DLSS use Apple's MetalFX upscaling instead (D3DMetal), and upscales with MetalFX on Mach9.")
                Toggle("VSync", isOn: $vsync)
                    .info("Shows each frame in step with the display's refresh, so the picture doesn't tear, and keeps games from drawing more frames than the display can show (\(Platform.displayHz) a second on this Mac's display). The time they'd spend on frames you never see goes to the game and macOS instead: cooler, quieter, and longer on battery.")
                Toggle("⌘ Command as Ctrl", isOn: $commandIsCtrl)
                    .info("Command works as Ctrl in games and apps, so ⌘C and ⌘S act as Ctrl+C and Ctrl+S.")
            } header: {
                Text("Defaults for New Games and Apps")
            } footer: {
                Text("Each game or app can change these in its own settings.")
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var runtimes: RuntimeManager

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if runtimes.rosetta {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Install Rosetta") { Task { await runtimes.installRosetta() } }
                            .disabled(runtimes.task != nil)
                    }
                } label: {
                    Text("Rosetta 2").info("Windows games and programs are Intel code; Rosetta 2 translates it for Apple silicon. MetalSharp Wine uses FEX instead and doesn't need it.")
                }
                LabeledContent {
                    if runtimes.gstreamerInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Install GStreamer") {
                            Task {
                                do { try await runtimes.installGStreamer() } catch { model.errorMessage = error.localizedDescription }
                            }
                        }
                        .disabled(runtimes.task != nil)
                    }
                } label: {
                    Text("GStreamer (video cutscenes)").info("Plays video in Wine Staging games and programs. The other engines include their own.")
                }
                LabeledContent {
                    if runtimes.sevenZipInstalled {
                        Label(runtimes.sevenZipVersion.map { "Installed (\($0))" } ?? "Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Install 7-Zip") {
                            Task {
                                do { try await runtimes.installSevenZip() } catch { model.errorMessage = error.localizedDescription }
                            }
                        }
                        .disabled(runtimes.task != nil)
                    }
                } label: {
                    Text("7-Zip (faster unpacking)").info("Unpacks games that come as archives, including multi-part ones. Without it, Ferry uses macOS's built-in unpacker for single archives.")
                }
            }

            Section {
                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Folder Access")
            } footer: {
                Text("macOS asks once when a game first reads Downloads, Documents, Desktop or an external drive. Full Disk Access skips those prompts.")
            }

            Section {
                Button("Run Setup Again") { model.runSetup() }
                    .disabled(model.setupRunning)
            } header: {
                Text("Repair")
            } footer: {
                Text("Reinstalls anything missing and rebuilds the ready-made Windows environments. Your games, settings and saves are kept.")
            }

            Section("Ferry's Files") {
                Button("Show Ferry Data Folder") { NSWorkspace.shared.open(Paths.root) }
                Button("Show Mac Shortcuts Folder") {
                    try? FileManager.default.createDirectory(at: Paths.shortcuts, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Paths.shortcuts)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ArgsEditor: View {
    @Binding var text: String
    @State private var rows: [Row] = []

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var value = ""
    }

    var body: some View {
        LabeledContent("Launch arguments") {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach($rows) { $row in
                    HStack(spacing: 4) {
                        TextField("For example, -windowed", text: $row.value)
                        Button { rows.removeAll { $0.id == row.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this argument")
                    }
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                }
                Button { rows.append(Row()) } label: {
                    Label("Add Argument", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .help("Extra options passed to the program when it starts, such as -windowed or -skipintro. Which ones work depends on the program.")
        .onAppear { rows = ArgsText.options(text).map { Row(value: $0) } }
        .onChange(of: rows) {
            text = rows.map { $0.value.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

struct EnvEditor: View {
    @Binding var text: String
    @State private var rows: [Row] = []

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var key = ""
        var value = ""
    }

    var body: some View {
        LabeledContent("Environment variables") {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 4) {
                        TextField("VARIABLE_NAME", text: field(row.id, \.key))
                            .frame(minWidth: 200, maxWidth: .infinity)
                        Text("=").foregroundStyle(.secondary)
                        TextField("Value", text: field(row.id, \.value))
                            .frame(width: 80)
                        Button { rows.removeAll { $0.id == row.id }; commit() } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this variable")
                    }
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                }
                Button { rows.append(Row()) } label: {
                    Label("Add Variable", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .help("Settings passed to Wine and its graphics layers when the program starts, written as NAME = value. For troubleshooting; most programs need none.")
        .onAppear { load(text) }
    }

    private func field(_ id: Row.ID, _ part: WritableKeyPath<Row, String>) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == id }?[keyPath: part] ?? "" },
            set: { value in
                guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[i][keyPath: part] = value
                commit()
            })
    }

    private func commit() {
        text = EnvText.text(rows.map { ($0.key, $0.value) })
        if rows.contains(where: { $0.key.contains("=") }) { load(text) }
    }

    private func load(_ s: String) {
        rows = EnvText.pairs(s).map { Row(key: $0.key, value: $0.value) }
    }
}
