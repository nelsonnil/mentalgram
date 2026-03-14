import Foundation
import JavaScriptCore

struct OCRTextValidator {

    // MARK: - Classification

    static func classify(_ raw: String) -> OCRStringType {
        let text = raw.replacingOccurrences(of: " ", with: "")

        if text.contains("=") {
            return .operation
        }

        if text.contains("/") || text.contains("-") || text.contains("\\") {
            if let date = parseDate(text) {
                return .date(date)
            }
        }

        return .text
    }

    // MARK: - Math operations

    static func evaluateOperation(_ raw: String) -> String {
        let expr = sanitizeForMath(raw)

        let validChars = CharacterSet(charactersIn: "0123456789+-*/().")
        guard expr.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return raw
        }

        guard let result = JSContext().evaluateScript(expr)?.toDouble(),
              !result.isNaN, !result.isInfinite else {
            return raw
        }

        return floor(result) == result ? "\(Int(result))" : String(format: "%.2f", result)
    }

    /// Replaces characters that OCR commonly confuses with digits/operators.
    static func sanitizeForMath(_ text: String) -> String {
        text
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: ":", with: "/")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "z", with: "2")
            .replacingOccurrences(of: "Z", with: "2")
            .replacingOccurrences(of: "E", with: "3")
            .replacingOccurrences(of: "A", with: "4")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "s", with: "5")
            .replacingOccurrences(of: "b", with: "6")
            .replacingOccurrences(of: "T", with: "7")
            .replacingOccurrences(of: "L", with: "7")
            .replacingOccurrences(of: "B", with: "8")
            .replacingOccurrences(of: "g", with: "9")
            .replacingOccurrences(of: "q", with: "9")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "O", with: "0")
    }

    // MARK: - Dates

    static func parseDate(_ text: String, usMonthFirst: Bool = false) -> Date? {
        let formatter = DateFormatter()
        let formats: [String] = usMonthFirst
            ? ["MM-dd-yy", "MM-dd-yyyy", "MM/dd/yy", "MM/dd/yyyy", "MM-dd", "MM/dd"]
            : ["dd-MM-yy", "dd-MM-yyyy", "dd/MM/yy", "dd/MM/yyyy", "dd-MM", "dd/MM"]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}
