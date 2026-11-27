import Foundation

func runAssistantCardRowsTests() {
    let g = UUID(), chat = UUID(), other = UUID(), grp = UUID()
    func change(_ chat: UUID, _ key: String, group: UUID? = nil) -> AssistantChange {
        AssistantChange(id: UUID(), game: g, chat: chat, date: Date(), reason: "r", what: .setting(key: key, old: "a", new: "b"), group: group)
    }
    let a = change(chat, "x"), b = change(other, "y"), c1 = change(chat, "z", group: grp), c2 = change(chat, "w", group: grp)
    let rows = [[c2, c1], [b], [a]]
    let fresh = AssistantCardRows.unseen(rows, chat: chat, seen: [])
    check(fresh.count == 2, "only this chat's rows are new")
    check(fresh[0][0].id == a.id && fresh[1].count == 2, "oldest row first, a group as one row")
    check(AssistantCardRows.unseen(rows, chat: chat, seen: [c1.id]).count == 1, "a row with a shown change is not new")
    let before: Set<UUID> = [a.id, b.id]
    let x2 = change(chat, "x"), m1 = change(chat, "m", group: grp), m2 = change(chat, "n", group: grp), y2 = change(chat, "y")
    check(AssistantCardRows.made([a, b, x2], since: before, chat: chat, key: "x").map(\.id) == [x2.id], "the new change for the key")
    check(AssistantCardRows.made([a, b], since: before, chat: chat, key: "x").isEmpty, "nothing changed: not the older change for the key")
    check(AssistantCardRows.made([a, b, m1, m2], since: before, chat: chat, key: "n").map(\.id) == [m1.id, m2.id], "a group, in the order made")
    check(AssistantCardRows.made([a, b, y2, x2], since: before, chat: chat, key: "x").map(\.id) == [x2.id], "another key changed meanwhile isn't this one's")
    check(AssistantCardRows.made([a, b, change(other, "x")], since: before, chat: chat, key: "x").isEmpty, "another chat's change isn't ours")
    check(AssistantCardRows.remaining([x2.id, a.id, y2.id], in: [a, b, y2]) == [a.id, y2.id], "the changes still logged, in order")
    check(AssistantCardRows.remaining([x2.id], in: [a]).isEmpty, "all undone: none left")
    check(AssistantCardRows.reason(reply: String(repeating: "a", count: 300), title: "t").count == 200, "reason cut to 200")
    check(AssistantCardRows.reason(reply: "  ", title: "t") == "t", "empty reply falls back to the title")
}
