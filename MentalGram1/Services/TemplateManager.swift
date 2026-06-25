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

// MARK: - Number Template

struct NumberTemplate: Identifiable, Equatable {
    let id: String           // folder name, e.g. "Default"
    let name: String         // display name
    let folderPath: String   // relative inside bundle: "number/{id}"

    static func == (lhs: NumberTemplate, rhs: NumberTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Card Template

struct CardTemplate: Identifiable, Equatable {
    let id: String           // folder name, e.g. "deck"
    let name: String         // display name
    let folderPath: String   // relative inside bundle: "cards/{id}"

    static func == (lhs: CardTemplate, rhs: CardTemplate) -> Bool {
        lhs.id == rhs.id
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

    // MARK: - Number Templates

    /// Returns all available number templates, sorted by name.
    func numberTemplates() -> [NumberTemplate] {
        guard let baseURL = Bundle.main.url(forResource: "number", withExtension: nil) else {
            return []
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles) else {
            return []
        }
        let subfolders = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url in
                let templateId = url.lastPathComponent
                return NumberTemplate(
                    id: templateId,
                    name: templateId,
                    folderPath: "number/\(templateId)"
                )
            }
            .sorted { $0.name < $1.name }

        return subfolders
    }

    /// Returns UIImages for the first `count` digits of the number template, for previewing.
    func previewImages(for template: NumberTemplate, count: Int = 4) -> [UIImage] {
        let digits = Array(["0","1","2","3","4","5","6","7","8","9"].prefix(count))
        return digits.compactMap { digit in
            numberImageData(for: digit, template: template).flatMap { UIImage(data: $0) }
        }
    }

    /// Loads all digit images for the template and returns them ready to pass to DataManager.createSet.
    func photos(for template: NumberTemplate) -> [(symbol: String, filename: String, imageData: Data)] {
        if let firstBank = numberTemplateBankFolders(for: template).first {
            return photos(for: template, bankFolder: firstBank.name, bankPosition: firstBank.position)
        }

        return ["0","1","2","3","4","5","6","7","8","9"].compactMap { digit -> (symbol: String, filename: String, imageData: Data)? in
            guard let data = numberImageData(for: digit, template: template) else { return nil }
            let filename = "\(digit)_template.jpg"
            return (symbol: digit, filename: filename, imageData: data)
        }
    }

    /// Loads a banked number template as bank position -> digit photos.
    func bankedPhotos(for template: NumberTemplate) -> [Int: [(symbol: String, filename: String, imageData: Data)]] {
        Dictionary(
            uniqueKeysWithValues: numberTemplateBankFolders(for: template).map { bank in
                (bank.position, photos(for: template, bankFolder: bank.name, bankPosition: bank.position))
            }
        )
    }

    func bankCount(for template: NumberTemplate) -> Int? {
        let count = numberTemplateBankFolders(for: template).count
        return count > 0 ? count : nil
    }

    /// Image data for a single digit from a number template.
    func numberImageData(for digit: String, template: NumberTemplate) -> Data? {
        let extensions = ["jpg", "jpeg", "png", "PNG", "JPG"]
        for ext in extensions {
            if let url = Bundle.main.url(
                forResource: digit,
                withExtension: ext,
                subdirectory: template.folderPath) {
                return try? Data(contentsOf: url)
            }
        }

        if let firstBank = numberTemplateBankFolders(for: template).first {
            return numberImageData(for: digit, template: template, bankFolder: firstBank.name)
        }

        return nil
    }

    // MARK: - Card Templates

    /// Returns all available playing-card templates, sorted by name.
    func cardTemplates() -> [CardTemplate] {
        guard let baseURL = Bundle.main.url(forResource: "cards", withExtension: nil) else {
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
                return CardTemplate(
                    id: templateId,
                    name: templateId,
                    folderPath: "cards/\(templateId)"
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Returns UIImages for the first `count` cards of the template, for previewing.
    func previewImages(for template: CardTemplate, count: Int = 4) -> [UIImage] {
        let symbols = Array(SetType.cardSlotLabels.prefix(count))
        return symbols.compactMap { symbol in
            cardImageData(for: symbol, template: template).flatMap { UIImage(data: $0) }
        }
    }

    /// Loads all 52 card images for the template and returns them ready for set creation.
    func photos(for template: CardTemplate) -> [(symbol: String, filename: String, imageData: Data)] {
        SetType.cardSlotLabels.compactMap { symbol in
            guard let data = cardImageData(for: symbol, template: template),
                  let fileStem = cardFileStem(for: symbol) else { return nil }
            let filename = "\(fileStem)_template.jpg"
            return (symbol: symbol, filename: filename, imageData: data)
        }
    }

    /// Image data for a single playing card from a card template.
    func cardImageData(for symbol: String, template: CardTemplate) -> Data? {
        guard let fileStem = cardFileStem(for: symbol) else { return nil }
        let extensions = ["jpg", "jpeg", "png", "PNG", "JPG"]
        for ext in extensions {
            if let url = Bundle.main.url(
                forResource: fileStem,
                withExtension: ext,
                subdirectory: template.folderPath) {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func numberTemplateBankFolders(for template: NumberTemplate) -> [(position: Int, name: String)] {
        guard let baseURL = Bundle.main.url(
            forResource: template.id,
            withExtension: nil,
            subdirectory: "number"
        ) else {
            return []
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let name = url.lastPathComponent
            let digits = name.filter(\.isNumber)
            guard let position = Int(digits), position > 0 else { return nil }
            return (position, name)
        }
        .sorted { $0.position < $1.position }
    }

    private func photos(
        for template: NumberTemplate,
        bankFolder: String,
        bankPosition: Int
    ) -> [(symbol: String, filename: String, imageData: Data)] {
        return ["0","1","2","3","4","5","6","7","8","9"].compactMap { digit -> (symbol: String, filename: String, imageData: Data)? in
            guard let data = numberImageData(for: digit, template: template, bankFolder: bankFolder) else {
                return nil
            }
            let filename = "\(digit)_bank\(bankPosition)_template.jpg"
            return (symbol: digit, filename: filename, imageData: data)
        }
    }

    private func numberImageData(for digit: String, template: NumberTemplate, bankFolder: String) -> Data? {
        let extensions = ["jpg", "jpeg", "png", "PNG", "JPG"]
        for ext in extensions {
            if let url = Bundle.main.url(
                forResource: digit,
                withExtension: ext,
                subdirectory: "\(template.folderPath)/\(bankFolder)") {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    private func cardFileStem(for symbol: String) -> String? {
        let suitMap: [Character: String] = ["♠": "S", "♥": "H", "♣": "C", "♦": "D"]
        guard let suit = symbol.last,
              let suffix = suitMap[suit] else { return nil }

        let value = String(symbol.dropLast())
        guard !value.isEmpty else { return nil }
        return value + suffix
    }

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
