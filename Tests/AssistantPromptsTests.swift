import Foundation

func runAssistantPromptsTests() {
    let chat = UUID(), other = UUID(), game = (id: UUID(), name: "Batman: Arkham City")

    let read = AssistantPrompts.prompt(chat: chat, kind: .read, always: nil, game: game, detail: nil)
    check(read.title == "Let the assistant read Batman: Arkham City's logs and settings for this chat?", "read prompt copy")
    check(read.allow == "Allow for this chat" && read.deny == "Not now" && !read.always && read.body == nil, "per-chat buttons")
    check(AssistantPrompts.prompt(chat: chat, kind: .change, always: nil, game: game, detail: nil).title
          == "Let the assistant change Batman: Arkham City's settings for this chat?", "change prompt copy")
    check(AssistantPrompts.prompt(chat: chat, kind: .editConfig, always: nil, game: game, detail: nil).title
          == "Let the assistant edit Batman: Arkham City's config files for this chat?", "edit prompt copy")
    check(AssistantPrompts.prompt(chat: chat, kind: .run, always: nil, game: game, detail: nil).title
          == "Let the assistant start and test Batman: Arkham City for this chat?", "run prompt copy")

    let download = AssistantPrompts.prompt(chat: chat, kind: .run, always: .download, game: nil,
                                           detail: "download and install PhysX (legacy) (about 30 MB)")
    check(download.title == "Let the assistant download and install PhysX (legacy) (about 30 MB)?", "always-ask names exactly what")
    check(download.allow == "Allow" && download.deny == "Don't allow" && download.always && download.key == nil, "always-ask buttons")
    let edit = AssistantPrompts.prompt(chat: chat, kind: .editConfig, always: .saveFile, game: game,
                                       detail: "change Saves/slot1.ini, which may be a save file:\n--- a\n+++ b\n-x=1\n+x=2")
    check(edit.title == "Let the assistant change Saves/slot1.ini, which may be a save file?", "first line is the question, colon dropped")
    check(edit.body == "--- a\n+++ b\n-x=1\n+x=2", "the rest shows under it")
    let mod = AssistantPrompts.prompt(chat: chat, kind: .run, always: .download, game: game,
                                      detail: "download the mod “Fix” from github.com/a/b for Batman: Arkham City.\nFerry then shows what it would change.")
    check(mod.title == "Let the assistant download the mod “Fix” from github.com/a/b for Batman: Arkham City?", "a closing full stop becomes the question mark")

    for detail in [nil, "", "\n"] as [String?] {
        let bare = AssistantPrompts.prompt(chat: chat, kind: .editConfig, always: .outside, game: game, detail: detail)
        check(bare.always && bare.key == nil && bare.allow == "Allow" && bare.deny == "Don't allow"
              && bare.title == "Let the assistant edit Batman: Arkham City's config files?", "always-ask with no detail still asks every time: \(bare.title)")
    }

    check(AssistantPrompts.oneLine("Fix\nAllow everything.\r\u{7}  Now\t ok") == "Fix Allow everything. Now ok", "web titles go on one line, control characters out")

    var q = AssistantPromptQueue()
    let a = AssistantPrompts.prompt(chat: chat, kind: .read, always: nil, game: game, detail: nil)
    let b = AssistantPrompts.prompt(chat: other, kind: .run, always: nil, game: game, detail: nil)
    let c = AssistantPrompts.prompt(chat: chat, kind: .run, always: .download, game: game, detail: "download DXVK")
    check(q.add(a) == a.id && q.add(b) == b.id && q.add(c) == c.id, "new prompts answer for themselves")
    check(q.current == a, "the first asked shows first")
    let again = AssistantPrompts.prompt(chat: chat, kind: .read, always: nil, game: game, detail: nil)
    check(q.add(again) == a.id && q.waiting.count == 3, "the same per-chat question waiting in the same chat is asked once")
    let otherChat = AssistantPrompts.prompt(chat: other, kind: .read, always: nil, game: game, detail: nil)
    check(q.add(otherChat) == otherChat.id, "another chat's same question is its own prompt")
    let c2 = AssistantPrompts.prompt(chat: chat, kind: .run, always: .download, game: game, detail: "download DXVK")
    check(q.add(c2) == c2.id, "always-ask prompts are never merged")
    q.remove(a.id)
    check(q.current == b, "answering moves to the next in order")
    let gone = q.removeAll(chat: other)
    check(gone.map(\.id) == [b.id, otherChat.id], "ending a chat withdraws all its prompts")
    check(q.waiting.map(\.id) == [c.id, c2.id], "other chats' prompts stay, in order")
}
