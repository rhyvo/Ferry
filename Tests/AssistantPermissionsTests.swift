import Foundation

func runAssistantPermissionsTests() {
    var p = AssistantPermissions()
    let g = UUID(), t0 = Date()
    p.grant(.read, game: g, now: t0)
    check(p.isAllowed(.read, game: g, now: t0.addingTimeInterval(60)), "grant allows that kind for that game")
    check(!p.isAllowed(.read, game: UUID(), now: t0.addingTimeInterval(60)), "permission is per game")
    check(!p.isAllowed(.change, game: g, now: t0.addingTimeInterval(60)), "permission is per kind")
    check(!p.isAllowed(.read, game: g, now: t0.addingTimeInterval(60 + 31 * 60)), "31 minutes idle clears the grant")
    check(!p.isAllowed(.read, game: g, now: t0.addingTimeInterval(61)), "expiry clears every grant, not just the check")

    var q = AssistantPermissions()
    q.grant(.run, game: g, now: t0)
    check(q.isAllowed(.run, game: g, now: t0.addingTimeInterval(25 * 60)), "a successful check counts as activity")
    check(q.isAllowed(.run, game: g, now: t0.addingTimeInterval(50 * 60)), "activity keeps the grant alive")
    q.touch(now: t0.addingTimeInterval(60 * 60))
    check(q.isAllowed(.run, game: g, now: t0.addingTimeInterval(85 * 60)), "touch counts as activity")
}
