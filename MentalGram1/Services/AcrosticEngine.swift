import Foundation

// MARK: - Acrostic Engine
//
// Converts a prediction into an acrostic bio text.
//
// • Letter character → one line = a real word in the user's language that
//   starts with that letter (from AcrosticWordBank). Repeated letters rotate
//   through the word list so no word is reused.
//
// • Digit character → one line = that digit followed by 5 random digits,
//   giving a 6-digit string that looks like a real phone-like number.
//
// • Mixed input (e.g. "3c") → each character is handled by its own rule.
//
// Examples
//   "12"  → "134543"   (1 + 5 random digits)
//           "287461"   (2 + 5 random digits)
//
//   "354" → "367821"
//           "541093"
//           "428754"
//
//   "3c"  → "391045"   (digit rule)
//           "Caracol"  (letter rule, Spanish)

struct AcrosticEngine {

    // MARK: - Public API

    /// Builds the acrostic bio string, or nil if the input is empty.
    /// Lines are joined by "\n" and trimmed to the Instagram 150-char limit.
    static func build(word: String, locale: Locale = .current) -> String? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let language = locale.language.languageCode?.identifier ?? "en"
        var usageIndex: [String: Int] = [:]
        var lines: [String] = []

        for char in clean.uppercased() {
            lines.append(line(for: char, language: language, usageIndex: &usageIndex))
        }

        let result = lines.joined(separator: "\n")

        // Instagram bio limit is 150 characters — trim from the end if needed.
        if result.count > 150 {
            var trimmed = lines
            while trimmed.joined(separator: "\n").count > 150, !trimmed.isEmpty {
                trimmed.removeLast()
            }
            return trimmed.isEmpty ? nil : trimmed.joined(separator: "\n")
        }

        return result
    }

    /// Preview helper — returns an array of (character, line) pairs for display.
    static func preview(word: String, locale: Locale = .current) -> [(letter: String, word: String)] {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let language = locale.language.languageCode?.identifier ?? "en"
        var usageIndex: [String: Int] = [:]
        var pairs: [(String, String)] = []

        for char in clean {
            let key  = String(char)
            let text = line(for: char, language: language, usageIndex: &usageIndex)
            pairs.append((key, text))
        }
        return pairs
    }

    // MARK: - Private helpers

    /// Produces the bio line for a single character.
    private static func line(for char: Character,
                              language: String,
                              usageIndex: inout [String: Int]) -> String {
        if char.isNumber {
            return digitLine(startingWith: char)
        } else {
            return letterLine(for: char, language: language, usageIndex: &usageIndex)
        }
    }

    /// Digit rule: the digit itself + 5 random digits = 6-character string.
    private static func digitLine(startingWith digit: Character) -> String {
        let randomDigits = (0..<5).map { _ in String(Int.random(in: 0...9)) }.joined()
        return String(digit) + randomDigits
    }

    /// Letter rule: a real word from AcrosticWordBank starting with that letter.
    private static func letterLine(for char: Character,
                                   language: String,
                                   usageIndex: inout [String: Int]) -> String {
        let key   = String(char)
        let words = AcrosticWordBank.words(for: char, language: language)
        let index = usageIndex[key, default: 0] % words.count
        usageIndex[key] = index + 1
        return words[index]
    }
}
