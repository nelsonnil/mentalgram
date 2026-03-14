import Foundation

enum OCRStringType {
    case text           // Plain text, delivered as-is
    case operation      // Math expression → delivers calculated result
    case date(Date)     // Date → delivers formatted string
}
