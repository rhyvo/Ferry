import Foundation

func runAssistantChangesTests() {
    let url = tempDir().appendingPathComponent("changes.json")
    check(AssistantChangeLog(url: url).changes.isEmpty, "a missing file is an empty log")
    var log = AssistantChangeLog(url: url)
    let g = UUID(), chat = UUID()
    do {
        try log.record(.init(id: UUID(), game: g, chat: chat, date: Date(), reason: "a", what: .setting(key: "maxTessellation", old: "0", new: "16")))
        try log.record(.init(id: UUID(), game: g, chat: chat, date: Date().addingTimeInterval(1), reason: "b", what: .setting(key: "maxTessellation", old: "16", new: "4")))
        try log.record(.init(id: UUID(), game: g, chat: UUID(), date: Date().addingTimeInterval(2), reason: "other chat", what: .arguments(old: "", new: "-x")))
    } catch { check(false, "record threw \(error)") }
    let plan = log.undoPlan(chat: chat)
    check(plan.count == 2, "undo plan holds only that chat's changes")
    if case .setting(_, let old, _) = plan.last!.what { check(old == "0", "oldest change is reverted last") } else { check(false, "expected a setting") }
    if case .setting(_, _, let new) = plan.first!.what { check(new == "4", "newest change is reverted first") } else { check(false, "expected a setting") }
    check(AssistantChangeLog(url: url).changes.count == 3, "log is persisted")
    do {
        try log.remove(plan.map(\.id))
        check(log.changes.count == 1, "remove drops the given changes")
        check(AssistantChangeLog(url: url).changes.count == 1, "remove is persisted")
    } catch { check(false, "remove threw \(error)") }

    let bad = tempDir().appendingPathComponent("changes.json")
    try? Data("not json".utf8).write(to: bad)
    var broken = AssistantChangeLog(url: bad)
    check(broken.changes.isEmpty, "a corrupt file starts an empty log")
    check((try? String(contentsOf: bad.appendingPathExtension("corrupt"), encoding: .utf8)) == "not json", "corrupt file is kept aside")
    do {
        try broken.record(.init(id: UUID(), game: g, chat: chat, date: Date(), reason: "c", what: .environment(old: "a", new: "b")))
        check(AssistantChangeLog(url: bad).changes.count == 1, "record after corruption writes a valid file")
    } catch { check(false, "record after corruption threw \(error)") }
}
