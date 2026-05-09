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
    /// Non-nil when the last KV sync had a problem (e.g. quota exceeded, iCloud unavailable).
    @Published private(set) var lastKVError: String?
    /// How many sets JSON bytes are currently in the KV backup.
    @Published private(set) var backedUpSetsBytes: Int = 0

    private let kv = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    private let prefix = "backup_"
    private let backupDateKey = "backup_lastSyncDate"
    private let setsKVKey = "backup_com.vault.sets"

    // MARK: - Debounce (auto-sync called from DataManager.saveSets)
    // 60-second window protects against accidental deletes being immediately backed up.
    // Manual "Back up now" and app-backgrounding bypass this via syncToCloud(immediate:true).
    private var debounceTimer: Timer?
    private let debouncedDelay: TimeInterval = 60

    // ── Settings keys to include (excluding sets — handled separately below) ──
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
        "activeWordSetId", "activeNumberSetId", "activeCustomSetId", "activeCardSetId",
        // NOTE: Sets JSON (com.vault.sets.*) is backed up separately in syncToCloud()
        // because DataManager uses an account-scoped key: "com.vault.sets.<userId>"
    ]

    private init() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        lastBackupDate  = kv.object(forKey: backupDateKey) as? Date
        backedUpSetsBytes = kv.data(forKey: setsKVKey)?.count ?? 0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalKVChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv
        )
        kv.synchronize()
    }

    // MARK: - Public API

    var hasCloudBackup: Bool {
        iCloudAvailable && kv.object(forKey: backupDateKey) != nil
    }

    /// Called automatically from DataManager.saveSets().
    /// Schedules a debounced backup (60 s delay) so that accidental deletes/crashes
    /// within that window do NOT immediately overwrite the existing iCloud backup.
    func scheduleDebouncedSync() {
        DispatchQueue.main.async {
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debouncedDelay, repeats: false) { [weak self] _ in
                print("☁️ [BACKUP] Debounce elapsed — running auto-sync")
                self?.syncToCloud(immediate: false)
            }
        }
    }

    /// Copies all local settings + sets JSON → iCloud KV store.
    /// - `immediate: true`  — used for manual "Back up now" button and app backgrounding.
    /// - `immediate: false` — called internally after debounce; same logic, just labelled.
    func syncToCloud(immediate: Bool = true) {
        guard iCloudAvailable else {
            print("☁️ [BACKUP] iCloud not available — skipping sync")
            return
        }

        // Cancel any pending debounce if we're doing an immediate sync
        if immediate {
            DispatchQueue.main.async { self.debounceTimer?.invalidate() }
        }

        DispatchQueue.main.async { self.isSyncing = true }

        var savedCount = 0

        // 1. Regular settings keys
        for key in Self.settingsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                kv.set(value, forKey: prefix + key)
                savedCount += 1
            } else {
                kv.removeObject(forKey: prefix + key)
            }
        }

        // 2. Sets JSON — DataManager uses an account-scoped key: "com.vault.sets.<userId>"
        //    We must read from there, not from the legacy "com.vault.sets" key.
        let userId = InstagramService.shared.session.userId
        let scopedKey = "com.vault.sets.\(userId.isEmpty ? "guest" : userId)"

        if let setsData = UserDefaults.standard.data(forKey: scopedKey) {
            kv.set(setsData, forKey: setsKVKey)
            let sizeKB = setsData.count / 1024
            print("☁️ [BACKUP] Sets backed up from '\(scopedKey)' (\(sizeKB) KB)")
            savedCount += 1
        } else if let legacyData = UserDefaults.standard.data(forKey: "com.vault.sets") {
            // Fallback: legacy key (pre-account-scoping installs)
            kv.set(legacyData, forKey: setsKVKey)
            print("☁️ [BACKUP] Sets backed up from legacy key (\(legacyData.count / 1024) KB)")
            savedCount += 1
        } else {
            kv.removeObject(forKey: setsKVKey)
            print("☁️ [BACKUP] No sets data found to back up (scopedKey='\(scopedKey)')")
        }

        let now = Date()
        kv.set(now, forKey: backupDateKey)
        let syncOK = kv.synchronize()

        // Calculate total bytes used in KV store to watch quota (limit is 1 MB)
        let kvSetsBytes = (kv.data(forKey: setsKVKey)?.count ?? 0)
        let totalKVBytes = Self.settingsKeys.reduce(0) { acc, key in
            if let d = kv.data(forKey: prefix + key) { return acc + d.count }
            if let s = kv.string(forKey: prefix + key) { return acc + s.utf8.count }
            return acc
        } + kvSetsBytes
        let totalKB = totalKVBytes / 1024
        let quotaKB = 1024  // NSUbiquitousKeyValueStore hard limit: 1 MB
        let warningThresholdKB = 800  // Warn at 80%

        var kvError: String? = nil
        if !syncOK {
            kvError = "iCloud KV synchronize() returned false — changes may not be uploaded yet."
            print("☁️ [BACKUP] ⚠️ kv.synchronize() returned false")
        } else if totalKB >= warningThresholdKB {
            kvError = "Backup approaching iCloud KV quota (\(totalKB) KB / \(quotaKB) KB)."
            print("☁️ [BACKUP] ⚠️ KV store usage: \(totalKB) KB / \(quotaKB) KB")
        }

        DispatchQueue.main.async {
            self.lastBackupDate = now
            self.isSyncing = false
            self.lastKVError = kvError
            self.backedUpSetsBytes = kvSetsBytes
        }

        let syncMark = syncOK ? "✅" : "⚠️"
        print("☁️ [BACKUP] \(syncMark) Synced \(savedCount) keys to iCloud KV store (\(totalKB) KB total, sync=\(syncOK))")
    }

    /// Restores all settings from iCloud KV store → local UserDefaults.
    /// After calling this, DataManager.reloadAfterRestore() MUST be called
    /// to pick up the restored sets data (it calls migrateLegacySetsIfNeeded internally).
    @discardableResult
    func restoreFromCloud() -> Bool {
        guard hasCloudBackup else {
            print("☁️ [BACKUP] No cloud backup found (iCloudAvailable=\(iCloudAvailable))")
            return false
        }

        // Ensure we have the latest data from iCloud before reading
        kv.synchronize()

        var restored = 0

        // 1. Regular settings keys
        for key in Self.settingsKeys {
            if let value = kv.object(forKey: prefix + key) {
                UserDefaults.standard.set(value, forKey: key)
                restored += 1
                print("☁️ [BACKUP]   ✓ restored key '\(key)'")
            } else {
                print("☁️ [BACKUP]   - key '\(key)' not in backup")
            }
        }

        // 2. Sets JSON — write to the LEGACY key so migrateLegacySetsIfNeeded()
        //    in DataManager.reloadAfterRestore() can pick it up and move it to the scoped key.
        if let setsData = kv.data(forKey: setsKVKey) {
            UserDefaults.standard.set(setsData, forKey: "com.vault.sets")
            let sizeKB = setsData.count / 1024
            print("☁️ [BACKUP]   ✓ restored sets JSON (\(sizeKB) KB) → 'com.vault.sets' (pending migration)")
            restored += 1
        } else {
            print("☁️ [BACKUP]   ⚠️ No sets JSON found in backup (key='\(setsKVKey)')")
        }

        UserDefaults.standard.synchronize()
        print("☁️ [BACKUP] ✅ Restored \(restored) keys from iCloud KV store")
        LogManager.shared.success("iCloud restore: \(restored) keys restored", category: .general)
        return restored > 0
    }

    // MARK: - Diagnostics

    /// Returns a human-readable summary of what is currently stored in the KV backup.
    func backupDiagnostics() -> String {
        var lines: [String] = ["=== iCloud KV Backup Diagnostics ==="]
        lines.append("iCloud available: \(iCloudAvailable)")
        lines.append("Has backup: \(hasCloudBackup)")
        if let date = lastBackupDate {
            lines.append("Last backup: \(date)")
        } else {
            lines.append("Last backup: never")
        }

        var found = 0
        for key in Self.settingsKeys {
            if kv.object(forKey: prefix + key) != nil { found += 1 }
        }
        lines.append("Settings keys in backup: \(found)/\(Self.settingsKeys.count)")

        if let setsData = kv.data(forKey: setsKVKey) {
            lines.append("Sets JSON in backup: \(setsData.count / 1024) KB")
        } else {
            lines.append("Sets JSON in backup: MISSING ⚠️")
        }

        let userId = InstagramService.shared.session.userId
        let scopedKey = "com.vault.sets.\(userId.isEmpty ? "guest" : userId)"
        if let local = UserDefaults.standard.data(forKey: scopedKey) {
            lines.append("Local sets (scoped): \(local.count / 1024) KB at '\(scopedKey)'")
        } else {
            lines.append("Local sets (scoped): NONE at '\(scopedKey)'")
        }
        if let legacy = UserDefaults.standard.data(forKey: "com.vault.sets") {
            lines.append("Local sets (legacy): \(legacy.count / 1024) KB")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Detect first install needing restore

    var needsCloudRestore: Bool {
        let installFlag = "app_data_initialized"
        let isFirstRun  = !UserDefaults.standard.bool(forKey: installFlag)
        return isFirstRun && hasCloudBackup
    }

    func markInstallComplete() {
        UserDefaults.standard.set(true, forKey: "app_data_initialized")
    }

    // MARK: - External change handler

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
