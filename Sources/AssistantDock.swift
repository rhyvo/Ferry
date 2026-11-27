import AppKit
import Combine
import SwiftUI

struct AssistantDock: View {
    @EnvironmentObject var model: AppModel
    let space: CGFloat
    @State private var draft = ""
    @State private var pickedGame: UUID? = nil
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let session = model.assistantSession {
                AssistantDockSession(session: session, space: space, draft: $draft, focused: $focused)
                    .id(session.chatID)
            } else {
                AssistantDockBar(game: $pickedGame, draft: $draft, focused: $focused, unread: false,
                                 submit: { start(sending: true) }, open: { start(sending: false) })
            }
        }
        .onChange(of: model.assistantDockOpen) { _, open in if !open { focused = false } }
    }

    private func start(sending: Bool) {
        model.openAssistant(for: pickedGame)
        guard sending, let session = model.assistantSession, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.send(draft)
        draft = ""
    }
}

private struct AssistantDockSession: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: AssistantChatSession
    let space: CGFloat
    @Binding var draft: String
    let focused: FocusState<Bool>.Binding
    @AppStorage("assistantDockHeight") private var height = 320.0
    @State private var dragStart: CGFloat? = nil
    @State private var liveHeight: CGFloat? = nil
    @State private var cursorPushed = false
    @State private var refresh = 0

    private func clamped(_ h: CGFloat) -> CGFloat { min(space, max(200, min(h, space - 120))) }

    var body: some View {
        if model.assistantDockOpen {
            panel
        } else {
            AssistantDockBar(game: $session.gameID, draft: $draft, focused: focused, unread: session.unread,
                             submit: send, open: { model.assistantDockOpen = true })
        }
    }

    private var panel: some View {
        let _ = refresh
        let chosen = AssistantChatSession.chosen()
        return VStack(spacing: 0) {
            handle
            AssistantHeader(modelName: chosen.name) { model.assistantDockOpen = false }
            Divider()
            AssistantTranscript(session: session)
                .frame(maxHeight: .infinity)
            Divider()
            AssistantInput(session: session, draft: $draft, focused: focused, blocker: chosen.blocker)
        }
        .frame(height: clamped(liveHeight ?? CGFloat(height)))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in refresh += 1 }
    }

    private var handle: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside, !cursorPushed { NSCursor.resizeUpDown.push(); cursorPushed = true }
            else if !inside, cursorPushed { NSCursor.pop(); cursorPushed = false }
        }
        .onDisappear { if cursorPushed { NSCursor.pop(); cursorPushed = false } }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? clamped(liveHeight ?? CGFloat(height))
                    dragStart = start
                    liveHeight = clamped(start - drag.translation.height)
                }
                .onEnded { _ in
                    if let live = liveHeight { height = Double(live) }
                    liveHeight = nil
                    dragStart = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Resize the assistant")
        .accessibilityValue("\(Int(clamped(CGFloat(height)))) points")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = direction == .increment ? 40 : -40
            height = Double(clamped(clamped(CGFloat(height)) + step))
        }
    }

    private func send() {
        if !session.busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.send(draft)
            draft = ""
        }
        model.assistantDockOpen = true
    }
}

private struct AssistantDockBar: View {
    @Binding var game: UUID?
    @Binding var draft: String
    let focused: FocusState<Bool>.Binding
    let unread: Bool
    let submit: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Color.accentColor)
                    .overlay(alignment: .topTrailing) {
                        if unread {
                            Circle().fill(.red).frame(width: 7, height: 7).offset(x: 4, y: -3)
                        }
                    }
                    .help(unread ? "The assistant replied" : "The assistant")
                    .accessibilityLabel(unread ? "Assistant, new reply" : "Assistant")
                AssistantGameMenu(game: $game)
                TextField("Ask the assistant about a game…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused)
                    .onSubmit(submit)
                Button(action: open) {
                    Label("Open the assistant", systemImage: "chevron.up").labelStyle(.iconOnly)
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }
                    .buttonStyle(.borderless)
                    .help("Open the assistant")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
