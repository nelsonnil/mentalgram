import Foundation

protocol OCRDelegate: AnyObject {
    /// Called ONCE with the processed result (text, math result, or formatted date).
    func ocrDidRecognize(text: String, type: OCRStringType)
}
