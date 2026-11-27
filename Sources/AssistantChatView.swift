import AppKit
import SwiftUI

struct AssistantGameMenu: View {
    @EnvironmentObject var model: AppModel
    @Binding var game: UUID?

    var body: some View {
        Picker("Game", selection: Binding(
            get: { game.flatMap { id in model.game(id).map { $0.id } } },
            set: { game = $0 }
        )) {
            Text("No game").tag(UUID?.none)
            Divider()
            ForEach(model.games) { g in Text(g.name).tag(UUID?.some(g.id)) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 200)
        .help("The game this chat is about")
    }
}

struct AssistantHeader: View {
    @EnvironmentObject var model: AppModel
    let modelName: String
    let collapse: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text("Assistant").font(.headline)
            } icon: {
                Image(systemName: "sparkle").foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text(modelName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Change the model in Settings ▸ AI")
            Button("New Chat") { model.newAssistantChat() }
                .help("Ends this chat and starts a new one: the assistant asks again before reading or changing anything")
            Button(action: collapse) {
                Label("Collapse", systemImage: "chevron.down").labelStyle(.iconOnly)
                    .frame(width: 28, height: 24).contentShape(Rectangle())
            }
                .buttonStyle(.borderless)
                .help("Shrink the assistant to one line; the chat stays")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct AssistantTranscript: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: AssistantChatSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.items.isEmpty {
                        Text(session.gameID.flatMap { model.game($0) }.map { "Ask about \($0.name): why it won't start, how to make it run better, what a setting does." }
                             ?? "Ask about a game in your library, or choose one below.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }
                    ForEach(session.items) { item in
                        row(item).id(item.id)
                    }
                    if session.busy {
                        ProgressView().controlSize(.small).id("busy")
                    }
                }
                .padding(16)
            }
            .onChange(of: session.items.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { scrollToEnd(proxy) }
            }
            .onAppear { DispatchQueue.main.async { scrollToEnd(proxy) } }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if session.busy { proxy.scrollTo("busy", anchor: .bottom) } else if let last = session.items.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item {
        case .person(_, let text):
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
        case .assistant(_, let text):
            AssistantReply(text: text)
        case .activity(_, let text):
            Label(text, systemImage: "gearshape")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .note(_, let text):
            Label(text, systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .card(let id, let card):
            cardView(id, card)
        }
    }

    private func cardView(_ id: UUID, _ card: AssistantCard) -> some View {
        var failure: String? = nil
        if case .failed(let why) = card.state { failure = why }
        return VStack(alignment: .leading, spacing: 6) {
            Label(card.title, systemImage: "slider.horizontal.3")
                .font(.callout.weight(.semibold))
            Text(card.detail.isEmpty ? card.reason : card.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(card.detail.isEmpty ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if case .fix(let step) = card.kind {
                    fixButtons(id, card, step)
                } else {
                    changeButtons(id, card)
                }
                if card.startResult == "" {
                    Text("Started").font(.caption).foregroundStyle(.secondary)
                } else if let why = card.startResult {
                    Text(why).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func changeButtons(_ id: UUID, _ card: AssistantCard) -> some View {
        let canUndo: Bool = { if case .changes(let ids) = card.kind { return !ids.isEmpty } else { return true } }()
        switch card.state {
        case .ready:
            EmptyView()
        case .failed:
            if canUndo { Button("Undo") { session.undo(id) }.disabled(card.working) }
        case .done:
            if canUndo { Button("Undo") { session.undo(id) }.disabled(card.working) }
            if card.startResult != "", let g = model.game(card.game) {
                Button("Start \(g.name)") { session.start(id) }.disabled(card.working)
            }
        case .undone:
            Text("Undone").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fixButtons(_ id: UUID, _ card: AssistantCard, _ step: FixStep) -> some View {
        let done: Bool = { if case .done = card.state { return true } else { return false } }()
        switch step.action {
        case .settings:
            Button(step.button) { session.apply(id) }.disabled(card.working)
        case .picker(let key, let choices):
            let current = model.game(card.game).flatMap { g in SettingsCatalog.entry(key)?.get(g.settings).text } ?? ""
            let label = choices.first { $0.value == current }?.label.replacingOccurrences(of: " (lowest)", with: "")
                ?? (key == "maxTessellation" ? current : choices.first?.label ?? "")
            Menu(label) {
                ForEach(choices, id: \.value) { choice in
                    Button(choice.label) { session.apply(id, value: choice.value) }
                    if choice == choices.first { Divider() }
                }
            }
            .fixedSize()
            .disabled(card.working)
        case .install(let component, let then):
            let c = Component(rawValue: component)
            if let c, model.componentStatus[c]?.installed == true {
                if then.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Installed").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(step.afterInstall) { session.apply(id) }.disabled(card.working)
                }
            } else {
                Button(c != nil && model.installingComponent == c ? "Installing…" : step.button) { session.install(id) }
                    .disabled(model.installingComponent != nil || model.setupRunning || model.updating)
            }
        case .library:
            if !done {
                Button(step.button) { session.install(id) }
            } else if model.preparing.contains(card.game) {
                Text("Reinstalling…").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .open:
            Button(step.button) { session.openFix(id) }
            if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        case .note:
            EmptyView()
        }
    }
}

private struct AssistantReply: View {
    let text: String
    @State private var hovering = false
    @FocusState private var copyFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ChatMarkdownView(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { ChatMarkdownView.copy(text) } label: { Label("Copy Reply", systemImage: "doc.on.doc") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy Reply")
                .focused($copyFocused)
                .opacity(hovering || copyFocused ? 1 : 0.35)
        }
        .onHover { hovering = $0 }
    }
}

struct AssistantInput: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: AssistantChatSession
    @Binding var draft: String
    let focused: FocusState<Bool>.Binding
    let blocker: String?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            AssistantGameMenu(game: $session.gameID)
            if let blocker {
                Text(blocker)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open Settings ▸ AI") {
                    UserDefaults.standard.set("ai", forKey: SettingsView.tabKey)
                    openSettings()
                }
            } else {
                TextField("Ask the assistant…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused)
                    .onSubmit(send)
                    .task {
                        try? await Task.sleep(for: .milliseconds(250))
                        focused.wrappedValue = true
                    }
                if !session.busy {
                    Button(action: send) { Label("Send", systemImage: "arrow.up.circle.fill") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send (Return)")
                }
            }
            if session.busy {
                Button { session.stop() } label: { Label("Stop", systemImage: "stop.circle.fill") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .keyboardShortcut(".", modifiers: [.command])
                    .help("Stop the reply (⌘.)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        guard !session.busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.send(draft)
        draft = ""
    }
}

struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ChatMarkdown.blocks(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
        .contextMenu {
            Button("Copy Reply") { Self.copy(text) }
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private func view(_ block: ChatMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let t):
            inline(t).font(level <= 2 ? .title3 : .headline).bold()
        case .paragraph(let t):
            inline(t)
        case .bullet(let t, let depth):
            item("•", t, depth)
        case .numbered(let n, let t, let depth):
            item("\(n).", t, depth)
        case .rule:
            Divider()
        case .code(let c):
            Text(c)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func item(_ marker: String, _ t: String, _ depth: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
            inline(t)
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    private func inline(_ t: String) -> Text {
        let math = ChatMarkdown.plainMath(t)
        return Text((try? AttributedString(markdown: math, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(math))
    }
}
