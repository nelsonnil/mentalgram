import Foundation
import Combine

/// Handles incoming URL scheme actions and stores them for PerformanceView to consume.
///
/// Supported URLs:
///   vault://note?text=<encoded text>                     → send as Instagram Note (legacy, maps to text1)
///   vault://note?text1=<v>&text2=<v>&text3=<v>&text4=<v>&text5=<v>   → multi-placeholder Note
///   vault://bio?text=<encoded text>                      → update Instagram Biography (legacy)
///   vault://bio?text1=<v>&text2=<v>&text3=<v>&text4=<v>&text5=<v>    → multi-placeholder Biography
///   vault://perform?bio=<encoded text>&reveal=<word>      → bio first, then queued Post Prediction
///   vault://perform?text1=<v>&text2=<v>&card=3D           → multi-placeholder bio first, then queued card
///   vault://perform?bio1=<v>&bio2=<v>&card=3D             → alias for text1/text2
///   vault://perform?bio=<encoded text>&card=3D            → bio first, then queued Playing Card (S/H/C/D)
///   vault://reveal?word=<encoded word>  → Word Reveal: unarchive letter photos for the given word
///   vault://reveal?slot=<number>        → Custom Set Reveal: unarchive the photo at slot 1–100
///   vault://reveal?card=<symbol>        → Playing Card Reveal: unarchive a card (e.g. AS, 10H, 3D)
///
/// Line breaks in note/bio text — supported encodings (any of these work):
///   %0A          — standard URL-encoded newline  (vault://bio?text=Line1%0ALine2)
///   \n           — literal backslash-n           (vault://bio?text=Line1\nLine2)
///   {newline}    — named token                   (vault://bio?text=Line1{newline}Line2)
///   {br}         — short alias for {newline}
///   <br>         — HTML tag (some tools emit this)
///
/// Flow:
///   1. App receives URL → URLActionManager.shared.handleURL(_:)
///   2. HomeView observes pendingMode and switches to the Performance tab (tab 0)
///   3. PerformanceView.onAppear calls consume() and executes the action
class URLActionManager: ObservableObject {
    static let shared = URLActionManager()
    private init() {}

    /// The mode of the pending action: "note", "bio", or "" (none).
    @Published private(set) var pendingMode: String = ""
    /// Primary text (legacy / text1 value) — kept for backward compat with consumers that only read this.
    @Published private(set) var pendingText: String = ""
    /// Multi-placeholder values keyed by "text1" … "text5".
    @Published private(set) var pendingValues: [String: String] = [:]

    // MARK: - URL Parsing

    /// Returns true if the URL was a valid vault:// action.
    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "vault" else { return false }

        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // ── Profile picture variants ──────────────────────────────────────────
        if host == "profilepic" {
            let source = components?.queryItems?.first(where: { $0.name == "source" })?.value ?? "last"
            let data   = components?.queryItems?.first(where: { $0.name == "data"   })?.value ?? ""

            if !data.isEmpty {
                // Base64 image sent by an external app
                print("📲 [URL] vault://profilepic?data=<base64> received (\(data.count) chars)")
                DispatchQueue.main.async {
                    self.pendingMode = "profilepic_base64"
                    self.pendingText = data
                }
            } else if source == "clipboard" {
                print("📲 [URL] vault://profilepic?source=clipboard received")
                DispatchQueue.main.async {
                    self.pendingMode = "profilepic_clipboard"
                    self.pendingText = ""
                }
            } else {
                // Default: last gallery photo
                print("📲 [URL] vault://profilepic (last gallery photo) received")
                DispatchQueue.main.async {
                    self.pendingMode = "profilepic_last"
                    self.pendingText = ""
                }
            }
            return true
        }

        // Helper: extract a named param from URLComponents or raw query string
        func extractParam(_ name: String) -> String? {
            if let v = components?.queryItems?.first(where: { $0.name == name })?.value,
               !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let rawQuery = url.query ?? url.absoluteString.components(separatedBy: "?").dropFirst().first else { return nil }
            for param in rawQuery.components(separatedBy: "&") {
                guard param.hasPrefix("\(name)=") else { continue }
                let raw = String(param.dropFirst(name.count + 1))
                let decoded = raw.removingPercentEncoding ?? raw
                let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }

        // ── Combined performance flow: bio first, then Post Prediction ────────
        if host == "perform" {
            var bioValues: [String: String] = [:]
            for idx in 1...5 {
                if let value = extractParam("text\(idx)") ?? extractParam("bio\(idx)") {
                    bioValues["text\(idx)"] = value
                }
            }
            if bioValues["text1"] == nil, let bio = extractParam("bio") {
                bioValues["text1"] = bio
            }

            guard let primaryBio = bioValues["text1"], !primaryBio.isEmpty else {
                print("⚠️ [URL] vault://perform missing 'bio', 'text1', or 'bio1' parameter")
                return false
            }

            var values: [String: String] = ["bio": primaryBio]
            for (key, value) in bioValues {
                values[key] = value
            }
            if let reveal = extractParam("reveal") ?? extractParam("word") {
                values["reveal"] = reveal
            } else if let slot = extractParam("slot") {
                values["slot"] = slot
            } else if let card = extractParam("card") {
                values["card"] = card
            } else {
                print("⚠️ [URL] vault://perform missing 'reveal', 'slot', or 'card' parameter")
                return false
            }

            print("📲 [URL] vault://perform received (bio + queued reveal)")
            DispatchQueue.main.async {
                self.pendingMode = "perform"
                self.pendingText = primaryBio
                self.pendingValues = values
            }
            return true
        }

        // ── Reveal variants: word / custom slot / playing card ───────────────
        if host == "reveal" {
            let items = components?.queryItems ?? []
            let setName = extractParam("set")  // Optional set name parameter

            // vault://reveal?word=COCHE  (Word Reveal)
            // vault://reveal?word=COCHE&set=MySet  (Word Reveal with specific set)
            if let raw = items.first(where: { $0.name == "word" })?.value,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = setName.map { " from set '\($0)'" } ?? ""
                print("📲 [URL] vault://reveal?word received: \"\(word.prefix(40))\"\(msg)")
                DispatchQueue.main.async {
                    self.pendingMode = "reveal"
                    self.pendingText = word
                    self.pendingValues = setName.map { ["set": $0] } ?? [:]
                }
                return true
            }

            // vault://reveal?slot=15  (Custom Set Reveal, slot 1–100)
            // vault://reveal?slot=15&set=MySet  (Custom Set with specific set name)
            if let raw = items.first(where: { $0.name == "slot" })?.value,
               let slot = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...100).contains(slot) {
                let msg = setName.map { " from set '\($0)'" } ?? ""
                print("📲 [URL] vault://reveal?slot received: \(slot)\(msg)")
                DispatchQueue.main.async {
                    self.pendingMode = "reveal_slot"
                    self.pendingText = "\(slot)"
                    self.pendingValues = setName.map { ["set": $0] } ?? [:]
                }
                return true
            }

            // vault://reveal?card=3D  (Playing Card Reveal: S/H/C/D suits)
            // vault://reveal?card=3D&set=MyCardSet  (Card with specific set name)
            if let raw = items.first(where: { $0.name == "card" })?.value,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let msg = setName.map { " from set '\($0)'" } ?? ""
                print("📲 [URL] vault://reveal?card received: \"\(symbol)\"\(msg)")
                DispatchQueue.main.async {
                    self.pendingMode = "reveal_card"
                    self.pendingText = symbol
                    self.pendingValues = setName.map { ["set": $0] } ?? [:]
                }
                return true
            }

            print("⚠️ [URL] vault://reveal: missing or invalid 'word', 'slot', or 'card' parameter in \(url)")
            return false
        }

        // ── Note / Bio text variants ──────────────────────────────────────────
        guard host == "note" || host == "bio" else {
            print("⚠️ [URL] Unknown action: \(host)")
            return false
        }

        // Try multi-placeholder params first (text1..text5), then legacy "text"
        var values: [String: String] = [:]
        if let v1 = extractParam("text1") { values["text1"] = v1 }
        if let v2 = extractParam("text2") { values["text2"] = v2 }
        if let v3 = extractParam("text3") { values["text3"] = v3 }
        if let v4 = extractParam("text4") { values["text4"] = v4 }
        if let v5 = extractParam("text5") { values["text5"] = v5 }
        // Legacy "text" → maps to text1
        if values.isEmpty, let legacy = extractParam("text") { values["text1"] = legacy }

        guard !values.isEmpty else {
            print("⚠️ [URL] Missing or empty 'text'/'text1' parameter in URL: \(url)")
            return false
        }

        let primaryText = values["text1"] ?? ""
        print("📲 [URL] vault://\(host) received, values=\(values.map { "\($0.key)=\($0.value.prefix(20))" }.joined(separator: ", "))")

        DispatchQueue.main.async {
            self.pendingMode   = host
            self.pendingText   = primaryText
            self.pendingValues = values
        }
        return true
    }

    // MARK: - Consumption

    /// Called by PerformanceView to retrieve and clear the pending action.
    /// Returns `(mode, text, values)` where `values` contains keyed placeholders ("text1" … "text5").
    /// `text` is the legacy primary value (= values["text1"] if present).
    /// Note: pendingText may be empty for modes that carry no payload (e.g. profilepic_last).
    func consume() -> (mode: String, text: String, values: [String: String])? {
        guard !pendingMode.isEmpty else { return nil }
        let result = (mode: pendingMode, text: pendingText, values: pendingValues)
        pendingMode   = ""
        pendingText   = ""
        pendingValues = [:]
        return result
    }

    // MARK: - URL Builder

    /// Builds a vault:// URL for the given mode and text (legacy single-value), with proper URL encoding.
    static func buildURL(mode: String, text: String) -> String {
        var components = URLComponents()
        components.scheme = "vault"
        components.host   = mode
        components.queryItems = [URLQueryItem(name: "text1", value: text)]
        return components.url?.absoluteString ?? "vault://\(mode)?text1=\(text)"
    }

    /// Builds a vault:// URL with multiple placeholder values.
    static func buildURL(mode: String, values: [String: String]) -> String {
        var components = URLComponents()
        components.scheme = "vault"
        components.host   = mode
        let orderedKeys = ["text1", "text2", "text3", "text4", "text5"].filter { values[$0] != nil }
        components.queryItems = orderedKeys.map { URLQueryItem(name: $0, value: values[$0]!) }
        return components.url?.absoluteString ?? "vault://\(mode)"
    }

    // MARK: - Reveal URL builders

    /// vault://reveal?word=COCHE  — Word Reveal: unarchive letter photos for `word`.
    static func revealURL(word: String) -> String {
        var c = URLComponents(); c.scheme = "vault"; c.host = "reveal"
        c.queryItems = [URLQueryItem(name: "word", value: word)]
        return c.url?.absoluteString ?? "vault://reveal?word=\(word)"
    }

    /// vault://reveal?slot=15  — Custom Set Reveal: unarchive the photo at slot 1–100.
    static func revealCustomSlotURL(slot: Int) -> String {
        var c = URLComponents(); c.scheme = "vault"; c.host = "reveal"
        c.queryItems = [URLQueryItem(name: "slot", value: "\(slot)")]
        return c.url?.absoluteString ?? "vault://reveal?slot=\(slot)"
    }

    /// vault://reveal?card=J%E2%99%A0  — Playing Card Reveal: unarchive a card photo (e.g. J♠, 10♥, K♦).
    static func revealCardURL(symbol: String) -> String {
        var c = URLComponents(); c.scheme = "vault"; c.host = "reveal"
        c.queryItems = [URLQueryItem(name: "card", value: symbol)]
        return c.url?.absoluteString ?? "vault://reveal?card=\(symbol)"
    }

    // MARK: - Profile pic URL builders

    /// vault://profilepic  → uploads the most recent photo from the gallery
    static var profilePicLastURL: String { "vault://profilepic" }

    /// vault://profilepic?source=clipboard  → uploads the image currently in the clipboard
    static var profilePicClipboardURL: String { "vault://profilepic?source=clipboard" }

    /// vault://profilepic?data=<base64>  → uploads a base64-encoded image from an external app.
    /// Vault handles resizing (max 512×512) and compression internally.
    static func profilePicBase64URL(imageData: Data) -> String {
        let b64 = imageData.base64EncodedString()
        var components = URLComponents()
        components.scheme     = "vault"
        components.host       = "profilepic"
        components.queryItems = [URLQueryItem(name: "data", value: b64)]
        return components.url?.absoluteString ?? "vault://profilepic?data=\(b64)"
    }
}
