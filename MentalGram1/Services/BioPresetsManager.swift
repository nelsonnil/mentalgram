import Foundation
import Combine
import SwiftUI

struct BioPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var text: String
}

final class BioPresetsManager: ObservableObject {
    static let shared = BioPresetsManager()
    private init() { load() }

    private let key = "bio_presets_v1"

    @Published var presets: [BioPreset] = []

    // MARK: - CRUD

    func save(name: String, text: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let label = trimmedName.isEmpty ? String(trimmedText.prefix(30)) : trimmedName
        presets.append(BioPreset(name: label, text: trimmedText))
        persist()
    }

    func update(_ preset: BioPreset, name: String, text: String) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        presets[idx].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func delete(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        persist()
    }

    func delete(_ preset: BioPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BioPreset].self, from: data) else { return }
        presets = decoded
    }
}
