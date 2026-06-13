import Foundation

// MARK: - Acrostic Engine
//
// Converts a word into an acrostic bio text.
// Each letter of the input word becomes one line of the bio,
// where that line starts with the corresponding letter.
//
// Rotation: if the same letter appears more than once, the engine
// cycles through the 3 available words so the same word is never repeated.
//
// Example  →  "BANANA"
//   B → Barco
//   A → Árbol       (A[0])
//   N → Norte       (N[0])
//   A → Avión       (A[1], different from Árbol)
//   N → Nube        (N[1], different from Norte)
//   A → Azul        (A[2])

struct AcrosticEngine {

    // Returns the acrostic bio string, or nil if the input is empty.
    // Each letter produces one line; lines are joined by "\n".
    static func build(word: String, locale: Locale = .current) -> String? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let language = locale.language.languageCode?.identifier ?? "en"
        var usageIndex: [String: Int] = [:]   // tracks rotation per letter
        var lines: [String] = []

        for char in clean.uppercased() {
            let key = String(char)
            let words = AcrosticWordBank.words(for: char, language: language)
            let index = usageIndex[key, default: 0] % words.count
            lines.append(words[index])
            usageIndex[key] = index + 1
        }

        let result = lines.joined(separator: "\n")

        // Instagram bio limit is 150 characters
        if result.count > 150 {
            // Trim lines from the end until it fits
            var trimmed = lines
            while trimmed.joined(separator: "\n").count > 150, !trimmed.isEmpty {
                trimmed.removeLast()
            }
            return trimmed.isEmpty ? nil : trimmed.joined(separator: "\n")
        }

        return result
    }

    // Preview helper — returns an array of (letter, word) pairs for display
    static func preview(word: String, locale: Locale = .current) -> [(letter: String, word: String)] {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let language = locale.language.languageCode?.identifier ?? "en"
        var usageIndex: [String: Int] = [:]
        var pairs: [(String, String)] = []

        for char in clean {
            let key = String(char)
            let words = AcrosticWordBank.words(for: char, language: language)
            let index = usageIndex[key, default: 0] % words.count
            pairs.append((key, words[index]))
            usageIndex[key] = index + 1
        }
        return pairs
    }
}
