import Foundation
import UIKit
import Combine

// MARK: - Backup Routine

struct BackupRoutine: Identifiable, Codable, Equatable {
    let schemaVersion: Int
    let id: UUID
    var name: String
    let createdAt: Date
    let settingsPlistData: Data

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Backup Routine Manager

final class BackupRoutineManager: ObservableObject {
    static let shared = BackupRoutineManager()

    static let storageKey = "backup_routines_v1"
    static let pendingShortcutRoutineIdKey = "backupRoutine_pendingShortcutRoutineId"
    static let pendingOpenPerformanceKey = "backupRoutine_pendingOpenPerformance"
    static let openPerformanceNotification = Notification.Name("BackupRoutineOpenPerformance")

    private static let maxRoutineCount = 4
    private static let maxStoredBytes = 512 * 1024
    private static let shortcutPrefix = "com.mentalgram.routine."
    private static let extraRoutineKeyPrefixes = [
        "bio_", "note_", "integ_", "ocr_", "force", "amnesia_", "followingMagic",
        "dateForce_", "lockscreen", "performance", "ppTop", "activeSet",
        "activeWordSetId", "activeNumberSetId", "activeCustomSetId", "activeCardSetId",
        "lastPostPrediction", "autoProfilePic", "launchDirectly", "limitsGuide",
        "fakeHomeScreen", "clipboardAuto", "last_note", "perf_local", "postPred"
    ]

    @Published private(set) var routines: [BackupRoutine] = []

    var maxRoutines: Int { Self.maxRoutineCount }
    var canCreateRoutine: Bool { routines.count < Self.maxRoutineCount }

    private var baseRoutineSettingsKeys: [String] {
        CloudBackupService.settingsKeys.filter {
            $0 != Self.storageKey
                && $0 != Self.pendingShortcutRoutineIdKey
                && $0 != Self.pendingOpenPerformanceKey
        }
    }

    private var currentRoutineSettingsKeys: [String] {
        let currentKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { key in
            Self.extraRoutineKeyPrefixes.contains { key.hasPrefix($0) }
        }
        return Array(Set(baseRoutineSettingsKeys).union(currentKeys)).sorted()
    }

    private init() {
        reloadFromUserDefaults()
    }

    @discardableResult
    func createRoutine(named rawName: String) -> BackupRoutine? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, canCreateRoutine else { return nil }
        guard let settingsData = makeSettingsPlistData() else { return nil }

        let routine = BackupRoutine(
            schemaVersion: 1,
            id: UUID(),
            name: name,
            createdAt: Date(),
            settingsPlistData: settingsData
        )

        routines.insert(routine, at: 0)
        persist()
        updateShortcutItems()
        LogManager.shared.success("Backup routine created: \(name)", category: .general)
        return routine
    }

    @discardableResult
    func restoreRoutine(id: UUID, openPerformance: Bool = false) -> Bool {
        guard let routine = routines.first(where: { $0.id == id }) else { return false }
        let ok = restoreRoutine(routine, openPerformance: openPerformance)
        if ok {
            LogManager.shared.success("Backup routine restored: \(routine.name)", category: .general)
        }
        return ok
    }

    @discardableResult
    func restoreRoutine(_ routine: BackupRoutine, openPerformance: Bool = false) -> Bool {
        guard let settings = decodeSettings(from: routine.settingsPlistData) else { return false }

        let ud = UserDefaults.standard
        let keysToRestore = Set(baseRoutineSettingsKeys)
            .union(settings.keys)
            .union(UserDefaults.standard.dictionaryRepresentation().keys.filter { key in
                Self.extraRoutineKeyPrefixes.contains { key.hasPrefix($0) }
            })
            .subtracting([Self.storageKey, Self.pendingShortcutRoutineIdKey, Self.pendingOpenPerformanceKey])

        for key in keysToRestore {
            if let value = settings[key] {
                ud.set(value, forKey: key)
            } else {
                ud.removeObject(forKey: key)
            }
        }

        ud.synchronize()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: ud)
        DataManager.shared.reloadAfterRestore()

        if openPerformance {
            ud.set(true, forKey: Self.pendingOpenPerformanceKey)
            for delay in [0.2, 0.6, 1.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NotificationCenter.default.post(name: Self.openPerformanceNotification, object: routine.id)
                }
            }
        }

        return true
    }

    func deleteRoutine(id: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        let removed = routines.remove(at: index)
        persist()
        updateShortcutItems()
        LogManager.shared.info("Backup routine deleted: \(removed.name)", category: .general)
    }

    func reloadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           data.count <= Self.maxStoredBytes,
           let decoded = try? JSONDecoder().decode([BackupRoutine].self, from: data) {
            routines = Array(decoded.prefix(Self.maxRoutineCount))
            persistLocalOnlyIfSmallerThan(data)
        } else {
            if let data = UserDefaults.standard.data(forKey: Self.storageKey),
               data.count > Self.maxStoredBytes {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
                LogManager.shared.warning("Backup routines discarded: stored payload too large (\(data.count / 1024) KB)", category: .general)
            }
            routines = []
        }
        updateShortcutItems()
    }

    func queueShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let id = routineId(from: shortcutItem) else { return false }
        UserDefaults.standard.set(id.uuidString, forKey: Self.pendingShortcutRoutineIdKey)
        UserDefaults.standard.set(true, forKey: Self.pendingOpenPerformanceKey)
        LogManager.shared.info("Backup routine shortcut queued for Performance", category: .general)
        return true
    }

    @discardableResult
    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let id = routineId(from: shortcutItem) else { return false }
        UserDefaults.standard.set(id.uuidString, forKey: Self.pendingShortcutRoutineIdKey)
        UserDefaults.standard.set(true, forKey: Self.pendingOpenPerformanceKey)
        LogManager.shared.info("Backup routine shortcut received while app was running", category: .general)
        if restoreRoutine(id: id, openPerformance: true) {
            return true
        }
        LogManager.shared.warning("Backup routine shortcut queued because restore was not ready", category: .general)
        return true
    }

    @discardableResult
    func restorePendingShortcutIfNeeded() -> Bool {
        let ud = UserDefaults.standard
        guard let raw = ud.string(forKey: Self.pendingShortcutRoutineIdKey),
              let id = UUID(uuidString: raw) else { return false }
        ud.removeObject(forKey: Self.pendingShortcutRoutineIdKey)
        let restored = restoreRoutine(id: id, openPerformance: true)
        if !restored {
            LogManager.shared.warning("Pending backup routine shortcut could not be restored", category: .general)
        }
        return restored
    }

    func consumePendingOpenPerformance() -> Bool {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: Self.pendingOpenPerformanceKey) else { return false }
        ud.removeObject(forKey: Self.pendingOpenPerformanceKey)
        return true
    }

    func clearPendingShortcutRequest() {
        UserDefaults.standard.removeObject(forKey: Self.pendingShortcutRoutineIdKey)
    }

    // MARK: - Snapshot

    private func makeSettingsPlistData() -> Data? {
        var snapshot: [String: Any] = [:]
        let ud = UserDefaults.standard

        for key in currentRoutineSettingsKeys {
            guard let value = ud.object(forKey: key) else { continue }
            guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
                print("⚠️ [ROUTINE] Skipping non-property-list setting '\(key)'")
                continue
            }
            snapshot[key] = value
        }

        do {
            return try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        } catch {
            print("❌ [ROUTINE] Could not encode settings snapshot: \(error)")
            return nil
        }
    }

    private func decodeSettings(from data: Data) -> [String: Any]? {
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            print("❌ [ROUTINE] Could not decode settings snapshot: \(error)")
            return nil
        }
    }

    // MARK: - Persistence / Shortcuts

    private func persist() {
        if let data = try? JSONEncoder().encode(routines) {
            guard data.count <= Self.maxStoredBytes else {
                LogManager.shared.warning("Backup routines not persisted: payload too large (\(data.count / 1024) KB)", category: .general)
                return
            }
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            CloudBackupService.shared.scheduleDebouncedSync()
        }
    }

    private func persistLocalOnlyIfSmallerThan(_ oldData: Data) {
        guard let newData = try? JSONEncoder().encode(routines),
              newData.count < oldData.count else { return }
        UserDefaults.standard.set(newData, forKey: Self.storageKey)
        LogManager.shared.info("Backup routines compacted: \(oldData.count / 1024) KB → \(newData.count / 1024) KB", category: .general)
    }

    private func updateShortcutItems() {
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = self.routines.prefix(Self.maxRoutineCount).map { routine in
                UIApplicationShortcutItem(
                    type: Self.shortcutPrefix + routine.id.uuidString,
                    localizedTitle: routine.trimmedName,
                    localizedSubtitle: "Go to Performance",
                    icon: UIApplicationShortcutIcon(systemImageName: "arrow.triangle.2.circlepath")
                )
            }
        }
    }

    private func routineId(from shortcutItem: UIApplicationShortcutItem) -> UUID? {
        guard shortcutItem.type.hasPrefix(Self.shortcutPrefix) else { return nil }
        let raw = String(shortcutItem.type.dropFirst(Self.shortcutPrefix.count))
        return UUID(uuidString: raw)
    }
}
