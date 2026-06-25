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

        let language = languageCode(for: clean, locale: locale)
        var usageIndex: [String: Int] = [:]
        var lines: [String] = []

        for token in tokens(for: clean, language: language) {
            lines.append(line(for: token, language: language, usageIndex: &usageIndex))
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
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = languageCode(for: clean, locale: locale)
        var usageIndex: [String: Int] = [:]
        var pairs: [(String, String)] = []

        for token in tokens(for: clean, language: language) {
            let text = line(for: token, language: language, usageIndex: &usageIndex)
            pairs.append((token, text))
        }
        return pairs
    }

    // MARK: - Private helpers

    private static let vietnameseCharacterSet = CharacterSet(charactersIn: "ĂăÂâĐđÊêÔôƠơƯưÁáÀàẢảÃãẠạẮắẰằẲẳẴẵẶặẤấẦầẨẩẪẫẬậÉéÈèẺẻẼẽẸẹẾếỀềỂểỄễỆệÍíÌìỈỉĨĩỊịÓóÒòỎỏÕõỌọỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợÚúÙùỦủŨũỤụỨứỪừỬửỮữỰựÝýỲỳỶỷỸỹỴỵ")

    private static func languageCode(for word: String, locale: Locale) -> String {
        let localeLanguage = locale.language.languageCode?.identifier ?? "en"
        if localeLanguage.lowercased().hasPrefix("vi") {
            return "vi"
        }
        if word.rangeOfCharacter(from: vietnameseCharacterSet) != nil {
            return "vi"
        }
        return localeLanguage
    }

    /// Tokeniza la palabra letra por letra.
    /// Vietnamita se escribe letra por letra (C+H+Ó = 3 letras, no un cluster).
    private static func tokens(for word: String, language: String) -> [String] {
        let upper = word.uppercased()
        return upper.map { String($0) }
    }

    /// Produces the bio line for a single character or language-specific token.
    private static func line(for token: String,
                              language: String,
                              usageIndex: inout [String: Int]) -> String {
        if token.count == 1, let char = token.first, char.isNumber {
            return digitLine(startingWith: char)
        } else {
            return letterLine(for: token, language: language, usageIndex: &usageIndex)
        }
    }

    /// Digit rule: the digit itself + 5 random digits = 6-character string.
    private static func digitLine(startingWith digit: Character) -> String {
        let randomDigits = (0..<5).map { _ in String(Int.random(in: 0...9)) }.joined()
        return String(digit) + randomDigits
    }

    /// Letter rule: a real word from AcrosticWordBank starting with that letter.
    private static func letterLine(for token: String,
                                   language: String,
                                   usageIndex: inout [String: Int]) -> String {
        let key = token.uppercased()
        let words = AcrosticWordBank.words(forKey: key, language: language)
        let index = usageIndex[key, default: 0] % words.count
        usageIndex[key] = index + 1
        return words[index]
    }
}
