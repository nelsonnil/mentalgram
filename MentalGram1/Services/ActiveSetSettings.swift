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

    private init() {
        activeSetId = ActiveSetSettings.loadId(key: "activeSetId")
        if let raw = UserDefaults.standard.string(forKey: "activeSetType") {
            activeSetType = SetType(rawValue: raw)
        } else {
            activeSetType = nil
        }
        migrateFromPerTypeKeysIfNeeded()
    }

    // MARK: - Backward-compatible per-type accessors (derived)

    var activeWordSetId: UUID?   { activeSetType == .word   ? activeSetId : nil }
    var activeNumberSetId: UUID? { activeSetType == .number ? activeSetId : nil }
    var activeCustomSetId: UUID? { activeSetType == .custom ? activeSetId : nil }
    var activeCardSetId: UUID?   { activeSetType == .card   ? activeSetId : nil }

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
        } else if activeSetType == type {
            // Only clear if the set currently active is of this type.
            activeSetId = nil
            activeSetType = nil
        }
    }

    /// Convenience global setter from a PhotoSet (single active set semantics).
    func setActive(_ set: PhotoSet?) {
        if let set = set {
            activeSetId = set.id
            activeSetType = set.type
        } else {
            activeSetId = nil
            activeSetType = nil
        }
    }

    func clearActive() {
        activeSetId = nil
        activeSetType = nil
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
