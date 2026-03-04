import Foundation
import Combine

// MARK: - CloudBackupService
// Persists all app settings to iCloud KV Store so they survive uninstall/reinstall.
// Uses NSUbiquitousKeyValueStore (max 1 MB total, ideal for small settings + set metadata).
// Image files are handled separately by iCloudDriveSync.

class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()

    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var iCloudAvailable: Bool = false
    @Published private(set) var isSyncing: Bool = false

    private let kv = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    // Prefix to avoid clashing with any future Apple keys
    private let prefix = "backup_"
    private let backupDateKey = "backup_lastSyncDate"

    // ── UserDefaults keys to include in the backup ────────────────────────────
    // Excludes: session credentials, device IDs, cooldown timestamps (all device-specific)
    static let settingsKeys: [String] = [
        // DateForce
        "dateForce_enabled", "dateForce_format", "dateForce_mode",
        "dateForce_timeOffset", "dateForce_autoMax", "dateForce_dateGroupSize",
        // ForceReel
        "forceReel_enabled", "forceReel_mediaId", "forceReel_sourceUsername",
        "forceReel_thumbnailURL", "forceReel_videoURL",
        // Force Number Reveal
        "forceNumberRevealEnabled",
        "forceNumberAutoReArchiveEnabled", "forceNumberAutoReArchiveMinutes",
        // Following Magic
        "followingMagicEnabled", "followingMagicDuration",
        "followingMagicGlitch", "followingMagicTriggerDelay",
        // Secret Input
        "secretInputEnabled", "secretInputMode", "secretInputCustomUsername",
        // Misc
        "autoProfilePicOnPerformance", "last_note_text",
        // Active set IDs
        "activeWordSetId", "activeNumberSetId", "activeCustomSetId",
        // Sets metadata (JSON encoded by DataManager)
        "com.vault.sets",
    ]

    private init() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        lastBackupDate  = kv.object(forKey: backupDateKey) as? Date

        // Listen for changes pushed from another device / iCloud
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalKVChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv
        )

        // Kick off initial sync from iCloud so the local KV cache is up to date
        kv.synchronize()
    }

    // MARK: - Public API

    /// Returns true if iCloud is signed in AND the KV store already has a backup.
    var hasCloudBackup: Bool {
        iCloudAvailable && kv.object(forKey: backupDateKey) != nil
    }

    /// Copies all local UserDefaults values → iCloud KV store.
    /// Call after any settings change (debounced by callers).
    func syncToCloud() {
        guard iCloudAvailable else {
            print("☁️ [BACKUP] iCloud not available — skipping sync")
            return
        }

        DispatchQueue.main.async { self.isSyncing = true }

        for key in Self.settingsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                kv.set(value, forKey: prefix + key)
            } else {
                kv.removeObject(forKey: prefix + key)
            }
        }

        let now = Date()
        kv.set(now, forKey: backupDateKey)
        kv.synchronize()

        DispatchQueue.main.async {
            self.lastBackupDate = now
            self.isSyncing = false
        }
        print("☁️ [BACKUP] Synced \(Self.settingsKeys.count) keys to iCloud KV store")
    }

    /// Restores all settings from iCloud KV store → local UserDefaults.
    /// Call on first launch after reinstall when `hasCloudBackup` is true.
    @discardableResult
    func restoreFromCloud() -> Bool {
        guard hasCloudBackup else {
            print("☁️ [BACKUP] No cloud backup found")
            return false
        }

        var restored = 0
        for key in Self.settingsKeys {
            if let value = kv.object(forKey: prefix + key) {
                UserDefaults.standard.set(value, forKey: key)
                restored += 1
            }
        }

        UserDefaults.standard.synchronize()
        print("☁️ [BACKUP] Restored \(restored) keys from iCloud KV store")
        return restored > 0
    }

    // MARK: - Detect first install needing restore

    /// True when the app was just freshly installed AND a cloud backup exists.
    /// After calling `restoreFromCloud()`, call `markInstallComplete()`.
    var needsCloudRestore: Bool {
        let installFlag = "app_data_initialized"
        let isFirstRun  = !UserDefaults.standard.bool(forKey: installFlag)
        return isFirstRun && hasCloudBackup
    }

    func markInstallComplete() {
        UserDefaults.standard.set(true, forKey: "app_data_initialized")
    }

    // MARK: - External change handler (pushed from another device)

    @objc private func externalKVChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            print("☁️ [BACKUP] iCloud pushed updated settings — ignoring (manual restore only)")
        case NSUbiquitousKeyValueStoreAccountChange:
            DispatchQueue.main.async {
                self.iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
            }
        default:
            break
        }
    }
}
