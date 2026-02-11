import Foundation
import UIKit
import Combine
import CryptoKit
import Network

/// Instagram Private API client - Pure Swift, no Python needed.
/// Replicates what instagrapi does: HTTP requests to Instagram's private API.
class InstagramService: ObservableObject {
    static let shared = InstagramService()
    
    @Published var session: InstagramSession = .empty
    @Published var isLoggedIn: Bool = false
    
    // Network monitoring
    @Published var isConnected: Bool = true
    @Published var connectionType: String = "unknown"
    
    // Anti-bot lockdown
    @Published var isLocked: Bool = false
    @Published var lockReason: String = ""
    @Published var lockUntil: Date?
    private var consecutiveErrors: Int = 0
    
    // Network change tracking (anti-bot protection)
    private var lastConnectionType: String = "unknown"
    private var lastNetworkChangeTime: Date?
    @Published var isNetworkStabilizing: Bool = false
    private let networkStabilizationDelay: TimeInterval = 4.0 // seconds
    
    private let baseURL = "https://i.instagram.com/api/v1"
    private lazy var userAgent = DeviceInfo.shared.instagramUserAgent
    private let deviceId: String // Persistent device ID for this install
    private let clientUUID: String // Client UUID (like _uuid in instagrapi)
    private let sigKeyVersion = "4"
    private let sigKey = "109513c04303341a7daf27bb329532b6a76c178d78911a750e0620efaffb2d0c" // Instagram's signature key
    
    // Separate sessions: GET can wait, POST cannot (anti-bot)
    private lazy var getSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.waitsForConnectivity = true  // Safe for GET requests
        return URLSession(configuration: config)
    }()
    
    private lazy var postSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.waitsForConnectivity = false  // CRITICAL: Don't auto-retry POSTs
        return URLSession(configuration: config)
    }()
    
    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.vault.network")
    
    private init() {
        // CRITICAL ANTI-BOT: Device IDs stored in KEYCHAIN (survives reinstalls)
        // UserDefaults gets wiped on reinstall, causing "new device" each time = bot flag!
        
        // Migration: if ID exists in UserDefaults but not Keychain, migrate it
        let keychainDeviceKey = "com.mindup.instagram.deviceId"
        let keychainClientKey = "com.mindup.instagram.clientUUID"
        
        if let keychainDeviceId = KeychainService.shared.loadString(forKey: keychainDeviceKey) {
            // Keychain has the ID - use it (persists across reinstalls)
            self.deviceId = keychainDeviceId
            print("📱 [DEVICE] Using Keychain device ID: \(String(keychainDeviceId.prefix(8)))... ✅")
        } else if let oldDeviceId = UserDefaults.standard.string(forKey: "instagram_device_id") {
            // Migrate from UserDefaults to Keychain
            KeychainService.shared.saveString(oldDeviceId, forKey: keychainDeviceKey)
            self.deviceId = oldDeviceId
            print("📱 [DEVICE] Migrated device ID to Keychain: \(String(oldDeviceId.prefix(8)))... ✅")
        } else {
            // First ever launch - generate and save to Keychain
            let newDeviceId = UUID().uuidString
            KeychainService.shared.saveString(newDeviceId, forKey: keychainDeviceKey)
            UserDefaults.standard.set(newDeviceId, forKey: "instagram_device_id") // backup
            self.deviceId = newDeviceId
            print("📱 [DEVICE] Generated new device ID (Keychain): \(String(newDeviceId.prefix(8)))...")
        }
        
        if let keychainClientUUID = KeychainService.shared.loadString(forKey: keychainClientKey) {
            self.clientUUID = keychainClientUUID
        } else if let oldClientUUID = UserDefaults.standard.string(forKey: "instagram_client_uuid") {
            KeychainService.shared.saveString(oldClientUUID, forKey: keychainClientKey)
            self.clientUUID = oldClientUUID
        } else {
            let newUUID = UUID().uuidString
            KeychainService.shared.saveString(newUUID, forKey: keychainClientKey)
            UserDefaults.standard.set(newUUID, forKey: "instagram_client_uuid")
            self.clientUUID = newUUID
        }
        
        // Try to restore session from Keychain
        if let saved = KeychainService.shared.loadSession(), saved.isLoggedIn {
            self.session = saved
            self.isLoggedIn = true
            print("✅ Session restored for @\(saved.username)")
        }
        
        // Start network monitoring
        startNetworkMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let newConnectionType = self.getConnectionType(path) ?? "unknown"
                let wasConnected = self.isConnected
                let newConnected = (path.status == .satisfied)
                
                // Detect network change (WiFi → Cellular, WiFi A → WiFi B, etc.)
                if self.lastConnectionType != "unknown" && self.lastConnectionType != newConnectionType && newConnected {
                    print("🔄 [NETWORK] Connection changed: \(self.lastConnectionType) → \(newConnectionType)")
                    self.lastNetworkChangeTime = Date()
                    self.isNetworkStabilizing = true
                    
                    // Auto-disable stabilizing after delay
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(self.networkStabilizationDelay * 1_000_000_000))
                        self.isNetworkStabilizing = false
                        print("✅ [NETWORK] Stabilization complete")
                    }
                }
                
                self.isConnected = newConnected
                self.connectionType = newConnectionType
                self.lastConnectionType = newConnectionType
                
                print("📶 [NETWORK] Connection: \(newConnectionType) - \(newConnected ? "Connected" : "Disconnected")")
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func getConnectionType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Unknown"
        }
    }
    
    /// Wait for network connection to be restored (with timeout)
    func waitForConnection(timeout: TimeInterval = 30) async throws {
        let start = Date()
        while !isConnected {
            if Date().timeIntervalSince(start) > timeout {
                throw InstagramError.networkError("Connection timeout after \(Int(timeout))s")
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
    }
    
    // MARK: - Bot Detection & Lockdown
    
    /// Analyze API response for bot detection signals
    private func checkForBotSignals(data: Data) async throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return // Not JSON, skip check
        }
        
        let status = json["status"] as? String ?? ""
        let message = json["message"] as? String ?? ""
        let messageLower = message.lowercased()
        
        // Level 3: Challenge required - Instagram wants verification
        if json["challenge"] != nil || messageLower.contains("challenge_required") {
            print("🚨 BOT DETECTED: Challenge required")
            await triggerLockdown(
                reason: "Instagram is asking for verification (challenge_required). Open Instagram app and complete the verification, then come back.",
                duration: 600 // 10 minutes
            )
            throw InstagramError.botDetected("Challenge required - complete verification in Instagram app")
        }
        
        // Level 4: Login required - session invalidated
        if messageLower.contains("login_required") {
            print("🚨 BOT DETECTED: Login required (session invalidated)")
            await triggerLockdown(
                reason: "Instagram invalidated your session. This may indicate suspicious activity was detected.",
                duration: 1800 // 30 minutes
            )
            throw InstagramError.botDetected("Session invalidated by Instagram")
        }
        
        // Level 2: Spam/rate limit detection
        if let spam = json["spam"] as? Bool, spam == true {
            print("🚨 BOT DETECTED: Spam flag")
            await triggerLockdown(
                reason: "Instagram flagged this as spam. Stop all activity and wait.",
                duration: 600 // 10 minutes
            )
            throw InstagramError.botDetected("Flagged as spam")
        }
        
        // Level 1: Action blocked
        if messageLower.contains("action blocked") || messageLower.contains("temporarily blocked") {
            print("🚨 BOT DETECTED: Action blocked")
            await triggerLockdown(
                reason: "Instagram has temporarily blocked actions. Do NOT retry. Wait at least 15 minutes.",
                duration: 900 // 15 minutes
            )
            throw InstagramError.botDetected("Action blocked by Instagram")
        }
        
        // Track consecutive "fail" statuses
        if status == "fail" {
            await MainActor.run { consecutiveErrors += 1 }
            
            // 3 consecutive fails → precautionary lockdown
            if consecutiveErrors >= 3 {
                print("🚨 PRECAUTIONARY LOCKDOWN: 3 consecutive API fails")
                await triggerLockdown(
                    reason: "Multiple consecutive errors detected. Pausing all activity as a precaution to avoid triggering bot detection.",
                    duration: 300 // 5 minutes
                )
            }
        }
    }
    
    @MainActor
    private func triggerLockdown(reason: String, duration: TimeInterval) {
        isLocked = true
        lockReason = reason
        lockUntil = Date().addingTimeInterval(duration)
        
        print("🔒 [LOCKDOWN] Activated for \(Int(duration/60)) minutes")
        print("🔒 [LOCKDOWN] Reason: \(reason)")
    }
    
    @MainActor
    func unlock() {
        isLocked = false
        lockReason = ""
        lockUntil = nil
        consecutiveErrors = 0
        print("🔓 [LOCKDOWN] Deactivated")
    }
    
    @MainActor
    func emergencyLogout() {
        // Clear session
        session = .empty
        isLoggedIn = false
        KeychainService.shared.deleteSession()
        
        // Reset lockdown
        unlock()
        
        // Clear cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("instagram.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        // Clear cached data
        URLCache.shared.removeAllCachedResponses()
        
        print("🚨 [EMERGENCY] Full logout and cache clear completed")
    }
    
    /// Waits if network changed recently (anti-bot protection)
    /// Returns immediately if network is stable
    func waitForNetworkStability() async throws {
        // Check if network changed recently
        if let changeTime = lastNetworkChangeTime {
            let timeSinceChange = Date().timeIntervalSince(changeTime)
            
            if timeSinceChange < networkStabilizationDelay {
                let remainingDelay = networkStabilizationDelay - timeSinceChange
                print("⏳ [NETWORK] Waiting \(String(format: "%.1f", remainingDelay))s for network stability...")
                
                await MainActor.run {
                    self.isNetworkStabilizing = true
                }
                
                try await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
                
                await MainActor.run {
                    self.isNetworkStabilizing = false
                }
                
                print("✅ [NETWORK] Network stable, proceeding...")
            }
        }
    }
    
    // MARK: - Session from WebView Login
    
    /// Called after WebView login captures cookies
    func setSessionFromCookies(cookies: [HTTPCookie]) {
        var sessionId = ""
        var csrfToken = ""
        var userId = ""
        
        for cookie in cookies {
            switch cookie.name {
            case "sessionid":
                sessionId = cookie.value
            case "csrftoken":
                csrfToken = cookie.value
            case "ds_user_id":
                userId = cookie.value
            default:
                break
            }
        }
        
        guard !sessionId.isEmpty, !userId.isEmpty else {
            print("❌ Missing required cookies")
            return
        }
        
        // Store cookies in shared cookie storage for URLSession
        let cookieStorage = HTTPCookieStorage.shared
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
        
        self.session = InstagramSession(
            sessionId: sessionId,
            csrfToken: csrfToken,
            userId: userId,
            username: "",
            isLoggedIn: true
        )
        
        // Fetch username
        Task {
            if let username = await fetchUsername() {
                await MainActor.run {
                    self.session.username = username
                    self.isLoggedIn = true
                    KeychainService.shared.saveSession(self.session)
                    print("✅ Logged in as @\(username)")
                }
            } else {
                await MainActor.run {
                    self.isLoggedIn = true
                    KeychainService.shared.saveSession(self.session)
                }
            }
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        session = .empty
        isLoggedIn = false
        KeychainService.shared.deleteSession()
        
        // Clear cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        print("✅ Logged out successfully")
    }
    
    // MARK: - Reset Device ID (use with caution)
    
    func resetDeviceIdentifiers() {
        UserDefaults.standard.removeObject(forKey: "instagram_device_id")
        UserDefaults.standard.removeObject(forKey: "instagram_client_uuid")
        print("🔄 Device identifiers reset")
        print("⚠️  Restart the app and login again with new device ID")
    }
    
    // MARK: - Check Friendship Status
    
    func checkFollowingStatus(userId: String) async throws -> (isFollowing: Bool, isRequested: Bool) {
        print("🔍 [FRIENDSHIP] Checking complete friendship status for user ID: \(userId)")
        
        let data = try await apiRequest(
            method: "GET",
            path: "/friendships/show/\(userId)/"
        )
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let following = json["following"] as? Bool ?? false
            let outgoingRequest = json["outgoing_request"] as? Bool ?? false
            print("✅ [FRIENDSHIP] Following: \(following), Outgoing request: \(outgoingRequest)")
            return (following, outgoingRequest)
        }
        
        print("⚠️ [FRIENDSHIP] Could not determine friendship status")
        return (false, false)
    }
    
    // MARK: - Follow/Unfollow
    
    func followUser(userId: String) async throws -> Bool {
        print("➕ [FOLLOW] Starting follow request")
        print("➕ [FOLLOW] Target user ID: \(userId)")
        print("➕ [FOLLOW] Current user ID: \(session.userId)")
        print("➕ [FOLLOW] Client UUID: \(clientUUID)")
        
        // Simulate human delay (2-5 seconds - a real person takes time to decide)
        let delay = UInt64.random(in: 2_000_000_000...5_000_000_000)
        print("⏱️ [FOLLOW] Waiting \(Double(delay) / 1_000_000_000.0) seconds...")
        try await Task.sleep(nanoseconds: delay)
        
        let data = try await apiRequest(
            method: "POST",
            path: "/friendships/create/\(userId)/",
            body: [
                "user_id": userId,
                "_uid": session.userId,
                "_uuid": clientUUID,
                "radio_type": currentRadioType
            ]
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("➕ [FOLLOW] Full response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("➕ [FOLLOW] Response keys: \(json.keys)")
            
            if let status = json["status"] as? String {
                print("➕ [FOLLOW] Status: \(status)")
                if status == "ok" {
                    print("✅ [FOLLOW] Successfully followed user")
                    return true
                }
            }
            
            if let message = json["message"] as? String {
                print("⚠️ [FOLLOW] Message: \(message)")
            }
        }
        
        print("❌ [FOLLOW] Failed to follow user - response was not 'ok'")
        return false
    }
    
    func unfollowUser(userId: String) async throws -> Bool {
        print("➖ [UNFOLLOW] Starting unfollow request")
        print("➖ [UNFOLLOW] Target user ID: \(userId)")
        print("➖ [UNFOLLOW] Current user ID: \(session.userId)")
        print("➖ [UNFOLLOW] Client UUID: \(clientUUID)")
        
        // Simulate human delay
        let delay = UInt64.random(in: 500_000_000...1_500_000_000)
        print("⏱️ [UNFOLLOW] Waiting \(Double(delay) / 1_000_000_000.0) seconds...")
        try await Task.sleep(nanoseconds: delay)
        
        let data = try await apiRequest(
            method: "POST",
            path: "/friendships/destroy/\(userId)/",
            body: [
                "user_id": userId,
                "_uid": session.userId,
                "_uuid": clientUUID,
                "radio_type": currentRadioType
            ]
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("➖ [UNFOLLOW] Full response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("➖ [UNFOLLOW] Response keys: \(json.keys)")
            
            if let status = json["status"] as? String {
                print("➖ [UNFOLLOW] Status: \(status)")
                if status == "ok" {
                    print("✅ [UNFOLLOW] Successfully unfollowed user")
                    return true
                }
            }
            
            if let message = json["message"] as? String {
                print("⚠️ [UNFOLLOW] Message: \(message)")
            }
        }
        
        print("❌ [UNFOLLOW] Failed to unfollow user - response was not 'ok'")
        return false
    }
    
    // MARK: - Common Headers
    
    /// Returns the radio_type matching the real current connection
    private var currentRadioType: String {
        switch connectionType {
        case "WiFi": return "wifi-none"
        case "Cellular": return "cell-none"
        default: return "wifi-none"
        }
    }
    
    private func buildHeaders() -> [String: String] {
        let device = DeviceInfo.shared
        return [
            "User-Agent": userAgent,
            "X-CSRFToken": session.csrfToken,
            "X-IG-App-ID": "936619743392459",
            "X-IG-Device-ID": deviceId,
            "X-IG-Connection-Type": connectionType == "WiFi" ? "WIFI" : "4G",
            "X-IG-Capabilities": "36r/F/8=",
            "X-IG-App-Locale": device.deviceLocale,
            "X-IG-Device-Locale": device.deviceLocale,
            "X-Requested-With": "XMLHttpRequest",
            "Accept-Language": "\(device.deviceLanguage)-\(Locale.current.region?.identifier ?? "US"),\(device.deviceLanguage);q=0.9",
            "Accept-Encoding": "gzip, deflate",
            "Content-Type": "application/x-www-form-urlencoded",
            "Cookie": "sessionid=\(session.sessionId); csrftoken=\(session.csrfToken); ds_user_id=\(session.userId)"
        ]
    }
    
    // MARK: - Generate Signature (HMAC-SHA256)
    
    private func generateSignature(data: String) -> String {
        let key = SymmetricKey(data: Data(sigKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - API Request Helper
    
    private func apiRequest(
        method: String,
        path: String,
        body: [String: String]? = nil
    ) async throws -> Data {
        // Check if we're locked down
        if isLocked {
            throw InstagramError.botDetected("App is in lockdown mode. Wait for countdown to finish.")
        }
        
        // Check network connection
        if !isConnected {
            print("📶 [NETWORK] No connection detected, waiting...")
            try await waitForConnection()
        }
        
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw InstagramError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30  // 30s timeout
        
        let headers = buildHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)
        }
        
        // Use different sessions: GET can wait, POST cannot (critical for bot detection)
        let session = (method == "GET") ? getSession : postSession
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // Network error - safe to retry
            print("🌐 [NETWORK] URLError: \(error.localizedDescription)")
            throw InstagramError.networkError(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstagramError.invalidResponse
        }
        
        // Check for bot detection signals in HTTP status
        if httpResponse.statusCode == 429 {
            // Rate limited
            await triggerLockdown(reason: "Rate limited by Instagram. Too many requests.", duration: 300)
            throw InstagramError.botDetected("Rate limited (HTTP 429). Wait 5 minutes.")
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw InstagramError.sessionExpired
        }
        
        if httpResponse.statusCode >= 400 {
            // Try to parse error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = errorJson["message"] as? String ?? ""
                
                // Check for challenge_required - MUST trigger lockdown
                if message.contains("challenge_required") {
                    print("🚨 [API] Instagram requires verification challenge")
                    print("🚨 [API] Go to Instagram app/website to complete verification")
                    await triggerLockdown(
                        reason: "Instagram requires verification (challenge_required). Open Instagram app, complete the verification, then wait 10 minutes before using this app again.",
                        duration: 600 // 10 minutes
                    )
                    throw InstagramError.challengeRequired
                }
                
                if !message.isEmpty {
                    print("❌ [API] HTTP \(httpResponse.statusCode): \(message)")
                    throw InstagramError.apiError("HTTP \(httpResponse.statusCode): \(message)")
                }
            }
            
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ [API] HTTP \(httpResponse.statusCode)")
                print("❌ [API] Response: \(String(errorString.prefix(200)))")
            }
            throw InstagramError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // Check for bot detection signals in response body
        try await checkForBotSignals(data: data)
        
        // Success - reset consecutive error counter
        await MainActor.run { consecutiveErrors = 0 }
        
        return data
    }
    
    // MARK: - Fetch Username
    
    func fetchUsername() async -> String? {
        do {
            let data = try await apiRequest(method: "GET", path: "/accounts/current_user/?edit=true")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let user = json["user"] as? [String: Any],
               let username = user["username"] as? String {
                return username
            }
        } catch {
            print("❌ Error fetching username: \(error)")
        }
        return nil
    }
    
    // MARK: - Get User Media
    
    func getUserMedia(userId: String? = nil, maxId: String? = nil) async throws -> ([InstagramMedia], String?) {
        let uid = userId ?? session.userId
        var path = "/feed/user/\(uid)/"
        if let maxId = maxId {
            path += "?max_id=\(maxId)"
        }
        
        let data = try await apiRequest(method: "GET", path: path)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return ([], nil)
        }
        
        let nextMaxId = json["next_max_id"] as? String
        
        var medias: [InstagramMedia] = []
        
        for item in items {
            guard let pk = item["pk"] as? Int64 else { continue }
            
            let caption = (item["caption"] as? [String: Any])?["text"] as? String ?? ""
            
            var imageUrl = ""
            if let imageVersions = item["image_versions2"] as? [String: Any],
               let candidates = imageVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let url = firstCandidate["url"] as? String {
                imageUrl = url
            }
            
            let takenAt: Date?
            if let timestamp = item["taken_at"] as? TimeInterval {
                takenAt = Date(timeIntervalSince1970: timestamp)
            } else {
                takenAt = nil
            }
            
            let media = InstagramMedia(
                id: String(pk),
                mediaId: String(pk),
                imageURL: imageUrl,
                caption: caption,
                takenAt: takenAt,
                isArchived: false
            )
            medias.append(media)
        }
        
        return (medias, nextMaxId)
    }
    
    // MARK: - Archive Photo
    
    func archivePhoto(mediaId: String) async throws -> Bool {
        print("📦 [ARCHIVE] Starting archive for media ID: \(mediaId)")
        
        // Simulate human delay
        let delay = UInt64.random(in: 1_000_000_000...2_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s before archive...")
        try await Task.sleep(nanoseconds: delay)
        
        // Instagram expects media_id in format: pk_userid (e.g., 3827949643435346901_80533585162)
        let fullMediaId: String
        if mediaId.contains("_") {
            fullMediaId = mediaId
        } else {
            fullMediaId = "\(mediaId)_\(session.userId)"
        }
        
        print("   Full media ID: \(fullMediaId)")
        
        let data = try await apiRequest(
            method: "POST",
            path: "/media/\(fullMediaId)/only_me/",
            body: ["media_id": fullMediaId]
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("   Archive response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            if status == "ok" {
                print("✅ [ARCHIVE] Photo archived successfully")
                return true
            } else {
                print("❌ [ARCHIVE] Archive failed. Status: \(status)")
                return false
            }
        }
        
        print("❌ [ARCHIVE] Failed to parse archive response")
        return false
    }
    
    // MARK: - Unarchive Photo
    
    func unarchivePhoto(mediaId: String) async throws -> Bool {
        print("📤 [UNARCHIVE] Starting unarchive for media ID: \(mediaId)")
        
        // Simulate human delay
        let delay = UInt64.random(in: 1_000_000_000...2_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s before unarchive...")
        try await Task.sleep(nanoseconds: delay)
        
        // Instagram expects media_id in format: pk_userid
        let fullMediaId: String
        if mediaId.contains("_") {
            fullMediaId = mediaId
        } else {
            fullMediaId = "\(mediaId)_\(session.userId)"
        }
        
        print("   Full media ID: \(fullMediaId)")
        
        let data = try await apiRequest(
            method: "POST",
            path: "/media/\(fullMediaId)/undo_only_me/",
            body: ["media_id": fullMediaId]
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("   Unarchive response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            if status == "ok" {
                print("✅ [UNARCHIVE] Photo unarchived successfully")
                return true
            } else {
                print("❌ [UNARCHIVE] Unarchive failed. Status: \(status)")
                return false
            }
        }
        
        print("❌ [UNARCHIVE] Failed to parse unarchive response")
        return false
    }
    
    // MARK: - Comment on Photo
    
    func commentOnMedia(mediaId: String, text: String) async throws -> String? {
        print("💬 [COMMENT] Posting comment on media ID: \(mediaId)")
        print("   Text: \"\(text)\"")
        
        // Extract just the PK (without _userid) for comment endpoint
        let pk = mediaId.split(separator: "_").first.map(String.init) ?? mediaId
        print("   Using PK for comment: \(pk)")
        
        // Simulate human delay
        let delay = UInt64.random(in: 2_000_000_000...3_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s before comment...")
        try await Task.sleep(nanoseconds: delay)
        
        // Build signed data (like instagrapi's with_action_data)
        let idempotenceToken = UUID().uuidString
        
        let bodyDict: [String: Any] = [
            "comment_text": text,
            "delivery_class": "organic",
            "feed_position": "0",
            "container_module": "self_comments_v2_feed_contextual_self_profile",
            "idempotence_token": idempotenceToken,
            "_uuid": clientUUID,
            "_uid": session.userId,
            "_csrftoken": session.csrfToken,
            "radio_type": currentRadioType
        ]
        
        // Convert to JSON string (instagrapi uses dumps + signature)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: bodyDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ [COMMENT] Failed to serialize body")
            throw InstagramError.invalidURL
        }
        
        // Build signed_body with REAL HMAC-SHA256 signature
        let signature = generateSignature(data: jsonString)
        let signedBody = "signed_body=\(signature).\(jsonString)&ig_sig_key_version=\(sigKeyVersion)"
        
        print("   JSON body: \(jsonString)")
        print("   HMAC signature (first 32 chars): \(String(signature.prefix(32)))...")
        print("   Signed body (first 200 chars): \(String(signedBody.prefix(200)))...")
        
        // Custom request for signed data
        guard let url = URL(string: "\(baseURL)/media/\(pk)/comment/") else {
            throw InstagramError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let headers = buildHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = signedBody.data(using: .utf8)
        
        let (data, response) = try await postSession.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("   Comment HTTP status: \(httpResponse.statusCode)")
        }
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("   Comment response: \(jsonString)")
        }
        
        // Check for errors
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw InstagramError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let comment = json["comment"] as? [String: Any] {
            
            // Try different pk formats
            let commentId: String?
            if let pkString = comment["pk"] as? String {
                commentId = pkString
            } else if let pkInt64 = comment["pk"] as? Int64 {
                commentId = String(pkInt64)
            } else if let pkInt = comment["pk"] as? Int {
                commentId = String(pkInt)
            } else {
                commentId = nil
            }
            
            if let commentId = commentId {
                print("✅ [COMMENT] Comment posted! ID: \(commentId)")
                return commentId
            }
        }
        
        print("❌ [COMMENT] Failed to get comment ID from response")
        return nil
    }
    
    // MARK: - Delete Comment
    
    func deleteComment(mediaId: String, commentId: String) async throws -> Bool {
        let data = try await apiRequest(
            method: "POST",
            path: "/media/\(mediaId)/comment/\(commentId)/delete/",
            body: [:]
        )
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            return status == "ok"
        }
        
        return false
    }
    
    // MARK: - Get Latest Follower
    
    func getLatestFollower() async throws -> InstagramFollower? {
        print("👤 [FOLLOWER] Fetching latest follower...")
        
        let data = try await apiRequest(
            method: "GET",
            path: "/friendships/\(session.userId)/followers/?count=1"
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("   Follower response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let users = json["users"] as? [[String: Any]],
           let first = users.first {
            
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 DATOS COMPLETOS DEL ÚLTIMO FOLLOWER:")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            for (key, value) in first.sorted(by: { $0.key < $1.key }) {
                print("   \(key): \(value)")
            }
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
            
            // Campos importantes - maneja pk como String o Int
            let userId: String
            if let pkString = first["pk"] as? String {
                userId = pkString
            } else if let pkInt64 = first["pk"] as? Int64 {
                userId = String(pkInt64)
            } else if let pkInt = first["pk"] as? Int {
                userId = String(pkInt)
            } else {
                userId = "0"
            }
            
            let username = first["username"] as? String ?? ""
            let fullName = first["full_name"] as? String ?? ""
            let isVerified = first["is_verified"] as? Bool ?? false
            let isPrivate = first["is_private"] as? Bool ?? false
            let profilePicURL = first["profile_pic_url"] as? String
            let hasAnonymousProfilePicture = first["has_anonymous_profile_picture"] as? Bool ?? false
            
            print("✅ Follower extraído:")
            print("   User ID: \(userId)")
            print("   Username: @\(username)")
            print("   Full Name: \(fullName)")
            print("   Is Verified: \(isVerified ? "✓" : "✗")")
            print("   Is Private: \(isPrivate ? "✓" : "✗")")
            print("   Has Profile Pic: \(hasAnonymousProfilePicture ? "✗" : "✓")")
            print("   Profile Pic URL: \(profilePicURL ?? "N/A")")
            
            let follower = InstagramFollower(
                userId: userId,
                username: username,
                fullName: fullName,
                profilePicURL: profilePicURL
            )
            
            print("✅ [FOLLOWER] Found: @\(follower.username) (\(follower.fullName))")
            return follower
        }
        
        print("❌ [FOLLOWER] No followers found or failed to parse")
        return nil
    }
    
    // MARK: - Get User Full Info (with followers count, following, posts, etc.)
    
    func getUserFullInfo(userId: String) async throws -> [String: Any]? {
        print("👤 [USER INFO] Fetching full info for user ID: \(userId)")
        
        let data = try await apiRequest(
            method: "GET",
            path: "/users/\(userId)/info/"
        )
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("   User info response: \(jsonString)")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let user = json["user"] as? [String: Any] {
            
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 DATOS COMPLETOS DEL USUARIO:")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            for (key, value) in user.sorted(by: { $0.key < $1.key }) {
                print("   \(key): \(value)")
            }
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
            
            // Datos importantes
            let followerCount = user["follower_count"] as? Int ?? 0
            let followingCount = user["following_count"] as? Int ?? 0
            let mediaCount = user["media_count"] as? Int ?? 0
            let biography = user["biography"] as? String ?? ""
            
            print("✅ User info extraído:")
            print("   Followers: \(followerCount)")
            print("   Following: \(followingCount)")
            print("   Posts: \(mediaCount)")
            print("   Bio: \(biography)")
            
            return user
        }
        
        print("❌ [USER INFO] Failed to parse user info")
        return nil
    }
    
    // MARK: - Get Profile Info (Complete Profile Data)
    
    func getProfileInfo(userId: String? = nil) async throws -> InstagramProfile? {
        let uid = userId ?? session.userId
        let isOwnProfile = (uid == session.userId)
        print("📊 [PROFILE] Fetching complete profile for user ID: \(uid)")
        print("📊 [PROFILE] Is own profile: \(isOwnProfile)")
        
        let data = try await apiRequest(method: "GET", path: "/users/\(uid)/info/")
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any] else {
            print("❌ [PROFILE] Failed to parse user data")
            return nil
        }
        
        // Debug: Print user data
        print("📊 [PROFILE] User data keys: \(user.keys.sorted().joined(separator: ", "))")
        if let profilePicUrl = user["profile_pic_url"] as? String {
            print("📊 [PROFILE] Profile pic URL found: \(String(profilePicUrl.prefix(80)))...")
        } else {
            print("⚠️ [PROFILE] No profile_pic_url field found")
        }
        
        // Extract userId (handle different types)
        let extractedUserId: String
        if let pkInt64 = user["pk"] as? Int64 {
            extractedUserId = String(pkInt64)
            print("📊 [PROFILE] userId extracted as Int64: \(extractedUserId)")
        } else if let pkString = user["pk"] as? String {
            extractedUserId = pkString
            print("📊 [PROFILE] userId extracted as String: \(extractedUserId)")
        } else if let pkInt = user["pk"] as? Int {
            extractedUserId = String(pkInt)
            print("📊 [PROFILE] userId extracted as Int: \(extractedUserId)")
        } else if let pkId = user["pk_id"] as? String {
            extractedUserId = pkId
            print("📊 [PROFILE] userId extracted from pk_id: \(extractedUserId)")
        } else {
            extractedUserId = "0"
            print("⚠️ [PROFILE] Could not extract userId, defaulting to '0'")
        }
        
        // Check if we're following this user and if there's a pending request
        var isFollowing = false
        var isFollowRequested = false
        
        // First, try to get friendship_status from the user object
        if let friendshipStatus = user["friendship_status"] as? [String: Any] {
            isFollowing = friendshipStatus["following"] as? Bool ?? false
            isFollowRequested = friendshipStatus["outgoing_request"] as? Bool ?? false
            print("📊 [PROFILE] Friendship status from user object - Following: \(isFollowing), Requested: \(isFollowRequested)")
        } else if !isOwnProfile {
            // If not our own profile and no friendship_status in response, 
            // fetch it separately using the friendships endpoint
            print("📊 [PROFILE] No friendship_status in response, fetching separately...")
            
            do {
                let friendshipData = try await apiRequest(
                    method: "GET", 
                    path: "/friendships/show/\(uid)/"
                )
                
                if let friendshipJson = try? JSONSerialization.jsonObject(with: friendshipData) as? [String: Any] {
                    isFollowing = friendshipJson["following"] as? Bool ?? false
                    isFollowRequested = friendshipJson["outgoing_request"] as? Bool ?? false
                    print("📊 [PROFILE] Friendship status from separate call - Following: \(isFollowing), Requested: \(isFollowRequested)")
                } else {
                    print("⚠️ [PROFILE] Could not parse friendship status from separate call")
                }
            } catch {
                print("⚠️ [PROFILE] Error fetching friendship status: \(error)")
            }
        } else {
            print("📊 [PROFILE] Own profile, isFollowing = false, isFollowRequested = false")
        }
        
        // Check if profile is private
        let isPrivate = user["is_private"] as? Bool ?? false
        print("📊 [PROFILE] Profile is private: \(isPrivate)")
        print("📊 [PROFILE] We are following: \(isFollowing)")
        print("📊 [PROFILE] Request pending: \(isFollowRequested)")
        
        // Only fetch followers and media if:
        // 1. It's our own profile, OR
        // 2. Profile is public, OR
        // 3. Profile is private BUT we follow them (NOT just requested)
        // IMPORTANT: Do NOT fetch if only "requested" - this triggers bot detection
        let shouldFetchProtectedData = isOwnProfile || !isPrivate || (isFollowing && !isFollowRequested)
        print("📊 [PROFILE] Should fetch protected data: \(shouldFetchProtectedData)")
        
        var followedBy: [InstagramFollower] = []
        var mediaURLs: [String] = []
        
        if shouldFetchProtectedData {
            print("✅ [PROFILE] Fetching followers and media (profile is accessible)")
            // Get first 3 followers for "Followed by" section
            followedBy = try await getFollowedByUsers(userId: uid, count: 3)
            
            // Get media thumbnails (18 photos for grid)
            let mediaItems = try await getUserMediaItems(userId: uid, amount: 18)
            mediaURLs = mediaItems.map { $0.imageURL }
            
            print("📊 [PROFILE] Media URLs count: \(mediaURLs.count)")
        } else {
            print("⚠️ [PROFILE] Skipping followers/media fetch (private profile, not following)")
            print("💡 [PROFILE] This prevents Instagram from flagging as bot behavior")
        }
        
        let profile = InstagramProfile(
            userId: extractedUserId,
            username: user["username"] as? String ?? "",
            fullName: user["full_name"] as? String ?? "",
            biography: user["biography"] as? String ?? "",
            externalUrl: user["external_url"] as? String,
            profilePicURL: user["profile_pic_url"] as? String ?? "",
            isVerified: user["is_verified"] as? Bool ?? false,
            isPrivate: user["is_private"] as? Bool ?? false,
            followerCount: user["follower_count"] as? Int ?? 0,
            followingCount: user["following_count"] as? Int ?? 0,
            mediaCount: user["media_count"] as? Int ?? 0,
            followedBy: followedBy,
            isFollowing: isFollowing,
            isFollowRequested: isFollowRequested,
            cachedAt: Date(),
            cachedMediaURLs: mediaURLs
        )
        
        print("✅ [PROFILE] Profile loaded for @\(profile.username)")
        print("📊 [PROFILE] Profile pic URL: \(profile.profilePicURL.isEmpty ? "EMPTY" : String(profile.profilePicURL.prefix(80)))")
        return profile
    }
    
    // MARK: - Get Followed By Users
    
    func getFollowedByUsers(userId: String, count: Int) async throws -> [InstagramFollower] {
        print("👥 [FOLLOWERS] Fetching \(count) followers for user ID: \(userId)")
        
        let data = try await apiRequest(
            method: "GET",
            path: "/friendships/\(userId)/followers/?count=\(count)"
        )
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [[String: Any]] else {
            print("❌ [FOLLOWERS] Failed to parse followers data")
            return []
        }
        
        print("👥 [FOLLOWERS] Found \(users.count) followers in response")
        
        var followers: [InstagramFollower] = []
        for (index, user) in users.prefix(count).enumerated() {
            print("👥 [FOLLOWERS] Processing follower \(index + 1)")
            print("👥 [FOLLOWERS] Follower keys: \(user.keys.sorted().joined(separator: ", "))")
            
            let userId = String(user["pk"] as? Int64 ?? 0)
            let username = user["username"] as? String ?? ""
            let fullName = user["full_name"] as? String ?? ""
            let profilePicURL = user["profile_pic_url"] as? String
            
            if let picURL = profilePicURL {
                print("👥 [FOLLOWERS] Follower \(index + 1) pic URL: \(String(picURL.prefix(80)))...")
            } else {
                print("⚠️ [FOLLOWERS] Follower \(index + 1) has no profile pic URL")
            }
            
            followers.append(InstagramFollower(
                userId: userId,
                username: username,
                fullName: fullName,
                profilePicURL: profilePicURL
            ))
        }
        
        print("✅ [FOLLOWERS] Processed \(followers.count) followers")
        return followers
    }
    
    // MARK: - Get User Media Items (Extended with metadata)
    
    func getUserMediaItems(userId: String? = nil, amount: Int = 18) async throws -> [InstagramMediaItem] {
        let uid = userId ?? session.userId
        print("📷 [MEDIA] Fetching \(amount) media items for user ID: \(uid)")
        
        let path = "/feed/user/\(uid)/"
        let data = try await apiRequest(method: "GET", path: path)
        
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📷 [MEDIA] Raw response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [MEDIA] Failed to parse JSON")
            return []
        }
        
        // Debug: Print available keys
        print("📷 [MEDIA] Response keys: \(json.keys.sorted())")
        
        guard let items = json["items"] as? [[String: Any]] else {
            print("❌ [MEDIA] No 'items' key found or invalid format")
            print("📷 [MEDIA] Available keys: \(json.keys.joined(separator: ", "))")
            
            // Try alternative: get from user info endpoint
            return try await getUserMediaFromAlternativeEndpoint(userId: uid, amount: amount)
        }
        
        print("📷 [MEDIA] Found \(items.count) items in response")
        
        var mediaItems: [InstagramMediaItem] = []
        
        for (index, item) in items.prefix(amount).enumerated() {
            print("📷 [MEDIA] Processing item \(index + 1)/\(items.count)")
            
            // Try multiple ways to get the pk
            var pkValue: Int64?
            
            // Method 1: Direct pk field
            if let pk = item["pk"] as? Int64 {
                pkValue = pk
                print("📷 [MEDIA] Item \(index + 1): Found pk directly: \(pk)")
            }
            // Method 2: pk as String
            else if let pkString = item["pk"] as? String, let pk = Int64(pkString) {
                pkValue = pk
                print("📷 [MEDIA] Item \(index + 1): Found pk as string: \(pk)")
            }
            // Method 3: Extract from strong_id__ (format: "mediaId_userId")
            else if let strongId = item["strong_id__"] as? String {
                let components = strongId.split(separator: "_")
                if let firstPart = components.first, let pk = Int64(String(firstPart)) {
                    pkValue = pk
                    print("📷 [MEDIA] Item \(index + 1): Extracted pk from strong_id__: \(pk)")
                }
            }
            // Method 4: Try id field
            else if let id = item["id"] as? String, let pk = Int64(id) {
                pkValue = pk
                print("📷 [MEDIA] Item \(index + 1): Found pk in id field: \(pk)")
            }
            
            guard let pk = pkValue else {
                print("⚠️ [MEDIA] Item \(index + 1) has no valid pk in any field")
                print("⚠️ [MEDIA] Available keys: \(item.keys.sorted().joined(separator: ", "))")
                continue
            }
            
            let caption = (item["caption"] as? [String: Any])?["text"] as? String
            
            var imageUrl = ""
            if let imageVersions = item["image_versions2"] as? [String: Any],
               let candidates = imageVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let url = firstCandidate["url"] as? String {
                imageUrl = url
                print("📷 [MEDIA] Item \(index + 1): Found image URL")
            } else {
                print("⚠️ [MEDIA] Item \(index + 1): No image URL found")
            }
            
            let takenAt: Date?
            if let timestamp = item["taken_at"] as? TimeInterval {
                takenAt = Date(timeIntervalSince1970: timestamp)
            } else {
                takenAt = nil
            }
            
            let likeCount = item["like_count"] as? Int
            let commentCount = item["comment_count"] as? Int
            
            // Extract video URL if it's a video
            var videoUrl: String?
            if let videoVersions = item["video_versions"] as? [[String: Any]],
               let firstVideo = videoVersions.first,
               let url = firstVideo["url"] as? String {
                videoUrl = url
            }
            
            // Determine media type
            let mediaType: InstagramMediaItem.MediaType
            if let carouselMedia = item["carousel_media"] as? [[String: Any]], !carouselMedia.isEmpty {
                mediaType = .carousel
            } else if videoUrl != nil {
                mediaType = .video
            } else {
                mediaType = .photo
            }
            
            let mediaItem = InstagramMediaItem(
                id: String(pk),
                mediaId: String(pk),
                imageURL: imageUrl,
                videoURL: videoUrl,
                caption: caption,
                takenAt: takenAt,
                likeCount: likeCount,
                commentCount: commentCount,
                mediaType: mediaType
            )
            mediaItems.append(mediaItem)
        }
        
        print("✅ [MEDIA] Fetched \(mediaItems.count) media items")
        return mediaItems
    }
    
    // MARK: - Get User Media from Alternative Endpoint
    
    private func getUserMediaFromAlternativeEndpoint(userId: String, amount: Int) async throws -> [InstagramMediaItem] {
        print("📷 [MEDIA ALT] Trying alternative endpoint for user ID: \(userId)")
        
        // Try using user_medias endpoint with rank_token
        let rankToken = UUID().uuidString
        let path = "/feed/user/\(userId)/?rank_token=\(rankToken)&max_id="
        
        let data = try await apiRequest(method: "GET", path: path)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📷 [MEDIA ALT] Response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            print("❌ [MEDIA ALT] Failed to get items from alternative endpoint")
            return []
        }
        
        print("📷 [MEDIA ALT] Found \(items.count) items")
        
        var mediaItems: [InstagramMediaItem] = []
        
        for item in items.prefix(amount) {
            // Try multiple ways to get the pk
            var pkValue: Int64?
            
            if let pk = item["pk"] as? Int64 {
                pkValue = pk
            } else if let pkString = item["pk"] as? String, let pk = Int64(pkString) {
                pkValue = pk
            } else if let strongId = item["strong_id__"] as? String {
                let components = strongId.split(separator: "_")
                if let firstPart = components.first, let pk = Int64(String(firstPart)) {
                    pkValue = pk
                }
            } else if let id = item["id"] as? String, let pk = Int64(id) {
                pkValue = pk
            }
            
            guard let pk = pkValue else { continue }
            
            let caption = (item["caption"] as? [String: Any])?["text"] as? String
            
            var imageUrl = ""
            if let imageVersions = item["image_versions2"] as? [String: Any],
               let candidates = imageVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let url = firstCandidate["url"] as? String {
                imageUrl = url
            }
            
            // Extract video URL if it's a video
            var videoUrl: String?
            if let videoVersions = item["video_versions"] as? [[String: Any]],
               let firstVideo = videoVersions.first,
               let url = firstVideo["url"] as? String {
                videoUrl = url
            }
            
            let mediaItem = InstagramMediaItem(
                id: String(pk),
                mediaId: String(pk),
                imageURL: imageUrl,
                videoURL: videoUrl,
                caption: caption,
                takenAt: nil,
                likeCount: nil,
                commentCount: nil,
                mediaType: videoUrl != nil ? .video : .photo
            )
            mediaItems.append(mediaItem)
        }
        
        print("✅ [MEDIA ALT] Fetched \(mediaItems.count) media items from alternative endpoint")
        return mediaItems
    }
    
    // MARK: - Get Explore Feed
    
    func getExploreFeed(maxId: String? = nil) async throws -> ([InstagramMediaItem], String?) {
        print("🔍 [EXPLORE] Fetching explore feed...")
        
        // Use cluster_id for more items (Instagram's internal explore pagination)
        var path = "/discover/topical_explore/?is_prefetch=false&omit_cover_media=true&module=explore_popular&reels_configuration=hide_explore_media_reels_media&use_sectional_payload=true&timezone_offset=3600&session_id=\(UUID().uuidString)"
        
        if let maxId = maxId {
            path += "&max_id=\(maxId)"
        }
        
        let data = try await apiRequest(method: "GET", path: path)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🔍 [EXPLORE] Response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [EXPLORE] Failed to parse JSON")
            return ([], nil)
        }
        
        print("🔍 [EXPLORE] Response keys: \(json.keys.sorted().joined(separator: ", "))")
        
        // Try different response structures
        var items: [[String: Any]] = []
        var nextMaxId: String?
        
        // Structure 1: sectional_items -> layout_content -> medias/clips/fill_items
        if let sectionalItems = json["sectional_items"] as? [[String: Any]] {
            print("🔍 [EXPLORE] Found sectional_items structure with \(sectionalItems.count) sections")
            for (sectionIndex, section) in sectionalItems.enumerated() {
                print("🔍 [EXPLORE] Section \(sectionIndex + 1) keys: \(section.keys.sorted().joined(separator: ", "))")
                
                if let layoutContent = section["layout_content"] as? [String: Any] {
                    print("🔍 [EXPLORE]   layout_content keys: \(layoutContent.keys.sorted().joined(separator: ", "))")
                    
                    // Method 1: Check for medias array
                    if let medias = layoutContent["medias"] as? [[String: Any]] {
                        print("🔍 [EXPLORE]   Found \(medias.count) medias in section \(sectionIndex + 1)")
                        for mediaWrapper in medias {
                            if let media = mediaWrapper["media"] as? [String: Any] {
                                items.append(media)
                            }
                        }
                    }
                    
                    // Method 2: Check for one_by_two_item.clips.items
                    if let oneByTwoItem = layoutContent["one_by_two_item"] as? [String: Any],
                       let clips = oneByTwoItem["clips"] as? [String: Any],
                       let clipsItems = clips["items"] as? [[String: Any]] {
                        print("🔍 [EXPLORE]   Found \(clipsItems.count) clips in section \(sectionIndex + 1)")
                        for clipItem in clipsItems {
                            if let media = clipItem["media"] as? [String: Any] {
                                items.append(media)
                            }
                        }
                    }
                    
                    // Method 3: Check for fill_items
                    if let fillItems = layoutContent["fill_items"] as? [[String: Any]] {
                        print("🔍 [EXPLORE]   Found \(fillItems.count) fill_items in section \(sectionIndex + 1)")
                        for fillItem in fillItems {
                            if let media = fillItem["media"] as? [String: Any] {
                                items.append(media)
                            }
                        }
                    }
                }
            }
            nextMaxId = json["next_max_id"] as? String
        }
        // Structure 2: items directly
        else if let directItems = json["items"] as? [[String: Any]] {
            print("🔍 [EXPLORE] Found direct items structure with \(directItems.count) items")
            items = directItems
            nextMaxId = json["next_max_id"] as? String
        }
        
        print("🔍 [EXPLORE] Total raw items extracted: \(items.count)")
        
        var mediaItems: [InstagramMediaItem] = []
        
        for (index, item) in items.enumerated() {
            // Try multiple ways to get the pk
            var pkValue: Int64?
            
            if let pk = item["pk"] as? Int64 {
                pkValue = pk
            } else if let pkString = item["pk"] as? String, let pk = Int64(pkString) {
                pkValue = pk
            } else if let strongId = item["strong_id__"] as? String {
                let components = strongId.split(separator: "_")
                if let firstPart = components.first, let pk = Int64(String(firstPart)) {
                    pkValue = pk
                }
            } else if let id = item["id"] as? String, let pk = Int64(id) {
                pkValue = pk
            }
            
            guard let pk = pkValue else {
                print("⚠️ [EXPLORE] Item \(index + 1)/\(items.count) has no valid pk, keys: \(item.keys.sorted().joined(separator: ", "))")
                continue
            }
            
            let caption = (item["caption"] as? [String: Any])?["text"] as? String
            
            var imageUrl = ""
            if let imageVersions = item["image_versions2"] as? [String: Any],
               let candidates = imageVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let url = firstCandidate["url"] as? String {
                imageUrl = url
            }
            
            guard !imageUrl.isEmpty else {
                print("⚠️ [EXPLORE] Item \(index + 1)/\(items.count) has no image URL")
                continue
            }
            
            let takenAt: Date?
            if let timestamp = item["taken_at"] as? TimeInterval {
                takenAt = Date(timeIntervalSince1970: timestamp)
            } else {
                takenAt = nil
            }
            
            let likeCount = item["like_count"] as? Int
            let commentCount = item["comment_count"] as? Int
            
            // Extract video URL if it's a video
            var videoUrl: String?
            if let videoVersions = item["video_versions"] as? [[String: Any]],
               let firstVideo = videoVersions.first,
               let url = firstVideo["url"] as? String {
                videoUrl = url
            }
            
            // Determine media type
            let mediaType: InstagramMediaItem.MediaType
            if let carouselMedia = item["carousel_media"] as? [[String: Any]], !carouselMedia.isEmpty {
                mediaType = .carousel
            } else if videoUrl != nil {
                mediaType = .video
            } else {
                mediaType = .photo
            }
            
            let mediaItem = InstagramMediaItem(
                id: String(pk),
                mediaId: String(pk),
                imageURL: imageUrl,
                videoURL: videoUrl,
                caption: caption,
                takenAt: takenAt,
                likeCount: likeCount,
                commentCount: commentCount,
                mediaType: mediaType
            )
            mediaItems.append(mediaItem)
        }
        
        print("✅ [EXPLORE] Successfully parsed \(mediaItems.count) items with valid images")
        return (mediaItems, nextMaxId)
    }
    
    // MARK: - Upload Photo
    
    func uploadPhoto(imageData: Data, caption: String = "") async throws -> String? {
        print("📤 [UPLOAD] Starting photo upload...")
        print("   Image size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
        
        // ANTI-BOT: Check lockdown
        if isLocked {
            print("🚨 [UPLOAD] Lockdown active - ABORT")
            throw InstagramError.apiError("Lockdown active. Wait before uploading.")
        }
        
        // ANTI-BOT: Check cooldown between uploads
        let (onCooldown, remaining) = isPhotoUploadOnCooldown()
        if onCooldown {
            let minutes = remaining / 60
            let seconds = remaining % 60
            print("⏰ [UPLOAD] Still on cooldown: \(minutes)m \(seconds)s remaining")
            throw InstagramError.apiError("Please wait \(minutes)m \(seconds)s before uploading another photo.")
        }
        
        // ANTI-BOT: Detect duplicate image (prevent uploading same photo twice)
        let imageHash = hashImageData(imageData)
        if let lastHash = UserDefaults.standard.string(forKey: "last_upload_photo_hash"),
           lastHash == imageHash {
            print("⚠️ [UPLOAD] Same image already uploaded - SKIP")
            throw InstagramError.apiError("This photo was already uploaded. Duplicate uploads may trigger bot detection.")
        }
        
        // ANTI-BOT: Wait if network changed recently
        try await waitForNetworkStability()
        
        print("   Image hash: \(String(imageHash.prefix(16)))...")
        
        // Step 1: Generate upload ID and names (like instagrapi)
        let uploadId = String(Int(Date().timeIntervalSince1970 * 1000))
        let uploadName = "\(uploadId)_0_\(Int.random(in: 1000000000...9999999999))"
        let waterfallId = UUID().uuidString
        print("   Upload ID: \(uploadId)")
        print("   Upload Name: \(uploadName)")
        print("   Waterfall ID: \(waterfallId)")
        
        // Step 2: Build rupload_params JSON (exactly like instagrapi)
        let ruploadParams: [String: Any] = [
            "retry_context": "{\"num_step_auto_retry\":0,\"num_reupload\":0,\"num_step_manual_retry\":0}",
            "media_type": "1",
            "xsharing_user_ids": "[]",
            "upload_id": uploadId,
            "image_compression": "{\"lib_name\":\"moz\",\"lib_version\":\"3.1.m\",\"quality\":\"80\"}"
        ]
        
        guard let ruploadParamsData = try? JSONSerialization.data(withJSONObject: ruploadParams),
              let ruploadParamsString = String(data: ruploadParamsData, encoding: .utf8) else {
            print("❌ [UPLOAD] Failed to serialize rupload params")
            throw InstagramError.uploadFailed
        }
        
        // Step 3: Upload image bytes (exactly like instagrapi)
        guard let uploadURL = URL(string: "https://i.instagram.com/rupload_igphoto/\(uploadName)") else {
            print("❌ [UPLOAD] Invalid URL")
            throw InstagramError.invalidURL
        }
        
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        
        // Critical headers (matching instagrapi exactly)
        uploadRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        uploadRequest.setValue("sessionid=\(session.sessionId); csrftoken=\(session.csrfToken); ds_user_id=\(session.userId)", forHTTPHeaderField: "Cookie")
        uploadRequest.setValue(session.csrfToken, forHTTPHeaderField: "X-CSRFToken")
        uploadRequest.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        uploadRequest.setValue(deviceId, forHTTPHeaderField: "X-IG-Device-ID")
        uploadRequest.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        
        // Upload-specific headers (matching instagrapi exactly)
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(String(imageData.count), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue(ruploadParamsString, forHTTPHeaderField: "X-Instagram-Rupload-Params")
        uploadRequest.setValue(waterfallId, forHTTPHeaderField: "X_FB_PHOTO_WATERFALL_ID")
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "X-Entity-Type")
        uploadRequest.setValue(uploadName, forHTTPHeaderField: "X-Entity-Name")
        uploadRequest.setValue(String(imageData.count), forHTTPHeaderField: "X-Entity-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "Offset")
        
        uploadRequest.httpBody = imageData
        
        print("   Sending image bytes to Instagram...")
        let (uploadData, uploadResponse) = try await postSession.data(for: uploadRequest)
        
        if let httpResponse = uploadResponse as? HTTPURLResponse {
            print("   Upload response status: \(httpResponse.statusCode)")
        }
        
        if let jsonString = String(data: uploadData, encoding: .utf8) {
            print("   Upload response body: \(jsonString)")
        }
        
        guard let uploadJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let uploadIdResponse = uploadJson["upload_id"] as? String else {
            print("❌ [UPLOAD] Failed to get upload_id from response")
            if let uploadJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any] {
                print("   Response JSON: \(uploadJson)")
            }
            throw InstagramError.uploadFailed
        }
        
        print("✅ [UPLOAD] Image bytes uploaded. Upload ID: \(uploadIdResponse)")
        
        // Human delay before configure
        let delay = UInt64.random(in: 3_000_000_000...4_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s before configure...")
        try await Task.sleep(nanoseconds: delay)
        
        // Step 4: Configure media (with more complete data like instagrapi)
        let configBody: [String: String] = [
            "upload_id": uploadIdResponse,
            "caption": caption,
            "source_type": "4",
            "media_folder": "Camera",
            "device_id": deviceId
        ]
        
        print("   Configuring media...")
        let configData = try await apiRequest(
            method: "POST",
            path: "/media/configure/",
            body: configBody
        )
        
        if let jsonString = String(data: configData, encoding: .utf8) {
            print("   Configure response: \(jsonString)")
        }
        
        if let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let media = configJson["media"] as? [String: Any] {
            
            // Instagram puede devolver pk como String o Int64, manejamos ambos
            let mediaId: String?
            if let pkString = media["pk"] as? String {
                mediaId = pkString
            } else if let pkInt = media["pk"] as? Int64 {
                mediaId = String(pkInt)
            } else if let pkInt = media["pk"] as? Int {
                mediaId = String(pkInt)
            } else {
                mediaId = nil
            }
            
            if let mediaId = mediaId {
                print("✅ [UPLOAD] Photo uploaded successfully! Media ID: \(mediaId)")
                
                // ANTI-BOT: Save hash and cooldown after successful upload
                let imageHash = hashImageData(imageData)
                UserDefaults.standard.set(imageHash, forKey: "last_upload_photo_hash")
                
                // Cooldown: 2 minutes between photo uploads (realistic human behavior)
                let cooldownUntil = Date().addingTimeInterval(120) // 2 min
                UserDefaults.standard.set(cooldownUntil, forKey: "photo_upload_cooldown_until")
                print("   Cooldown set: 2 minutes before next upload")
                
                return mediaId
            }
        }
        
        print("❌ [UPLOAD] Failed to get media ID from configure response")
        return nil
    }
    
    /// Check if photo upload is on cooldown
    private func isPhotoUploadOnCooldown() -> (onCooldown: Bool, remainingSeconds: Int) {
        guard let cooldownUntil = UserDefaults.standard.object(forKey: "photo_upload_cooldown_until") as? Date else {
            return (false, 0)
        }
        
        let remaining = cooldownUntil.timeIntervalSinceNow
        if remaining > 0 {
            return (true, Int(remaining))
        }
        
        // Cooldown expired
        UserDefaults.standard.removeObject(forKey: "photo_upload_cooldown_until")
        return (false, 0)
    }
    
    // MARK: - Reveal (Unarchive + Comment with latest follower)
    
    func reveal(mediaId: String) async throws -> (success: Bool, follower: String?, commentId: String?) {
        print("✨ [REVEAL] Starting reveal for media ID: \(mediaId)")
        
        // Step 1: Unarchive
        print("   Step 1: Unarchiving...")
        let unarchived = try await unarchivePhoto(mediaId: mediaId)
        
        guard unarchived else {
            print("❌ [REVEAL] Unarchive failed")
            return (false, nil, nil)
        }
        
        print("✅ [REVEAL] Unarchived successfully")
        
        // IMPORTANT: Instagram needs time to process the unarchive before allowing comments
        let delay = UInt64.random(in: 10_000_000_000...15_000_000_000) // 10-15 seconds
        print("   Waiting \(delay / 1_000_000_000)s before commenting (Instagram needs time)...")
        try await Task.sleep(nanoseconds: delay)
        
        // Step 2: Get latest follower
        print("   Step 2: Fetching latest follower...")
        let follower = try await getLatestFollower()
        let followerName = follower?.fullName ?? follower?.username ?? "you"
        print("   Follower name: \(followerName)")
        
        // Step 3: Comment
        print("   Step 3: Posting comment...")
        let commentText = "\(followerName), this was written for you"
        let commentId = try await commentOnMedia(mediaId: mediaId, text: commentText)
        
        if let commentId = commentId {
            print("✅ [REVEAL] Comment posted successfully! ID: \(commentId)")
        } else {
            print("⚠️ [REVEAL] Comment posting failed")
        }
        
        return (true, followerName, commentId)
    }
    
    // MARK: - Hide (Delete comment + Archive)
    
    func hide(mediaId: String, commentId: String?) async throws -> Bool {
        // Step 1: Delete comment if exists
        if let commentId = commentId {
            _ = try await deleteComment(mediaId: mediaId, commentId: commentId)
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))
        }
        
        // Step 2: Archive
        return try await archivePhoto(mediaId: mediaId)
    }
    
    // MARK: - Search Users
    
    func searchUsers(query: String) async throws -> [UserSearchResult] {
        guard !query.isEmpty else { return [] }
        
        print("🔍 [SEARCH] Searching for: \(query)")
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/users/search/?q=\(encodedQuery)&search_surface=user_search_page"
        
        let data = try await apiRequest(method: "GET", path: path)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [[String: Any]] else {
            print("❌ [SEARCH] Failed to parse search results")
            return []
        }
        
        print("🔍 [SEARCH] Found \(users.count) users")
        
        var results: [UserSearchResult] = []
        
        for user in users.prefix(20) {
            let pk = user["pk"] as? Int64
            let pkString = user["pk"] as? String
            let userId = pk != nil ? String(pk!) : (pkString ?? "")
            
            let username = user["username"] as? String ?? ""
            let fullName = user["full_name"] as? String ?? ""
            let profilePicUrl = user["profile_pic_url"] as? String ?? ""
            let isVerified = user["is_verified"] as? Bool ?? false
            
            let result = UserSearchResult(
                userId: userId,
                username: username,
                fullName: fullName,
                profilePicURL: profilePicUrl,
                isVerified: isVerified
            )
            results.append(result)
        }
        
        return results
    }
    
    func searchAndLoadUserProfile(username: String) async throws -> InstagramProfile {
        print("🔍 [SEARCH] Loading profile for @\(username)")
        
        // First search to get user ID
        let results = try await searchUsers(query: username)
        
        guard let exactMatch = results.first(where: { $0.username.lowercased() == username.lowercased() }) else {
            print("❌ [SEARCH] User @\(username) not found")
            throw InstagramError.apiError("Usuario no encontrado")
        }
        
        print("✅ [SEARCH] Found user ID: \(exactMatch.userId)")
        
        // Load full profile
        guard let profile = try await getProfileInfo(userId: exactMatch.userId) else {
            print("❌ [SEARCH] Failed to load profile for user ID: \(exactMatch.userId)")
            throw InstagramError.apiError("Error al cargar el perfil")
        }
        
        return profile
    }
    
    // MARK: - Instagram Notes
    
    /// Create an Instagram Note (bubble above profile pic in DMs)
    /// Max 60 characters, lasts 24 hours
    func createNote(text: String, audience: Int = 0) async throws -> Bool {
        print("📝 [NOTE] Creating note: \"\(text)\"")
        
        // Validate
        guard !text.isEmpty else {
            throw InstagramError.apiError("Note text cannot be empty")
        }
        guard text.count <= 60 else {
            throw InstagramError.apiError("Note must be 60 characters or less (\(text.count) given)")
        }
        
        // ANTI-BOT: Check lockdown
        if isLocked {
            throw InstagramError.apiError("Lockdown active. Wait before creating a note.")
        }
        
        // ANTI-BOT: Check cooldown (prevent spam)
        let (onCooldown, remaining) = isNoteOnCooldown()
        if onCooldown {
            let minutes = remaining / 60
            let seconds = remaining % 60
            throw InstagramError.apiError("Please wait \(minutes)m \(seconds)s before sending another note.")
        }
        
        // ANTI-BOT: Detect duplicate text (prevent spam)
        if let lastNote = UserDefaults.standard.string(forKey: "last_note_text"),
           lastNote == text {
            throw InstagramError.apiError("You already sent this note. Instagram may flag duplicate notes as spam.\n\nPlease write something different.")
        }
        
        // ANTI-BOT: Wait if network changed recently
        try await waitForNetworkStability()
        
        // ANTI-BOT: Human delay (1-3 seconds) - longer than before
        let delay = UInt64.random(in: 1_000_000_000...3_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s (human delay)...")
        try await Task.sleep(nanoseconds: delay)
        
        let body: [String: String] = [
            "audience": String(audience),
            "text": text,
            "_csrftoken": session.csrfToken,
            "_uid": session.userId,
            "_uuid": clientUUID,
            "uuid": UUID().uuidString
        ]
        
        let data = try await apiRequest(
            method: "POST",
            path: "/notes/create_note/",
            body: body
        )
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String, status == "ok" {
                print("✅ [NOTE] Note created successfully")
                
                // ANTI-BOT: Save text to prevent duplicates
                UserDefaults.standard.set(text, forKey: "last_note_text")
                
                // ANTI-BOT: Set cooldown (60 seconds between notes)
                let cooldownUntil = Date().addingTimeInterval(60)
                UserDefaults.standard.set(cooldownUntil, forKey: "note_cooldown_until")
                
                return true
            } else {
                let message = json["message"] as? String ?? "Unknown error"
                print("❌ [NOTE] Failed: \(message)")
                throw InstagramError.apiError("Note failed: \(message)")
            }
        }
        
        return false
    }
    
    /// Check if notes are on cooldown
    private func isNoteOnCooldown() -> (onCooldown: Bool, remainingSeconds: Int) {
        guard let cooldownUntil = UserDefaults.standard.object(forKey: "note_cooldown_until") as? Date else {
            return (false, 0)
        }
        
        let remaining = cooldownUntil.timeIntervalSinceNow
        if remaining > 0 {
            return (true, Int(remaining))
        }
        
        // Cooldown expired
        UserDefaults.standard.removeObject(forKey: "note_cooldown_until")
        return (false, 0)
    }
    
    /// Delete the current Instagram Note
    func deleteNote(noteId: String) async throws -> Bool {
        print("🗑️ [NOTE] Deleting note: \(noteId)")
        
        if isLocked {
            throw InstagramError.apiError("Lockdown active.")
        }
        
        try await waitForNetworkStability()
        
        let body: [String: String] = [
            "id": noteId,
            "_csrftoken": session.csrfToken,
            "_uid": session.userId,
            "_uuid": clientUUID,
            "uuid": UUID().uuidString
        ]
        
        let data = try await apiRequest(
            method: "POST",
            path: "/notes/delete_note/",
            body: body
        )
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String, status == "ok" {
            print("✅ [NOTE] Note deleted")
            return true
        }
        
        return false
    }
    
    // MARK: - Change Profile Picture
    
    /// Changes Instagram profile picture
    /// CRITICAL ANTI-BOT: Only call after checking:
    /// - Network is stable
    /// - No lockdown active
    /// - Image hash is different from last upload
    func changeProfilePicture(imageData: Data) async throws -> Bool {
        print("🖼️ [PROFILE PIC] Starting profile picture change...")
        
        // CRITICAL: Check lockdown
        if isLocked {
            print("🚨 [PROFILE PIC] Lockdown active - ABORT")
            throw InstagramError.apiError("Lockdown active. Wait before changing profile picture.")
        }
        
        // ANTI-BOT: Wait if network changed recently
        try await waitForNetworkStability()
        
        // Check if image hash matches last upload (prevent duplicate)
        let imageHash = hashImageData(imageData)
        if let lastHash = UserDefaults.standard.string(forKey: "last_profile_pic_hash"),
           lastHash == imageHash {
            print("⚠️ [PROFILE PIC] Same image already uploaded - SKIP")
            throw InstagramError.apiError("This is already your profile picture. Please select a different image.")
        }
        
        // Convert to JPEG if needed (Instagram requires JPEG)
        guard let uiImage = UIImage(data: imageData),
              let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
            print("❌ [PROFILE PIC] Failed to convert image to JPEG")
            throw InstagramError.apiError("Failed to process image")
        }
        
        print("   Image size: \(jpegData.count / 1024) KB")
        print("   Image hash: \(String(imageHash.prefix(16)))...")
        
        // ANTI-BOT: Human delay before upload (2-4 seconds)
        let humanDelay = UInt64.random(in: 2_000_000_000...4_000_000_000)
        print("   Waiting \(humanDelay / 1_000_000_000)s (human delay)...")
        try await Task.sleep(nanoseconds: humanDelay)
        
        // STEP 1: Upload image via rupload_igphoto (same as regular photo upload)
        let uploadId = String(Int(Date().timeIntervalSince1970 * 1000))
        let uploadName = "\(uploadId)_0_\(Int.random(in: 1000000000...9999999999))"
        let waterfallId = UUID().uuidString
        
        print("   Upload ID: \(uploadId)")
        
        let ruploadParams: [String: Any] = [
            "retry_context": "{\"num_step_auto_retry\":0,\"num_reupload\":0,\"num_step_manual_retry\":0}",
            "media_type": "1",
            "xsharing_user_ids": "[]",
            "upload_id": uploadId,
            "image_compression": "{\"lib_name\":\"moz\",\"lib_version\":\"3.1.m\",\"quality\":\"80\"}"
        ]
        
        guard let ruploadParamsData = try? JSONSerialization.data(withJSONObject: ruploadParams),
              let ruploadParamsString = String(data: ruploadParamsData, encoding: .utf8) else {
            throw InstagramError.uploadFailed
        }
        
        guard let uploadURL = URL(string: "https://i.instagram.com/rupload_igphoto/\(uploadName)") else {
            throw InstagramError.invalidURL
        }
        
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        
        // Critical headers (matching instagrapi exactly)
        uploadRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        uploadRequest.setValue("sessionid=\(session.sessionId); csrftoken=\(session.csrfToken); ds_user_id=\(session.userId)", forHTTPHeaderField: "Cookie")
        uploadRequest.setValue(session.csrfToken, forHTTPHeaderField: "X-CSRFToken")
        uploadRequest.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        uploadRequest.setValue(deviceId, forHTTPHeaderField: "X-IG-Device-ID")
        uploadRequest.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        
        // Upload-specific headers
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(String(jpegData.count), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue(ruploadParamsString, forHTTPHeaderField: "X-Instagram-Rupload-Params")
        uploadRequest.setValue(waterfallId, forHTTPHeaderField: "X_FB_PHOTO_WATERFALL_ID")
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "X-Entity-Type")
        uploadRequest.setValue(uploadName, forHTTPHeaderField: "X-Entity-Name")
        uploadRequest.setValue(String(jpegData.count), forHTTPHeaderField: "X-Entity-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "Offset")
        
        uploadRequest.httpBody = jpegData
        
        print("   Step 1: Uploading image bytes...")
        let (uploadData, uploadResponse) = try await postSession.data(for: uploadRequest)
        
        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse,
              uploadHttpResponse.statusCode == 200,
              let uploadJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let uploadIdResponse = uploadJson["upload_id"] as? String else {
            print("❌ [PROFILE PIC] Failed to upload image bytes")
            if let errorText = String(data: uploadData, encoding: .utf8) {
                print("   Error: \(errorText)")
            }
            throw InstagramError.uploadFailed
        }
        
        print("   ✅ Image uploaded. Upload ID: \(uploadIdResponse)")
        
        // ANTI-BOT: Human delay between upload and configure (1-3 seconds)
        let configDelay = UInt64.random(in: 1_000_000_000...3_000_000_000)
        print("   Waiting \(configDelay / 1_000_000_000)s before configure...")
        try await Task.sleep(nanoseconds: configDelay)
        
        // STEP 2: Call change_profile_picture with upload_id
        print("   Step 2: Setting as profile picture...")
        let configBody: [String: String] = [
            "upload_id": uploadIdResponse,
            "_csrftoken": session.csrfToken,
            "_uid": session.userId,
            "_uuid": clientUUID
        ]
        
        let data = try await apiRequest(
            method: "POST",
            path: "/accounts/change_profile_picture/",
            body: configBody
        )
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String, status == "ok" {
                print("✅ [PROFILE PIC] Profile picture changed successfully!")
                
                // Save hash to prevent duplicate uploads
                UserDefaults.standard.set(imageHash, forKey: "last_profile_pic_hash")
                
                // ANTI-BOT: Add cooldown before next profile pic change
                let cooldownUntil = Date().addingTimeInterval(300) // 5 minutes
                UserDefaults.standard.set(cooldownUntil, forKey: "profile_pic_cooldown_until")
                
                return true
            } else {
                let message = json["message"] as? String ?? "Unknown error"
                print("❌ [PROFILE PIC] Failed: \(message)")
                throw InstagramError.apiError("Profile picture change failed: \(message)")
            }
        }
        
        print("❌ [PROFILE PIC] Unexpected response format")
        return false
    }
    
    /// Hash image data to detect duplicates
    private func hashImageData(_ data: Data) -> String {
        var hash = 0
        for byte in data {
            hash = (hash &* 31) &+ Int(byte)
        }
        return String(format: "%016x", hash)
    }
    
    /// Check if profile pic change is on cooldown
    func isProfilePicOnCooldown() -> (onCooldown: Bool, remainingSeconds: Int) {
        guard let cooldownUntil = UserDefaults.standard.object(forKey: "profile_pic_cooldown_until") as? Date else {
            return (false, 0)
        }
        
        let remaining = cooldownUntil.timeIntervalSinceNow
        if remaining > 0 {
            return (true, Int(remaining))
        }
        
        // Cooldown expired, clear it
        UserDefaults.standard.removeObject(forKey: "profile_pic_cooldown_until")
        return (false, 0)
    }
}

// MARK: - Errors

enum InstagramError: LocalizedError {
    case invalidURL
    case invalidResponse
    case sessionExpired
    case challengeRequired
    case apiError(String)
    case uploadFailed
    case notLoggedIn
    case networkError(String)    // Safe to retry - network issue, not Instagram rejection
    case botDetected(String)     // STOP EVERYTHING - Instagram detected suspicious activity
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .sessionExpired: return "Session expired. Please login again."
        case .challengeRequired: return "Instagram requires verification. Please complete the challenge in the Instagram app or website."
        case .apiError(let msg): return "API Error: \(msg)"
        case .uploadFailed: return "Upload failed"
        case .notLoggedIn: return "Not logged in"
        case .networkError(let msg): return "Network Error: \(msg)"
        case .botDetected(let msg): return "⚠️ Safety Lock: \(msg)"
        }
    }
    
    /// Whether this error is safe to retry (network issue, not Instagram rejection)
    var isNetworkError: Bool {
        if case .networkError = self { return true }
        return false
    }
    
    /// Whether Instagram detected bot behavior - STOP ALL ACTIVITY
    var isBotDetection: Bool {
        if case .botDetected = self { return true }
        return false
    }
}
