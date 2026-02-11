import Foundation
import Security

/// Securely stores Instagram session in iOS Keychain
class KeychainService {
    static let shared = KeychainService()
    
    private let sessionKey = "com.mindup.instagram.session"
    
    private init() {}
    
    // MARK: - Save Session
    
    func saveSession(_ session: InstagramSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    // MARK: - Load Session
    
    func loadSession() -> InstagramSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(InstagramSession.self, from: data) else {
            return nil
        }
        
        return session
    }
    
    // MARK: - Delete Session
    
    func deleteSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Generic String Storage (for device IDs that MUST persist across reinstalls)
    
    func saveString(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func loadString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    func deleteString(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
