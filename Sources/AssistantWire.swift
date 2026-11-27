import Foundation

enum AssistantWire {
    static let maxLine = 8 << 20

    static func encode(_ obj: [String: Any]) -> Data {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else {
            return Data("{}\n".utf8)
        }
        return data + [10]
    }

    static func decodeLines(_ buffer: inout Data) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var start = buffer.startIndex
        while let end = buffer[start...].firstIndex(of: 10) {
            let line = buffer[start..<end]
            start = end + 1
            if line.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 13 }) { continue }
            let obj = line.count <= maxLine ? (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] : nil
            out.append(obj ?? [:])
        }
        buffer.removeSubrange(buffer.startIndex..<start)
        if buffer.count > maxLine {
            buffer = Data()
            out.append([:])
        }
        return out
    }
}
