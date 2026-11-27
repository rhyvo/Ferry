import AppKit
import SwiftUI

struct AISettingsView: View {
    static let mcpEnabledKey = "assistantMCPEnabled"
    static let claudeCodeSetup = "claude mcp add ferry -- /Applications/Ferry.app/Contents/MacOS/ferry-mcp"
    static let claudeDesktopSetup = #"{"mcpServers":{"ferry":{"command":"/Applications/Ferry.app/Contents/MacOS/ferry-mcp"}}}"#

    @EnvironmentObject var model: AppModel
    static let claudeCodeFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    static let claudeDesktopFile = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")

    @AppStorage(AISettingsView.mcpEnabledKey) private var enabled = false
    @State private var setupMessage: String?
    @State private var refresh = 0

    @State private var choice = AssistantModelChoice.load(.standard)
    @State private var keyText = ""
    @State private var keyVersion = 0
    @State private var listed: [String] = []
    @State private var listError: String?
    @State private var loading = false
    @State private var keyMessage: String?
    @State private var loadedBase = AssistantModelChoice.load(.standard).base

    @State private var servers = MCPServerConfig.load(.standard)
    @State private var addingServer = false
    @State private var testResults: [UUID: String] = [:]

    private var appleReason: String? { AppleAssistant.unavailableReason }
    private func hasKey(_ p: AssistantProvider) -> Bool { AssistantChatSession.hasKey(p) }

    var body: some View {
        Form {
            assistantSection
            mcpSection
            Section {
                Toggle("Use Ferry from other AI apps", isOn: $enabled)
                    .info("Lets AI apps on this Mac, like Claude Code or Claude Desktop, use Ferry: read a game's logs and settings, change them, and start and test it. Ferry asks you the first time each kind of action is used in a chat, and every time before downloading, deleting, touching save files or anything outside the game's folders. While it's on, any program on this Mac can connect to Ferry.")
            } header: {
                Text("AI Apps")
            }
            Section {
                setupLine("Claude Code", Self.claudeCodeSetup, file: Self.claudeCodeFile, app: nil)
                setupLine("Claude Desktop", Self.claudeDesktopSetup, file: Self.claudeDesktopFile, app: Self.claudeDesktopFile.deletingLastPathComponent())
                if let setupMessage {
                    Text(setupMessage).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("Add puts Ferry in that app's settings for you (Claude Code here also means the Code tab of the Claude app). Or copy the line: for Claude Code, run it in Terminal; for Claude Desktop, add it to its config file (Settings ▸ Developer ▸ Edit Config). Other AI apps: give them the ferry-mcp command.")
            }
            Section("Connected AI Apps") {
                let chats = model.assistantChats.values.sorted { ($0.client, $0.id.uuidString) < ($1.client, $1.id.uuidString) }
                if chats.isEmpty {
                    Text("None right now").foregroundStyle(.secondary)
                }
                ForEach(chats, id: \.id) { chat in
                    HStack {
                        Text(chat.client.isEmpty ? "Unnamed app" : chat.client)
                        Spacer()
                        Button("Disconnect") { model.endAssistantChat(chat.id) }
                            .help("Ends this chat: Ferry forgets what you allowed in it and withdraws its questions.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct LoadID: Equatable { var provider: AssistantProvider; var base: String; var keyVersion: Int }

    private var providerTitles: [AssistantProvider: String] {
        let _ = keyVersion
        return Dictionary(uniqueKeysWithValues: AssistantProvider.allCases.map { p in
            let needs = AssistantModels.needs(p, hasKey: hasKey(p), appleReason: appleReason)
            return (p, needs.map { "\(p.title) (\($0))" } ?? p.title)
        })
    }

    private var assistantSection: some View {
        let _ = keyVersion
        let p = choice.provider
        let titles = providerTitles
        return Section {
            Picker("Assistant", selection: Binding(get: { choice.provider }, set: { choose($0) })) {
                ForEach(AssistantProvider.allCases, id: \.self) { prov in
                    Text(titles[prov] ?? prov.title).tag(prov)
                        .disabled(prov == .apple && appleReason != nil)
                }
            }
            .info("The AI that answers in the assistant at the bottom of Ferry's window. Apple's runs on this Mac and sends nothing out. The others send your questions, and what Ferry reads of the game to answer them, to that service, using your own key.")
            if let why = AssistantModels.needs(p, hasKey: hasKey(p), appleReason: appleReason) {
                Text(why).font(.callout).foregroundStyle(.secondary)
            }
            if p != .apple {
                LabeledContent("API key") {
                    HStack {
                        SecureField("API key", text: $keyText).labelsHidden()
                        Button("Save") { saveKey() }.disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove") { removeKey() }.disabled(!hasKey(p))
                    }
                }
                Text(hasKey(p) ? "A key is saved. " + AssistantModels.billingNote(p) : AssistantModels.billingNote(p))
                    .font(.callout).foregroundStyle(.secondary)
                if let keyMessage { Text(keyMessage).font(.callout).foregroundStyle(.secondary) }
                if p == .other {
                    TextField("Address", text: $choice.base, prompt: Text("https://example.com/v1"))
                        .onSubmit { commitBase() }
                        .onChange(of: choice.base) { _, _ in commitBase() }
                        .onDisappear { commitBase() }
                    if !choice.base.trimmingCharacters(in: .whitespaces).isEmpty,
                       case .refused(let why) = AssistantModels.baseURL(choice.base) {
                        Text(why).font(.callout).foregroundStyle(.secondary)
                    }
                }
                modelRow
            }
        } header: {
            Text("Assistant")
        } footer: {
            Text("A change applies to the next message you send, not one already running.")
        }
        .task(id: LoadID(provider: p, base: loadedBase, keyVersion: keyVersion)) { await loadModels() }
    }

    static let mcpNeedsKeyModel = "Needs a Claude, ChatGPT, Gemini or other model: Apple's model doesn't use actions."

    private var mcpSection: some View {
        let apple = choice.provider == .apple
        return Section {
            if apple {
                Text(Self.mcpNeedsKeyModel).font(.callout).foregroundStyle(.secondary)
            }
            Group {
                if servers.isEmpty {
                    Text("None added").foregroundStyle(.secondary)
                }
                ForEach($servers) { $server in
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(isOn: Binding(get: { server.enabled }, set: { server.enabled = $0; saveServers() })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                Text(([server.command] + [MCPServerConfig.joinArguments(server.arguments)]).filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                                if let result = testResults[server.id] {
                                    Text(result).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Test") { test(server) }.disabled(testResults[server.id] == "Testing…")
                        Button("Remove") {
                            let id = server.id
                            servers.removeAll { $0.id == id }
                            testResults[id] = nil
                            saveServers()
                        }
                    }
                }
                Button("Add Server…") { addingServer = true }
            }
            .disabled(apple)
        } header: {
            Text("MCP Servers")
        } footer: {
            Text("Programs that give the assistant more tools, like reading files or searching the web. Ferry starts the ones that are on when a chat begins, and asks you before the assistant first uses each one's tools in a chat. Add only programs you trust: they run on this Mac with your permissions.")
        }
        .sheet(isPresented: $addingServer) {
            MCPServerAddSheet { servers.append($0); saveServers() }
        }
    }

    private func saveServers() { MCPServerConfig.save(servers, .standard) }

    private func test(_ server: MCPServerConfig) {
        testResults[server.id] = "Testing…"
        Task {
            let client = MCPClient(config: server)
            let text: String
            do {
                let tools = try await client.start()
                text = tools.count == 1 ? "1 tool" : "\(tools.count) tools"
            } catch {
                text = "Didn't start: " + ((error as? MCPClientError)?.message ?? error.localizedDescription)
            }
            client.stop()
            if servers.contains(where: { $0.id == server.id }) { testResults[server.id] = text }
        }
    }

    @ViewBuilder private var modelRow: some View {
        if listed.isEmpty {
            TextField("Model", text: Binding(get: { choice.model }, set: { choice.model = $0; choice.save(.standard) }),
                      prompt: Text(loading ? "Loading…" : "Model name"))
        } else {
            Picker("Model", selection: Binding(get: { choice.model }, set: { choice.model = $0; choice.save(.standard) })) {
                if !listed.contains(choice.model) { Text("Choose…").tag(choice.model) }
                ForEach(listed, id: \.self) { Text($0).tag($0) }
            }
        }
        if let listError { Text("Couldn't load the models: \(listError)").font(.callout).foregroundStyle(.secondary) }
    }

    private func choose(_ p: AssistantProvider) {
        UserDefaults.standard.set(p.rawValue, forKey: "assistantProvider")
        let base = choice.base
        choice = AssistantModelChoice.load(.standard)
        if choice.base.isEmpty { choice.base = base }
        loadedBase = choice.base
        keyText = ""
        keyMessage = nil
        listed = []
        listError = nil
    }

    private func commitBase() {
        guard choice.provider == .other, case .ok = AssistantModels.baseURL(choice.base) else { return }
        choice.save(.standard)
        loadedBase = choice.base
    }

    private func saveKey() {
        let p = choice.provider
        do {
            try Keychain.write(keyText, account: p.rawValue)
            keyMessage = nil
        } catch {
            keyMessage = "Couldn't save the key in your Keychain."
        }
        keyText = ""
        keyVersion += 1
    }

    private func removeKey() {
        Keychain.delete(choice.provider.rawValue)
        keyMessage = nil
        listed = []
        listError = nil
        keyVersion += 1
    }

    private func loadModels() async {
        let p = choice.provider
        listError = nil
        guard let wire = p.wire else { listed = []; return }
        let base: URL
        if let d = p.defaultBase { base = d } else if case .ok(let url) = AssistantModels.baseURL(loadedBase) { base = url } else { listed = []; return }
        if p.needsKey, !hasKey(p) { listed = []; return }
        var key = ""
        if hasKey(p) {
            switch Keychain.read(p.rawValue) {
            case .found(let k): key = k
            case .missing: if p.needsKey { listed = []; return }
            case .unreadable: listed = []; listError = nil; keyMessage = KeyRead.unreadableNote; return
            }
        }
        loading = true
        defer { loading = false }
        let request = wire.modelsRequest(base: base, key: key)
        do {
            let (data, status) = try await URLSession.shared.send(request)
            guard p == choice.provider else { return }
            guard (200...299).contains(status) else {
                listed = []
                listError = ChatWireError.message(status: status, body: data, provider: p == .other ? "The service" : p.title, key: key)
                return
            }
            let ids = Array(Set(wire.parseModels(data))).sorted()
            guard !ids.isEmpty else {
                listed = []
                listError = "\(p == .other ? "The service" : p.title) sent a list Ferry couldn't read. Type the model's name."
                return
            }
            listed = ids
            let picked = AssistantModels.pick(listed: ids, remembered: choice.model, suggested: model.suggestedModel(p))
            choice.model = picked ?? ""
            choice.save(.standard)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            listed = []
            listError = (error as? URLError)?.code == .timedOut ? "it took too long to answer. Type the model's name."
                : "Ferry couldn't reach it. Check the internet connection, then type the model's name."
        }
    }

    private func setupLine(_ title: String, _ line: String, file: URL, app: URL?) -> some View {
        let _ = refresh
        let added = AssistantSetup.isAdded(try? Data(contentsOf: file))
        let installed = app.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
        let needs = !enabled ? "Turn on Use Ferry from other AI apps first." : installed ? nil : "\(title) isn't installed."
        return LabeledContent {
            HStack {
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(enabled ? .primary : .tertiary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line, forType: .string)
                }
                Button(added ? "Added" : "Add") { add(title, to: file) }
                    .disabled(added || !installed)
            }
        } label: {
            settingLabel(title, needs: needs)
        }
        .disabled(!enabled)
    }

    private func add(_ title: String, to file: URL) {
        do {
            let data = try AssistantSetup.adding(to: try? Data(contentsOf: file), file: file.lastPathComponent)
            let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions]
            try data.write(to: file, options: .atomic)
            if let mode { try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path) }
            setupMessage = title == "Claude Desktop" ? "Added. Quit and reopen Claude Desktop to use Ferry there."
                : "Added. Start a new chat in Claude Code to use Ferry there."
        } catch {
            setupMessage = error.localizedDescription
        }
        refresh += 1
    }
}

private struct MCPServerAddSheet: View {
    let add: (MCPServerConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""
    @State private var arguments = ""

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an MCP Server").font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text("Files"))
                TextField("Command", text: $command, prompt: Text("npx"))
                TextField("Arguments", text: $arguments, prompt: Text("-y @modelcontextprotocol/server-filesystem ~/Documents"))
            }
            Text("The command and arguments that start the server, as its instructions give them for other AI apps. Quote an argument that has spaces in it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    add(MCPServerConfig(id: UUID(), name: trimmed(name), command: trimmed(command),
                                        arguments: MCPServerConfig.splitArguments(arguments), enabled: true))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty || trimmed(command).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
