import Foundation
import Combine

// MARK: - Auto Input Mode

enum AutoInputMode: String, CaseIterable {
    case off       = "off"
    case clipboard = "clipboard"
    case api       = "api"
    case ocr       = "ocr"

    var displayName: String {
        switch self {
        case .off:       return "Off"
        case .clipboard: return "Clipboard"
        case .api:       return "API"
        case .ocr:       return "OCR"
        }
    }

    var icon: String {
        switch self {
        case .off:       return "minus.circle"
        case .clipboard: return "doc.on.clipboard"
        case .api:       return "bolt.fill"
        case .ocr:       return "camera.viewfinder"
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

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .inject:  return "Inject"
        case .custom1: return "Custom API 1"
        case .custom2: return "Custom API 2"
        case .custom3: return "Custom API 3"
        }
    }
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

    // Selected source per target ("bio", "note", "pp")
    @Published var bioApiSource: ApiSource {
        didSet { UserDefaults.standard.set(bioApiSource.rawValue, forKey: "integ_bioApiSource") }
    }
    @Published var noteApiSource: ApiSource {
        didSet { UserDefaults.standard.set(noteApiSource.rawValue, forKey: "integ_noteApiSource") }
    }
    @Published var ppApiSource: ApiSource {
        didSet { UserDefaults.standard.set(ppApiSource.rawValue, forKey: "integ_ppApiSource") }
    }

    private init() {
        let ud = UserDefaults.standard
        injectID      = ud.string(forKey: "integ_injectID")      ?? ""
        customApi1Url = ud.string(forKey: "integ_custom1Url")    ?? ""
        customApi1Field = ud.string(forKey: "integ_custom1Field") ?? ""
        customApi2Url = ud.string(forKey: "integ_custom2Url")    ?? ""
        customApi2Field = ud.string(forKey: "integ_custom2Field") ?? ""
        customApi3Url = ud.string(forKey: "integ_custom3Url")    ?? ""
        customApi3Field = ud.string(forKey: "integ_custom3Field") ?? ""
        bioApiSource  = ApiSource(rawValue: ud.integer(forKey: "integ_bioApiSource"))  ?? .none
        noteApiSource = ApiSource(rawValue: ud.integer(forKey: "integ_noteApiSource")) ?? .none
        ppApiSource   = ApiSource(rawValue: ud.integer(forKey: "integ_ppApiSource"))   ?? .none
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
        }
    }

    func fetchBioValue()  async -> String? { await fetchValue(for: bioApiSource) }
    func fetchNoteValue() async -> String? { await fetchValue(for: noteApiSource) }
    func fetchPPValue()   async -> String? { await fetchValue(for: ppApiSource) }

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
