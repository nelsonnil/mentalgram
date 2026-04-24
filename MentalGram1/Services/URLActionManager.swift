import Foundation
import Combine

/// Handles incoming URL scheme actions and stores them for PerformanceView to consume.
///
/// Supported URLs:
///   vault://note?text=<encoded text>    → send as Instagram Note
///   vault://bio?text=<encoded text>     → update Instagram Biography
///   vault://reveal?word=<encoded word>  → Word Reveal: unarchive letter photos for the given word
///   vault://reveal?slot=<number>        → Custom Set Reveal: unarchive the photo at slot 1–100
///   vault://reveal?card=<symbol>        → Playing Card Reveal: unarchive a card (e.g. J♠, 10♥, K♦)
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
    /// The text to send when the action is executed.
    @Published private(set) var pendingText: String = ""

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

        // ── Reveal variants: word / custom slot / playing card ───────────────
        if host == "reveal" {
            let items = components?.queryItems ?? []

            // vault://reveal?word=COCHE  (Word Reveal)
            if let raw = items.first(where: { $0.name == "word" })?.value,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📲 [URL] vault://reveal?word received: \"\(word.prefix(40))\"")
                DispatchQueue.main.async { self.pendingMode = "reveal";      self.pendingText = word }
                return true
            }

            // vault://reveal?slot=15  (Custom Set Reveal, slot 1–100)
            if let raw = items.first(where: { $0.name == "slot" })?.value,
               let slot = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...100).contains(slot) {
                print("📲 [URL] vault://reveal?slot received: \(slot)")
                DispatchQueue.main.async { self.pendingMode = "reveal_slot"; self.pendingText = "\(slot)" }
                return true
            }

            // vault://reveal?card=J%E2%99%A0  (Playing Card Reveal, e.g. J♠ 10♥ K♦)
            if let raw = items.first(where: { $0.name == "card" })?.value,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📲 [URL] vault://reveal?card received: \"\(symbol)\"")
                DispatchQueue.main.async { self.pendingMode = "reveal_card"; self.pendingText = symbol }
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

        guard let textItem = components?.queryItems?.first(where: { $0.name == "text" }),
              let raw = textItem.value,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            print("⚠️ [URL] Missing or empty 'text' parameter in URL: \(url)")
            return false
        }

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📲 [URL] vault://\(host) received, text=\"\(text.prefix(40))\"")

        DispatchQueue.main.async {
            self.pendingMode = host
            self.pendingText = text
        }
        return true
    }

    // MARK: - Consumption

    /// Called by PerformanceView to retrieve and clear the pending action.
    /// Note: pendingText may be empty for modes that carry no payload (e.g. profilepic_last).
    func consume() -> (mode: String, text: String)? {
        guard !pendingMode.isEmpty else { return nil }
        let result = (mode: pendingMode, text: pendingText)
        pendingMode = ""
        pendingText = ""
        return result
    }

    // MARK: - URL Builder

    /// Builds a vault:// URL for the given mode and text, with proper URL encoding.
    /// The user only needs to provide plain text — spaces, accents, etc. are encoded automatically.
    static func buildURL(mode: String, text: String) -> String {
        var components = URLComponents()
        components.scheme = "vault"
        components.host   = mode
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        return components.url?.absoluteString ?? "vault://\(mode)?text=\(text)"
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
