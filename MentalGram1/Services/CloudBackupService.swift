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
    /// userId that owns the sets JSON currently in the cloud backup. Lets the safe
    /// auto-backup avoid clobbering a different account's backup.
    private let setsOwnerKey = "backup_setsOwnerUserId"
    /// Timestamp when the sets JSON was last backed up. Used to detect if the cloud
    /// backup is older than the local data (e.g., restore timing race on multi-device).
    private let setsTimestampKey = "backup_setsTimestamp"

    // MARK: - Debounce
    // Backups are manual-only. These properties remain for backward compatibility with
    // older call sites, but scheduleDebouncedSync() intentionally does not upload.
    private var debounceTimer: Timer?
    private let debouncedDelay: TimeInterval = 60

    // ── Settings keys to include (excluding sets — handled separately below) ──
    static let settingsKeys: [String] = [
        // DateForce
        "dateForce_enabled", "dateForce_format", "dateForce_mode",
        "dateForce_timeOffset", "dateForce_autoCount", "dateForce_autoMax",
        "dateForce_dateGroupSize", "dateForce_selectedIds", "dateForce_baselineIds",
        // ForceReel
        "forceReel_enabled", "forceReel_mediaId", "forceReel_sourceUsername",
        "forceReel_thumbnailURL", "forceReel_videoURL", "forceReel_likeCount",
        "forceReel_commentCount", "forceReel_caption", "forceReel_slots_v2",
        // ForcePost
        "forcePost_enabled", "forcePost_entries_v2",
        "forcePost_userId", "forcePost_username", "forcePost_mediaId",
        "forcePost_mediaURL", "forcePost_mediaItem",
        // Force Number Reveal
        "forceNumberRevealEnabled", "forceNumberRevealGridSwipeEnabled",
        "forceNumberRevealOcrEnabled",
        "forceNumberAutoReArchiveEnabled", "forceNumberAutoReArchiveMinutes",
        "reArchive_pendingIds", "reArchive_deadline",
        // Amnesia Carousel — toggle, both uploaded post IDs and reveal state so the effect
        // is restored ready-to-perform without re-uploading. The migration flag is included
        // so the restored reveal state is not reset by the one-time safety migration.
        "amnesia_enabled", "amnesia_shortCarouselMediaId",
        "amnesia_fullCarouselMediaId", "amnesia_isRevealed",
        "amnesia_reveal_state_safety_migration_v1", "amnesia_ownerUserId",
        // Following Magic
        "followingMagicEnabled", "followingMagicDuration",
        "followingMagicGlitch", "followingMagicTriggerDelay",
        "followingMagicTargetFollowers", "followingMagicTransferEnabled",
        "followingMagicTransferOffset",
        // Secret Input
        "secretInputEnabled", "secretInputMode", "secretInputCustomUsername",
        // Lockscreen Input
        "lockscreenInputEnabled",
        // Bio templates (all 4 slots)
        "bio_template", "bio_template_2", "bio_template_3", "bio_template_4",
        "bio_active_slot", "bio_acrostic_enabled", "bio_feature_enabled",
        "bioTopInputMode",
        // Note template & settings
        "note_template", "note_feature_enabled", "noteTopInputMode",
        "note_duplicate_warning_text",
        // Integrations / custom APIs (IntegrationsSettings)
        "integ_injectID",
        "integ_custom1Name", "integ_custom2Name", "integ_custom3Name",
        "integ_custom1Url",  "integ_custom2Url",  "integ_custom3Url",
        "integ_custom1Field","integ_custom2Field", "integ_custom3Field",
        "integ_bioApiSource", "integ_noteApiSource", "integ_ppApiSource",
        "integ_noteText1Source", "integ_noteText2Source", "integ_noteText3Source",
        "integ_noteText4Source", "integ_noteText5Source",
        "integ_bioText1Source",  "integ_bioText2Source",  "integ_bioText3Source",
        "integ_bioText4Source",  "integ_bioText5Source",
        "integ_bioTemplate2Text1Source", "integ_bioTemplate2Text2Source",
        "integ_bioTemplate2Text3Source", "integ_bioTemplate2Text4Source",
        "integ_bioTemplate2Text5Source",
        "integ_bioTemplate3Text1Source", "integ_bioTemplate3Text2Source",
        "integ_bioTemplate3Text3Source", "integ_bioTemplate3Text4Source",
        "integ_bioTemplate3Text5Source",
        "integ_bioTemplate4Text1Source", "integ_bioTemplate4Text2Source",
        "integ_bioTemplate4Text3Source", "integ_bioTemplate4Text4Source",
        "integ_bioTemplate4Text5Source",
        // OCR settings
        "ocr_language", "ocr_camera",
        // App behaviour
        "autoProfilePicOnPerformance", "launchDirectlyToPerformance",
        "limitsGuideRead", "fakeHomeScreenEnabled",
        "clipboardAutoMode", "clipboardAutoLastSent",
        "performanceCoverMode", "ppTopInputMode",
        "performance_test_mode_enabled",
        "activeSetId", "activeSetType", "postPredictionEnabled",
        "lastPostPredictionSetId", "lastPostPredictionSetType",
        // Last note text / duplicate guard
        "last_note_text", "last_note_sent_text", "last_note_sent_timestamp",
        "last_note_sent_date",
        // Local replica state that can be visible immediately after a routine restore
        "perf_local_bio_override_text", "perf_local_bio_override_timestamp",
        "postPredRevealRingActive",
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

    /// Schedules a debounced **safe** auto-backup. Coalesces rapid changes into one
    /// upload. Unlike syncToCloud (the manual button), this never regresses a good cloud
    /// backup — see performSafeAutoBackup() for the guards.
    func scheduleDebouncedSync() {
        DispatchQueue.main.async {
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(
                withTimeInterval: self.debouncedDelay, repeats: false
            ) { [weak self] _ in
                self?.performSafeAutoBackup()
            }
        }
    }

    /// Safe automatic backup. Unlike syncToCloud (the manual "Back up now"), this NEVER
    /// regresses a good cloud backup:
    ///  • Settings keys are always mirrored (current local values are the truth).
    ///  • Sets JSON is written only when it won't clobber a *different* account's backup
    ///    and won't replace a non-empty backup with an empty (0-set) local state.
    ///  • It does not run the full photo re-sync — set photos upload per-set on change.
    func performSafeAutoBackup() {
        guard iCloudAvailable else { return }

        DispatchQueue.global(qos: .utility).async {
            var savedCount = 0

            // 1. Settings keys — additive/update only. We deliberately do NOT remove cloud
            //    keys that are absent locally: a not-yet-restored or failed-restore install
            //    has empty locals and must never wipe good cloud settings. (The manual
            //    "Back up now" path is authoritative and still prunes removed keys.)
            for key in Self.settingsKeys {
                if let value = UserDefaults.standard.object(forKey: key) {
                    self.kv.set(value, forKey: self.prefix + key)
                    savedCount += 1
                }
            }
            self.kv.removeObject(forKey: self.prefix + BackupRoutineManager.storageKey)

            // 2. Sets JSON — guarded against cross-account clobber and empty regressions.
            let userId = InstagramService.shared.session.userId
            let currentOwner = userId.isEmpty ? "guest" : userId
            let scopedKey = "com.vault.sets.\(currentOwner)"
            let localData = UserDefaults.standard.data(forKey: scopedKey)
                ?? UserDefaults.standard.data(forKey: "com.vault.sets")
            let localSetCount = Self.decodeSetCount(localData)

            let cloudData = self.kv.data(forKey: self.setsKVKey)
            let cloudSetCount = Self.decodeSetCount(cloudData)
            let cloudOwner = self.kv.string(forKey: self.setsOwnerKey)

            let canWriteSets: Bool
            var skipReason: String? = nil
            if localData == nil || localSetCount == 0 {
                // Never push an empty/unknown local state over the cloud backup.
                canWriteSets = false
                skipReason = "local is empty (\(localSetCount) sets)"
            } else if cloudData == nil || cloudSetCount == 0 {
                // Empty cloud → safe to seed.
                canWriteSets = true
            } else if let cloudOwner, cloudOwner != currentOwner {
                // Different account with real data → never auto-clobber. Manual only.
                canWriteSets = false
                skipReason = "cloud belongs to '\(cloudOwner)', current '\(currentOwner)'"
            } else if localSetCount < cloudSetCount {
                // Auto-backup must NEVER reduce the set count in the cloud.
                // If local has fewer sets than the cloud backup it could mean a migration
                // race, a partial restore, or a bug — protecting the cloud is safer.
                // The user can use the manual "Back up now" button to intentionally reduce.
                canWriteSets = false
                skipReason = "REGRESSION GUARD — local \(localSetCount) sets < cloud \(cloudSetCount) sets. Manual backup required to reduce count."
                LogManager.shared.warning(
                    "Auto-backup regression guard: local has \(localSetCount) sets but cloud has \(cloudSetCount). Skipping to protect backup. Use 'Back up now' to override.",
                    category: .general
                )
            } else {
                // Same account, local count >= cloud count → safe to update.
                canWriteSets = true
            }

            if canWriteSets, let localData {
                let now = Date()
                self.kv.set(localData, forKey: self.setsKVKey)
                self.kv.set(currentOwner, forKey: self.setsOwnerKey)
                self.kv.set(now.timeIntervalSince1970, forKey: self.setsTimestampKey)
                savedCount += 1
            } else if let reason = skipReason {
                print("☁️ [BACKUP] Safe auto-backup: kept cloud sets (\(reason))")
            }

            let now = Date()
            self.kv.set(now, forKey: self.backupDateKey)
            let ok = self.kv.synchronize()

            let kvSetsBytes = self.kv.data(forKey: self.setsKVKey)?.count ?? 0
            DispatchQueue.main.async {
                self.lastBackupDate = now
                self.backedUpSetsBytes = kvSetsBytes
            }
            print("☁️ [BACKUP] ✅ Safe auto-backup: \(savedCount) keys, setsWritten=\(canWriteSets), sync=\(ok)")
        }
    }

    /// Lightweight set-count without fully decoding the model (avoids coupling to schema).
    private static func decodeSetCount(_ data: Data?) -> Int {
        guard let data else { return 0 }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return arr.count
        }
        return 0
    }

    /// Copies all local settings + sets JSON → iCloud KV store.
    /// Use only from explicit user actions, e.g. the "Back up now" button.
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
        kv.removeObject(forKey: prefix + BackupRoutineManager.storageKey)

        // 2. Sets JSON — DataManager uses an account-scoped key: "com.vault.sets.<userId>"
        //    We must read from there, not from the legacy "com.vault.sets" key.
        let userId = InstagramService.shared.session.userId
        let scopedKey = "com.vault.sets.\(userId.isEmpty ? "guest" : userId)"

        let backupOwner = userId.isEmpty ? "guest" : userId
        let setsDataToBackup: Data? = UserDefaults.standard.data(forKey: scopedKey)
            ?? UserDefaults.standard.data(forKey: "com.vault.sets")
        let localSetCountForManual = Self.decodeSetCount(setsDataToBackup)
        let cloudSetCountForManual = Self.decodeSetCount(kv.data(forKey: setsKVKey))

        if localSetCountForManual > 0 && localSetCountForManual < cloudSetCountForManual {
            // Warn in log when manual backup would reduce the cloud set count.
            // The user pressed "Back up now" intentionally, so we still proceed —
            // but the warning helps diagnose accidental overwrites.
            LogManager.shared.warning(
                "Manual backup: local has \(localSetCountForManual) sets but cloud had \(cloudSetCountForManual). Cloud will be reduced. (Intentional manual backup.)",
                category: .general
            )
        }

        if let setsData = setsDataToBackup {
            let now = Date()
            kv.set(setsData, forKey: setsKVKey)
            kv.set(backupOwner, forKey: setsOwnerKey)
            kv.set(now.timeIntervalSince1970, forKey: setsTimestampKey)
            let sizeKB = setsData.count / 1024
            let source = UserDefaults.standard.data(forKey: scopedKey) != nil ? scopedKey : "com.vault.sets (legacy)"
            print("☁️ [BACKUP] Sets backed up from '\(source)' (\(sizeKB) KB, \(localSetCountForManual) sets, timestamp=\(now.timeIntervalSince1970))")
            savedCount += 1

            // Save a crash-safe snapshot to iCloud Drive (never overwritten by auto-backup)
            iCloudDriveSync.shared.saveSnapshotToiCloudDrive(setsData, setCount: localSetCountForManual)
        } else {
            kv.removeObject(forKey: setsKVKey)
            kv.removeObject(forKey: setsTimestampKey)
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

        // Also sync photo files and cover images to iCloud Drive so they survive a reinstall.
        iCloudDriveSync.shared.syncAllPhotosToCloud { uploaded, skipped, _ in
            if uploaded > 0 {
                print("☁️ [BACKUP] iCloud Drive: \(uploaded) new photo(s) uploaded alongside KV backup")
            }
        }
        HomeScreenIllusionService.shared.uploadToCloud()
        LockscreenInputSettings.shared.uploadWallpaperToCloud()
        AmnesiaCarouselSettings.shared.uploadImagesToCloud()

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
            // Timestamp regression check: warn if cloud backup has fewer sets than local.
            // This helps diagnose multi-device timing issues where Device B uploads new
            // sets but Device A restores before iCloud propagates the latest backup.
            let cloudTimestamp = kv.double(forKey: setsTimestampKey)
            let userId = InstagramService.shared.session.userId
            let localKey = userId.isEmpty ? "com.vault.sets" : "com.vault.sets.\(userId)"
            if let localData = UserDefaults.standard.data(forKey: localKey) {
                let localSetCount = Self.decodeSetCount(localData)
                let cloudSetCount = Self.decodeSetCount(setsData)
                
                // Simple heuristic: if cloud has fewer sets, it's likely older.
                // Combined with the timestamp (if available), this catches most timing races.
                if cloudSetCount > 0 && localSetCount > 0 && cloudSetCount < localSetCount {
                    let cloudDate = cloudTimestamp > 0 ? Date(timeIntervalSince1970: cloudTimestamp) : nil
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    let dateInfo = cloudDate != nil ? " from \(formatter.string(from: cloudDate!))" : ""
                    LogManager.shared.warning(
                        "⚠️ RESTORE WARNING: Cloud backup\(dateInfo) has \(cloudSetCount) sets, but your local data has \(localSetCount) sets. This can happen if another device backed up recently but iCloud hasn't synced yet. To avoid data loss, wait 2-3 minutes after backing up on one device before restoring on another.",
                        category: .general
                    )
                    print("☁️ [BACKUP]   ⚠️ REGRESSION: cloud has \(cloudSetCount) sets, local has \(localSetCount) — proceeding with restore (user action)")
                }
            }
            
            UserDefaults.standard.set(setsData, forKey: "com.vault.sets")
            let sizeKB = setsData.count / 1024
            print("☁️ [BACKUP]   ✓ restored sets JSON (\(sizeKB) KB, timestamp=\(cloudTimestamp)) → 'com.vault.sets' (pending migration)")
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
