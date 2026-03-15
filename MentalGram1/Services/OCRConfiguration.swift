import AVFoundation

struct OCRConfiguration {
    /// Recognition language. Persisted to UserDefaults key "ocr_language".
    var language: String = "es-ES"
    /// Camera position. Persisted to UserDefaults key "ocr_camera" (0=back, 1=front).
    var cameraPosition: AVCaptureDevice.Position = .back
    /// Minimum character count for a candidate to be considered valid.
    var minimumWordSize: Int = 2
    /// Times the same text must appear consecutively to be confirmed.
    var occurrences: Int = 3
    /// Whether to apply Vision language correction (disable for exact word/number recognition).
    var useLanguageCorrection: Bool = false

    // MARK: - Supported languages

    static let supportedLanguages: [(display: String, code: String)] = [
        ("Español",   "es-ES"),
        ("English",   "en-US"),
        ("Français",  "fr-FR"),
        ("Deutsch",   "de-DE"),
        ("Italiano",  "it-IT"),
        ("Português", "pt-BR"),
        ("中文",       "zh-Hans"),
        ("日本語",     "ja-JP"),
        ("한국어",     "ko-KR"),
        ("Русский",   "ru-RU"),
        ("العربية",   "ar-SA")
    ]

    static func displayName(for code: String) -> String {
        supportedLanguages.first { $0.code == code }?.display ?? code
    }

    // MARK: - Load from UserDefaults

    static func fromUserDefaults() -> OCRConfiguration {
        let ud = UserDefaults.standard
        let lang = ud.string(forKey: "ocr_language") ?? "es-ES"
        let cam: AVCaptureDevice.Position = ud.integer(forKey: "ocr_camera") == 1 ? .front : .back
        return OCRConfiguration(language: lang, cameraPosition: cam)
    }
}
