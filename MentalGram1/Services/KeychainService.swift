import Foundation
import Security

/// Securely stores Instagram session in iOS Keychain.
///
/// Storage policy:
/// All items are saved with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
/// This means:
///   • Items are accessible after the first device unlock (survives app relaunches).
///   • Items are NOT included in iCloud or iTunes backups.
///   • Items are NOT restored on a new device or after a restore.
///
/// This is critical for `deviceId` / `clientUUID`: if those were restored from a
/// backup, the new install would re-use the previous device fingerprint and inherit
/// any server-side flags Instagram had attached to it — putting the user straight
/// back into the "validateSession 200 but logged-out" loop. With ThisDeviceOnly,
/// reinstalling or restoring the iPhone produces a fresh fingerprint automatically.
class KeychainService {
    static let shared = KeychainService()
    
    private let sessionKey = "com.mindup.instagram.session"
    private let credentialsUsernameKey = "com.mentalgram.instagram.cred.username"
    private let credentialsPasswordKey = "com.mentalgram.instagram.cred.password"
    private let deviceIdKey = "com.mindup.instagram.deviceId"
    private let clientUUIDKey = "com.mindup.instagram.clientUUID"

    /// Accessibility flag used by every Keychain item we own.
    /// Local-only: not synced via iCloud Keychain, not included in backups.
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private init() {
        migrateLegacyItemsToThisDeviceIfNeeded()
    }

    // MARK: - Save Session
    
    func saveSession(_ session: InstagramSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        saveData(data, forKey: sessionKey)
    }
    
    // MARK: - Load Session
    
    func loadSession() -> InstagramSession? {
        guard let data = loadData(forKey: sessionKey),
              let session = try? JSONDecoder().decode(InstagramSession.self, from: data) else {
            return nil
        }
        return session
    }
    
    // MARK: - Delete Session
    
    func deleteSession() {
        deleteItem(forKey: sessionKey)
    }
    
    // MARK: - Instagram Credentials (for auto-fill re-login)

    /// Saves username and password in Keychain (AES-256, app-only access).
    func saveCredentials(username: String, password: String) {
        saveString(username, forKey: credentialsUsernameKey)
        saveString(password, forKey: credentialsPasswordKey)
        print("🔑 [KEYCHAIN] Credentials saved for @\(username)")
    }

    /// Returns stored (username, password) or nil if not saved.
    func loadCredentials() -> (username: String, password: String)? {
        guard let username = loadString(forKey: credentialsUsernameKey),
              let password = loadString(forKey: credentialsPasswordKey),
              !username.isEmpty, !password.isEmpty else { return nil }
        return (username, password)
    }

    /// Clears saved credentials (call on logout or account change).
    func clearCredentials() {
        deleteString(forKey: credentialsUsernameKey)
        deleteString(forKey: credentialsPasswordKey)
        print("🔑 [KEYCHAIN] Credentials cleared")
    }

    // MARK: - Generic String Storage
    
    func saveString(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(data, forKey: key)
    }
    
    func loadString(forKey key: String) -> String? {
        guard let data = loadData(forKey: key),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    func deleteString(forKey key: String) {
        deleteItem(forKey: key)
    }

    // MARK: - Generic Data Storage (shared by every accessor above)

    private func saveData(_ data: Data, forKey key: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? (result as? Data) : nil
    }

    private func deleteItem(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - One-time migration to ThisDeviceOnly accessibility

    /// Re-saves any pre-existing Keychain item that may have been created with
    /// the old `kSecAttrAccessibleAfterFirstUnlock` flag (backup-able). After
    /// running, every item is stored with `…ThisDeviceOnly`, so a future
    /// reinstall or iPhone restore will start fresh.
    private func migrateLegacyItemsToThisDeviceIfNeeded() {
        let migrationFlag = "com.mentalgram.keychain.thisdeviceonly_v1"
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }

        let keysToMigrate = [
            sessionKey,
            credentialsUsernameKey,
            credentialsPasswordKey,
            deviceIdKey,
            clientUUIDKey
        ]

        var migrated = 0
        for key in keysToMigrate {
            guard let data = loadData(forKey: key) else { continue }
            deleteItem(forKey: key)
            saveData(data, forKey: key)
            migrated += 1
        }

        UserDefaults.standard.set(true, forKey: migrationFlag)
        print("🔐 [KEYCHAIN] Migrated \(migrated) item(s) to ThisDeviceOnly accessibility")
    }
}
