import Foundation
import Combine

// MARK: - Auto Input Mode

enum AutoInputMode: String, CaseIterable {
    case off        = "off"
    case clipboard  = "clipboard"
    case api        = "api"
    case ocr        = "ocr"
    case clockInput = "clockInput"

    var displayName: String {
        switch self {
        case .off:        return "Off"
        case .clipboard:  return "Clipboard"
        case .api:        return "API"
        case .ocr:        return "OCR"
        case .clockInput: return "Clock"
        }
    }

    var icon: String {
        switch self {
        case .off:        return "minus.circle"
        case .clipboard:  return "doc.on.clipboard"
        case .api:        return "bolt.fill"
        case .ocr:        return "camera.viewfinder"
        case .clockInput: return "hand.draw.fill"
        }
    }
}

// MARK: - API Source

enum ApiSource: Int, CaseIterable {
    case none       = 0
    case inject     = 1
    case custom1    = 2
    case custom2    = 3
    case custom3    = 4
    case ocr        = 5   // event-driven — not polled, filled when camera recognises a word

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .inject:  return "Inject"
        case .custom1: return IntegrationsSettings.shared.customApi1Name.isEmpty ? "API 1" : IntegrationsSettings.shared.customApi1Name
        case .custom2: return IntegrationsSettings.shared.customApi2Name.isEmpty ? "API 2" : IntegrationsSettings.shared.customApi2Name
        case .custom3: return IntegrationsSettings.shared.customApi3Name.isEmpty ? "API 3" : IntegrationsSettings.shared.customApi3Name
        case .ocr:     return "OCR"
        }
    }

    /// OCR is event-driven, not polled — exclude it from API polling loops.
    var isPolled: Bool { self != .none && self != .ocr }
}

struct ApiFetchedValue {
    let value: String
    let changeToken: String
}

// MARK: - IntegrationsSettings

final class IntegrationsSettings: ObservableObject {
    static let shared = IntegrationsSettings()

    // Inject
    @Published var injectID: String {
        didSet { UserDefaults.standard.set(injectID, forKey: "integ_injectID") }
    }

    // Custom API names (user-defined labels shown in pickers)
    @Published var customApi1Name: String {
        didSet { UserDefaults.standard.set(customApi1Name, forKey: "integ_custom1Name") }
    }
    @Published var customApi2Name: String {
        didSet { UserDefaults.standard.set(customApi2Name, forKey: "integ_custom2Name") }
    }
    @Published var customApi3Name: String {
        didSet { UserDefaults.standard.set(customApi3Name, forKey: "integ_custom3Name") }
    }

    // Custom APIs
    @Published var customApi1Url: String {
        didSet { UserDefaults.standard.set(customApi1Url, forKey: "integ_custom1Url") }
    }
    @Published var customApi1Field: String {
        didSet { UserDefaults.standard.set(customApi1Field, forKey: "integ_custom1Field") }
    }
    @Published var customApi2Url: String {
        didSet { UserDefaults.standard.set(customApi2Url, forKey: "integ_custom2Url") }
    }
    @Published var customApi2Field: String {
        didSet { UserDefaults.standard.set(customApi2Field, forKey: "integ_custom2Field") }
    }
    @Published var customApi3Url: String {
        didSet { UserDefaults.standard.set(customApi3Url, forKey: "integ_custom3Url") }
    }
    @Published var customApi3Field: String {
        didSet { UserDefaults.standard.set(customApi3Field, forKey: "integ_custom3Field") }
    }

    // Selected source per target ("bio", "note", "pp") — legacy single-source (maps to text1)
    @Published var bioApiSource: ApiSource {
        didSet { UserDefaults.standard.set(bioApiSource.rawValue, forKey: "integ_bioApiSource") }
    }
    @Published var noteApiSource: ApiSource {
        didSet { UserDefaults.standard.set(noteApiSource.rawValue, forKey: "integ_noteApiSource") }
    }
    @Published var ppApiSource: ApiSource {
        didSet { UserDefaults.standard.set(ppApiSource.rawValue, forKey: "integ_ppApiSource") }
    }

    // Per-placeholder sources for Note template
    @Published var noteText1Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText1Source.rawValue, forKey: "integ_noteText1Source") }
    }
    @Published var noteText2Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText2Source.rawValue, forKey: "integ_noteText2Source") }
    }
    @Published var noteText3Source: ApiSource {
        didSet { UserDefaults.standard.set(noteText3Source.rawValue, forKey: "integ_noteText3Source") }
    }

    // Per-placeholder sources for Bio template
    @Published var bioText1Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText1Source.rawValue, forKey: "integ_bioText1Source") }
    }
    @Published var bioText2Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText2Source.rawValue, forKey: "integ_bioText2Source") }
    }
    @Published var bioText3Source: ApiSource {
        didSet { UserDefaults.standard.set(bioText3Source.rawValue, forKey: "integ_bioText3Source") }
    }

    private init() {
        let ud = UserDefaults.standard
        injectID        = ud.string(forKey: "integ_injectID")       ?? ""
        customApi1Name  = ud.string(forKey: "integ_custom1Name")    ?? ""
        customApi2Name  = ud.string(forKey: "integ_custom2Name")    ?? ""
        customApi3Name  = ud.string(forKey: "integ_custom3Name")    ?? ""
        customApi1Url   = ud.string(forKey: "integ_custom1Url")     ?? ""
        customApi1Field = ud.string(forKey: "integ_custom1Field")   ?? ""
        customApi2Url   = ud.string(forKey: "integ_custom2Url")     ?? ""
        customApi2Field = ud.string(forKey: "integ_custom2Field")   ?? ""
        customApi3Url   = ud.string(forKey: "integ_custom3Url")     ?? ""
        customApi3Field = ud.string(forKey: "integ_custom3Field")   ?? ""
        bioApiSource    = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteApiSource   = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        ppApiSource     = ApiSource(rawValue: ud.integer(forKey: "integ_ppApiSource"))   ?? .none
        // Per-placeholder sources — migrate legacy single-source on first launch
        let legacyNote  = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        let legacyBio   = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteText1Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText1Source")) ?? legacyNote
        noteText2Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText2Source")) ?? .none
        noteText3Source = ApiSource(rawValue: ud.integer(forKey: "integ_noteText3Source")) ?? .none
        bioText1Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText1Source"))  ?? legacyBio
        bioText2Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText2Source"))  ?? .none
        bioText3Source  = ApiSource(rawValue: ud.integer(forKey: "integ_bioText3Source"))  ?? .none
    }

    // MARK: - Fetch

    /// Returns the text fetched from the currently configured source for a given target.
    func fetchValue(for source: ApiSource) async -> String? {
        guard let payload = await fetchPayload(for: source) else { return nil }
        return payload.value
    }

    /// Returns the fetched value plus a token used for change detection.
    /// Inject exposes `count`, so we use it to avoid reacting to the last stored input on app launch.
    func fetchPayload(for source: ApiSource) async -> ApiFetchedValue? {
        switch source {
        case .none:    return nil
        case .inject:  return await loadInjectApiPayload(injectID: injectID)
        case .custom1: return await loadCustomApiPayload(url: customApi1Url, field: customApi1Field)
        case .custom2: return await loadCustomApiPayload(url: customApi2Url, field: customApi2Field)
        case .custom3: return await loadCustomApiPayload(url: customApi3Url, field: customApi3Field)
        case .ocr:     return nil  // event-driven — not polled
        }
    }

    func fetchBioValue()  async -> String? { await fetchValue(for: bioApiSource) }
    func fetchNoteValue() async -> String? { await fetchValue(for: noteApiSource) }
    func fetchPPValue()   async -> String? { await fetchValue(for: ppApiSource) }

    /// Fetches all three placeholder values for a given target ("note" or "bio") in parallel.
    /// Returns a dict: ["text1": value, "text2": value, "text3": value] (only non-nil entries).
    /// Fetches API-polled placeholder values in parallel (skips .ocr — that is event-driven).
    /// Pass `ocrValues` to inject already-captured OCR words into the correct slots.
    func fetchTemplatePlaceholders(for target: String, ocrValues: [String: String] = [:]) async -> [String: String] {
        let s1 = target == "note" ? noteText1Source : bioText1Source
        let s2 = target == "note" ? noteText2Source : bioText2Source
        let s3 = target == "note" ? noteText3Source : bioText3Source

        async let v1 = s1.isPolled ? fetchValue(for: s1) : nil
        async let v2 = s2.isPolled ? fetchValue(for: s2) : nil
        async let v3 = s3.isPolled ? fetchValue(for: s3) : nil
        let (r1, r2, r3) = await (v1, v2, v3)

        var result: [String: String] = [:]
        if let r1 { result["text1"] = r1 }
        if let r2 { result["text2"] = r2 }
        if let r3 { result["text3"] = r3 }
        // Inject OCR-captured values for slots assigned to .ocr
        if s1 == .ocr, let v = ocrValues["text1"] { result["text1"] = v }
        if s2 == .ocr, let v = ocrValues["text2"] ?? ocrValues["text1"] { result["text2"] = v }
        if s3 == .ocr, let v = ocrValues["text3"] ?? ocrValues["text1"] { result["text3"] = v }
        return result
    }

    /// Returns true if any placeholder source is configured for the given target (excluding .none).
    func hasTemplateSources(for target: String) -> Bool {
        if target == "note" {
            return noteText1Source != .none || noteText2Source != .none || noteText3Source != .none
        }
        return bioText1Source != .none || bioText2Source != .none || bioText3Source != .none
    }

    /// Returns which slot (1/2/3) is assigned to OCR for the given target, or nil if none.
    func ocrSlot(for target: String) -> Int? {
        let sources = target == "note"
            ? [noteText1Source, noteText2Source, noteText3Source]
            : [bioText1Source,  bioText2Source,  bioText3Source]
        return sources.firstIndex(of: .ocr).map { $0 + 1 }
    }

    // MARK: - Inject (11z.co)

    func loadInjectApi(injectID: String) async -> String? {
        await loadInjectApiPayload(injectID: injectID)?.value
    }

    func loadInjectApiPayload(injectID: String) async -> ApiFetchedValue? {
        let cleanID = injectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return nil }
        guard let url = URL(string: "https://11z.co/_w/\(cleanID)/selection") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let token = Self.injectChangeToken(from: json)
                for key in ["value", "word", "selection", "input", "text"] {
                    if let value = Self.nonEmptyString(from: json[key]) {
                        return ApiFetchedValue(value: value, changeToken: token ?? value)
                    }
                }
                for (key, val) in json {
                    if let s = Self.nonEmptyString(from: val), !Self.injectMetadataKeys.contains(key) {
                        return ApiFetchedValue(value: s, changeToken: token ?? s)
                    }
                }
            }
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return ApiFetchedValue(value: text, changeToken: text)
            }
            return nil
        } catch {
            print("❌ [INTEG] Inject fetch error: \(error)")
            return nil
        }
    }

    // MARK: - Custom API

    func loadCustomApi(url: String, field: String) async -> String? {
        await loadCustomApiPayload(url: url, field: field)?.value
    }

    func loadCustomApiPayload(url: String, field: String) async -> ApiFetchedValue? {
        let cleanUrl   = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty, !cleanField.isEmpty,
              let apiURL = URL(string: cleanUrl) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            if let v = json[cleanField] as? String {
                return ApiFetchedValue(value: v, changeToken: v)
            }
            if let v = json[cleanField] {
                let value = String(describing: v)
                return ApiFetchedValue(value: value, changeToken: value)
            }
            return nil
        } catch {
            print("❌ [INTEG] Custom API fetch error: \(error)")
            return nil
        }
    }

    private static let injectMetadataKeys: Set<String> = [
        "count", "id", "status", "created_at", "updated_at", "timestamp"
    ]

    private static func injectChangeToken(from json: [String: Any]) -> String? {
        guard let rawCount = json["count"] else { return nil }
        if let count = rawCount as? Int {
            return "count:\(count)"
        }
        if let count = rawCount as? Int64 {
            return "count:\(count)"
        }
        if let count = rawCount as? Double {
            return "count:\(count)"
        }
        let token = String(describing: rawCount).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : "count:\(token)"
    }

    private static func nonEmptyString(from value: Any?) -> String? {
        guard let value else { return nil }
        let string: String
        if let value = value as? String {
            string = value
        } else if value is NSNull {
            return nil
        } else {
            string = String(describing: value)
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
