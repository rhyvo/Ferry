import Foundation
import Security

enum KeyRead: Equatable {
    case found(String), missing, unreadable

    static let unreadableNote = "Ferry couldn't read the API key from your Keychain. Allow Ferry when the Mac asks, or save the key again in Settings ▸ AI."
}

enum Keychain {
    struct Failure: Error { let status: OSStatus }

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    private static func cached(_ account: String) -> String? { lock.withLock { cache[account] } }
    private static func remember(_ value: String?, _ account: String) { lock.withLock { cache[account] = value } }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Ferry AI", kSecAttrAccount as String: account]
    }

    static func hasKey(_ account: String) -> Bool {
        if cached(account) != nil { return true }
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    static func read(_ account: String) -> KeyRead {
        if let v = cached(account) { return .found(v) }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        let r = classify(status, out as? Data)
        if case .found(let v) = r { remember(v, account) }
        return r
    }

    static func classify(_ status: OSStatus, _ data: Data?) -> KeyRead {
        switch status {
        case errSecSuccess:
            guard let data, let s = String(data: data, encoding: .utf8),
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .missing }
            return .found(s)
        case errSecItemNotFound:
            return .missing
        default:
            return .unreadable
        }
    }

    static func write(_ value: String, account: String) throws {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { delete(account); return }
        let data = Data(v.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { remember(v, account); return }
        if status != errSecItemNotFound { SecItemDelete(query(account) as CFDictionary) }
        var add = query(account)
        add[kSecValueData as String] = data
        let added = SecItemAdd(add as CFDictionary, nil)
        if added != errSecSuccess { throw Failure(status: added) }
        remember(v, account)
    }

    static func delete(_ account: String) {
        remember(nil, account)
        SecItemDelete(query(account) as CFDictionary)
    }
}
