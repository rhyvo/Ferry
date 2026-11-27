import Foundation

func runAssistantWireTests() {
    let encoded = AssistantWire.encode(["op": "hello", "client": "Claude Code"])
    check(encoded.last == 10 && encoded.dropLast().firstIndex(of: 10) == nil, "encode ends with one newline")

    var buffer = AssistantWire.encode(["op": "tools"]) + AssistantWire.encode(["op": "call", "id": 7]) + Data(#"{"op":"ca"#.utf8)
    let two = AssistantWire.decodeLines(&buffer)
    check(two.count == 2 && two[0]["op"] as? String == "tools" && two[1]["id"] as? Int == 7, "two whole lines come back")
    check(buffer == Data(#"{"op":"ca"#.utf8), "the half line stays in the buffer")
    buffer.append(Data(#"ll","id":8}"#.utf8 + [10]))
    let third = AssistantWire.decodeLines(&buffer)
    check(third.count == 1 && third[0]["id"] as? Int == 8 && buffer.isEmpty, "the rest of it completes the line")

    var junk = Data("\n  \n{nope\n[1,2]\n".utf8)
    let bad = AssistantWire.decodeLines(&junk)
    check(bad.count == 2 && bad.allSatisfy(\.isEmpty) && junk.isEmpty, "blank lines skipped; unreadable lines come back empty")

    var huge = Data(#"{"op":"call","args":{"text":""#.utf8) + Data(repeating: 65, count: AssistantWire.maxLine)
    let dropped = AssistantWire.decodeLines(&huge)
    check(dropped.count == 1 && dropped[0].isEmpty && huge.isEmpty, "a line over 8 MB is dropped and the buffer reset")
    var under = Data(repeating: 32, count: AssistantWire.maxLine - 10)
    check(AssistantWire.decodeLines(&under).isEmpty && under.count == AssistantWire.maxLine - 10, "a long partial line under the cap waits")
}
