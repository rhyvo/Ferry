import AppKit
import SwiftUI

struct TroubleshootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let gameID: UUID

    @State private var symptom: Symptom? = nil
    @State private var done: Set<String> = []
    @State private var findings: [LogFinding] = []

    private var game: Game? { model.game(gameID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let g = game { GameIconView(game: g, side: 32) }
                Text(symptom?.title ?? "What's happening with \(game?.name ?? "it")?")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
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
                if let g = game {
                    Button("Ask the assistant") {
                        model.openAssistant(for: g.id)
                        dismiss()
                    }
                    .help("Opens the assistant at the bottom of Ferry's window about this \(g.noun): it can read the log and settings, and suggest or make changes")
                    Button("Report a Bug…") { NSWorkspace.shared.open(bugReportURL(g)) }
                        .help("Opens a bug report on Ferry's GitHub with this \(g.noun)'s details filled in (no file paths). You can read and change everything before sending it.")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }

    private func bugReportURL(_ g: Game) -> URL {
        var c = URLComponents(string: "https://github.com/rhyvo/Ferry/issues/new")!
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var items = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "ferry-version", value: version),
            URLQueryItem(name: "mac", value: "\(Self.macModel), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
            URLQueryItem(name: "game", value: g.name),
            URLQueryItem(name: "engine", value: model.subtitle(for: g)),
        ]
        if let symptom {
            items.append(URLQueryItem(name: "title", value: "\(g.name): \(symptom.title)"))
            items.append(URLQueryItem(name: "what-happened", value: symptom.title + "\n\n"))
        }
        c.queryItems = items
        return c.url!
    }

    private static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &name, &size, nil, 0)
        return String(cString: name)
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

    private func steps(for symptom: Symptom, _ g: Game) -> some View {
        let list = TroubleshootFixes.steps(for: symptom, model.fixContext(g))
        return ForEach(list, id: \.id) { render($0, g) }
    }

    @ViewBuilder
    private func render(_ s: FixStep, _ g: Game) -> some View {
        switch s.action {
        case .note:
            note(s.detail)
        case .settings(let changes):
            let isToggle = s.button == "Turn On" || s.button == "Turn Off"
            stepCard(title: s.title, detail: s.detail) {
                if isToggle {
                    Button(s.button) { change(g) { TroubleshootFixes.apply(changes, to: &$0.settings) }; done.insert(s.id) }
                        .disabled(s.inEffect)
                    if done.contains(s.id) { Text("Start the \(g.noun) to try it").font(.caption).foregroundStyle(.secondary) }
                    else if s.inEffect { Text(s.button == "Turn On" ? "Already on" : "Already off").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Button(s.button) { change(g) { TroubleshootFixes.apply(changes, to: &$0.settings) }; done.insert(s.id) }
                        .disabled(s.inEffect && !done.contains(s.id))
                    if done.contains(s.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if s.inEffect { Text("Already on").font(.caption).foregroundStyle(.secondary) }
                }
            }
        case .picker(let key, let choices):
            let current = SettingsCatalog.entry(key)?.get(g.settings).text ?? ""
            let label = choices.first { $0.value == current }?.label.replacingOccurrences(of: " (lowest)", with: "")
                ?? (key == "maxTessellation" ? current : choices.first?.label ?? "")
            stepCard(title: s.title, detail: s.detail) {
                Menu(label) {
                    ForEach(choices, id: \.value) { choice in
                        Button(choice.label) {
                            change(g) { TroubleshootFixes.apply([SettingChange(key: key, value: choice.value)], to: &$0.settings) }
                            done.insert(s.id)
                        }
                        if choice == choices.first { Divider() }
                    }
                }
                .fixedSize()
                if done.contains(s.id) { Text("Start the \(g.noun) to try it").font(.caption).foregroundStyle(.secondary) }
            }
        case .install(let component, let then):
            let c = Component(rawValue: component)
            let detail = c.flatMap { c in
                then.isEmpty ? nil : "\(s.detail) Ferry downloads it once first (\(c.title), about \(DiskUsage.text(Int64(c.approxBytes)))); then turn it on here."
            } ?? s.detail
            stepCard(title: s.title, detail: detail) {
                Button(c != nil && model.installingComponent == c ? "Installing…" : s.button) {
                    if let c { model.installComponentNow(c) }
                }
                .disabled(model.installingComponent != nil || model.setupRunning || model.updating)
            }
        case .library:
            EmptyView()
        case .open(let target):
            stepCard(title: s.title, detail: s.detail) {
                Button(s.button) {
                    switch target {
                    case .desktopAndDock:
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
                    case .battery:
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
                    case .log:
                        model.showLog(g.id, "game")
                    }
                    done.insert(s.id)
                }
                if done.contains(s.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
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
                case .useDX9:
                    Button(g.settings.useDX9 ? "Turned On" : "Use DirectX 9") { model.apply(f.fix, to: g.id); done.insert("log-" + f.id) }
                        .disabled(g.settings.useDX9)
                case .fastSyncOff:
                    Button(g.settings.fastSync ? "Turn Off Fast Sync" : "Turned Off") { model.apply(f.fix, to: g.id); done.insert("log-" + f.id) }
                        .disabled(!g.settings.fastSync)
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
