import Foundation
import Security

/// what a read of the smartthings token gave back
public enum TokenRead: Equatable, Sendable {
    case token(String)
    case absent
    /// the keychain refused (user cancelled, or access not allowed without a prompt)
    case denied
}

/// secrets in the keychain, service arriq: the smartthings token (account smartthings) and the hue bridge key
/// (account hue). never logged, never in settings, never in a file.
/// the keychain can show a prompt that blocks the caller: never call `read`/`load` on the main thread.
public enum TokenStore {
    static let service = "arriq"
    public static let smartThings = "smartthings"
    public static let hue = "hue"

    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// true when a token item exists. reads attributes only and never shows a prompt, so it is safe at launch.
    public static func exists(_ account: String = smartThings) -> Bool {
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        // interaction not allowed: the item exists but needs a prompt to open it
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// reads the secret. may show a keychain prompt; call off the main thread.
    public static func read(_ account: String = smartThings) -> TokenRead {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return .denied }
        return .token(token)
    }

    public static func load(_ account: String = smartThings) -> String? {
        if case .token(let t) = read(account) { return t }
        return nil
    }

    /// nil or empty deletes the token. true when the keychain ends in the requested state.
    @discardableResult
    public static func save(_ token: String?, account: String = smartThings) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        guard let t = token?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return true }
        var add = query(account)
        add[kSecValueData as String] = Data(t.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
