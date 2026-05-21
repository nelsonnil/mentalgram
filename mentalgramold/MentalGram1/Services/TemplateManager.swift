import SwiftUI

// MARK: - Letter Template

struct LetterTemplate: Identifiable, Equatable {
    let id: String           // folder name, e.g. "Original"
    let name: String         // display name, e.g. "Original"
    let alphabet: AlphabetType
    let folderPath: String   // relative inside bundle: "letras/{alphabet}/{id}"

    static func == (lhs: LetterTemplate, rhs: LetterTemplate) -> Bool {
        lhs.id == rhs.id && lhs.alphabet == rhs.alphabet
    }
}

// MARK: - Template Manager

final class TemplateManager {
    static let shared = TemplateManager()
    private init() {}

    // MARK: - Discover templates

    /// Returns all available templates for a given alphabet, sorted by name.
    func templates(for alphabet: AlphabetType) -> [LetterTemplate] {
        let folderName = alphabetFolderName(alphabet)
        guard let baseURL = Bundle.main.url(
                forResource: folderName,
                withExtension: nil,
                subdirectory: "letras") else {
            return []
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles) else {
            return []
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url in
                let templateId = url.lastPathComponent
                return LetterTemplate(
                    id: templateId,
                    name: templateId,
                    alphabet: alphabet,
                    folderPath: "letras/\(folderName)/\(templateId)"
                )
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Load preview images (first N letters)

    /// Returns UIImages for the first `count` letters of the template, for previewing.
    func previewImages(for template: LetterTemplate, count: Int = 4) -> [UIImage] {
        let letters = Array(template.alphabet.characters.prefix(count))
        return letters.compactMap { letter in
            imageData(for: letter, template: template).flatMap { UIImage(data: $0) }
        }
    }

    // MARK: - Load all photos for set creation

    /// Loads all letter images for the template and returns them ready to pass to DataManager.createSet.
    func photos(for template: LetterTemplate) -> [(symbol: String, filename: String, imageData: Data)] {
        template.alphabet.characters.compactMap { letter in
            guard let data = imageData(for: letter, template: template) else { return nil }
            let filename = "\(letter.lowercased())_template.jpg"
            return (symbol: letter, filename: filename, imageData: data)
        }
    }

    // MARK: - Image data for a single letter

    func imageData(for letter: String, template: LetterTemplate) -> Data? {
        let folderName = alphabetFolderName(template.alphabet)
        let extensions = ["jpg", "jpeg", "png", "PNG", "JPG"]

        for ext in extensions {
            if let url = Bundle.main.url(
                forResource: letter,
                withExtension: ext,
                subdirectory: "letras/\(folderName)/\(template.id)") {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Maps AlphabetType to the folder name inside `letras/`.
    /// Only alphabets with an existing folder will return templates.
    private func alphabetFolderName(_ alphabet: AlphabetType) -> String {
        switch alphabet {
        case .latin:      return "latin"
        case .spanish:    return "español"
        case .german:     return "alemán"
        case .french:     return "francés"
        case .portuguese: return "portugués"
        default:          return alphabet.rawValue
        }
    }
}
