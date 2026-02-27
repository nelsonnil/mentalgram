import Foundation
import Combine

/// Stores which set is "active" for each type (word / number / custom).
/// Only one set per type can be active at a time.
/// Used by the secret word reveal (ExploreView) and force number reveal (PerformanceView).
class ActiveSetSettings: ObservableObject {
    static let shared = ActiveSetSettings()

    @Published var activeWordSetId: UUID? {
        didSet { save(activeWordSetId, key: "activeWordSetId") }
    }
    @Published var activeNumberSetId: UUID? {
        didSet { save(activeNumberSetId, key: "activeNumberSetId") }
    }
    @Published var activeCustomSetId: UUID? {
        didSet { save(activeCustomSetId, key: "activeCustomSetId") }
    }

    private init() {
        activeWordSetId   = load(key: "activeWordSetId")
        activeNumberSetId = load(key: "activeNumberSetId")
        activeCustomSetId = load(key: "activeCustomSetId")
    }

    // MARK: - Helpers

    func activeId(for type: SetType) -> UUID? {
        switch type {
        case .word:   return activeWordSetId
        case .number: return activeNumberSetId
        case .custom: return activeCustomSetId
        }
    }

    func setActive(_ id: UUID?, for type: SetType) {
        switch type {
        case .word:   activeWordSetId   = id
        case .number: activeNumberSetId = id
        case .custom: activeCustomSetId = id
        }
    }

    func isActive(_ setId: UUID, type: SetType) -> Bool {
        activeId(for: type) == setId
    }

    // MARK: - Persistence

    private func save(_ id: UUID?, key: String) {
        UserDefaults.standard.set(id?.uuidString, forKey: key)
    }

    private func load(key: String) -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: str)
    }
}
