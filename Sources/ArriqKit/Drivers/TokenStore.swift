import Foundation
import Security

/// what a read of the smartthings token gave back
public enum TokenRead: Equatable, Sendable {
    case token(String)
    case absent
    /// the keychain refused (user cancelled, or access not allowed without a prompt)
    case denied
}

/// smartthings token in the keychain (service arriq, account smartthings). never logged, never in settings.
/// the keychain can show a prompt that blocks the caller: never call this on the main thread.
public enum TokenStore {
    static let service = "arriq"
    static let account = "smartthings"

    static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// true when a token item exists. reads attributes only and never shows a prompt, so it is safe at launch.
    public static func exists() -> Bool {
        var q = query()
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        // interaction not allowed: the item exists but needs a prompt to open it
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// reads the secret. may show a keychain prompt; call off the main thread.
    public static func read() -> TokenRead {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return .denied }
        return .token(token)
    }

    public static func load() -> String? {
        if case .token(let t) = read() { return t }
        return nil
    }

    /// nil or empty deletes the token. true when the keychain ends in the requested state.
    @discardableResult
    public static func save(_ token: String?) -> Bool {
        SecItemDelete(query() as CFDictionary)
        guard let t = token?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return true }
        var add = query()
        add[kSecValueData as String] = Data(t.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
