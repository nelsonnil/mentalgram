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

// MARK: - Interface Kind

/// Exclusive performance input interfaces. Only ONE kind may be active across
/// the active set + all bio/note {textN} sources at the same time, because there is
/// a single capture per performance feeding every consumer, and that capture can only
/// produce ONE type of value via ONE device. The same kind may repeat across set/bio/
/// notes (one capture fills all). Different kinds conflict.
///
/// Lockscreen and Clock each have two variants because the same physical device can
/// only be in one mode at a time (numbers OR cards), so e.g. a Number Lockscreen and a
/// Card Lockscreen cannot coexist.
enum InterfaceKind: String, Hashable {
    case ocr, numberClock, cardClock, numberLockscreen, cardLockscreen

    var displayName: String {
        switch self {
        case .ocr:              return "Camera (OCR)"
        case .numberClock:      return "Number Clock"
        case .cardClock:        return "Card Clock"
        case .numberLockscreen: return "Number Lockscreen"
        case .cardLockscreen:   return "Card Lockscreen"
        }
    }
}

// MARK: - API Source

enum ApiSource: Int, CaseIterable {
    case none             = 0
    case inject           = 1
    case custom1          = 2
    case custom2          = 3
    case custom3          = 4
    case ocr              = 5   // interface: camera recognises a word/card
    case numberLockscreen = 6   // interface: fake lockscreen digit entry → number (was .lockscreen)
    case numberClock      = 7   // interface: black screen swipe → number
    case cardClock        = 8   // interface: black screen swipe → card (value+suit)
    case cardLockscreen   = 9   // interface: fake lockscreen card code → card (value+suit)

    var displayName: String {
        switch self {
        case .none:             return "None"
        case .inject:           return "Inject"
        case .custom1:          return IntegrationsSettings.shared.customApi1Name.isEmpty ? "API 1" : IntegrationsSettings.shared.customApi1Name
        case .custom2:          return IntegrationsSettings.shared.customApi2Name.isEmpty ? "API 2" : IntegrationsSettings.shared.customApi2Name
        case .custom3:          return IntegrationsSettings.shared.customApi3Name.isEmpty ? "API 3" : IntegrationsSettings.shared.customApi3Name
        case .ocr:              return "OCR"
        case .numberLockscreen: return "Number Lockscreen"
        case .numberClock:      return "Number Clock"
        case .cardClock:        return "Card Clock"
        case .cardLockscreen:   return "Card Lockscreen"
        }
    }

    /// The exclusive interface kind this source requires (nil for polled API / none).
    var interfaceKind: InterfaceKind? {
        switch self {
        case .ocr:              return .ocr
        case .numberLockscreen: return .numberLockscreen
        case .numberClock:      return .numberClock
        case .cardClock:        return .cardClock
        case .cardLockscreen:   return .cardLockscreen
        default:                return nil
        }
    }

    /// Interface-family sources need an exclusive fullscreen UI / device event.
    var isInterfaceInput: Bool { interfaceKind != nil }

    /// Only API sources are polled; OCR and the clock/lockscreen interfaces are event-driven.
    var isPolled: Bool { self != .none && interfaceKind == nil }
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
        // Interface-family sources are captured live at performance, never polled here.
        case .ocr, .numberLockscreen, .cardLockscreen, .numberClock, .cardClock: return nil
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

    // MARK: - Interface conflict validation
    //
    // Only ONE interface kind (OCR / Lockscreen / Number Clock / Card Clock) may be
    // active across the active set + all bio/note {textN} sources at the same time,
    // because each needs its own dedicated screen/event. Polled API sources (Inject,
    // API 1-3) never conflict and may be mixed freely.

    /// Interface kind required by the currently-active set (nil if none / api / grid).
    /// Lockscreen resolves to its number/card variant based on the set type, because the
    /// lockscreen produces a number for number/custom sets and a card for card sets.
    private func activeSetInterfaceKind() -> InterfaceKind? {
        guard let id = ActiveSetSettings.shared.activeSetId,
              let set = DataManager.shared.sets.first(where: { $0.id == id }) else { return nil }
        switch set.resolvedInputMethod {
        case .ocr:        return .ocr
        case .clockInput: return .numberClock
        case .cardClock:  return .cardClock
        case .lockscreen: return set.type == .card ? .cardLockscreen : .numberLockscreen
        default:          return nil
        }
    }

    /// All (target, token, source) entries for bio + note templates.
    private var allTokenSourceEntries: [(target: String, token: String, source: ApiSource)] {
        [("bio",  "{text1}", bioText1Source),  ("bio",  "{text2}", bioText2Source),  ("bio",  "{text3}", bioText3Source),
         ("note", "{text1}", noteText1Source), ("note", "{text2}", noteText2Source), ("note", "{text3}", noteText3Source)]
    }

    /// Interface kinds currently in use, optionally excluding one token (the one being edited).
    func interfaceKindsInUse(excludingTarget: String? = nil, excludingToken: String? = nil) -> Set<InterfaceKind> {
        var kinds = Set<InterfaceKind>()
        if let k = activeSetInterfaceKind() { kinds.insert(k) }
        for e in allTokenSourceEntries {
            if e.target == excludingTarget && e.token == excludingToken { continue }
            if let k = e.source.interfaceKind { kinds.insert(k) }
        }
        return kinds
    }

    /// Whether `candidate` can be assigned to (target, token) without an interface conflict.
    /// Polled / none sources are always allowed. An interface source is allowed only when no
    /// other (different) interface kind is already in use anywhere.
    func canSelectSource(_ candidate: ApiSource, target: String, token: String) -> Bool {
        guard let candKind = candidate.interfaceKind else { return true }
        let others = interfaceKindsInUse(excludingTarget: target, excludingToken: token)
        return others.isEmpty || (others.count == 1 && others.first == candKind)
    }

    /// The interface kind already established elsewhere that blocks different interface
    /// selections for (target, token), or nil if none is established yet.
    func blockingInterfaceKind(target: String, token: String) -> InterfaceKind? {
        interfaceKindsInUse(excludingTarget: target, excludingToken: token).first
    }

    /// Human-readable list of locations where interface-family inputs are currently
    /// configured (excluding the slot being edited). Used to build conflict alert messages.
    /// Returns e.g. ["Active Set (Lockscreen)", "Biography {text2} (Number Clock)"]
    func conflictLocations(excludingTarget: String, excludingToken: String) -> [String] {
        var locations: [String] = []
        if let k = activeSetInterfaceKind() {
            let name = DataManager.shared.sets
                .first(where: { $0.id == ActiveSetSettings.shared.activeSetId })?.name ?? "Active Set"
            locations.append("\(name) (\(k.displayName))")
        }
        let targetLabels = ["bio": "Biography", "note": "Notes"]
        for e in allTokenSourceEntries {
            if e.target == excludingTarget && e.token == excludingToken { continue }
            guard let k = e.source.interfaceKind else { continue }
            let tLabel = targetLabels[e.target] ?? e.target
            locations.append("\(tLabel) \(e.token) (\(k.displayName))")
        }
        return locations
    }

    /// Clears all interface-family sources across bio and notes that conflict with
    /// `kind`, then assigns `kind`'s matching source to the given (target, token).
    /// Call this when the user taps "Continue" on the conflict alert.
    func resolveConflictAndSet(source: ApiSource, target: String, token: String) {
        guard let incomingKind = source.interfaceKind else {
            // Not an interface source — just assign directly
            setSource(source, target: target, token: token)
            return
        }
        // Clear any slot whose interface kind differs from incomingKind
        for e in allTokenSourceEntries {
            guard let k = e.source.interfaceKind, k != incomingKind else { continue }
            setSource(.none, target: e.target, token: e.token)
        }
        // Assign the new source to the edited slot
        setSource(source, target: target, token: token)
    }

    /// Sets a single source slot by (target, token).
    func setSource(_ source: ApiSource, target: String, token: String) {
        switch (target, token) {
        case ("note", "{text1}"): noteText1Source = source
        case ("note", "{text2}"): noteText2Source = source
        case ("note", "{text3}"): noteText3Source = source
        case ("bio",  "{text1}"): bioText1Source  = source
        case ("bio",  "{text2}"): bioText2Source  = source
        case ("bio",  "{text3}"): bioText3Source  = source
        default: break
        }
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
