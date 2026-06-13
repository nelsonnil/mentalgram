import Foundation
import Combine

/// Stores the single "active" set for the whole app.
/// Only ONE set can be active at a time (regardless of type) to avoid input
/// conflicts (e.g. lockscreen routing digits to a number set vs. a card to a
/// card set). The active set's own `inputMethod` decides how reveals happen.
///
/// The per-type accessors (`activeWordSetId`, etc.) are kept for backward
/// compatibility and are derived from the single active set.
class ActiveSetSettings: ObservableObject {
    static let shared = ActiveSetSettings()

    /// The single globally-active set id (nil = nothing active).
    @Published var activeSetId: UUID? {
        didSet { save(activeSetId, key: "activeSetId") }
    }

    /// Type of the active set, persisted so per-type accessors work without DataManager.
    @Published var activeSetType: SetType? {
        didSet { UserDefaults.standard.set(activeSetType?.rawValue, forKey: "activeSetType") }
    }

    /// Global Post Prediction switch. When disabled, no set is active and Performance
    /// will not reveal/unarchive a set. Kept separate from `activeSetId` so the UI can
    /// clearly explain that Post Prediction itself is off.
    @Published var isPostPredictionEnabled: Bool {
        didSet { UserDefaults.standard.set(isPostPredictionEnabled, forKey: "postPredictionEnabled") }
    }

    private init() {
        let loadedActiveSetId = ActiveSetSettings.loadId(key: "activeSetId")
        let loadedActiveSetType: SetType?
        if let raw = UserDefaults.standard.string(forKey: "activeSetType") {
            loadedActiveSetType = SetType(rawValue: raw)
        } else {
            loadedActiveSetType = nil
        }
        let loadedPostPredictionEnabled: Bool
        if UserDefaults.standard.object(forKey: "postPredictionEnabled") == nil {
            loadedPostPredictionEnabled = loadedActiveSetId != nil
        } else {
            loadedPostPredictionEnabled = UserDefaults.standard.bool(forKey: "postPredictionEnabled")
        }

        activeSetId = loadedActiveSetId
        activeSetType = loadedActiveSetType
        isPostPredictionEnabled = loadedPostPredictionEnabled

        migrateFromPerTypeKeysIfNeeded()
    }

    // MARK: - Backward-compatible per-type accessors (derived)

    var activeWordSetId: UUID?   { activeSetType == .word   ? activeSetId : nil }
    var activeNumberSetId: UUID? { activeSetType == .number ? activeSetId : nil }
    var activeCustomSetId: UUID? { activeSetType == .custom ? activeSetId : nil }
    var activeCardSetId: UUID?   { activeSetType == .card   ? activeSetId : nil }
    var activeListSetId: UUID?   { activeSetType == .list   ? activeSetId : nil }

    // MARK: - Helpers

    func activeId(for type: SetType) -> UUID? {
        activeSetType == type ? activeSetId : nil
    }

    /// Activates a set for a given type. Because only one set is active globally,
    /// this implicitly deactivates any previously active set of any type.
    func setActive(_ id: UUID?, for type: SetType) {
        if let id = id {
            activeSetId = id
            activeSetType = type
            isPostPredictionEnabled = true
            saveLastActive(id: id, type: type)
        } else if activeSetType == type {
            // Only clear if the set currently active is of this type.
            clearActive()
        }
    }

    /// Convenience global setter from a PhotoSet (single active set semantics).
    func setActive(_ set: PhotoSet?) {
        if let set = set {
            activeSetId = set.id
            activeSetType = set.type
            isPostPredictionEnabled = true
            saveLastActive(id: set.id, type: set.type)
        } else {
            clearActive()
        }
    }

    func clearActive() {
        rememberCurrentActive()
        activeSetId = nil
        activeSetType = nil
        isPostPredictionEnabled = false
    }

    func setPostPredictionEnabled(_ enabled: Bool, availableSets: [PhotoSet]) {
        if enabled {
            isPostPredictionEnabled = true
            restoreLastActiveIfNeeded(availableSets: availableSets)
        } else {
            clearActive()
        }
    }

    private func restoreLastActiveIfNeeded(availableSets: [PhotoSet]) {
        guard activeSetId == nil,
              let lastId = ActiveSetSettings.loadId(key: "lastPostPredictionSetId"),
              let set = availableSets.first(where: { $0.id == lastId }) else { return }
        activeSetId = set.id
        activeSetType = set.type
    }

    private func rememberCurrentActive() {
        guard let activeSetId, let activeSetType else { return }
        saveLastActive(id: activeSetId, type: activeSetType)
    }

    private func saveLastActive(id: UUID, type: SetType) {
        save(id, key: "lastPostPredictionSetId")
        UserDefaults.standard.set(type.rawValue, forKey: "lastPostPredictionSetType")
    }

    func isActive(_ setId: UUID, type: SetType) -> Bool {
        activeSetId == setId && activeSetType == type
    }

    func isActive(_ setId: UUID) -> Bool {
        activeSetId == setId
    }

    // MARK: - Migration

    /// One-time migration from the old 4-key model (one active set per type) to
    /// the single-active-set model. Picks the first non-nil legacy key and clears
    /// the rest so only one set remains active.
    private func migrateFromPerTypeKeysIfNeeded() {
        let migrationKey = "activeSetMigratedToSingleV1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let legacy: [(key: String, type: SetType)] = [
            ("activeWordSetId",   .word),
            ("activeNumberSetId", .number),
            ("activeCustomSetId", .custom),
            ("activeCardSetId",   .card)
        ]

        if activeSetId == nil {
            for entry in legacy {
                if let str = UserDefaults.standard.string(forKey: entry.key),
                   let id = UUID(uuidString: str) {
                    activeSetId = id
                    activeSetType = entry.type
                    break
                }
            }
        }

        // Remove all legacy keys so they don't reactivate stale sets.
        for entry in legacy {
            UserDefaults.standard.removeObject(forKey: entry.key)
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Persistence

    private func save(_ id: UUID?, key: String) {
        UserDefaults.standard.set(id?.uuidString, forKey: key)
    }

    private static func loadId(key: String) -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: str)
    }
}
