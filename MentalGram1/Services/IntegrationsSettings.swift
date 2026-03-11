import Foundation
import Combine

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

    // Selected source per target ("bio" or "note")
    @Published var bioApiSource: ApiSource {
        didSet { UserDefaults.standard.set(bioApiSource.rawValue, forKey: "integ_bioApiSource") }
    }
    @Published var noteApiSource: ApiSource {
        didSet { UserDefaults.standard.set(noteApiSource.rawValue, forKey: "integ_noteApiSource") }
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
    }

    // MARK: - Fetch

    /// Returns the text fetched from the currently configured source for a given target.
    func fetchValue(for source: ApiSource) async -> String? {
        switch source {
        case .none:    return nil
        case .inject:  return await loadInjectApi(injectID: injectID)
        case .custom1: return await loadCustomApi(url: customApi1Url, field: customApi1Field)
        case .custom2: return await loadCustomApi(url: customApi2Url, field: customApi2Field)
        case .custom3: return await loadCustomApi(url: customApi3Url, field: customApi3Field)
        }
    }

    func fetchBioValue()  async -> String? { await fetchValue(for: bioApiSource) }
    func fetchNoteValue() async -> String? { await fetchValue(for: noteApiSource) }

    // MARK: - Inject (11z.co)

    func loadInjectApi(injectID: String) async -> String? {
        let cleanID = injectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return nil }
        guard let url = URL(string: "https://11z.co/_w/\(cleanID)/selection") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let v = json["value"] as? String, !v.isEmpty { return v }
                if let w = json["word"]  as? String, !w.isEmpty { return w }
                for (key, val) in json {
                    if let s = val as? String, !s.isEmpty, key != "id", key != "status" { return s }
                }
            }
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
            return nil
        } catch {
            print("❌ [INTEG] Inject fetch error: \(error)")
            return nil
        }
    }

    // MARK: - Custom API

    func loadCustomApi(url: String, field: String) async -> String? {
        let cleanUrl   = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty, !cleanField.isEmpty,
              let apiURL = URL(string: cleanUrl) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            if let v = json[cleanField] as? String { return v }
            if let v = json[cleanField] { return String(describing: v) }
            return nil
        } catch {
            print("❌ [INTEG] Custom API fetch error: \(error)")
            return nil
        }
    }
}
