import AppKit
import SwiftUI
import UserNotifications

struct AssistantPromptView: View {
    let prompt: AssistantPrompt
    let answer: (Bool) -> Void
    @State private var ready = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                Text(prompt.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let body = prompt.body {
                ScrollView {
                    Text(body)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 280)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Spacer()
                Button(prompt.deny) { answer(false) }
                    .keyboardShortcut(.cancelAction)
                Button(prompt.allow) { answer(true) }
            }
            .disabled(!ready)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            ready = true
        }
        .padding(20)
        .frame(width: 460)
        .ferryTheme()
    }
}

@MainActor
final class AssistantPrompter: NSObject, UNUserNotificationCenterDelegate {
    private var queue = AssistantPromptQueue()
    private var waiting: [UUID: [CheckedContinuation<Bool, Never>]] = [:]
    private var shown: (id: UUID, panel: NSPanel)?

    func ask(_ p: AssistantPrompt) async -> Bool {
        await withCheckedContinuation { c in
            let id = queue.add(p)
            waiting[id, default: []].append(c)
            showNext()
        }
    }

    func cancel(chat: UUID) {
        for p in queue.removeAll(chat: chat) {
            if shown?.id == p.id { close() }
            finish(p.id, false)
        }
        showNext()
    }

    private func answer(_ id: UUID, _ yes: Bool) {
        guard shown?.id == id else { return }
        queue.remove(id)
        close()
        finish(id, yes)
        showNext()
    }

    private func finish(_ id: UUID, _ yes: Bool) {
        for c in waiting.removeValue(forKey: id) ?? [] { c.resume(returning: yes) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    private func showNext() {
        guard shown == nil, let p = queue.current else { return }
        let host = NSHostingController(rootView: AssistantPromptView(prompt: p) { [weak self] yes in self?.answer(p.id, yes) })
        host.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled]
        panel.title = "Ferry"
        shown = (p.id, panel)
        if let main = mainWindow {
            var parent = main
            while let sheet = parent.attachedSheet { parent = sheet }
            if NSApp.isActive {
                if main.isMiniaturized { main.deminiaturize(nil) }
                main.makeKeyAndOrderFront(nil)
            }
            parent.beginSheet(panel)
        } else {
            panel.hidesOnDeactivate = false
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
        if !NSApp.isActive { Task { await notify(p) } }
    }

    private func close() {
        guard let panel = shown?.panel else { return }
        shown = nil
        if let parent = panel.sheetParent { parent.endSheet(panel) } else { panel.orderOut(nil) }
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { w in
            let id = w.identifier?.rawValue ?? ""
            return (id == "main" || id.hasPrefix("main-")) && (w.isVisible || w.isMiniaturized)
        }
    }

    private func notify(_ p: AssistantPrompt) async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard shown?.id == p.id else { return }
        guard status == .authorized || status == .provisional else {
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Ferry: the assistant is asking"
        content.body = p.title
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: p.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NSApp.activate()
            guard let panel = shown?.panel else { return }
            guard let window = panel.sheetParent == nil ? panel : mainWindow else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
