import Foundation
import UIKit
import Combine
import CryptoKit
import Network
import WebKit

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
    /// Counts only API "fail" statuses that indicate real bot-risk signals.
    /// Network errors, timeouts, and transient GET challenges do NOT increment this.
    /// Precautionary lockdown fires at 5 consecutive bot-signal fails.
    private var consecutiveBotSignalErrors: Int = 0

    // Session expiry — set true when any API call returns 403/401
    // Cleared automatically on successful login
    @Published var isSessionExpired: Bool = false

    /// True while a reveal (unarchive) or re-archive operation is running.
    /// Blocks pull-to-refresh in PerformanceView to avoid extra API calls mid-operation.
    @Published var isRevealOperationActive: Bool = false

    /// True while a profile picture upload is in progress (autoProfilePicOnPerformance).
    /// Used to block simultaneous OCR reveal operations (anti-bot: avoid two POST operations at once).
    @Published var isUploadingProfilePic: Bool = false
    /// Counts consecutive challenge_required responses (GET or POST).
    /// After ≥2, UI messages suggest re-login as a solution.
    @Published var challengeRequiredStreak: Int = 0
    /// True for ~5 minutes after any challenge_required is detected (GET or POST).
    /// Views use this to skip non-essential API calls and avoid cascading bot signals.
    @Published var isSessionChallenged: Bool = false
    
    // Network change tracking (anti-bot protection)
    private var lastConnectionType: String = "unknown"
    private var lastNetworkChangeTime: Date?
    @Published var isNetworkStabilizing: Bool = false
    @Published var networkChangedDuringUpload: Bool = false // Alert for active uploads
    private let networkStabilizationDelay: TimeInterval = 4.0 // seconds

    // Cold-start warm-up (anti-bot: avoid API calls immediately after session restore)
    private var sessionRestoredAt: Date? = nil
    private let sessionWarmupDelay: TimeInterval = 3.0 // seconds
    
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
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    private lazy var postSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.waitsForConnectivity = false  // CRITICAL: Don't auto-retry POSTs
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    // MARK: - Pigeon Session (anti-bot: session tracking like real Instagram app)
    private var pigeonSessionId: String = UUID().uuidString
    private let bloksVersionId = "0a3ae4c88248863609c67e278f34af44673cff300bc76add965a9fb036bd3ca3"
    
    // MARK: - Bandwidth Simulation (anti-bot: report realistic connection speeds)
    private var bandwidthSpeedKbps: String = "\(Int.random(in: 2500...8000))"
    private var bandwidthTotalBytesB: Int = 0
    private var bandwidthTotalTimeMs: Int = 0

    // MARK: - WWW-Claim (anti-bot: Instagram rotates this per session; "0" only valid before first call)
    private var wwwClaim: String = "0"
    
    // MARK: - Rate Limiting (anti-bot: max 60 actions/hour)
    private var actionTimestamps: [Date] = []
    private let maxActionsPerHour: Int = 55 // Safe margin below 60
    @Published var actionsThisHour: Int = 0
    @Published var isRateLimited: Bool = false
    
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
            self.sessionRestoredAt = Date()  // Mark cold-start time for warm-up delay
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
                    LogManager.shared.warning("Network changed during session: \(self.lastConnectionType) → \(newConnectionType)", category: .network)
                    self.lastNetworkChangeTime = Date()
                    self.isNetworkStabilizing = true
                    self.networkChangedDuringUpload = true  // Alert active uploads
                    
                    // Auto-disable stabilizing after delay
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(self.networkStabilizationDelay * 1_000_000_000))
                        self.isNetworkStabilizing = false
                        print("✅ [NETWORK] Stabilization complete")
                        LogManager.shared.network("Network stabilization complete")
                    }
                }
                
                self.isConnected = newConnected
                self.connectionType = newConnectionType
                self.lastConnectionType = newConnectionType
                
                let statusText = newConnected ? "Connected" : "Disconnected"
                print("📶 [NETWORK] Connection: \(newConnectionType) - \(statusText)")
                LogManager.shared.network("\(newConnectionType) - \(statusText)")
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
    /// `isWriteOperation`: true for POST/PUT/DELETE, false for GET.
    /// For read-only (GET) requests, challenge_required is treated as a transient
    /// soft-check — we throw the error but skip the app-wide lockdown screen.
    private func checkForBotSignals(data: Data, isWriteOperation: Bool = true) async throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return // Not JSON, skip check
        }
        
        let status = json["status"] as? String ?? ""
        let message = json["message"] as? String ?? ""
        let messageLower = message.lowercased()
        
        // Level 3: Challenge required - Instagram wants verification.
        // For write operations: full lockdown (real bot-risk event).
        // For read (GET) operations: throw without lockdown — GET challenge_required is
        // typically a transient soft-check that clears on its own; no action needed.
        if json["challenge"] != nil || messageLower.contains("challenge_required") {
            print("🚨 BOT DETECTED: Challenge required")
            LogManager.shared.bot("Challenge required - Instagram wants verification")
            await markSessionChallenged(duration: 120)
            // Both GET and POST trigger a visible lockdown so the magician always knows
            // to open the Instagram app and complete any pending verification prompt.
            // POST operations get a longer lockdown (3 min); GET gets a shorter one (2 min)
            // since GET challenges are often transient soft-checks that self-clear.
            let lockDuration: TimeInterval = isWriteOperation ? 180 : 120
            await triggerLockdown(
                reason: "Instagram ha pedido verificación. Abre la app de Instagram — si ves un aviso de verificación, complétalo. Si no aparece nada, la sesión se reanudará automáticamente en 2 minutos.",
                duration: lockDuration
            )
            if isWriteOperation {
                throw InstagramError.botDetected("Challenge required - complete verification in Instagram app")
            } else {
                throw InstagramError.challengeRequired
            }
        }
        
        // Level 4: Login required - session invalidated
        if messageLower.contains("login_required") {
            print("🚨 BOT DETECTED: Login required (session invalidated)")
            LogManager.shared.bot("Login required - Session invalidated by Instagram")
            await triggerLockdown(
                reason: "Instagram invalidated your session. This may indicate suspicious activity was detected.",
                duration: 1800 // 30 minutes
            )
            throw InstagramError.botDetected("Session invalidated by Instagram")
        }
        
        // Level 2: Spam/rate limit detection
        if let spam = json["spam"] as? Bool, spam == true {
            print("🚨 BOT DETECTED: Spam flag")
            LogManager.shared.bot("Spam flag detected by Instagram")
            await triggerLockdown(
                reason: "Instagram flagged this as spam. Stop all activity and wait.",
                duration: 600 // 10 minutes
            )
            throw InstagramError.botDetected("Flagged as spam")
        }
        
        // Level 1: Action blocked
        if messageLower.contains("action blocked") || messageLower.contains("temporarily blocked") {
            print("🚨 BOT DETECTED: Action blocked")
            LogManager.shared.bot("Action blocked by Instagram - temporary ban")
            await triggerLockdown(
                reason: "Instagram has temporarily blocked actions. Do NOT retry. Wait at least 15 minutes.",
                duration: 900 // 15 minutes
            )
            throw InstagramError.botDetected("Action blocked by Instagram")
        }
        
        // Track consecutive "fail" statuses as potential bot signals.
        // Only "fail" with messages that are NOT network errors count toward
        // the precautionary lockdown. This avoids false lockdowns from WiFi drops.
        if status == "fail" {
            let isNetworkRelated = messageLower.contains("connection")
                || messageLower.contains("timeout")
                || messageLower.contains("network")
                || messageLower.contains("offline")
            await MainActor.run {
                consecutiveErrors += 1
                if !isNetworkRelated { consecutiveBotSignalErrors += 1 }
            }
            
            // 5 consecutive bot-signal fails → precautionary lockdown
            if consecutiveBotSignalErrors >= 5 {
                print("🚨 PRECAUTIONARY LOCKDOWN: \(consecutiveBotSignalErrors) consecutive bot-signal API fails")
                LogManager.shared.bot("Precautionary lockdown - \(consecutiveBotSignalErrors) consecutive bot-signal API failures")
                await triggerLockdown(
                    reason: "Multiple consecutive API errors detected. Pausing all activity as a precaution.",
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
    
    /// Marks the session as challenged for `duration` seconds.
    /// During this window, views skip non-essential API calls (profile loads, profile pic
    /// auto-upload, explore refreshes) to avoid cascading bot signals. Does NOT block
    /// uploads/archives, which have their own flow management.
    /// Default 60s cooldown — enough to prevent cascading calls but not so long
    /// that the user feels the app is broken. POST operations (archive/unarchive)
    /// check this flag and abort to avoid triggering a full lockdown.
    private func markSessionChallenged(duration: TimeInterval = 60) async {
        await MainActor.run { isSessionChallenged = true }
        print("⚠️ [SESSION] Marked as challenged — background API calls paused for \(Int(duration))s")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
            await MainActor.run {
                self.isSessionChallenged = false
                print("✅ [SESSION] Challenge window cleared — normal operation resumed")
            }
        }
    }

    @MainActor
    func unlock() {
        isLocked = false
        lockReason = ""
        lockUntil = nil
        consecutiveErrors = 0
        consecutiveBotSignalErrors = 0
        print("🔓 [LOCKDOWN] Deactivated")
    }

    /// Resets the exponential backoff counter without touching lockdown state.
    /// Call after background/optional operations that should not penalise user-facing requests.
    @MainActor
    func resetBackoff() {
        consecutiveErrors = 0
        consecutiveBotSignalErrors = 0
    }

    /// Lightweight session probe: makes a single minimal GET request to Instagram.
    /// Returns `true` if the session is valid (200 OK with user data), `false` if
    /// the session is expired or the challenge is still pending.
    /// Used by the auto-recovery mechanism when the app returns from background
    /// after a lockdown — if the user dismissed the challenge in the real Instagram
    /// app, this probe will succeed and the lockdown is cleared automatically.
    func probeSession() async -> Bool {
        guard isLoggedIn, !session.sessionId.isEmpty else { return false }
        do {
            // Use the accounts/current_user endpoint — minimal payload, no side effects.
            let url = URL(string: "https://i.instagram.com/api/v1/accounts/current_user/?edit=true")!
            var req = URLRequest(url: url)
            req.setValue("sessionid=\(session.sessionId); ds_user_id=\(session.userId)", forHTTPHeaderField: "Cookie")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["user"] != nil {
                print("✅ [PROBE] Session valid — challenge was resolved")
                return true
            }
            print("⚠️ [PROBE] Session probe failed — status \(http.statusCode)")
            return false
        } catch {
            print("⚠️ [PROBE] Session probe error: \(error.localizedDescription)")
            return false
        }
    }
    
    @MainActor
    /// Dismiss the session-expired overlay without logging out.
    /// Use this to let the magician navigate to Settings and re-login manually.
    func dismissSessionExpiredOverlay() {
        isSessionExpired = false
    }

    func emergencyLogout() {
        // Clear session state
        session = .empty
        isLoggedIn = false
        isSessionExpired = false   // ← dismiss the SessionGuardView overlay
        KeychainService.shared.deleteSession()
        KeychainService.shared.clearCredentials()

        // Reset lockdown
        unlock()

        // Clear profile cache (disk + memory)
        ProfileCacheService.shared.clearAll()
        ProfileCacheService.shared.pendingProfilePic = nil
        UserDefaults.standard.removeObject(forKey: "instagram_mid")

        // Clear HTTP cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("instagram.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        // Clear WKWebView session data
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { }

        // Clear cached data
        URLCache.shared.removeAllCachedResponses()

        print("🚨 [EMERGENCY] Full logout and cache clear completed")
    }

    // MARK: - Session Validation

    enum SessionStatus {
        case valid
        case expired
        case challenged
        case networkError
    }

    /// Lightweight GET to check whether the current session is still alive.
    /// Does NOT trigger lockdown by itself — only sets `isSessionExpired` when appropriate.
    /// Use this for pre-flight checks (e.g., before entering Performance view).
    func validateSession() async -> SessionStatus {
        guard isLoggedIn else { return .expired }
        guard isConnected else { return .networkError }

        print("🔍 [SESSION] Validating session...")
        do {
            let data = try await apiRequest(method: "GET", path: "/accounts/current_user/?edit=true")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["user"] != nil {
                await MainActor.run { isSessionExpired = false }
                print("✅ [SESSION] Session is valid")
                return .valid
            }
            // Response was 200 but no "user" key — treat as expired
            await MainActor.run { isSessionExpired = true }
            print("⚠️ [SESSION] Unexpected response structure — marking as expired")
            return .expired
        } catch InstagramError.sessionExpired {
            await MainActor.run { isSessionExpired = true }
            print("❌ [SESSION] Session expired (401/403)")
            return .expired
        } catch InstagramError.challengeRequired {
            print("⚠️ [SESSION] Challenge required during validation")
            return .challenged
        } catch InstagramError.networkError {
            print("📶 [SESSION] Network error during validation")
            return .networkError
        } catch {
            print("⚠️ [SESSION] Validation error: \(error) — assuming network issue")
            return .networkError
        }
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

    /// Waits until at least `sessionWarmupDelay` seconds have elapsed since the app
    /// restored its session from Keychain (cold start). Prevents the first API call
    /// from firing too quickly after launch, which Instagram flags as bot behaviour.
    func waitForSessionWarmup() async throws {
        guard let restoredAt = sessionRestoredAt else { return }
        let elapsed = Date().timeIntervalSince(restoredAt)
        guard elapsed < sessionWarmupDelay else {
            sessionRestoredAt = nil  // Warm-up complete — clear to avoid future waits
            return
        }
        let remaining = sessionWarmupDelay - elapsed
        print("⏳ [WARMUP] Cold-start detected — waiting \(String(format: "%.1f", remaining))s before first API call...")
        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        sessionRestoredAt = nil
        print("✅ [WARMUP] Session warm-up complete, proceeding with API call.")
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
                    self.isSessionExpired = false   // clear on successful login
                    KeychainService.shared.saveSession(self.session)
                    print("✅ Logged in as @\(username)")
                }
            } else {
                await MainActor.run {
                    self.isLoggedIn = true
                    self.isSessionExpired = false   // clear on successful login
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
        KeychainService.shared.clearCredentials()

        // Clear profile cache (disk + memory) so next login loads fresh data for the new account
        ProfileCacheService.shared.clearAll()
        ProfileCacheService.shared.pendingProfilePic = nil

        // Clear instagram_mid so it is re-fetched for the new account
        UserDefaults.standard.removeObject(forKey: "instagram_mid")

        // Clear HTTP cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        // Clear WKWebView session data (cookies + local storage) so the next login WebView
        // starts fresh and doesn't auto-restore the previous account's web session
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { }

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
        
        let delay = UInt64.random(in: 500_000_000...1_500_000_000)
        print("⏱️ [FOLLOW] Waiting \(Double(delay) / 1_000_000_000.0)s...")
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
    
    /// Builds the Cookie header from ALL cookies stored by the WebView login.
    /// Previously only 3 cookies were sent (sessionid, csrftoken, ds_user_id), which
    /// caused Notes (and other newer endpoints) to fail — they require cookies like
    /// `rur` (region routing), `mid` (machine id), `ig_did`, etc.
    private func buildCookieHeader() -> String {
        let igDomains = ["https://i.instagram.com", "https://www.instagram.com", "https://instagram.com"]
        var seen = Set<String>()
        var parts: [String] = []

        for domain in igDomains {
            guard let url = URL(string: domain) else { continue }
            let domainCookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            for cookie in domainCookies {
                guard !seen.contains(cookie.name) else { continue }
                seen.insert(cookie.name)
                parts.append("\(cookie.name)=\(cookie.value)")
            }
        }

        // Always ensure the three critical session cookies are present
        // (in case the cookie storage is empty — e.g. first launch before any response)
        if !seen.contains("sessionid")  { parts.append("sessionid=\(session.sessionId)") }
        if !seen.contains("csrftoken")  { parts.append("csrftoken=\(session.csrfToken)") }
        if !seen.contains("ds_user_id") { parts.append("ds_user_id=\(session.userId)") }

        let header = parts.joined(separator: "; ")
        print("🍪 [COOKIE] Sending \(parts.count) cookies: \(seen.sorted().joined(separator: ", "))")
        return header
    }

    private func buildHeaders() -> [String: String] {
        let device = DeviceInfo.shared
        
        // ANTI-BOT: Simulate realistic bandwidth tracking (accumulate like real app)
        bandwidthTotalBytesB += Int.random(in: 5000...50000)
        bandwidthTotalTimeMs += Int.random(in: 50...500)
        
        // ANTI-BOT: Refresh bandwidth speed occasionally (like real network fluctuation)
        if Int.random(in: 0...10) == 0 {
            bandwidthSpeedKbps = "\(Int.random(in: 2500...8000))"
        }
        
        var headers: [String: String] = [
            // Core identification
            "User-Agent": userAgent,
            "X-CSRFToken": session.csrfToken,
            "X-IG-App-ID": "936619743392459",
            "X-IG-Device-ID": deviceId,
            
            // Connection info
            "X-IG-Connection-Type": connectionType == "WiFi" ? "WIFI" : "4G",
            "X-IG-Connection-Speed": "\(Int.random(in: 1000...3700))kbps",
            "X-IG-Capabilities": "36r/F/8=",
            
            // Locale
            "X-IG-App-Locale": device.deviceLocale,
            "X-IG-Device-Locale": device.deviceLocale,
            
            // ANTI-BOT: Pigeon session tracking (like real Instagram app)
            "X-Pigeon-Session-Id": pigeonSessionId,
            "X-Pigeon-Rawclienttime": String(format: "%.3f", Date().timeIntervalSince1970),
            
            // ANTI-BOT: Bandwidth reporting (real app sends these)
            "X-IG-Bandwidth-Speed-KBPS": bandwidthSpeedKbps,
            "X-IG-Bandwidth-TotalBytes-B": String(bandwidthTotalBytesB),
            "X-IG-Bandwidth-TotalTime-MS": String(bandwidthTotalTimeMs),
            
            // ANTI-BOT: Bloks framework version
            "X-Bloks-Version-Id": bloksVersionId,
            "X-Bloks-Is-Layout-RTL": "false",
            
            // ANTI-BOT: WWW Claim — updated from response headers after each successful call
            "X-IG-WWW-Claim": wwwClaim,
            
            // Standard headers
            "X-Requested-With": "XMLHttpRequest",
            "Accept-Language": "\(device.deviceLanguage)-\(Locale.current.region?.identifier ?? "US"),\(device.deviceLanguage);q=0.9",
            "Accept-Encoding": "gzip, deflate",
            "Content-Type": "application/x-www-form-urlencoded",
            "Cookie": buildCookieHeader()
        ]
        
        // ANTI-BOT: Add X-MID if available (Machine ID, set by Instagram after first request)
        if let mid = UserDefaults.standard.string(forKey: "instagram_mid") {
            headers["X-MID"] = mid
        }
        
        return headers
    }
    
    /// Refresh Pigeon session ID (call when app comes to foreground)
    func refreshPigeonSession() {
        pigeonSessionId = UUID().uuidString
        print("🐦 [PIGEON] New session ID: \(String(pigeonSessionId.prefix(8)))...")
    }
    
    // MARK: - Rate Limiting (ANTI-BOT: max ~55 actions/hour)
    
    /// Track an action for rate limiting
    private func trackAction() {
        let now = Date()
        // Remove timestamps older than 1 hour
        actionTimestamps = actionTimestamps.filter { now.timeIntervalSince($0) < 3600 }
        actionTimestamps.append(now)
        
        DispatchQueue.main.async {
            self.actionsThisHour = self.actionTimestamps.count
            self.isRateLimited = self.actionTimestamps.count >= self.maxActionsPerHour
        }
        
        if actionTimestamps.count >= maxActionsPerHour {
            print("⚠️ [RATE LIMIT] \(actionTimestamps.count)/\(maxActionsPerHour) actions this hour - LIMIT REACHED")
            LogManager.shared.warning("Rate limit approaching: \(actionTimestamps.count)/\(maxActionsPerHour) actions/hour", category: .api)
        }
    }
    
    /// Check if rate limited (PUBLIC for views to show warning)
    func checkRateLimit() -> (limited: Bool, actionsUsed: Int, remaining: Int) {
        let now = Date()
        let recentActions = actionTimestamps.filter { now.timeIntervalSince($0) < 3600 }
        let remaining = max(0, maxActionsPerHour - recentActions.count)
        return (recentActions.count >= maxActionsPerHour, recentActions.count, remaining)
    }

    // MARK: - Media Status Pre-Check (ANTI-BOT: verify state before acting)

    /// Fetches the real archive status of a media item from Instagram.
    /// Uses a raw GET that does NOT count toward the write-action rate limit.
    /// Returns: true = archived (hidden), false = public (visible), nil = couldn't determine.
    func getMediaIsArchived(mediaId: String) async throws -> Bool? {
        guard isLoggedIn, !isLocked else {
            print("⚠️ [STATE-CHECK] Skipped (id: \(mediaId)) — not logged in or locked")
            return nil
        }

        let pk = mediaId.split(separator: "_").first.map(String.init) ?? mediaId
        print("🔍 [STATE-CHECK] Checking media (pk: \(pk))...")
        guard let url = URL(string: "\(baseURL)/media/\(pk)/info/") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let headers = buildHeaders()
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        do {
            let (data, response) = try await getSession.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("🔍 [STATE-CHECK] HTTP \(statusCode) for pk: \(pk)")

            guard statusCode < 400 else {
                print("⚠️ [STATE-CHECK] HTTP error \(statusCode) for pk: \(pk)")
                LogManager.shared.warning("State check HTTP \(statusCode) for media \(pk)", category: .api)
                if statusCode == 403 || statusCode == 401 {
                    await MainActor.run { self.isSessionExpired = true }
                    throw InstagramError.sessionExpired
                }
                // Detect challenge_required in error body (GET → no lockdown, just mark challenged)
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let msg = (errJson["message"] as? String ?? "").lowercased()
                    if errJson["challenge"] != nil || msg.contains("challenge_required") {
                        print("⚠️ [STATE-CHECK] challenge_required on GET (transient) — marking session challenged")
                        await markSessionChallenged(duration: 60)
                        throw InstagramError.challengeRequired
                    }
                }
                return nil
            }

            // Log raw response for debugging (truncated to 400 chars)
            if let raw = String(data: data, encoding: .utf8) {
                let preview = String(raw.prefix(400))
                print("🔍 [STATE-CHECK] Raw response: \(preview)")
                LogManager.shared.info("State check raw (pk: \(pk)): \(preview)", category: .api)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ [STATE-CHECK] Could not parse JSON for pk: \(pk)")
                return nil
            }

            // Detect bot signals in 200 body (e.g. challenge in a "status":"ok" response)
            try await checkForBotSignals(data: data, isWriteOperation: false)

            // Check top-level status
            let status = json["status"] as? String ?? "unknown"
            print("🔍 [STATE-CHECK] status=\(status) for pk: \(pk)")

            guard let items = json["items"] as? [[String: Any]], let first = items.first else {
                print("⚠️ [STATE-CHECK] No 'items' array or empty for pk: \(pk) — status: \(status)")
                LogManager.shared.warning("State check: no items returned for pk \(pk) (status: \(status))", category: .api)
                return nil
            }

            // Log all top-level keys in the item for debugging
            let itemKeys = first.keys.sorted().joined(separator: ", ")
            print("🔍 [STATE-CHECK] Item keys: \(itemKeys)")

            // Primary: is_archived field
            if let isArchived = first["is_archived"] as? Bool {
                print("✅ [STATE-CHECK] pk \(pk) → is_archived=\(isArchived)")
                LogManager.shared.info("State check result: pk \(pk) is_archived=\(isArchived)", category: .api)
                return isArchived
            }

            // Fallback: audience_setting (1 = only_me = archived)
            if let audience = first["audience_setting"] as? Int {
                let archived = audience == 1
                print("✅ [STATE-CHECK] pk \(pk) → audience_setting=\(audience) → archived=\(archived)")
                LogManager.shared.info("State check result via audience_setting: pk \(pk) archived=\(archived)", category: .api)
                return archived
            }

            // Fallback: visibility field
            if let visibility = first["visibility"] as? String {
                let archived = visibility == "private" || visibility == "only_me"
                print("✅ [STATE-CHECK] pk \(pk) → visibility=\(visibility) → archived=\(archived)")
                LogManager.shared.info("State check result via visibility: pk \(pk) visibility=\(visibility)", category: .api)
                return archived
            }

            // No archive field present → Instagram only adds visibility/is_archived
            // to posts that are archived. A public post simply omits these fields.
            // Treat absence of archive indicator as: not archived (visible).
            print("✅ [STATE-CHECK] pk \(pk) → no archive field = public/visible (not archived)")
            LogManager.shared.info("State check result: pk \(pk) has no archive field → treated as visible", category: .api)
            return false

        } catch {
            print("⚠️ [STATE-CHECK] Request failed for pk \(pk): \(error.localizedDescription)")
            LogManager.shared.warning("State check failed (pk: \(pk)): \(error.localizedDescription)", category: .api)
        }
        return nil
    }
    
    // MARK: - Exponential Backoff (ANTI-BOT)
    
    /// Calculate backoff delay based on consecutive errors
    private func backoffDelay() -> UInt64 {
        if consecutiveErrors <= 0 { return 0 }
        // Exponential: 2^errors seconds, max 5 minutes, with jitter
        let baseSeconds = min(pow(2.0, Double(consecutiveErrors)), 300.0)
        let jitter = Double.random(in: 0...baseSeconds * 0.3) // up to 30% jitter
        let totalSeconds = baseSeconds + jitter
        print("⏳ [BACKOFF] Error #\(consecutiveErrors) → waiting \(Int(totalSeconds))s")
        return UInt64(totalSeconds * 1_000_000_000)
    }
    
    // MARK: - Session Warm Up (ANTI-BOT: simulate app opening behavior)
    
    /// Perform a lightweight "warm up" request before heavy actions
    /// Simulates opening the app and browsing before taking action
    func warmUpSession() async {
        guard isLoggedIn else { return }
        guard !isLocked, !isSessionChallenged else {
            print("🚫 [WARMUP] Skipped — locked or session challenged")
            return
        }
        
        print("🔥 [WARMUP] Simulating app open behavior...")
        LogManager.shared.info("Session warm-up started", category: .api)
        
        // Small delay like a user opening the app
        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))
        
        // Make a lightweight GET request (like loading timeline)
        do {
            let _ = try await apiRequest(method: "GET", path: "/feed/timeline/")
            print("✅ [WARMUP] Timeline fetched - session is warm")
        } catch {
            print("⚠️ [WARMUP] Timeline fetch failed: \(error.localizedDescription)")
        }
        
        // Another small delay
        try? await Task.sleep(nanoseconds: UInt64.random(in: 500_000_000...1_500_000_000))
    }
    
    // MARK: - MID Extraction (ANTI-BOT: capture Machine ID from responses)
    
    /// Extract X-MID from response headers if Instagram sends it
    private func extractMID(from response: URLResponse?) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        
        // Check Set-Cookie headers for "mid=" value
        if let cookies = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            if let midRange = cookies.range(of: "mid=") {
                let afterMid = cookies[midRange.upperBound...]
                if let endRange = afterMid.range(of: ";") {
                    let mid = String(afterMid[..<endRange.lowerBound])
                    UserDefaults.standard.set(mid, forKey: "instagram_mid")
                    print("🔑 [MID] Captured Machine ID: \(String(mid.prefix(8)))...")
                }
            }
        }
        
        // Also check direct header
        if let mid = httpResponse.value(forHTTPHeaderField: "x-mid") {
            UserDefaults.standard.set(mid, forKey: "instagram_mid")
            print("🔑 [MID] Captured Machine ID from header: \(String(mid.prefix(8)))...")
        }
    }

    /// Extracts rotated CSRF token and X-IG-WWW-Claim from response headers.
    /// Instagram rotates both periodically; sending stale values causes silent POST failures
    /// on newer endpoints (Notes, DMs…).
    private func extractAndUpdateCSRF(from response: URLResponse?) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        // ── CSRF token ────────────────────────────────────────────────────────────
        // HTTPURLResponse.allHeaderFields collapses multiple Set-Cookie into one
        // comma-separated string on iOS, so we also check HTTPCookieStorage.shared.
        var newToken: String?

        if let cookieHeader = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            if let range = cookieHeader.range(of: "csrftoken=") {
                let after = cookieHeader[range.upperBound...]
                let token = after.prefix(while: { $0 != ";" && $0 != "," }).trimmingCharacters(in: .whitespaces)
                if !token.isEmpty { newToken = token }
            }
        }

        if newToken == nil,
           let url = URL(string: "https://i.instagram.com"),
           let storedCookie = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "csrftoken" }) {
            newToken = storedCookie.value
        }

        if let token = newToken, !token.isEmpty, token != session.csrfToken {
            print("🔑 [CSRF] Token rotated — updating session (\(String(token.prefix(8)))...)")
            session.csrfToken = token
            KeychainService.shared.saveSession(session)
        }

        // ── X-IG-WWW-Claim ───────────────────────────────────────────────────────
        // Instagram sends the updated claim in response headers.
        // Without the real value, newer endpoints (Notes, Direct…) return status:fail.
        let claimHeaders = ["ig-set-ig-u-ig-igHeader", "X-IG-WWW-Claim", "ig-set-ig-www-claim"]
        for headerName in claimHeaders {
            if let claim = httpResponse.allHeaderFields[headerName] as? String,
               !claim.isEmpty, claim != "0", claim != wwwClaim {
                print("🔑 [CLAIM] X-IG-WWW-Claim updated: \(String(claim.prefix(20)))...")
                wwwClaim = claim
                break
            }
        }
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
        // Auto-expire lockdown if the countdown has already passed
        if isLocked, let until = lockUntil, Date() > until {
            await MainActor.run { unlock() }
            print("🔓 [LOCKDOWN] Auto-expired — resuming normally")
        }

        // Check if we're locked down
        if isLocked {
            throw InstagramError.botDetected("App is in lockdown mode. Wait for countdown to finish.")
        }
        
        // ANTI-BOT: Check rate limit (max 55 actions/hour)
        let rateCheck = checkRateLimit()
        if rateCheck.limited {
            print("🚫 [RATE LIMIT] \(rateCheck.actionsUsed) actions in last hour - BLOCKED")
            LogManager.shared.warning("Rate limit reached (\(rateCheck.actionsUsed)/\(maxActionsPerHour)). Wait before continuing.", category: .api)
            throw InstagramError.apiError("Rate limit reached. \(rateCheck.actionsUsed) actions in the last hour. Wait a few minutes before continuing.")
        }
        
        // ANTI-BOT: Apply exponential backoff if we've had consecutive errors
        let backoff = backoffDelay()
        if backoff > 0 {
            try await Task.sleep(nanoseconds: backoff)
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
        
        // Track this action for rate limiting
        trackAction()
        
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
        
        // ANTI-BOT: Extract MID (Machine ID) from response if present
        extractMID(from: response)

        // Auth: refresh CSRF token if Instagram rotated it (prevents POST failures)
        extractAndUpdateCSRF(from: response)

        // ANTI-BOT: Reset consecutive errors on success
        if httpResponse.statusCode == 200 {
            consecutiveErrors = 0
            consecutiveBotSignalErrors = 0
            challengeRequiredStreak = 0
        } else {
            consecutiveErrors += 1
        }
        
        // Check for bot detection signals in HTTP status
        if httpResponse.statusCode == 429 {
            // Rate limited
            await triggerLockdown(reason: "Rate limited by Instagram. Too many requests.", duration: 300)
            throw InstagramError.botDetected("Rate limited (HTTP 429). Wait 5 minutes.")
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { self.isSessionExpired = true }
            throw InstagramError.sessionExpired
        }
        
        if httpResponse.statusCode >= 400 {
            // Try to parse error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = errorJson["message"] as? String ?? ""
                
                // Check for challenge_required.
                // For GET (read-only) endpoints Instagram sometimes returns challenge_required
                // transiently — no real verification screen appears in the Instagram app.
                // Triggering a full lockdown for a read-only soft-check is too aggressive;
                // we throw the error so the caller can show a message and let the user retry.
                // For POST/write operations the lockdown is still required.
                if message.contains("challenge_required") {
                    await MainActor.run { challengeRequiredStreak += 1 }
                    // After 3+ consecutive challenges, escalate to session expired so
                    // SessionGuardView appears and prompts the magician to re-login.
                    if challengeRequiredStreak >= 3 {
                        await MainActor.run { isSessionExpired = true }
                        print("🔴 [SESSION] challengeRequiredStreak=\(challengeRequiredStreak) — escalating to isSessionExpired")
                    }
                    // Always notify the magician regardless of GET/POST, so they can
                    // open Instagram and complete any pending verification prompt manually.
                    // GET challenges use a shorter lockdown (2 min) since they are often
                    // transient; undo the consecutive-error increment so they don't also
                    // cascade into a precautionary lockdown.
                    if method == "GET" {
                        consecutiveErrors = max(0, consecutiveErrors - 1)
                    }
                    let lockDuration: TimeInterval = (method == "GET") ? 120 : 180
                    print("🚨 [API] challenge_required (\(method)) — streak \(challengeRequiredStreak) — triggering \(Int(lockDuration))s lockdown")
                    LogManager.shared.warning("challenge_required (\(method)) streak:\(challengeRequiredStreak) — lockdown \(Int(lockDuration))s", category: .api)
                    await markSessionChallenged(duration: lockDuration)
                    await triggerLockdown(
                        reason: "Instagram ha pedido verificación. Abre la app de Instagram — si ves un aviso de verificación, complétalo. Si no aparece nada, la sesión se reanudará automáticamente en 2 minutos.",
                        duration: lockDuration
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
        
        // Check for bot detection signals in response body.
        // Pass isWriteOperation so challenge_required on GET skips the lockdown screen.
        try await checkForBotSignals(data: data, isWriteOperation: method != "GET")
        
        // Success - reset consecutive error counters
        await MainActor.run {
            consecutiveErrors = 0
            consecutiveBotSignalErrors = 0
        }
        
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
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("📷 [MEDIA] Response is not a JSON dictionary")
            return ([], nil)
        }

        let items = json["items"] as? [[String: Any]] ?? []
        print("📷 [MEDIA] Response keys: \(json.keys.sorted().joined(separator: ", "))")
        print("📷 [MEDIA] items count: \(items.count), more_available: \(json["more_available"] ?? "nil")")

        // next_max_id can come as String or Int depending on API version
        let nextMaxId: String?
        if let s = json["next_max_id"] as? String {
            nextMaxId = s
        } else if let n = json["next_max_id"] as? NSNumber {
            nextMaxId = n.stringValue
        } else {
            nextMaxId = nil
        }

        // Log first item's pk type for debugging
        if let firstItem = items.first {
            let pkVal = firstItem["pk"]
            print("📷 [MEDIA] First item pk type: \(type(of: pkVal as Any)), value: \(pkVal ?? "nil")")
        }
        
        var medias: [InstagramMedia] = []
        
        for item in items {
            // Robust pk extraction: handle Int64, Int, NSNumber, or String
            let pkString: String
            if let pk64 = item["pk"] as? Int64 {
                pkString = String(pk64)
            } else if let pkInt = item["pk"] as? Int {
                pkString = String(pkInt)
            } else if let pkNum = item["pk"] as? NSNumber {
                pkString = pkNum.stringValue
            } else if let pkStr = item["pk"] as? String {
                pkString = pkStr
            } else {
                print("📷 [MEDIA] Skipping item — pk not parseable: \(type(of: item["pk"] as Any))")
                continue
            }
            
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
                id: pkString,
                mediaId: pkString,
                imageURL: imageUrl,
                caption: caption,
                takenAt: takenAt,
                isArchived: false
            )
            medias.append(media)
        }
        
        print("📷 [MEDIA] Parsed \(medias.count)/\(items.count) items")
        return (medias, nextMaxId)
    }
    
    // MARK: - Archive Photo
    
    /// Archives a photo on Instagram.
    /// - Parameter skipPreCheck: Pass `true` when the caller already verified the photo
    ///   is public (e.g. right after `getMediaIsArchived`). Avoids a redundant GET.
    func archivePhoto(mediaId: String, skipPreCheck: Bool = false) async throws -> Bool {
        print("📦 [ARCHIVE] Starting archive for media ID: \(mediaId) (skipPreCheck: \(skipPreCheck))")
        
        // ANTI-BOT: Check lockdown IMMEDIATELY (don't waste time on delay)
        if isLocked {
            print("🚨 [ARCHIVE] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot archive.")
        }
        if isSessionChallenged {
            print("🚨 [ARCHIVE] Session challenged - ABORT (would trigger lockdown)")
            throw InstagramError.challengeRequired
        }

        // PRE-CHECK: only run when the caller hasn't already verified state.
        // Skipping prevents duplicate GETs when called right after syncThenArchiveAll.
        if !skipPreCheck {
            if let alreadyArchived = try await getMediaIsArchived(mediaId: mediaId), alreadyArchived {
                print("ℹ️ [ARCHIVE] Pre-check: already archived on Instagram — skipping API call (ID: \(mediaId))")
                LogManager.shared.info("Archive skipped: already archived on Instagram (ID: \(mediaId))", category: .api)
                return true
            }
        }

        // ANTI-BOT: Realistic human delay (3-6 seconds with jitter)
        let baseDelay = UInt64.random(in: 3_000_000_000...6_000_000_000)
        let jitter = UInt64.random(in: 0...500_000_000) // up to 0.5s extra jitter
        let delay = baseDelay + jitter
        print("   Waiting \(String(format: "%.1f", Double(delay) / 1_000_000_000.0))s before archive...")
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
                LogManager.shared.success("Photo archived (ID: \(mediaId))", category: .api)
                
                // When called from S&A (skipPreCheck=true), S&A manages its own
                // inter-archive timing — don't impose an upload cooldown here.
                if !skipPreCheck {
                    let cooldownSeconds = Double.random(in: 160...220)
                    let cooldownUntil = Date().addingTimeInterval(cooldownSeconds)
                    UserDefaults.standard.set(cooldownUntil, forKey: "photo_upload_cooldown_until")
                    print("   ⏳ Cooldown set: \(Int(cooldownSeconds))s after archive")
                    LogManager.shared.info("Cooldown: \(Int(cooldownSeconds))s until next upload", category: .upload)
                }
                
                return true
            } else {
                print("❌ [ARCHIVE] Archive failed. Status: \(status)")
                LogManager.shared.error("Archive failed (ID: \(mediaId)) - Status: \(status)", category: .api)
                return false
            }
        }
        
        print("❌ [ARCHIVE] Failed to parse archive response")
        LogManager.shared.error("Archive failed (ID: \(mediaId)) - Parse error", category: .api)
        return false
    }
    
    // MARK: - Unarchive Photo
    
    /// - Parameter skipPreCheck: Pass `true` when the caller already knows the photo is archived
    ///   (e.g. photos just uploaded via this app and never publicly shown). Saves 1 GET per call.
    func unarchivePhoto(mediaId: String, skipPreCheck: Bool = false) async throws -> Bool {
        print("📤 [UNARCHIVE] Starting unarchive for media ID: \(mediaId) (skipPreCheck: \(skipPreCheck))")
        
        // ANTI-BOT: Check lockdown IMMEDIATELY (don't waste time on delay)
        if isLocked {
            print("🚨 [UNARCHIVE] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot reveal/unarchive.")
        }
        // If session was recently challenged, skip the POST — it will just trigger lockdown
        if isSessionChallenged {
            print("🚨 [UNARCHIVE] Session challenged - ABORT (would trigger lockdown)")
            throw InstagramError.challengeRequired
        }

        // PRE-CHECK: verify Instagram's real state before unarchiving.
        // Skip when caller guarantees the photo is archived (avoids 1 extra GET per letter).
        if !skipPreCheck {
            if let isArchived = try await getMediaIsArchived(mediaId: mediaId), !isArchived {
                print("ℹ️ [UNARCHIVE] Pre-check: already public on Instagram — skipping API call (ID: \(mediaId))")
                LogManager.shared.info("Unarchive skipped: already public on Instagram (ID: \(mediaId))", category: .api)
                return true
            }
        }

        // ANTI-BOT: Shorter delay for unarchive (used during performance/trick)
        // Only 2-3s since these are small bursts (max ~5 photos), not sustained patterns
        let baseDelay = UInt64.random(in: 2_000_000_000...3_000_000_000)
        let jitter = UInt64.random(in: 0...300_000_000)
        let delay = baseDelay + jitter
        print("   Waiting \(String(format: "%.1f", Double(delay) / 1_000_000_000.0))s before unarchive...")
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
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let status = json["status"] as? String ?? ""
            let message = (json["message"] as? String ?? "").lowercased()

            if status == "ok" {
                print("✅ [UNARCHIVE] Photo unarchived successfully")
                LogManager.shared.success("Photo revealed/unarchived (ID: \(mediaId))", category: .api)
                return true
            }

            // Instagram returns various messages when a photo is already public/not-archived.
            // Treat these as success so we don't count them as failures or retry them.
            let alreadyPublicHints = ["not archived", "already", "media not found", "not archived", "media_not_found"]
            if alreadyPublicHints.contains(where: { message.contains($0) }) {
                print("ℹ️ [UNARCHIVE] Photo already public / not archived (ID: \(mediaId)) — treating as success")
                LogManager.shared.success("Photo already public (ID: \(mediaId))", category: .api)
                return true
            }

            print("❌ [UNARCHIVE] Unarchive failed. Status: \(status), message: \(message)")
            LogManager.shared.error("Reveal/unarchive failed (ID: \(mediaId)) - Status: \(status)", category: .api)
            return false
        }

        print("❌ [UNARCHIVE] Failed to parse unarchive response")
        LogManager.shared.error("Reveal/unarchive failed (ID: \(mediaId)) - Parse error", category: .api)
        return false
    }
    
    // MARK: - Comment on Photo
    
    func commentOnMedia(mediaId: String, text: String) async throws -> String? {
        print("💬 [COMMENT] Posting comment on media ID: \(mediaId)")
        print("   Text: \"\(text)\"")
        
        // ANTI-BOT: Check lockdown IMMEDIATELY
        if isLocked {
            print("🚨 [COMMENT] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot post comments.")
        }
        
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
            // Detect challenge_required in error body (POST → full lockdown)
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let msg = (errJson["message"] as? String ?? "").lowercased()
                let errType = (errJson["error_type"] as? String ?? "").lowercased()
                if errJson["challenge"] != nil || msg.contains("challenge_required") || errType.contains("checkpoint") {
                    print("🚨 [COMMENT] checkpoint/challenge_required — triggering lockdown")
                    LogManager.shared.bot("Comment blocked: challenge_required")
                    await triggerLockdown(
                        reason: "Instagram blocked a comment request. Open the Instagram app if a checkpoint appeared.",
                        duration: 180
                    )
                    await markSessionChallenged(duration: 60)
                    throw InstagramError.botDetected("challenge_required on comment")
                }
            }
            throw InstagramError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Detect bot signals in 200 body
        try await checkForBotSignals(data: data, isWriteOperation: true)
        
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
        // ANTI-BOT: Check lockdown IMMEDIATELY
        if isLocked {
            print("🚨 [DELETE COMMENT] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot delete comments.")
        }
        
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
        
        // ANTI-BOT: Check lockdown IMMEDIATELY
        if isLocked {
            print("🚨 [FOLLOWER] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot fetch followers.")
        }
        
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

    /// Returns the most recent N followers (ordered newest first).
    /// Used by Date Force Auto mode to capture show participants.
    func getRecentFollowers(count: Int) async throws -> [InstagramFollower] {
        print("👥 [FOLLOWERS] Fetching latest \(count) followers...")

        if isLocked {
            throw InstagramError.botDetected("Lockdown active.")
        }

        let data = try await apiRequest(
            method: "GET",
            path: "/friendships/\(session.userId)/followers/?count=\(count)"
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [[String: Any]] else {
            print("❌ [FOLLOWERS] Failed to parse")
            return []
        }

        var followers: [InstagramFollower] = []
        for user in users.prefix(count) {
            let userId: String
            if let s = user["pk"] as? String { userId = s }
            else if let i = user["pk"] as? Int64 { userId = String(i) }
            else if let i = user["pk"] as? Int { userId = String(i) }
            else { continue }

            followers.append(InstagramFollower(
                userId: userId,
                username: user["username"] as? String ?? "",
                fullName: user["full_name"] as? String ?? "",
                profilePicURL: user["profile_pic_url"] as? String
            ))
        }

        print("✅ [FOLLOWERS] Got \(followers.count) followers")
        return followers
    }

    func getRecentFollowing(count: Int) async throws -> [InstagramFollower] {
        print("👥 [FOLLOWING] Fetching latest \(count) following...")

        if isLocked {
            throw InstagramError.botDetected("Lockdown active.")
        }

        let data = try await apiRequest(
            method: "GET",
            path: "/friendships/\(session.userId)/following/?count=\(count)"
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [[String: Any]] else {
            print("❌ [FOLLOWING] Failed to parse")
            return []
        }

        var following: [InstagramFollower] = []
        for user in users.prefix(count) {
            let userId: String
            if let s = user["pk"] as? String { userId = s }
            else if let i = user["pk"] as? Int64 { userId = String(i) }
            else if let i = user["pk"] as? Int { userId = String(i) }
            else { continue }

            following.append(InstagramFollower(
                userId: userId,
                username: user["username"] as? String ?? "",
                fullName: user["full_name"] as? String ?? "",
                profilePicURL: user["profile_pic_url"] as? String
            ))
        }

        print("✅ [FOLLOWING] Got \(following.count) following")
        return following
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
        var reelURLs: [String] = []
        var taggedURLs: [String] = []
        var initialMediaItems: [InstagramMediaItem] = []
        var highlights: [InstagramHighlight] = []

        if shouldFetchProtectedData {
            print("✅ [PROFILE] Fetching followers, media, reels, tagged & highlights (profile is accessible)")

            // Fetch all in parallel
            async let followersTask   = getFollowedByUsers(userId: uid, count: 6)
            async let mediaTask       = getUserMediaItems(userId: uid, amount: 18)
            async let reelsTask       = getUserReels(userId: uid, amount: 18)
            async let taggedTask      = getUserTagged(userId: uid, amount: 18)
            async let highlightsTask  = getUserHighlights(userId: uid)

            followedBy = try await followersTask
            let (mediaItems, _) = try await mediaTask
            mediaURLs = mediaItems.map { $0.imageURL }
            initialMediaItems = mediaItems

            // Non-critical — silent failures
            do { reelURLs   = try await reelsTask.map { $0.imageURL } }
            catch { print("⚠️ [PROFILE] Reels fetch failed (non-critical): \(error)") }

            do { taggedURLs = try await taggedTask.map { $0.imageURL } }
            catch { print("⚠️ [PROFILE] Tagged fetch failed (non-critical): \(error)") }

            do { highlights = try await highlightsTask }
            catch { print("⚠️ [PROFILE] Highlights fetch failed (non-critical): \(error)") }

            print("📊 [PROFILE] Posts: \(mediaURLs.count), Reels: \(reelURLs.count), Tagged: \(taggedURLs.count), Highlights: \(highlights.count)")
        } else {
            print("⚠️ [PROFILE] Skipping data fetch (private profile, not following)")
        }

        var profile = InstagramProfile(
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
            cachedMediaURLs: mediaURLs,
            cachedReelURLs: reelURLs,
            cachedTaggedURLs: taggedURLs,
            cachedHighlights: highlights
        )
        profile.cachedMediaItems = initialMediaItems

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
            
            let userId: String
            if let pkInt64 = user["pk"] as? Int64 {
                userId = String(pkInt64)
            } else if let pkStr = user["pk_id"] as? String ?? user["id"] as? String {
                userId = pkStr
            } else {
                userId = UUID().uuidString  // avoid duplicate IDs
            }
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
    
    // MARK: - Get User Reels
    
    func getUserReels(userId: String? = nil, amount: Int = 18) async throws -> [InstagramMediaItem] {
        let uid = userId ?? session.userId
        print("🎬 [REELS] Fetching reels for user ID: \(uid)")
        
        let body: [String: String] = [
            "target_user_id": uid,
            "page_size": String(amount),
            "include_feed_video": "true"
        ]
        let data = try await apiRequest(method: "POST", path: "/clips/user/", body: body)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [REELS] Failed to parse reels response")
            return []
        }
        
        // Log response structure for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🎬 [REELS] Raw response (first 600 chars): \(String(jsonString.prefix(600)))")
        }
        print("🎬 [REELS] Top-level keys: \(json.keys.sorted().joined(separator: ", "))")
        
        var items: [InstagramMediaItem] = []
        
        // Try "items" key first (each item may have a nested "media" object)
        if let reelsItems = json["items"] as? [[String: Any]] {
            print("🎬 [REELS] Found \(reelsItems.count) items under 'items' key")
            for item in reelsItems.prefix(amount) {
                let media = item["media"] as? [String: Any] ?? item
                guard let mediaItem = parseMediaItem(media) else { continue }
                items.append(mediaItem)
            }
        }
        // Fallback: some endpoints wrap under "clips_items"
        else if let clipsItems = json["clips_items"] as? [[String: Any]] {
            print("🎬 [REELS] Found \(clipsItems.count) items under 'clips_items' key")
            for item in clipsItems.prefix(amount) {
                let media = item["media"] as? [String: Any] ?? item
                guard let mediaItem = parseMediaItem(media) else { continue }
                items.append(mediaItem)
            }
        } else {
            print("⚠️ [REELS] No 'items' or 'clips_items' key found — account may have 0 reels or endpoint changed")
        }
        
        print("🎬 [REELS] Parsed \(items.count) reels")
        return items
    }
    
    // MARK: - Get User Tagged Posts
    
    func getUserTagged(userId: String? = nil, amount: Int = 18) async throws -> [InstagramMediaItem] {
        let uid = userId ?? session.userId
        print("🏷️ [TAGGED] Fetching tagged posts for user ID: \(uid)")
        
        let data = try await apiRequest(method: "GET", path: "/usertags/\(uid)/feed/")
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [TAGGED] Failed to parse tagged response")
            return []
        }
        
        // Log response structure for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🏷️ [TAGGED] Raw response (first 400 chars): \(String(jsonString.prefix(400)))")
        }
        print("🏷️ [TAGGED] Top-level keys: \(json.keys.sorted().joined(separator: ", "))")
        
        var items: [InstagramMediaItem] = []
        
        if let taggedItems = json["items"] as? [[String: Any]] {
            print("🏷️ [TAGGED] Found \(taggedItems.count) items")
            for item in taggedItems.prefix(amount) {
                guard let mediaItem = parseMediaItem(item) else { continue }
                items.append(mediaItem)
            }
        } else {
            print("⚠️ [TAGGED] No 'items' key found — account may have 0 tagged posts or endpoint changed")
        }
        
        print("🏷️ [TAGGED] Parsed \(items.count) tagged posts")
        return items
    }
    
    // MARK: - Get User Story Highlights

    func getUserHighlights(userId: String? = nil) async throws -> [InstagramHighlight] {
        let uid = userId ?? session.userId
        print("🌟 [HIGHLIGHTS] Fetching story highlights for user ID: \(uid)")

        let data = try await apiRequest(method: "GET", path: "/highlights/\(uid)/highlights_tray/")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tray = json["tray"] as? [[String: Any]] else {
            print("⚠️ [HIGHLIGHTS] No tray found in response")
            return []
        }

        var highlights: [InstagramHighlight] = []
        for item in tray {
            guard let id    = item["id"] as? String,
                  let title = item["title"] as? String else { continue }

            // Cover image: prefer cropped_image_version, fallback to cover_media_cropped_image
            var coverURL = ""
            if let coverMedia = item["cover_media"] as? [String: Any] {
                if let cropped = coverMedia["cropped_image_version"] as? [String: Any],
                   let url = cropped["url"] as? String {
                    coverURL = url
                } else if let imgVersions = coverMedia["image_versions2"] as? [String: Any],
                          let candidates = imgVersions["candidates"] as? [[String: Any]],
                          let first = candidates.first,
                          let url = first["url"] as? String {
                    coverURL = url
                }
            }
            guard !coverURL.isEmpty else { continue }
            highlights.append(InstagramHighlight(id: id, title: title, coverImageURL: coverURL))
        }

        print("🌟 [HIGHLIGHTS] Parsed \(highlights.count) highlights")
        return highlights
    }

    /// Shared parser for media items from different endpoints
    private func parseMediaItem(_ media: [String: Any]) -> InstagramMediaItem? {
        let mediaType = media["media_type"] as? Int ?? 1
        
        // Get thumbnail/cover image URL
        var imageURL = ""
        if let imageVersions = media["image_versions2"] as? [String: Any],
           let candidates = imageVersions["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let url = first["url"] as? String {
            imageURL = url
        }
        
        // For videos/reels, also get video URL
        var videoURL: String? = nil
        if mediaType == 2 {
            if let videoVersions = media["video_versions"] as? [[String: Any]],
               let first = videoVersions.first,
               let url = first["url"] as? String {
                videoURL = url
            }
        }
        
        guard !imageURL.isEmpty else { return nil }
        
        // Extract media ID
        let mediaId: String
        if let pk = media["pk"] as? Int64 {
            mediaId = String(pk)
        } else if let pk = media["pk"] as? String {
            mediaId = pk
        } else if let id = media["id"] as? String {
            mediaId = id
        } else {
            mediaId = UUID().uuidString
        }
        
        let ownerUsername = (media["user"] as? [String: Any])?["username"] as? String
        return InstagramMediaItem(
            id: mediaId,
            mediaId: mediaId,
            imageURL: imageURL,
            videoURL: videoURL,
            caption: (media["caption"] as? [String: Any])?["text"] as? String,
            takenAt: (media["taken_at"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            likeCount: media["like_count"] as? Int,
            commentCount: media["comment_count"] as? Int,
            mediaType: mediaType == 2 ? .video : (mediaType == 8 ? .carousel : .photo),
            ownerUsername: ownerUsername
        )
    }
    
    // MARK: - Get User Media Items (Extended with metadata)
    
    func getUserMediaItems(userId: String? = nil, amount: Int = 18, maxId: String? = nil) async throws -> ([InstagramMediaItem], String?) {
        let uid = userId ?? session.userId
        print("📷 [MEDIA] Fetching \(amount) media items for user ID: \(uid), maxId: \(maxId ?? "none")")
        
        var path = "/feed/user/\(uid)/"
        if let maxId = maxId {
            path += "?max_id=\(maxId)"
        }
        let data = try await apiRequest(method: "GET", path: path)
        
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📷 [MEDIA] Raw response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [MEDIA] Failed to parse JSON")
            return ([], nil)
        }
        
        // Debug: Print available keys
        print("📷 [MEDIA] Response keys: \(json.keys.sorted())")
        
        guard let items = json["items"] as? [[String: Any]] else {
            print("❌ [MEDIA] No 'items' key found or invalid format")
            print("📷 [MEDIA] Available keys: \(json.keys.joined(separator: ", "))")
            
            // Try alternative: get from user info endpoint
            return try await getUserMediaFromAlternativeEndpoint(userId: uid, amount: amount, maxId: maxId)
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
        
        // Get next_max_id for pagination
        let nextMaxId = json["next_max_id"] as? String
        
        print("✅ [MEDIA] Fetched \(mediaItems.count) media items, next_max_id: \(nextMaxId ?? "none")")
        return (mediaItems, nextMaxId)
    }
    
    // MARK: - Get User Media from Alternative Endpoint
    
    private func getUserMediaFromAlternativeEndpoint(userId: String, amount: Int, maxId: String?) async throws -> ([InstagramMediaItem], String?) {
        print("📷 [MEDIA ALT] Trying alternative endpoint for user ID: \(userId), maxId: \(maxId ?? "none")")
        
        // Try using user_medias endpoint with rank_token
        let rankToken = UUID().uuidString
        var path = "/feed/user/\(userId)/?rank_token=\(rankToken)"
        if let maxId = maxId {
            path += "&max_id=\(maxId)"
        }
        
        let data = try await apiRequest(method: "GET", path: path)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📷 [MEDIA ALT] Response (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            print("❌ [MEDIA ALT] Failed to get items from alternative endpoint")
            return ([], nil)
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
        
        let nextMaxId = json["next_max_id"] as? String
        
        print("✅ [MEDIA ALT] Fetched \(mediaItems.count) media items from alternative endpoint, next_max_id: \(nextMaxId ?? "none")")
        return (mediaItems, nextMaxId)
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
            let ownerUsername = (item["user"] as? [String: Any])?["username"] as? String
            
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
                mediaType: mediaType,
                ownerUsername: ownerUsername
            )
            mediaItems.append(mediaItem)
        }
        
        print("✅ [EXPLORE] Successfully parsed \(mediaItems.count) items with valid images")
        return (mediaItems, nextMaxId)
    }
    
    // MARK: - Upload Photo
    
    func uploadPhoto(imageData: Data, caption: String = "", allowDuplicates: Bool = false, photoIndex: Int? = nil, takenAt: Date? = nil) async throws -> String? {
        print("📤 [UPLOAD] Starting photo upload...")
        let photoDesc = photoIndex != nil ? "Photo #\(photoIndex! + 1)" : "Photo"
        LogManager.shared.upload("Starting upload: \(photoDesc) (\(imageData.count / 1024)KB)")
        
        if let index = photoIndex {
            print("   Photo index: \(index)")
        }
        print("   Image size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
        print("   Allow duplicates: \(allowDuplicates)")
        
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
            let photoInfo = photoIndex != nil ? " (Photo #\(photoIndex! + 1))" : ""
            throw InstagramError.apiError("Please wait \(minutes)m \(seconds)s before uploading another photo.\(photoInfo)")
        }
        
        // NOTE: Image is already aspect-adjusted and compressed when loaded from gallery
        print("✅ [UPLOAD] Using pre-processed image")
        
        // ANTI-BOT: For duplicate photos (Word/Number Reveal), make each copy unique
        // This prevents Instagram from detecting identical image uploads across banks
        let uploadData: Data
        if allowDuplicates {
            print("🎲 [UPLOAD] Duplicates allowed - making image unique for this bank...")
            uploadData = InstagramService.makeImageUnique(imageData: imageData)
        } else {
            uploadData = imageData
        }
        
        // ANTI-BOT: Detect duplicate image (prevent uploading same photo twice)
        // EXCEPTION: Word Reveal and Number Reveal already have unique bytes per bank
        let finalHash = hashImageData(uploadData)
        if !allowDuplicates {
            if let lastHash = UserDefaults.standard.string(forKey: "last_upload_photo_hash"),
               lastHash == finalHash {
                print("⚠️ [UPLOAD] Same image already uploaded - SKIP")
                let photoInfo = photoIndex != nil ? " Photo #\(photoIndex! + 1)" : " This photo"
                throw InstagramError.apiError("\(photoInfo) was already uploaded. Duplicate uploads may trigger bot detection.")
            }
        } else {
            print("✅ [UPLOAD] Duplicates allowed with unique bytes for this set type (Word/Number Reveal)")
        }
        
        // ANTI-BOT: Wait if network changed recently
        try await waitForNetworkStability()
        
        print("   Image hash: \(String(finalHash.prefix(16)))...")
        
        // Step 1: Generate upload ID and names (with realistic variation)
        // ANTI-BOT: Add small random offset to timestamp to avoid perfectly predictable IDs
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000) + Int.random(in: -500...500)
        let uploadId = String(timestampMs)
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
        
        // ANTI-BOT: Use ALL headers from buildHeaders() for consistency, then add upload-specific ones
        let baseHeaders = buildHeaders()
        for (key, value) in baseHeaders {
            // Skip Content-Type from base (upload uses octet-stream, not form-urlencoded)
            if key == "Content-Type" { continue }
            uploadRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Upload-specific headers (use uploadData which may be uniquified for duplicates)
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(String(uploadData.count), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue(ruploadParamsString, forHTTPHeaderField: "X-Instagram-Rupload-Params")
        uploadRequest.setValue(waterfallId, forHTTPHeaderField: "X_FB_PHOTO_WATERFALL_ID")
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "X-Entity-Type")
        uploadRequest.setValue(uploadName, forHTTPHeaderField: "X-Entity-Name")
        uploadRequest.setValue(String(uploadData.count), forHTTPHeaderField: "X-Entity-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "Offset")
        
        uploadRequest.httpBody = uploadData
        
        print("   Sending image bytes to Instagram...")
        let (responseData, uploadResponse) = try await postSession.data(for: uploadRequest)
        
        if let httpResponse = uploadResponse as? HTTPURLResponse {
            print("   Upload response status: \(httpResponse.statusCode)")
        }
        
        if let jsonString = String(data: responseData, encoding: .utf8) {
            print("   Upload response body: \(jsonString)")
        }
        
        // IMPROVED: Detailed error logging for upload failures
        let httpStatusCode = (uploadResponse as? HTTPURLResponse)?.statusCode ?? -1
        
        guard let uploadJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let uploadIdResponse = uploadJson["upload_id"] as? String else {
            // Extract detailed error info for debugging
            var errorDetail = "HTTP \(httpStatusCode)"
            if let uploadJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                print("   Response JSON: \(uploadJson)")
                if let message = uploadJson["message"] as? String {
                    errorDetail += " - \(message)"
                }
                if let status = uploadJson["status"] as? String {
                    errorDetail += " (status: \(status))"
                }
            } else if let bodyText = String(data: responseData, encoding: .utf8), !bodyText.isEmpty {
                errorDetail += " - Body: \(String(bodyText.prefix(200)))"
            }
            
            print("❌ [UPLOAD] Failed to get upload_id. Detail: \(errorDetail)")

            // If the upload response contains checkpoint_challenge_required with lock:true,
            // this is a REAL Instagram checkpoint — not a transient GET soft-check.
            // Trigger a proper lockdown so the user knows to complete verification.
            if let uploadJson2 = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                let msg2 = uploadJson2["message"] as? String ?? ""
                let errType = uploadJson2["error_type"] as? String ?? ""
                if msg2.contains("challenge_required") || errType.contains("checkpoint") {
                    let challengeDict = uploadJson2["challenge"] as? [String: Any]
                    let challengeURL  = challengeDict?["url"] as? String ?? "https://instagram.com"
                    let isLocked      = challengeDict?["lock"] as? Bool ?? false
                    print("🚨 [UPLOAD] checkpoint_challenge_required (lock:\(isLocked)) — triggering lockdown")
                    print("🚨 [UPLOAD] Complete checkpoint at: \(challengeURL)")
                    LogManager.shared.bot("Upload blocked: checkpoint_challenge_required (lock:\(isLocked))")
                    await triggerLockdown(
                        reason: "Instagram blocked the upload and requires checkpoint verification. Open the Instagram app — if you see a verification prompt complete it, otherwise wait ~5 minutes.",
                        duration: 300  // 5 minutes; user can unlock early after completing checkpoint
                    )
                    await markSessionChallenged(duration: 60)
                    throw InstagramError.botDetected("checkpoint_challenge_required (lock:\(isLocked))")
                }
            }

            let photoDesc = photoIndex != nil ? "Photo #\(photoIndex! + 1)" : "Photo"
            LogManager.shared.error("Upload failed: \(photoDesc) - \(errorDetail)", category: .upload)
            throw InstagramError.apiError("Upload failed (\(errorDetail))")
        }
        
        print("✅ [UPLOAD] Image bytes uploaded. Upload ID: \(uploadIdResponse)")
        
        // ANTI-BOT: Variable human delay before configure (3-7 seconds with jitter)
        let configBaseDelay = UInt64.random(in: 3_000_000_000...7_000_000_000)
        let configJitter = UInt64.random(in: 0...1_000_000_000) // up to 1s extra
        let configDelay = configBaseDelay + configJitter
        print("   Waiting \(String(format: "%.1f", Double(configDelay) / 1_000_000_000.0))s before configure...")
        try await Task.sleep(nanoseconds: configDelay)
        
        // Step 4: Configure media (with more complete data like instagrapi)
        var configBody: [String: String] = [
            "upload_id": uploadIdResponse,
            "caption": caption,
            "source_type": "4",
            "media_folder": "Camera",
            "device_id": deviceId
        ]
        // Grid position anchor: override taken_at so the photo slots into the correct
        // chronological position in the grid when it is later unarchived.
        // Without this, Instagram uses the current time → photo appears at the top.
        if let anchorDate = takenAt {
            configBody["taken_at"] = String(Int(anchorDate.timeIntervalSince1970))
            print("📍 [UPLOAD] taken_at overridden to \(anchorDate) for grid position anchoring")
        }
        
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
                let photoDesc = photoIndex != nil ? "Photo #\(photoIndex! + 1)" : "Photo"
                LogManager.shared.success("\(photoDesc) uploaded successfully (ID: \(mediaId))", category: .upload)
                
                // ANTI-BOT: Save hash and cooldown after successful upload
                let imageHash = hashImageData(uploadData)
                UserDefaults.standard.set(imageHash, forKey: "last_upload_photo_hash")
                
                // ANTI-BOT: DO NOT set cooldown here - it will be set AFTER archive completes
                // This ensures the full upload+archive cycle is counted, not just upload
                print("   ⏳ Cooldown will be set after archive completes")
                
                return mediaId
            }
        }
        
        print("❌ [UPLOAD] Failed to get media ID from configure response")
        LogManager.shared.error("Upload failed - no media ID received", category: .upload)
        return nil
    }
    
    /// Check if photo upload is on cooldown (PUBLIC for SetDetailView)
    func isPhotoUploadOnCooldown() -> (onCooldown: Bool, remainingSeconds: Int) {
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
        
        // ANTI-BOT: Check lockdown IMMEDIATELY
        if isLocked {
            print("🚨 [REVEAL] Lockdown active - ABORT")
            throw InstagramError.botDetected("Lockdown active. Cannot reveal photos during lockdown.")
        }
        
        // Step 1: Unarchive — skipPreCheck because caller already confirmed photo.isArchived == true
        print("   Step 1: Unarchiving (skipPreCheck=true — photo confirmed archived by DataManager)...")
        let unarchived = try await unarchivePhoto(mediaId: mediaId, skipPreCheck: true)
        
        guard unarchived else {
            print("❌ [REVEAL] Unarchive failed")
            return (false, nil, nil)
        }
        
        print("✅ [REVEAL] Unarchived successfully")
        
        // TEMPORARY: Auto-comment disabled until timing issues are resolved
        /*
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
        */
        
        return (true, nil, nil)
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

        print("   [NOTE] csrfToken=\(String(session.csrfToken.prefix(8)))... len=\(session.csrfToken.count) audience=\(audience)")
        print("   [NOTE] wwwClaim=\(String(wwwClaim.prefix(20)))")

        // Notes uses www.instagram.com (where the WebView session was established).
        // i.instagram.com returns web-style CORS headers for this endpoint, suggesting
        // the Notes backend lives under www. Using www directly avoids any routing mismatch.
        let notesBase = "https://www.instagram.com/api/v1"

        // ── Step 1: warm up ──────────────────────────────────────────────────────────────
        if let warmupURL = URL(string: "\(notesBase)/notes/update_notes_last_seen_timestamp/") {
            var warmupReq = URLRequest(url: warmupURL)
            warmupReq.httpMethod = "POST"
            warmupReq.timeoutInterval = 20
            var warmupHeaders = buildHeaders()
            warmupHeaders.removeValue(forKey: "Cookie") // let URLSession use stored cookies
            for (k, v) in warmupHeaders { warmupReq.setValue(v, forHTTPHeaderField: k) }
            let warmupBodyStr = "_uuid=\(clientUUID)&_uid=\(session.userId)&_csrftoken=\(session.csrfToken)"
            warmupReq.httpBody = warmupBodyStr.data(using: .utf8)
            if let (wd, wr) = try? await postSession.data(for: warmupReq),
               let wHttp = wr as? HTTPURLResponse {
                let ws = (try? JSONSerialization.jsonObject(with: wd) as? [String: Any])?["status"] as? String ?? "?"
                print("   [NOTE] Warm-up HTTP \(wHttp.statusCode) status=\(ws)")
                extractAndUpdateCSRF(from: wr)
            }
        }

        // ── Step 2: create the note ──────────────────────────────────────────────────────
        let body: [String: String] = [
            "_csrftoken":   session.csrfToken,
            "_uid":         session.userId,
            "_uuid":        clientUUID,
            "device_id":    deviceId,
            "audience":     String(audience),
            "note_style":   "0",
            "text":         text
        ]
        print("   [NOTE] Body params: \(body.keys.sorted().joined(separator: ", "))")

        guard let noteURL = URL(string: "\(notesBase)/notes/create_note/") else {
            throw InstagramError.invalidURL
        }
        var noteRequest = URLRequest(url: noteURL)
        noteRequest.httpMethod = "POST"
        noteRequest.timeoutInterval = 30
        var createHeaders = buildHeaders()
        createHeaders.removeValue(forKey: "Cookie") // let URLSession use stored cookies
        for (k, v) in createHeaders { noteRequest.setValue(v, forHTTPHeaderField: k) }
        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        noteRequest.httpBody = bodyString.data(using: .utf8)
        trackAction()
        let (data, noteResponse) = try await postSession.data(for: noteRequest)
        if let http = noteResponse as? HTTPURLResponse {
            print("   [NOTE] HTTP \(http.statusCode)")
            extractAndUpdateCSRF(from: noteResponse)
            extractMID(from: noteResponse)
        }

        if let rawResponse = String(data: data, encoding: .utf8) {
            print("   [NOTE] Raw response: \(rawResponse.prefix(400))")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String, status == "ok" {
                print("✅ [NOTE] Note created successfully")

                UserDefaults.standard.set(text, forKey: "last_note_text")
                UserDefaults.standard.set(Date(), forKey: "last_note_sent_date")
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
    
    // MARK: - Change Biography

    /// Updates the Instagram biography text via /accounts/edit_profile/.
    /// Preserves all existing profile fields — only `biography` is modified.
    func changeBiography(text: String) async throws -> Bool {
        print("📝 [BIO] Changing biography to: \"\(text)\"")

        guard text.count <= 150 else {
            throw InstagramError.apiError("Biography must be 150 characters or less (\(text.count) given).")
        }

        if isLocked {
            print("🚨 [BIO] Lockdown active — ABORT")
            throw InstagramError.apiError("Lockdown active. Wait before editing biography.")
        }

        // ANTI-BOT: Duplicate check
        if let lastBio = UserDefaults.standard.string(forKey: "last_biography_text"),
           lastBio == text {
            throw InstagramError.apiError("This is already your current biography. Please write something different.")
        }

        // ANTI-BOT: Cooldown between consecutive edits (120 s)
        if let cooldownUntil = UserDefaults.standard.object(forKey: "biography_cooldown_until") as? Date,
           cooldownUntil > Date() {
            let remaining = Int(cooldownUntil.timeIntervalSinceNow)
            throw InstagramError.apiError("Please wait \(remaining)s before editing biography again.")
        }

        try await waitForNetworkStability()

        // ANTI-BOT: Human delay (1–2 s)
        let delay = UInt64.random(in: 1_000_000_000...2_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s (human delay)…")
        try await Task.sleep(nanoseconds: delay)

        // Build body with ALL required fields — Instagram will 400 if any are missing.
        // email, phone, gender and birthday are not stored in InstagramProfile, so we
        // cache them in UserDefaults after the first successful fetch and reuse them.
        var email       = UserDefaults.standard.string(forKey: "ig_edit_email")    ?? ""
        var phone       = UserDefaults.standard.string(forKey: "ig_edit_phone")    ?? ""
        var gender      = UserDefaults.standard.string(forKey: "ig_edit_gender")   ?? ""
        var birthday    = UserDefaults.standard.string(forKey: "ig_edit_birthday") ?? ""
        var externalUrl = ProfileCacheService.shared.cachedProfile?.externalUrl    ?? ""
        var username    = ProfileCacheService.shared.cachedProfile?.username       ?? ""
        var firstName   = ProfileCacheService.shared.cachedProfile?.fullName       ?? ""

        // If we don't have cached edit-fields yet, fetch them once from Instagram.
        let missingEditFields = email.isEmpty && phone.isEmpty && gender.isEmpty
        if missingEditFields {
            print("📝 [BIO] No cached edit-fields — fetching from /accounts/current_user/ (one-time)…")
            if let currentUserData = try? await apiRequest(
                method: "GET",
                path:   "/accounts/current_user/?edit=true"
            ),
               let userJson = try? JSONSerialization.jsonObject(with: currentUserData) as? [String: Any],
               let user = userJson["user"] as? [String: Any] {
                email       = user["email"]        as? String ?? ""
                phone       = user["phone_number"] as? String ?? ""
                gender      = String(user["gender"] as? Int ?? 1)
                birthday    = user["birthday"]     as? String ?? ""
                externalUrl = user["external_url"] as? String ?? externalUrl
                username    = user["username"]     as? String ?? username
                firstName   = user["full_name"]    as? String ?? firstName

                // Cache for future calls — no GET needed next time
                UserDefaults.standard.set(email,    forKey: "ig_edit_email")
                UserDefaults.standard.set(phone,    forKey: "ig_edit_phone")
                UserDefaults.standard.set(gender,   forKey: "ig_edit_gender")
                UserDefaults.standard.set(birthday, forKey: "ig_edit_birthday")
                print("   ✅ Edit-fields cached. email=\(email.isEmpty ? "(empty)" : "***"), phone=\(phone.isEmpty ? "(empty)" : "***"), gender=\(gender)")
            } else {
                print("   ⚠️ [BIO] Could not fetch edit-fields — proceeding with empty email/phone (may fail)")
            }
        } else {
            print("📝 [BIO] Using cached edit-fields (no GET needed). gender=\(gender)")
        }

        let body: [String: String] = [
            "_csrftoken":   session.csrfToken,
            "_uid":         session.userId,
            "_uuid":        clientUUID,
            "device_id":    deviceId,
            "biography":    text,
            "email":        email,
            "phone_number": phone,
            "gender":       gender,
            "birthday":     birthday,
            "external_url": externalUrl,
            "username":     username,
            "first_name":   firstName
        ]

        let data = try await apiRequest(
            method: "POST",
            path:   "/accounts/edit_profile/",
            body:   body
        )

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String, status == "ok" {
                print("✅ [BIO] Biography updated successfully")
                LogManager.shared.success("Biography updated", category: .api)

                // Persist to prevent duplicates and start cooldown
                UserDefaults.standard.set(text, forKey: "last_biography_text")
                let cooldownUntil = Date().addingTimeInterval(120)
                UserDefaults.standard.set(cooldownUntil, forKey: "biography_cooldown_until")

                // Update in-memory cache so PerformanceView shows it instantly
                if let cached = ProfileCacheService.shared.cachedProfile {
                    let updated = InstagramProfile(
                        userId: cached.userId, username: cached.username,
                        fullName: cached.fullName, biography: text,
                        externalUrl: cached.externalUrl, profilePicURL: cached.profilePicURL,
                        isVerified: cached.isVerified, isPrivate: cached.isPrivate,
                        followerCount: cached.followerCount, followingCount: cached.followingCount,
                        mediaCount: cached.mediaCount, followedBy: cached.followedBy,
                        isFollowing: cached.isFollowing, isFollowRequested: cached.isFollowRequested,
                        cachedAt: cached.cachedAt, cachedMediaURLs: cached.cachedMediaURLs,
                        cachedReelURLs: cached.cachedReelURLs, cachedTaggedURLs: cached.cachedTaggedURLs,
                        cachedHighlights: cached.cachedHighlights
                    )
                    ProfileCacheService.shared.saveProfile(updated)
                }

                return true
            }

            let message = json["message"] as? String ?? "Unknown error"
            print("❌ [BIO] Failed: \(message)")
            throw InstagramError.apiError("Biography update failed: \(message)")
        }

        print("❌ [BIO] Could not parse response")
        throw InstagramError.apiError("Biography update failed: could not parse Instagram response.")
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

        // Prevent re-entrant calls (e.g. auto-pic + manual upload racing)
        guard !isUploadingProfilePic else {
            print("⚠️ [PROFILE PIC] Already uploading — skipped re-entrant call")
            throw InstagramError.apiError("A profile picture upload is already in progress.")
        }

        // Mark upload in progress globally so other API calls can yield.
        // defer guarantees the flag is cleared in every exit path (success, throw, or cancel).
        await MainActor.run { isUploadingProfilePic = true }
        defer { Task { @MainActor in self.isUploadingProfilePic = false } }

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
        
        // ANTI-BOT: Use ALL headers from buildHeaders() for consistency
        let baseHeaders = buildHeaders()
        for (key, value) in baseHeaders {
            if key == "Content-Type" { continue }
            uploadRequest.setValue(value, forHTTPHeaderField: key)
        }
        
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

            // Detect checkpoint_challenge_required (same pattern as uploadPhoto)
            if let errJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any] {
                let msg = errJson["message"] as? String ?? ""
                let errType = errJson["error_type"] as? String ?? ""
                if msg.contains("challenge_required") || errType.contains("checkpoint") {
                    let challengeDict = errJson["challenge"] as? [String: Any]
                    let isLock = challengeDict?["lock"] as? Bool ?? false
                    print("🚨 [PROFILE PIC] checkpoint_challenge_required (lock:\(isLock)) — triggering lockdown")
                    LogManager.shared.bot("Profile pic upload blocked: checkpoint_challenge_required (lock:\(isLock))")
                    await triggerLockdown(
                        reason: "Instagram blocked the profile pic upload and requires checkpoint verification. Open the Instagram app to complete it.",
                        duration: 300
                    )
                    await markSessionChallenged(duration: 60)
                    throw InstagramError.botDetected("checkpoint_challenge_required (lock:\(isLock))")
                }
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
    func hashImageData(_ data: Data) -> String {
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
    
    // MARK: - Image Orientation Fix
    
    /// Normalize image orientation to prevent rotation issues
    /// Images with EXIF orientation data need to be redrawn in the correct orientation
    private static func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        // If already in correct orientation, return as-is
        if image.imageOrientation == .up {
            return image
        }
        
        print("🔄 [ORIENTATION] Fixing orientation: \(image.imageOrientation.rawValue) → up")
        
        // Redraw image in correct orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? image
    }
    
    // MARK: - Image Aspect Ratio Adjustment
    
    /// Adjusts image to Instagram-compatible aspect ratio (1:1, 4:5, or 1.91:1)
    /// Returns adjusted image data or original if already valid
    /// PUBLIC: Called when selecting photos from gallery
    static func adjustImageAspectRatio(imageData: Data) -> Data {
        guard let originalImage = UIImage(data: imageData) else {
            print("⚠️ [ASPECT] Cannot create UIImage, using original")
            return imageData
        }
        
        // CRITICAL: Normalize orientation first to prevent rotation
        let image = normalizeImageOrientation(originalImage)
        
        let width = image.size.width
        let height = image.size.height
        let aspectRatio = width / height
        
        print("📐 [ASPECT] Original: \(Int(width))x\(Int(height)), ratio: \(String(format: "%.2f", aspectRatio))")
        
        // Instagram allowed ratios
        let squareRatio: CGFloat = 1.0        // 1:1
        let verticalRatio: CGFloat = 0.8      // 4:5
        let horizontalRatio: CGFloat = 1.91   // 1.91:1
        
        // Check if already valid (5% tolerance)
        let tolerance: CGFloat = 0.05
        let isAspectValid = abs(aspectRatio - squareRatio) < tolerance ||
                           abs(aspectRatio - verticalRatio) < tolerance ||
                           abs(aspectRatio - horizontalRatio) < tolerance
        
        if isAspectValid {
            // If aspect is valid AND orientation was correct, use original
            if originalImage.imageOrientation == .up {
                print("✅ [ASPECT] Already valid, no adjustment needed")
                return imageData
            }
            
            // If aspect is valid but orientation was wrong, re-encode the normalized image
            guard let reEncodedData = image.jpegData(compressionQuality: 0.95) else {
                print("⚠️ [ASPECT] Re-encoding failed, using original")
                return imageData
            }
            print("✅ [ASPECT] Orientation fixed (aspect ratio already valid)")
            return reEncodedData
        }
        
        // Determine target ratio
        let targetRatio: CGFloat
        if aspectRatio < 0.75 {
            // Very vertical → 4:5
            targetRatio = verticalRatio
            print("🔧 [ASPECT] Adjusting to 4:5 (vertical)")
        } else if aspectRatio > 2.0 {
            // Very horizontal → 1.91:1
            targetRatio = horizontalRatio
            print("🔧 [ASPECT] Adjusting to 1.91:1 (horizontal)")
        } else if aspectRatio < 0.9 {
            // Close to vertical → 4:5
            targetRatio = verticalRatio
            print("🔧 [ASPECT] Adjusting to 4:5 (vertical)")
        } else if aspectRatio > 1.5 {
            // Close to horizontal → 1.91:1
            targetRatio = horizontalRatio
            print("🔧 [ASPECT] Adjusting to 1.91:1 (horizontal)")
        } else {
            // Everything else → square
            targetRatio = squareRatio
            print("🔧 [ASPECT] Adjusting to 1:1 (square)")
        }
        
        // Calculate crop dimensions (center crop)
        let newWidth: CGFloat
        let newHeight: CGFloat
        
        if aspectRatio > targetRatio {
            // Too wide → crop width
            newHeight = height
            newWidth = height * targetRatio
        } else {
            // Too tall → crop height
            newWidth = width
            newHeight = width / targetRatio
        }
        
        // NEW: Use drawing instead of cgImage.cropping to preserve orientation
        let cropSize = CGSize(width: newWidth, height: newHeight)
        let cropRect = CGRect(
            x: (width - newWidth) / 2,
            y: (height - newHeight) / 2,
            width: newWidth,
            height: newHeight
        )
        
        // Create a new image context with the cropped size
        UIGraphicsBeginImageContextWithOptions(cropSize, false, image.scale)
        
        // Draw the image, cropped
        let drawRect = CGRect(
            x: -cropRect.origin.x,
            y: -cropRect.origin.y,
            width: width,
            height: height
        )
        image.draw(in: drawRect)
        
        guard let croppedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            print("❌ [ASPECT] Failed to crop, using original")
            return imageData
        }
        UIGraphicsEndImageContext()
        
        print("✅ [ASPECT] Cropped to \(Int(newWidth))x\(Int(newHeight))")
        
        // Convert back to JPEG
        guard let adjustedData = croppedImage.jpegData(compressionQuality: 0.9) else {
            print("❌ [ASPECT] Failed to convert to JPEG, using original")
            return imageData
        }
        
        print("✅ [ASPECT] Final size: \(adjustedData.count / 1024)KB")
        return adjustedData
    }
    
    // MARK: - Image Uniqueness (ANTI-BOT for duplicate photos across banks)
    
    /// Makes an image subtly unique by applying invisible pixel-level variations.
    /// This prevents Instagram from detecting that the same photo was uploaded multiple times.
    /// Changes are imperceptible to the human eye but produce a different file hash.
    static func makeImageUnique(imageData: Data) -> Data {
        guard let originalImage = UIImage(data: imageData) else {
            print("⚠️ [UNIQUE] Cannot create UIImage, using original")
            return imageData
        }
        
        let image = normalizeImageOrientation(originalImage)
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        // Create a mutable pixel buffer
        UIGraphicsBeginImageContextWithOptions(image.size, true, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            print("⚠️ [UNIQUE] Cannot create graphics context")
            return imageData
        }
        
        // Draw the original image
        image.draw(at: .zero)
        
        // ANTI-BOT: Apply subtle random pixel modifications
        // Modify 15-30 random pixels with tiny color shifts (invisible to the eye)
        let pixelCount = Int.random(in: 15...30)
        
        for _ in 0..<pixelCount {
            let x = CGFloat(Int.random(in: 1..<max(width - 1, 2)))
            let y = CGFloat(Int.random(in: 1..<max(height - 1, 2)))
            
            // Tiny color shift: just 1-3 units in RGB (out of 255), completely invisible
            let r = CGFloat(Int.random(in: 0...3)) / 255.0
            let g = CGFloat(Int.random(in: 0...3)) / 255.0
            let b = CGFloat(Int.random(in: 0...3)) / 255.0
            let alpha = CGFloat(Double.random(in: 0.01...0.03)) // nearly transparent
            
            context.setFillColor(red: r, green: g, blue: b, alpha: alpha)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        
        // ANTI-BOT: Slight JPEG quality variation (produces different compression artifacts)
        guard let uniqueImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            print("⚠️ [UNIQUE] Failed to create unique image")
            return imageData
        }
        UIGraphicsEndImageContext()
        
        // Vary JPEG quality slightly each time (0.82 to 0.88) for different byte patterns
        let quality = Double.random(in: 0.82...0.88)
        guard let uniqueData = uniqueImage.jpegData(compressionQuality: quality) else {
            print("⚠️ [UNIQUE] Failed to encode unique JPEG")
            return imageData
        }
        
        let originalKB = imageData.count / 1024
        let uniqueKB = uniqueData.count / 1024
        print("🎲 [UNIQUE] Image uniquified: \(originalKB)KB → \(uniqueKB)KB (\(pixelCount) pixels modified, quality: \(String(format: "%.2f", quality)))")
        LogManager.shared.info("Image uniquified: \(originalKB)KB → \(uniqueKB)KB (\(pixelCount)px modified)", category: .upload)
        
        return uniqueData
    }
    
    // MARK: - Image Compression (PUBLIC for photo selection)
    
    /// Compress image intelligently with adaptive quality
    /// Target: MAX 480KB (safe margin below 500KB limit)
    /// Uses calculated quality based on original size for optimal results
    /// PUBLIC: Called when selecting photos from gallery
    static func compressImageForUpload(imageData: Data, photoIndex: Int? = nil) -> Data {
        let sizeKB = imageData.count / 1024
        let photoDesc = photoIndex != nil ? "Photo #\(photoIndex! + 1)" : "Photo"
        
        print("📦 [COMPRESS] \(photoDesc) original size: \(sizeKB)KB")
        
        guard let originalImage = UIImage(data: imageData) else {
            print("❌ [COMPRESS] Failed to create UIImage")
            return imageData
        }
        
        // CRITICAL: Always normalize orientation first to prevent rotation
        let image = normalizeImageOrientation(originalImage)
        
        // If already small enough AND orientation was correct, use original
        // If orientation was fixed, we need to re-encode
        if imageData.count <= 500_000 && originalImage.imageOrientation == .up {
            print("✅ [COMPRESS] Already optimized (<500KB), no compression needed")
            // Don't log to LogManager to avoid cluttering logs - only print for debug
            return imageData
        }
        
        // If orientation was fixed but size is OK, just re-encode with high quality
        if imageData.count <= 500_000 {
            guard let reEncodedData = image.jpegData(compressionQuality: 0.95) else {
                print("⚠️ [COMPRESS] Re-encoding failed, using original")
                return imageData
            }
            let newSizeKB = reEncodedData.count / 1024
            print("✅ [COMPRESS] Orientation fixed: \(sizeKB)KB → \(newSizeKB)KB")
            LogManager.shared.info("\(photoDesc): Orientation fixed (\(newSizeKB)KB)", category: .upload)
            return reEncodedData
        }
        
        let originalSize = image.size
        print("📐 [COMPRESS] Original dimensions: \(Int(originalSize.width))x\(Int(originalSize.height))")
        
        let targetKB = 480 // Safe margin below 500KB limit
        let targetBytes = targetKB * 1024
        
        // ADAPTIVE COMPRESSION: Calculate optimal quality based on size
        // Formula: quality = sqrt(targetSize / originalSize)
        // This gives us the quality needed to reach target in ONE compression
        
        let sizeRatio = Double(targetBytes) / Double(imageData.count)
        var calculatedQuality = sqrt(sizeRatio)
        
        // Clamp quality between 0.70 (minimum acceptable) and 0.95 (maximum useful)
        calculatedQuality = max(0.70, min(0.95, calculatedQuality))
        
        print("🧮 [COMPRESS] Calculated optimal quality: \(String(format: "%.2f", calculatedQuality)) for target \(targetKB)KB")
        
        // If calculated quality is too low (<0.70), we need to resize first
        if calculatedQuality <= 0.70 {
            print("🔧 [COMPRESS] Quality too low, will resize to 1080px first")
            
            let maxDimension: CGFloat = 1080
            var newSize = originalSize
            
            if originalSize.width > maxDimension || originalSize.height > maxDimension {
                let ratio = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
                newSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
                print("   Resizing from \(Int(originalSize.width))x\(Int(originalSize.height)) to \(Int(newSize.width))x\(Int(newSize.height))")
            }
            
            // Resize
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                print("❌ [COMPRESS] Resize failed, using fallback compression")
                guard let compressed = image.jpegData(compressionQuality: 0.75) else {
                    return imageData
                }
                let finalSizeKB = compressed.count / 1024
                print("✅ [COMPRESS] Fallback: \(finalSizeKB)KB (quality 0.75)")
                LogManager.shared.info("\(photoDesc): \(sizeKB)KB → \(finalSizeKB)KB (fallback)", category: .upload)
                return compressed
            }
            UIGraphicsEndImageContext()
            
            // Now compress the resized image with quality 0.82
            guard let finalData = resizedImage.jpegData(compressionQuality: 0.82) else {
                print("❌ [COMPRESS] Failed to compress resized image")
                return imageData
            }
            
            let finalSizeKB = finalData.count / 1024
            let savedPercent = 100 - (finalSizeKB * 100 / sizeKB)
            print("✅ [COMPRESS] Resized + compressed: \(finalSizeKB)KB (from \(sizeKB)KB, -\(savedPercent)%)")
            LogManager.shared.success("\(photoDesc): \(sizeKB)KB → \(finalSizeKB)KB (resized + compressed, -\(savedPercent)%)", category: .upload)
            return finalData
        }
        
        // Apply calculated quality in ONE compression (no quality loss from multiple compressions)
        print("🔧 [COMPRESS] Applying quality \(String(format: "%.2f", calculatedQuality))...")
        guard let compressedData = image.jpegData(compressionQuality: calculatedQuality) else {
            print("❌ [COMPRESS] Compression failed, using original")
            return imageData
        }
        
        let finalSizeKB = compressedData.count / 1024
        
        // Verify result
        if compressedData.count >= imageData.count {
            print("⚠️ [COMPRESS] Compression didn't reduce size, using original")
            return imageData
        }
        
        let savedPercent = 100 - (finalSizeKB * 100 / sizeKB)
        print("✅ [COMPRESS] Final: \(finalSizeKB)KB (from \(sizeKB)KB, -\(savedPercent)%, quality \(String(format: "%.2f", calculatedQuality)))")
        LogManager.shared.success("\(photoDesc): \(sizeKB)KB → \(finalSizeKB)KB (adaptive quality \(String(format: "%.2f", calculatedQuality)), -\(savedPercent)%)", category: .upload)
        return compressedData
    }
    
    // MARK: - TEST: Get Archived Photos
    
    /// Get archived photos from Instagram's "Only Me" archive
    /// Returns array of media IDs, image URLs, and timestamps
    func testGetArchivedPhotos() async throws -> [(mediaId: String, imageURL: String, timestamp: Date?)] {
        print("🔍 [TEST] Attempting to fetch archived photos...")
        
        // Based on instagram_private_api documentation:
        // feed/only_me_feed/ is the correct endpoint for archived media
        // We'll also try some alternative endpoints as fallback
        let possiblePaths = [
            "/feed/only_me_feed/",                 // PRIMARY: Official archived feed endpoint
            "/feed/saved/",                        // Saved posts (sometimes confused with archive)
            "/archive/reel/day_shells/",           // Stories archive (different from posts)
        ]
        
        for path in possiblePaths {
            print("   Trying endpoint: \(path)")
            
            do {
                let data = try await apiRequest(method: "GET", path: path)
                
                // Try to parse response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("   ⚠️ Could not parse JSON from \(path)")
                    continue
                }
                
                print("   ✅ Got response from \(path)")
                print("   JSON keys: \(json.keys.joined(separator: ", "))")
                
                // Log response for debugging (truncated if too large)
                if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let preview = jsonString.prefix(500)
                    LogManager.shared.info("Archive endpoint \(path) response (first 500 chars):\n\(preview)...", category: .api)
                }
                
                // Check for error messages in response
                if let status = json["status"] as? String, status != "ok" {
                    if let message = json["message"] as? String {
                        print("   ⚠️ API returned status '\(status)': \(message)")
                        continue
                    }
                }
                
                // Try to extract media items from different possible response structures
                var archivedPhotos: [(String, String, Date?)] = []
                
                // STRUCTURE 1: Direct items array (feed/only_me_feed, feed/saved)
                // Example: { "items": [ { "pk": 123, "image_versions2": {...}, "taken_at": 1234567890 } ] }
                if let items = json["items"] as? [[String: Any]] {
                    print("   Found 'items' array with \(items.count) items")
                    
                    for item in items {
                        // Some endpoints wrap media in "media" key (like feed/saved)
                        let mediaItem = item["media"] as? [String: Any] ?? item
                        
                        if let pk = mediaItem["pk"] as? Int64 {
                            let mediaId = String(pk)
                            
                            // Extract image URL
                            var imageUrl = ""
                            if let imageVersions = mediaItem["image_versions2"] as? [String: Any],
                               let candidates = imageVersions["candidates"] as? [[String: Any]],
                               let firstCandidate = candidates.first,
                               let url = firstCandidate["url"] as? String {
                                imageUrl = url
                            }
                            
                            // Extract timestamp
                            let takenAt: Date?
                            if let timestamp = mediaItem["taken_at"] as? TimeInterval {
                                takenAt = Date(timeIntervalSince1970: timestamp)
                            } else if let timestamp = mediaItem["taken_at"] as? Int64 {
                                takenAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
                            } else {
                                takenAt = nil
                            }
                            
                            archivedPhotos.append((mediaId, imageUrl, takenAt))
                            print("      Found media: \(mediaId), timestamp: \(takenAt?.description ?? "nil")")
                        } else if let pkString = mediaItem["pk"] as? String,
                                  let pk = Int64(pkString) {
                            // Handle pk as string
                            let mediaId = String(pk)
                            
                            var imageUrl = ""
                            if let imageVersions = mediaItem["image_versions2"] as? [String: Any],
                               let candidates = imageVersions["candidates"] as? [[String: Any]],
                               let firstCandidate = candidates.first,
                               let url = firstCandidate["url"] as? String {
                                imageUrl = url
                            }
                            
                            let takenAt: Date?
                            if let timestamp = mediaItem["taken_at"] as? TimeInterval {
                                takenAt = Date(timeIntervalSince1970: timestamp)
                            } else if let timestamp = mediaItem["taken_at"] as? Int64 {
                                takenAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
                            } else {
                                takenAt = nil
                            }
                            
                            archivedPhotos.append((mediaId, imageUrl, takenAt))
                        }
                    }
                }
                
                // STRUCTURE 2: Archive day shells (nested structure)
                // Example: { "items": [ { "medias": [ {...} ] } ] }
                if archivedPhotos.isEmpty, let items = json["items"] as? [[String: Any]] {
                    for item in items {
                        if let medias = item["medias"] as? [[String: Any]] {
                            print("   Found 'medias' array in item")
                            for media in medias {
                                if let pk = media["pk"] as? Int64 {
                                    let mediaId = String(pk)
                                    var imageUrl = ""
                                    
                                    if let imageVersions = media["image_versions2"] as? [String: Any],
                                       let candidates = imageVersions["candidates"] as? [[String: Any]],
                                       let firstCandidate = candidates.first,
                                       let url = firstCandidate["url"] as? String {
                                        imageUrl = url
                                    }
                                    
                                    let takenAt: Date?
                                    if let timestamp = media["taken_at"] as? TimeInterval {
                                        takenAt = Date(timeIntervalSince1970: timestamp)
                                    } else if let timestamp = media["taken_at"] as? Int64 {
                                        takenAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
                                    } else {
                                        takenAt = nil
                                    }
                                    
                                    archivedPhotos.append((mediaId, imageUrl, takenAt))
                                }
                            }
                        }
                    }
                }
                
                if !archivedPhotos.isEmpty {
                    print("   🎉 SUCCESS! Found \(archivedPhotos.count) archived photos from \(path)")
                    LogManager.shared.success("Found \(archivedPhotos.count) archived photos from \(path)", category: .api)
                    return archivedPhotos
                } else {
                    print("   ⚠️ Response parsed but no media items found")
                }
                
            } catch let error as InstagramError {
                print("   ❌ Endpoint \(path) failed: \(error.localizedDescription)")
                LogManager.shared.warning("Endpoint \(path) failed: \(error.localizedDescription)", category: .api)
                // Continue trying other endpoints
            } catch {
                print("   ❌ Endpoint \(path) failed with unexpected error: \(error.localizedDescription)")
                // Continue trying other endpoints
            }
        }
        
        // If we get here, none of the endpoints worked
        print("❌ [TEST] Could not find archived photos from any endpoint")
        LogManager.shared.error("No archived photos found - tried \(possiblePaths.count) endpoints", category: .api)
        throw InstagramError.apiError("Could not access archived photos. This may be due to:\n• No archived photos exist\n• Endpoint access restricted\n• Session may need refresh")
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
