import Foundation
import UIKit
import Combine
import CryptoKit
import Network
import WebKit
import UserNotifications

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

    // MARK: - Session expiry context
    /// Why the session expired — drives the message shown in MagicianSessionPanel.
    enum SessionExpiredContext: Int {
        case unknown        = 0  // default; not enough info to determine cause
        case normal         = 1  // password change, inactivity, generic 403
        case restriction    = 2  // Instagram imposed a temporary account restriction
        case challenge      = 3  // challenge_required streak on POST
    }

    // Session expiry — set true when any API call returns 403/401.
    // Persisted to UserDefaults so the overlay reappears after an app restart.
    @Published var isSessionExpired: Bool = false
    @Published var sessionExpiredContext: SessionExpiredContext = .unknown

    /// How many times validateSession returned .expired since the last successful login.
    /// Persisted so the counter survives app restarts during a stuck-login loop.
    @Published var reloginFailCount: Int = UserDefaults.standard.integer(forKey: "relogin_fail_count")

    /// Coalesces duplicate foreground validation calls. Performance entry and the
    /// first-time loader can appear in the same second; without this they both hit
    /// /accounts/current_user/ and spend two actions from the same hourly budget.
    private var sessionValidationInFlight = false
    private var lastSessionValidationResult: SessionStatus?

    /// Coalesces duplicate own-profile loads. A fresh install/no-cache path can show
    /// the blocking loader while PerformanceView also appears, otherwise we fetch the
    /// full own profile twice (followers/feed/reels/tagged/highlights duplicated).
    private var ownProfileInfoTask: Task<InstagramProfile?, Error>?

    /// Sets session as expired with context and persists across app restarts.
    @MainActor
    func markSessionExpired(context: SessionExpiredContext) {
        isSessionExpired = true
        sessionExpiredContext = context
        reloginFailCount += 1
        UserDefaults.standard.set(true, forKey: "instagram_session_expired")
        UserDefaults.standard.set(context.rawValue, forKey: "instagram_session_expired_ctx")
        UserDefaults.standard.set(reloginFailCount, forKey: "relogin_fail_count")
        LogManager.shared.warning("Session expired — context: \(context)", category: .auth)
    }

    /// Clears session expired state and persistence.
    @MainActor
    func clearSessionExpired() {
        isSessionExpired = false
        sessionExpiredContext = .unknown
        reloginFailCount = 0
        UserDefaults.standard.removeObject(forKey: "instagram_session_expired")
        UserDefaults.standard.removeObject(forKey: "instagram_session_expired_ctx")
        UserDefaults.standard.removeObject(forKey: "relogin_fail_count")
    }

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
    /// True whenever there is at least one unresolved network/API error. Views use
    /// this to skip optimistic background refreshes that would fire into a broken
    /// session (e.g. the cold-start deferred refresh that was triggering
    /// challenge_required on /feed/user/ immediately after a /current_user/ timeout).
    @Published var hasRecentApiError: Bool = false

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
    private var deviceId: String // Persistent device ID for this install
    private var clientUUID: String // Client UUID (like _uuid in instagrapi)
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
    // Persisted in UserDefaults so it survives app restarts — Notes endpoint rejects wwwClaim="0".
    private var wwwClaim: String = UserDefaults.standard.string(forKey: "ig_www_claim") ?? "0"

    // MARK: - Bearer Authorization (modern IG auth — required by www edge stack since 2024+)
    //
    // ── BUG HISTORY (May-2026) ──────────────────────────────────────────────
    // Instagram migrated newer endpoints (/notes/*, profile reads, some DMs)
    // from cookie-only auth to Bearer-token auth. The server sends back the
    // token in the `ig-set-authorization` response header on successful
    // backend ("distillery") responses. Real Instagram clients store it and
    // re-send it as `Authorization: Bearer IGT:2:...` on subsequent requests.
    //
    // Without this header the edge ("www") stack returns HTTP 200 +
    // status:fail (the "We're sorry, but something went wrong" body) for the
    // entire account, even on simple reads like GET /accounts/current_user/.
    // This looks identical to a server-side soft-block on the account but is
    // actually the WAF refusing to forward unauthenticated traffic.
    //
    // Diagnostic: in a response header dump you'll see
    //   `ig-set-authorization: Bearer IGT:2:eyJk…`
    //   `ig-set-use-auth-header-for-sso: True`
    // on any endpoint that DID accept us (e.g. POST /accounts/edit_profile/).
    // Capture and re-send.
    // ─────────────────────────────────────────────────────────────────────────
    private var authBearer: String = UserDefaults.standard.string(forKey: "ig_auth_bearer") ?? ""
    
    // MARK: - Rate Limiting (anti-bot: max 60 actions/hour)
    private var actionTimestamps: [Date] = []
    private let maxActionsPerHour: Int = 55 // Safe margin below 60

    /// ANTI-BOT: In-memory cache of recent state-check results.
    /// Avoids hammering /media/{pk}/info/ when the user re-syncs the same set
    /// within minutes. Key = mediaId pk, Value = (isArchived, capturedAt).
    /// TTL controlled by `stateCheckCacheTTL`.
    private var stateCheckCache: [String: (isArchived: Bool, at: Date)] = [:]
    private let stateCheckCacheTTL: TimeInterval = 300 // 5 minutes
    /// Stop paginated archive scans when actionsThisHour reaches this threshold
    private let archiveScanRateLimitThreshold: Int = 45
    @Published var actionsThisHour: Int = 0
    @Published var isRateLimited: Bool = false
    private var lastRequestTimestamp: Date? = nil
    /// Rolling buffer of recent API calls for bot-detection diagnostics
    private var recentRequests: [(date: Date, method: String, path: String)] = []
    private let recentRequestsMax = 10

    // MARK: - Archive Scan Cache
    /// In-memory cache for the last archive scan result. Avoids re-scanning hundreds of
    /// photos every session. Invalidated automatically after unarchive/archive operations.
    private var archivedPhotoCache: [(mediaId: String, imageURL: String, timestamp: Date?, isVideo: Bool, videoURL: String?, videoAspectRatio: CGFloat?)]? = nil
    private var archivedPhotoCacheDate: Date? = nil
    private let archivedPhotoCacheTTL: TimeInterval = 600 // 10 minutes
    private(set) var lastArchiveScanCompleted: Bool = true
    private(set) var lastArchiveScanStopReason: String? = nil

    /// Invalidate the archive scan cache (call after any archive/unarchive action).
    func invalidateArchiveCache() {
        archivedPhotoCache = nil
        archivedPhotoCacheDate = nil
        lastArchiveScanCompleted = true
        lastArchiveScanStopReason = nil
        ArchivedPhotosCache.shared.invalidate()
        print("♻️ [ARCHIVE CACHE] Invalidated")
    }
    
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

            // CRITICAL: HTTPCookieStorage.shared lives in the app's data container,
            // which iOS WIPES on reinstall — but the Keychain (ThisDeviceOnly)
            // survives. So after a reinstall + iCloud restore we can end up with
            // `isLoggedIn=true` and a usable sessionId in Keychain, while
            // HTTPCookieStorage is empty → every Instagram request goes out without
            // `sessionid` / `csrftoken` / `ds_user_id` cookies and IG replies with
            // 200 status:fail (looks identical to a soft-block).
            // Rebuild the 3 critical cookies from the persisted session so URLSession
            // can authenticate the very first call after relaunch.
            rehydrateInstagramCookiesFromSessionIfNeeded(saved)

            // Restore persisted session-expired state so overlay appears immediately
            // after an app restart without needing a new API call.
            if UserDefaults.standard.bool(forKey: "instagram_session_expired") {
                self.isSessionExpired = true
                let ctxRaw = UserDefaults.standard.integer(forKey: "instagram_session_expired_ctx")
                self.sessionExpiredContext = SessionExpiredContext(rawValue: ctxRaw) ?? .unknown
                print("⚠️ [SESSION] Restored expired state from UserDefaults (context: \(self.sessionExpiredContext))")
            }
        }
        
        // ANTI-BOT: Restore the trailing window of recent action timestamps so
        // the burst guard works across quick relaunches.
        restoreRecentActionTimestamps()

        // Start network monitoring
        startNetworkMonitoring()
    }

    // MARK: - Cookie Rehydration (post-restart / post-reinstall)

    /// Rebuilds the 3 critical Instagram cookies (`sessionid`, `csrftoken`,
    /// `ds_user_id`) inside `HTTPCookieStorage.shared` from the persisted
    /// `InstagramSession`. We only do this when:
    ///   • The Keychain has a valid session (sessionId / userId non-empty), AND
    ///   • `HTTPCookieStorage` is missing `sessionid` for instagram.com.
    ///
    /// Background: `HTTPCookieStorage` lives in the app's data container so a
    /// reinstall (Fresh install detected) leaves it empty, even though the
    /// Keychain survives. Without these cookies every `apiRequest()` call goes
    /// out unauthenticated and IG replies with HTTP 200 + `status:"fail"` —
    /// looks identical to a soft-block.
    private func rehydrateInstagramCookiesFromSessionIfNeeded(_ session: InstagramSession) {
        guard !session.sessionId.isEmpty, !session.userId.isEmpty else {
            // Keychain still claims `isLoggedIn=true` but the bytes inside are
            // unusable. Without sessionId we can never authenticate. Mark the
            // session as expired so the UI shows the re-login flow instead of
            // an eternal skeleton.
            print("🍪 [REHYDRATE] Restored session has empty sessionId/userId — marking session expired so user can re-login")
            LogManager.shared.warning(
                "Cookie rehydrate skipped — restored session has empty sessionId/userId; forcing re-login overlay",
                category: .auth
            )
            UserDefaults.standard.set(true, forKey: "instagram_session_expired")
            UserDefaults.standard.set(SessionExpiredContext.normal.rawValue, forKey: "instagram_session_expired_ctx")
            self.isSessionExpired = true
            self.sessionExpiredContext = .normal
            return
        }

        let storage = HTTPCookieStorage.shared
        let igURL = URL(string: "https://www.instagram.com")!
        let existing = storage.cookies(for: igURL) ?? []

        let hasSessionId = existing.contains { $0.name == "sessionid" && !$0.value.isEmpty }
        let hasCsrf     = existing.contains { $0.name == "csrftoken"  && !$0.value.isEmpty }
        let hasDsUserId = existing.contains { $0.name == "ds_user_id" && !$0.value.isEmpty }

        if hasSessionId && hasCsrf && hasDsUserId {
            print("🍪 [REHYDRATE] HTTPCookieStorage already has sessionid + csrftoken + ds_user_id — no rebuild needed")
            return
        }

        print("🍪 [REHYDRATE] HTTPCookieStorage missing IG auth cookies (sessionid=\(hasSessionId) csrftoken=\(hasCsrf) ds_user_id=\(hasDsUserId)) — rebuilding from Keychain session")

        // Cookies must be valid for ALL instagram.com subdomains (www., i., etc.)
        // because the app hits both. Using `.instagram.com` as Domain achieves that.
        let expires = Date().addingTimeInterval(60 * 60 * 24 * 365)  // 1 year

        let cookieSpecs: [(String, String)] = [
            ("sessionid", session.sessionId),
            ("csrftoken", session.csrfToken),
            ("ds_user_id", session.userId)
        ]

        var built = 0
        for (name, value) in cookieSpecs where !value.isEmpty {
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: ".instagram.com",
                .path: "/",
                .expires: expires,
                .secure: true
            ]
            if let cookie = HTTPCookie(properties: props) {
                storage.setCookie(cookie)
                built += 1
            }
        }

        print("🍪 [REHYDRATE] Rebuilt \(built) cookie(s) in HTTPCookieStorage from restored session for ds_user_id=\(session.userId)")
        LogManager.shared.info(
            "Rehydrated \(built) IG cookie(s) in HTTPCookieStorage after Keychain restore (fresh install / data-container wipe recovery)",
            category: .auth
        )
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
            // Both GET and POST trigger a visible lockdown so the magician always knows
            // to open the Instagram app and complete any pending verification prompt.
            // POST operations get a longer lockdown (3 min); GET gets a shorter one (2 min)
            // since GET challenges are often transient soft-checks that self-clear.
            let lockDuration: TimeInterval = isWriteOperation ? 180 : 120
            await markSessionChallenged(duration: lockDuration)
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
                hasRecentApiError = true
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

        // Dump recent API calls to logs for bot-detection diagnosis
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let history = recentRequests.enumerated().map { i, req in
            let gapStr: String
            if i > 0 {
                let prevDate = recentRequests[i - 1].date
                gapStr = String(format: "+%.1fs", req.date.timeIntervalSince(prevDate))
            } else {
                gapStr = "start"
            }
            return "  \(df.string(from: req.date)) \(req.method) \(req.path) [\(gapStr)]"
        }.joined(separator: "\n")
        let diagMsg = "LOCKDOWN — last \(recentRequests.count) API calls:\n\(history)"
        LogManager.shared.bot(diagMsg)
        print("🔒 [LOCKDOWN] \(diagMsg)")
    }
    
    /// Marks the session as challenged for `duration` seconds.
    /// During this window, views skip non-essential API calls (profile loads, profile pic
    /// auto-upload, explore refreshes) to avoid cascading bot signals. Does NOT block
    /// uploads/archives, which have their own flow management.
    /// Default 60s cooldown — enough to prevent cascading calls but not so long
    /// that the user feels the app is broken. POST operations (archive/unarchive)
    /// check this flag and abort to avoid triggering a full lockdown.
    private func markSessionChallenged(duration: TimeInterval = 60) async {
        InstagramSafetyGate.shared.markChallenge(duration: duration)
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
        hasRecentApiError = false
        InstagramSafetyGate.shared.clearChallenge()
        print("🔓 [LOCKDOWN] Deactivated")
    }

    /// Resets the exponential backoff counter without touching lockdown state.
    /// Call after background/optional operations that should not penalise user-facing requests.
    @MainActor
    func resetBackoff() {
        consecutiveErrors = 0
        consecutiveBotSignalErrors = 0
        hasRecentApiError = false
    }

    /// Lightweight session probe: makes a single minimal GET request to Instagram.
    /// Returns `true` if the session is valid (200 OK with user data), `false` if
    /// the session is expired or the challenge is still pending.
    /// Used by the auto-recovery mechanism when the app returns from background
    /// after a lockdown — if the user dismissed the challenge in the real Instagram
    /// app, this probe will succeed and the lockdown is cleared automatically.
    func probeSession() async -> Bool {
        guard isLoggedIn, !session.sessionId.isEmpty else { return false }
        let probeDecision = InstagramSafetyGate.shared.canProbeSession()
        guard probeDecision.allowed else {
            LogManager.shared.warning("CHALLENGE CIRCUIT — probe blocked for \(probeDecision.waitSeconds)s", category: .api)
            return false
        }
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
                InstagramSafetyGate.shared.recordProbeResult(success: true)
                return true
            }
            print("⚠️ [PROBE] Session probe failed — status \(http.statusCode)")
            InstagramSafetyGate.shared.recordProbeResult(success: false)
            return false
        } catch {
            print("⚠️ [PROBE] Session probe error: \(error.localizedDescription)")
            InstagramSafetyGate.shared.recordProbeResult(success: false)
            return false
        }
    }
    
    @MainActor
    /// Dismiss the session-expired overlay without logging out.
    /// Use this to let the magician navigate to Settings and re-login manually.
    func dismissSessionExpiredOverlay() {
        clearSessionExpired()
    }

    func emergencyLogout() {
        // Clear session state
        session = .empty
        isLoggedIn = false
        Task { @MainActor in clearSessionExpired() }
        KeychainService.shared.deleteSession()
        KeychainService.shared.clearCredentials()

        // Stop background pre-loading.
        ProfileFullLoaderService.shared.pause()

        // Reset lockdown
        unlock()

        // Clear archive cache — next login belongs to a potentially different account
        invalidateArchiveCache()

        // Clear profile cache (disk + memory)
        ProfileCacheService.shared.clearAll()
        ProfileCacheService.shared.pendingProfilePic = nil
        UserDefaults.standard.removeObject(forKey: "instagram_mid")
        // Clear the captured Bearer auth token and WWW-Claim — they are account-scoped
        // and the next login may belong to a different account.
        UserDefaults.standard.removeObject(forKey: "ig_auth_bearer")
        UserDefaults.standard.removeObject(forKey: "ig_www_claim")
        authBearer = ""
        wwwClaim   = "0"

        // ── Reset device fingerprint ────────────────────────────────────────
        // Generate a fresh fingerprint immediately. Previously we only deleted
        // the persisted values, which required a force-quit before the in-memory
        // service stopped using the flagged deviceId.
        let keychainDeviceKey = "com.mindup.instagram.deviceId"
        let keychainClientKey = "com.mindup.instagram.clientUUID"
        let oldDeviceId = deviceId
        let newDeviceId = UUID().uuidString
        let newClientUUID = UUID().uuidString
        deviceId = newDeviceId
        clientUUID = newClientUUID
        KeychainService.shared.saveString(newDeviceId, forKey: keychainDeviceKey)
        KeychainService.shared.saveString(newClientUUID, forKey: keychainClientKey)
        UserDefaults.standard.set(newDeviceId, forKey: "instagram_device_id")
        UserDefaults.standard.set(newClientUUID, forKey: "instagram_client_uuid")
        UserDefaults.standard.removeObject(forKey: "emergency_restart_pending")
        print("🔄 [EMERGENCY] Device fingerprint regenerated immediately: \(String(newDeviceId.prefix(8)))...")
        LogManager.shared.info(
            "Emergency logout: device regenerated \(String(oldDeviceId.prefix(8)))… → \(String(newDeviceId.prefix(8)))…",
            category: .auth
        )

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

        if sessionValidationInFlight {
            print("🔁 [SESSION] Validation already in flight — waiting for shared result")
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !sessionValidationInFlight {
                    return lastSessionValidationResult ?? .networkError
                }
            }
            LogManager.shared.warning("validateSession shared wait timed out — returning networkError", category: .auth)
            return .networkError
        }
        sessionValidationInFlight = true

        // Track whether the session was ALREADY expired before this call (persisted
        // across a restart). If so, and the call confirms the session is still dead,
        // we auto-logout so the app goes straight to LoginView instead of showing
        // the confusing overlay with multiple buttons.
        let wasAlreadyExpired = isSessionExpired
        func finish(_ status: SessionStatus) -> SessionStatus {
            lastSessionValidationResult = status
            sessionValidationInFlight = false
            return status
        }

        print("🔍 [SESSION] Validating session...")
        do {
            // Try without ?edit=true first — that parameter can cause different/missing
            // response structures on some account types (e.g. Korean/regional accounts).
            let data = try await apiRequest(method: "GET", path: "/accounts/current_user/")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Valid if: "user" key present, OR status=="ok", OR no explicit error message.
                // This is intentionally lenient because 200 without "user" can be a format
                // variation, not a genuine expiry — as evidenced by other endpoints working fine.
                let hasUser = json["user"] != nil
                let statusOk = (json["status"] as? String) == "ok"
                let message = (json["message"] as? String)?.lowercased() ?? ""
                let statusCode = (json["status_code"] as? String)?.lowercased() ?? ""
                let hasErrorMsg = json["message"] != nil && (json["status"] as? String) == "fail"
                let loggedOut = (json["login_required"] as? Bool) == true
                let explicitLoginRequired = loggedOut
                    || message.contains("login_required")
                    || statusCode.contains("login_required")

                let snippet = String(describing: json.keys.prefix(6))
                print("🔍 [SESSION] current_user response keys: \(snippet)")
                LogManager.shared.debug("validateSession keys: \(snippet)", category: .api)

                if !hasErrorMsg && !explicitLoginRequired && (hasUser || statusOk || !json.isEmpty) {
                    await MainActor.run {
                        clearSessionExpired()
                        resetUploadPhaseAfterRelogin()
                    }
                    print("✅ [SESSION] Session is valid (hasUser:\(hasUser) statusOk:\(statusOk))")
                    return finish(.valid)
                }

                // HTTP 200 + status=fail is not always logout. Instagram sometimes returns
                // {"message":"We're sorry, but something went wrong.","status_code":"200","status":"fail"}
                // from /accounts/current_user/ while the same freshly captured cookies keep
                // working for other endpoints. Treat only explicit login_required (or real
                // 401/403 handled by apiRequest) as expired; generic 200/fail is a transient
                // validation/network-format problem and must not wipe the session or device.
                let bodyPreview = String(data: data.prefix(300), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ") ?? "<binary>"
                let responseMessage = (json["message"] as? String) ?? ""
                let responseStatusCode = (json["status_code"] as? String) ?? ""
                let cookieSummary = currentCookieSummary()
                let deviceIdPrefix = String(deviceId.prefix(8))
                print("⚠️ [SESSION] 200 but validation returned fail (keys:\(snippet))")
                LogManager.shared.warning("validateSession 200/fail indicator (keys:\(snippet))", category: .auth)
                LogManager.shared.warning(
                    "Session diagnostic | device:\(deviceIdPrefix)… status_code:\(responseStatusCode) message:\(responseMessage) cookies:\(cookieSummary) body:\(bodyPreview)",
                    category: .auth
                )
                if explicitLoginRequired {
                    print("🔑 [SESSION] login_required confirmed → auto-logout to LoginView")
                    LogManager.shared.warning("Auto-logout: explicit login_required from Instagram", category: .auth)
                    await markSessionExpired(context: .normal)
                    await MainActor.run { logout() }
                    return finish(.expired)
                }

                if wasAlreadyExpired {
                    print("ℹ️ [SESSION] Pre-expired flag + generic 200/fail — keeping session, returning networkError")
                    LogManager.shared.warning("Pre-expired flag ignored for generic 200/fail validation response", category: .auth)
                }
                return finish(.networkError)
            }
            // JSON parse failed entirely — treat as network/format error, not expiry
            print("⚠️ [SESSION] Could not parse response — treating as network error")
            return finish(.networkError)
        } catch InstagramError.sessionExpired {
            // Context already set by apiRequest — only set if not already marked
            if !isSessionExpired { await markSessionExpired(context: .normal) }
            print("❌ [SESSION] Session expired (401/403)")
            // Auto-logout: if the session was ALREADY marked expired before this call
            // (i.e. persisted from a previous session) and is still dead, go straight
            // to LoginView instead of leaving the user with a confusing overlay.
            if wasAlreadyExpired && isConnected {
                print("🔑 [SESSION] Pre-expired + confirmed dead (403) → auto-logout to LoginView")
                LogManager.shared.warning("Auto-logout: pre-expired session confirmed dead via 403", category: .auth)
                await MainActor.run { logout() }
            }
            return finish(.expired)
        } catch InstagramError.challengeRequired {
            print("⚠️ [SESSION] Challenge required during validation")
            return finish(.challenged)
        } catch InstagramError.networkError {
            print("📶 [SESSION] Network error during validation")
            return finish(.networkError)
        } catch {
            print("⚠️ [SESSION] Validation error: \(error) — assuming network issue")
            return finish(.networkError)
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

    /// Extra safety used only before media uploads. It does not change the
    /// normal upload/archive cooldown; it only avoids starting a POST while the
    /// app is in cold-start or the network just switched.
    func waitForUploadSafetyWindow(label: String = "upload") async throws {
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [UPLOAD] \(label) waiting for cold-start window — \(remaining)s")
            LogManager.shared.info("[COLD-START] Upload delayed — \(remaining)s", category: .upload)
            try await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 3...6)) * 1_000_000_000)
        }

        if let changeTime = lastNetworkChangeTime {
            let secondsSinceChange = Date().timeIntervalSince(changeTime)
            let uploadNetworkDelay: TimeInterval = 15
            if secondsSinceChange < uploadNetworkDelay {
                let wait = uploadNetworkDelay - secondsSinceChange
                print("⏳ [UPLOAD] \(label) waiting \(String(format: "%.1f", wait))s after network change")
                LogManager.shared.info("Upload delayed after network change: \(Int(ceil(wait)))s", category: .upload)
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        try await waitForNetworkStability()
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

        let igCookies = cookies.filter { $0.domain.contains("instagram.com") }
        LogManager.shared.info(
            "WebView login captured \(igCookies.count) IG cookie(s) — sessionid:\(sessionId.isEmpty ? "missing" : "len=\(sessionId.count)") ds_user_id:\(userId.isEmpty ? "missing" : userId) csrftoken:\(csrfToken.isEmpty ? "missing" : "set") device:\(String(deviceId.prefix(8)))…",
            category: .auth
        )
        
        guard !sessionId.isEmpty, !userId.isEmpty else {
            print("❌ Missing required cookies")
            LogManager.shared.warning("WebView login finished but sessionid/ds_user_id are empty — session NOT stored", category: .auth)
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
        
        // IMPORTANT: clear the persisted "session expired" state before any post-login
        // API call. A re-login can happen while `isSessionExpired` is still true from a
        // previous run; if we wait until after fetchUsername(), apiRequest() blocks the
        // username fetch locally with `sessionExpired` and the app falls into a false
        // logout loop even though WebView just captured a fresh sessionid.
        Task {
            await MainActor.run {
                self.isLoggedIn = true
                self.clearSessionExpired()
                self.isSessionChallenged = false
                self.hasRecentApiError = false
                KeychainService.shared.saveSession(self.session)
            }

            // Fetch username after the stale expired flag has been cleared.
            if let username = await fetchUsername() {
                await MainActor.run {
                    self.session.username = username
                    KeychainService.shared.saveSession(self.session)
                    print("✅ Logged in as @\(username)")
                    self.resetUploadPhaseAfterRelogin()
                }
                InstagramSafetyGate.shared.resetPerformanceThrottle()
                // ProfileFullLoaderService is deprecated — see init() comment.
            } else {
                await MainActor.run {
                    KeychainService.shared.saveSession(self.session)
                    self.resetUploadPhaseAfterRelogin()
                }
                InstagramSafetyGate.shared.resetPerformanceThrottle()
                // ProfileFullLoaderService is deprecated — see init() comment.
            }
        }
    }

    /// If an upload was stuck in `.sessionExpired` state, transition it back to `.paused`
    /// so the magician can tap "Resume" without having to force-quit the app.
    @MainActor
    private func resetUploadPhaseAfterRelogin() {
        let um = UploadManager.shared
        if case .sessionExpired = um.uploadPhase {
            um.uploadPhase = .paused
            um.currentPhaseDescription = String(localized: "Session restored — tap Resume to continue")
            print("🔓 [SESSION] uploadPhase reset from .sessionExpired → .paused after re-login")
            LogManager.shared.info("Upload phase reset to paused after re-login", category: .auth)
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        session = .empty
        isLoggedIn = false
        Task { @MainActor in clearSessionExpired() }
        KeychainService.shared.deleteSession()
        KeychainService.shared.clearCredentials()

        // Stop background pre-loading — it will resume on next login.
        ProfileFullLoaderService.shared.pause()

        // Keep profile cache on normal logout. ProfileCacheService is keyed by userId,
        // so re-login with the same account can show cached Performance content
        // immediately, while a different account reads from its own cache folder.
        ProfileCacheService.shared.pendingProfilePic = nil

        // Clear instagram_mid so it is re-fetched for the new account
        UserDefaults.standard.removeObject(forKey: "instagram_mid")
        // Clear the captured Bearer auth token and WWW-Claim — they are account-scoped.
        UserDefaults.standard.removeObject(forKey: "ig_auth_bearer")
        UserDefaults.standard.removeObject(forKey: "ig_www_claim")
        authBearer = ""
        wwwClaim   = "0"

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
            
            // ANTI-BOT: WWW Claim — Instagram requires this header to ALWAYS be present.
            //
            // ── HISTORY (May-2026) ──────────────────────────────────────────────
            // An earlier "fix" omitted this header when wwwClaim == "0", based on
            // the (wrong) assumption that the real Instagram app skips the header
            // on first launch. In reality the API treats a MISSING header as a
            // protocol violation and replies with HTTP 200 + status:fail on every
            // endpoint (bio, notes, profile read…). With the header set to "0"
            // Instagram accepts the request and, on success, returns a fresh
            // claim in X-IG-Set-WWW-Claim which we then capture and persist.
            // The mentalgramold reference implementation also hard-codes "0"
            // unconditionally and works correctly. Always send the header.
            // ────────────────────────────────────────────────────────────────────
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

        // Bearer auth — required by modern IG endpoints. See `authBearer` declaration
        // comment for full history. Without this header the www WAF stack returns
        // HTTP 200 + status:fail on /notes/, /accounts/current_user/, etc.
        //
        // We send a value as soon as we have a session, even before the server has
        // returned its first `ig-set-authorization` rotation. The token format is
        // `Bearer IGT:2:<base64-of-JSON({ds_user_id, sessionid})>` — a verifiable
        // re-encoding of cookies we already hold. Once the server returns a rotated
        // token in `ig-set-authorization`, extractAndUpdateCSRF persists it and this
        // function uses the rotated value on subsequent calls.
        let bearerToSend = !authBearer.isEmpty ? authBearer : buildBearerFromSession()
        if !bearerToSend.isEmpty {
            headers["Authorization"] = bearerToSend
        }

        return headers
    }

    /// Builds an `Authorization: Bearer IGT:2:<base64>` value from the current session
    /// data, matching the format Instagram's server returns in `ig-set-authorization`.
    /// Used as a bootstrap before the server has rotated its first Bearer token.
    private func buildBearerFromSession() -> String {
        guard !session.sessionId.isEmpty, !session.userId.isEmpty else { return "" }
        // Real IG payload uses a URL-encoded sessionid (the ":" in "57631997058:abc..."
        // is encoded as "%3A"). The session.sessionId we hold is already in that form
        // when restored from cookies, so we send it as-is.
        let payload: [String: Any] = [
            "ds_user_id": session.userId,
            "sessionid":  session.sessionId,
            "should_use_header_over_cookies": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return ""
        }
        let b64 = data.base64EncodedString()
        return "Bearer IGT:2:\(b64)"
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
        // ANTI-BOT: Persist the last 20 timestamps so the burst guard survives
        // a quick force-quit/relaunch cycle (e.g. user closes the app and
        // re-opens it within seconds — without persistence the in-memory array
        // is empty and the guard would let the first call through).
        persistRecentActionTimestamps()

        DispatchQueue.main.async {
            self.actionsThisHour = self.actionTimestamps.count
            self.isRateLimited = self.actionTimestamps.count >= self.maxActionsPerHour
        }

        if actionTimestamps.count >= maxActionsPerHour {
            print("⚠️ [RATE LIMIT] \(actionTimestamps.count)/\(maxActionsPerHour) actions this hour - LIMIT REACHED")
            LogManager.shared.warning("Rate limit approaching: \(actionTimestamps.count)/\(maxActionsPerHour) actions/hour", category: .api)
        }
    }

    /// Persist the full rolling hour of `actionTimestamps` to UserDefaults so both
    /// the burst guard and the hard rate-limit check survive app restarts or crashes.
    /// Entries older than 1 hour are dropped here (they'd be filtered on restore anyway).
    private func persistRecentActionTimestamps() {
        let now = Date()
        let withinHour = actionTimestamps
            .filter { now.timeIntervalSince($0) < 3600 }
            .map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(withinHour, forKey: "instagram_recent_actions")
    }

    /// Restore action timestamps from UserDefaults on launch.
    /// Filters out any entry older than 1 hour to keep the rolling rate-limit window honest.
    private func restoreRecentActionTimestamps() {
        guard let raw = UserDefaults.standard.array(forKey: "instagram_recent_actions") as? [Double] else { return }
        let now = Date()
        let restored = raw.map { Date(timeIntervalSince1970: $0) }
            .filter { now.timeIntervalSince($0) < 3600 }
        if !restored.isEmpty {
            actionTimestamps = restored
            print("🛡️ [BURST-GUARD] Restored \(restored.count) recent action timestamps from previous session")
        }
    }
    
    /// Check if rate limited (PUBLIC for views to show warning)
    func checkRateLimit() -> (limited: Bool, actionsUsed: Int, remaining: Int) {
        let now = Date()
        let recentActions = actionTimestamps.filter { now.timeIntervalSince($0) < 3600 }
        let remaining = max(0, maxActionsPerHour - recentActions.count)
        return (recentActions.count >= maxActionsPerHour, recentActions.count, remaining)
    }

    /// True when only user-critical actions should be allowed. Performance entry,
    /// first-time preload, reels/tagged/highlights, and silent refreshes use this to
    /// avoid spending the last actions in the hourly budget on optional cache work.
    var shouldUseCacheOnlyForOptionalCalls: Bool {
        let rate = checkRateLimit()
        return rate.actionsUsed >= 45 || rate.remaining <= 10
    }

    /// Returns the moment when ALL actions in the current rolling window will have
    /// expired (oldest action + 60 min). Returns nil when the budget is already full.
    func budgetRenewalTime() -> Date? {
        let now = Date()
        let recent = actionTimestamps.filter { now.timeIntervalSince($0) < 3600 }
        guard let oldest = recent.min() else { return nil }
        return oldest.addingTimeInterval(3600)
    }

    /// Returns true while any "heavy" foreground operation is in flight. Used by
    /// secondary surfaces (Explore mask refresh, Home follower probe, Date Force
    /// auto-load, second web_profile_info reconciliation) to defer their own API
    /// calls and prevent compound bot-like bursts.
    var isHeavyOperationActive: Bool {
        return UploadManager.shared.isActive
            || UploadManager.shared.isSyncArchiveActive
            || isRevealOperationActive
            || isUploadingProfilePic
    }

    /// Returns true if there have been `threshold` or more API requests within
    /// the last `seconds` seconds. Used by low-priority callers to skip themselves
    /// when many endpoints are already being hit (anti-burst).
    func hasRecentApiBurst(threshold: Int = 2, seconds: TimeInterval = 10) -> Bool {
        let now = Date()
        let recent = actionTimestamps.filter { now.timeIntervalSince($0) < seconds }.count
        return recent >= threshold
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
        // ANTI-BOT: If the session is already flagged as expired (carried over
        // from a previous run via UserDefaults, typical after a `restriction`
        // bot detection), refuse to fire. Otherwise every retry of S&A would
        // emit a fresh 403 storm against a token Instagram already invalidated.
        if isSessionExpired {
            print("⚠️ [STATE-CHECK] Skipped (id: \(mediaId)) — session is already expired")
            LogManager.shared.warning("[STATE-CHECK] Skipped — session already expired (re-login required)", category: .auth)
            throw InstagramError.sessionExpired
        }
        // ANTI-BOT: Cold-start and warm-resume windows block this GET. The sync
        // flow (which is the main caller) checks the window itself before
        // starting a batch, but defense in depth: if anything else triggers a
        // state-check inside the window, drop it silently.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [STATE-CHECK] Skipped — cold-start active (\(remaining)s remaining)")
            LogManager.shared.warning("[STATE-CHECK] Skipped — cold-start active (\(remaining)s)", category: .general)
            return nil
        }

        let pk = mediaId.split(separator: "_").first.map(String.init) ?? mediaId

        // ANTI-BOT: Post-reveal protection — if this media was just revealed by
        // the magician we keep it "read-locked" so the app does not produce a
        // suspicious reveal → check → archive ping-pong on the same mediaId.
        // The caller is expected to treat `nil` as "leave local state as-is".
        if InstagramSafetyGate.shared.isMediaPostRevealProtected(mediaId: mediaId) {
            let wait = InstagramSafetyGate.shared.postRevealSecondsRemaining
            print("🛡️ [STATE-CHECK] Skipped (pk: \(pk)) — post-reveal protected (\(wait)s left)")
            LogManager.shared.info("State check skipped: \(pk) post-reveal protected (\(wait)s)", category: .api)
            return nil
        }

        // ANTI-BOT: 5-min cache for state-checks. Two consecutive syncs on the
        // same set within the TTL hit the cache instead of the network, which
        // is the exact pattern Instagram flags as scripted polling.
        let now = Date()
        if let cached = stateCheckCache[pk],
           now.timeIntervalSince(cached.at) < stateCheckCacheTTL {
            let age = Int(now.timeIntervalSince(cached.at))
            print("💾 [STATE-CHECK] Cache hit (pk: \(pk), age \(age)s) → is_archived=\(cached.isArchived)")
            LogManager.shared.info("State check cache hit: pk \(pk) is_archived=\(cached.isArchived) (age \(age)s)", category: .api)
            return cached.isArchived
        }

        // ANTI-BOT: Count state-checks in the rolling-hour rate limit so the
        // SafetyGate sees the real activity (otherwise sync bursts are invisible
        // to the limiter and can stack with archives / refreshes).
        trackAction()

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
                    await markSessionExpired(context: challengeRequiredStreak > 0 ? .challenge : .restriction)
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
                stateCheckCache[pk] = (isArchived, Date())
                return isArchived
            }

            // Fallback: audience_setting (1 = only_me = archived)
            if let audience = first["audience_setting"] as? Int {
                let archived = audience == 1
                print("✅ [STATE-CHECK] pk \(pk) → audience_setting=\(audience) → archived=\(archived)")
                LogManager.shared.info("State check result via audience_setting: pk \(pk) archived=\(archived)", category: .api)
                stateCheckCache[pk] = (archived, Date())
                return archived
            }

            // Fallback: visibility field
            if let visibility = first["visibility"] as? String {
                let archived = visibility == "private" || visibility == "only_me"
                print("✅ [STATE-CHECK] pk \(pk) → visibility=\(visibility) → archived=\(archived)")
                LogManager.shared.info("State check result via visibility: pk \(pk) visibility=\(visibility)", category: .api)
                stateCheckCache[pk] = (archived, Date())
                return archived
            }

            // No archive field present → Instagram only adds visibility/is_archived
            // to posts that are archived. A public post simply omits these fields.
            // Treat absence of archive indicator as: not archived (visible).
            print("✅ [STATE-CHECK] pk \(pk) → no archive field = public/visible (not archived)")
            LogManager.shared.info("State check result: pk \(pk) has no archive field → treated as visible", category: .api)
            stateCheckCache[pk] = (false, Date())
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
        //
        // ── BUG HISTORY (May-2026) ──────────────────────────────────────────────
        // Earlier code looked up headers with `httpResponse.allHeaderFields[name]`,
        // which is a Dictionary lookup → case-SENSITIVE. Instagram's actual response
        // header is `X-IG-Set-WWW-Claim` (with the `Set-` segment), and the casing
        // of the key returned by URLSession varies between iOS versions and TLS
        // backends (HTTP/2 vs HTTP/3 routes can normalise to lowercase, others not).
        // The old code searched for "X-IG-WWW-Claim" (no Set-) and "ig-set-ig-www-claim"
        // (lowercase) → neither matched the server's exact casing → claim never
        // captured.
        //
        // CRITICAL — false-positive fix: a previous attempt OMITTED the
        // X-IG-WWW-Claim header when wwwClaim == "0", believing that was what the
        // real Instagram app does on first launch. THAT BROKE EVERY ENDPOINT —
        // missing the header makes IG return HTTP 200 + status:fail on bio, notes
        // and even read-only GETs. The header MUST be present at all times.
        // Sending "0" is correct for fresh sessions; IG returns a fresh claim in
        // X-IG-Set-WWW-Claim which we capture below. See buildHeaders() comment.
        //
        // Fix: use httpResponse.value(forHTTPHeaderField:), which is
        // case-insensitive on iOS 13+, and the correct header name `X-IG-Set-WWW-Claim`.
        // Fall back to a lowercase-key scan for unknown future header name variants.
        // ─────────────────────────────────────────────────────────────────────────
        var capturedClaim: String? = nil
        let claimHeaderCandidates = [
            "X-IG-Set-WWW-Claim",   // canonical — used by Instagram API responses
            "x-ig-set-www-claim",   // lowercase variant (HTTP/2/3 normalisation)
            "X-IG-WWW-Claim",       // legacy/echo variant (kept for safety)
        ]
        for name in claimHeaderCandidates {
            if let val = httpResponse.value(forHTTPHeaderField: name),
               !val.isEmpty, val != "0" {
                capturedClaim = val
                break
            }
        }
        // Last-resort: scan all header fields by lowercased key in case Instagram
        // introduces a new variant we haven't seen yet (e.g. "ig-set-claim").
        if capturedClaim == nil {
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String,
                   let v = value as? String,
                   k.lowercased().contains("www-claim") || k.lowercased().contains("ig-claim"),
                   !v.isEmpty, v != "0" {
                    print("🔑 [CLAIM] Found unknown claim-like header: \(k) — capturing")
                    capturedClaim = v
                    break
                }
            }
        }

        if let claim = capturedClaim, claim != wwwClaim {
            print("🔑 [CLAIM] X-IG-WWW-Claim updated: \(String(claim.prefix(20)))…")
            wwwClaim = claim
            UserDefaults.standard.set(claim, forKey: "ig_www_claim")
        }

        // ── ig-set-authorization (Bearer token) ─────────────────────────────────
        // Captured the same way as the claim — case-insensitive header lookup
        // plus a lowercase-key scan as last-resort. The value already begins
        // with "Bearer IGT:2:..." and is sent back verbatim as Authorization.
        var capturedBearer: String? = nil
        let bearerHeaderCandidates = [
            "ig-set-authorization",
            "Ig-Set-Authorization",
            "IG-Set-Authorization",
        ]
        for name in bearerHeaderCandidates {
            if let val = httpResponse.value(forHTTPHeaderField: name), !val.isEmpty {
                capturedBearer = val
                break
            }
        }
        if capturedBearer == nil {
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String,
                   k.lowercased() == "ig-set-authorization", !v.isEmpty {
                    capturedBearer = v
                    break
                }
            }
        }
        if let bearer = capturedBearer, bearer != authBearer {
            // Only persist if the token has a payload — IG sometimes echoes an empty
            // `ig-set-authorization: ` header on error responses (means "no change").
            let trimmed = bearer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("IGT:") {
                print("🔐 [BEARER] Authorization token \(authBearer.isEmpty ? "captured" : "rotated"): \(String(trimmed.prefix(30)))…")
                authBearer = trimmed
                UserDefaults.standard.set(trimmed, forKey: "ig_auth_bearer")
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
        body: [String: String]? = nil,
        rawBody: String? = nil
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

        // Hard block: session was invalidated (403 login_required). Do NOT send any more
        // requests until the user re-logs in — continued requests accelerate bot flagging.
        if isSessionExpired {
            print("🔴 [SESSION] Blocked API call — session is expired. Re-login required.")
            throw InstagramError.sessionExpired
        }

        // Persistent safety gate: blocks/retries patterns that look like testing
        // bursts (rapid refreshes, post-reveal re-archives, pending challenges).
        try await InstagramSafetyGate.shared.waitForApiSlot(method: method, path: path)

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
        
        if let rawBody = rawBody {
            // Pre-encoded body — caller has already handled encoding (e.g. mixed JSON fields).
            request.httpBody = rawBody.data(using: .utf8)
        } else if let body = body {
            // Properly percent-encode each value so special characters (newlines → %0A,
            // spaces → %20, ampersands → %26, etc.) survive the API round-trip intact.
            // Raw string concatenation silently strips or breaks multi-line biography text.
            var components = URLComponents()
            components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)
        }
        
        // Track this action for rate limiting
        trackAction()
        InstagramSafetyGate.shared.recordApiRequest(method: method, path: path)

        // Log the request with timing info
        let now = Date()
        let gap: String
        if let last = lastRequestTimestamp {
            let elapsed = now.timeIntervalSince(last)
            gap = String(format: "%.1fs", elapsed)
        } else {
            gap = "first"
        }
        lastRequestTimestamp = now
        let rateInfo = checkRateLimit()
        let shortPath = path.components(separatedBy: "?").first ?? path
        LogManager.shared.log(
            "\(method) \(shortPath) [gap:\(gap)] [actions:\(rateInfo.actionsUsed)/\(maxActionsPerHour)] [errors:\(consecutiveErrors)]",
            level: .debug, category: .api
        )
        recentRequests.append((date: now, method: method, path: shortPath))
        if recentRequests.count > recentRequestsMax { recentRequests.removeFirst() }
        
        // Use different sessions: GET can wait, POST cannot (critical for bot detection)
        let session = (method == "GET") ? getSession : postSession
        
        let requestStart = CFAbsoluteTimeGetCurrent()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            let duration = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - requestStart) * 1000)
            print("🌐 [NETWORK] URLError: \(error.localizedDescription)")
            LogManager.shared.error("\(method) \(shortPath) NETWORK ERROR [\(duration)]: \(error.localizedDescription)", category: .api)
            // Mark API error so background tasks (e.g. cold-start deferred refresh)
            // can skip firing into a broken/unstable session.
            await MainActor.run { hasRecentApiError = true }
            throw InstagramError.networkError(error.localizedDescription)
        }
        
        let duration = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - requestStart) * 1000)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstagramError.invalidResponse
        }

        // ── DEEP DIAGNOSTIC for soft-fail responses (May-2026) ──────────────────
        // When IG returns 200 with a tiny body that's actually status:fail, the
        // standard log line is misleading. Dump full response headers + body so
        // we can tell apart server-side account flags from client-side regressions
        // (User-Agent / Bloks mismatch, missing cookies, malformed body, etc).
        // Triggers on any response < 300 bytes for /notes/, /accounts/, /usertags/.
        if data.count < 300 &&
           (shortPath.contains("/notes/") ||
            shortPath.contains("/accounts/") ||
            shortPath.contains("/usertags/")) {
            print("🩺 [DIAG] \(method) \(shortPath) returned only \(data.count) bytes — likely soft-fail")
            print("🩺 [DIAG] Request outgoing headers:")
            for (k, v) in request.allHTTPHeaderFields ?? [:] {
                let preview = (v.count > 100) ? "\(v.prefix(100))…(+\(v.count - 100))" : v
                print("🩺   \(k): \(preview)")
            }
            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                let preview = bodyStr.count > 400 ? "\(bodyStr.prefix(400))…(+\(bodyStr.count - 400))" : bodyStr
                print("🩺 [DIAG] Request body: \(preview)")
            }
            print("🩺 [DIAG] Response status: \(httpResponse.statusCode)")
            print("🩺 [DIAG] Response headers:")
            for (k, v) in httpResponse.allHeaderFields {
                if let key = k as? String, let val = v as? String {
                    let preview = val.count > 100 ? "\(val.prefix(100))…(+\(val.count - 100))" : val
                    print("🩺   \(key): \(preview)")
                }
            }
            if let s = String(data: data, encoding: .utf8) {
                print("🩺 [DIAG] Response body: \(s)")
            }
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
            hasRecentApiError = false
        } else {
            consecutiveErrors += 1
            hasRecentApiError = true
            LogManager.shared.warning("\(method) \(shortPath) HTTP \(httpResponse.statusCode) [\(duration)] [consecutiveErrors:\(consecutiveErrors)]", category: .api)
        }
        
        // Check for bot detection signals in HTTP status
        if httpResponse.statusCode == 429 {
            LogManager.shared.bot("\(method) \(shortPath) → HTTP 429 Rate Limited [\(duration)] [actions:\(rateInfo.actionsUsed)/\(maxActionsPerHour)]")
            await triggerLockdown(reason: "Rate limited by Instagram. Too many requests.", duration: 300)
            throw InstagramError.botDetected("Rate limited (HTTP 429). Wait 5 minutes.")
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            LogManager.shared.bot("\(method) \(shortPath) → HTTP \(httpResponse.statusCode) Session expired [\(duration)]")
            // Infer context: if no challenge history this is likely an account restriction;
            // otherwise attribute to the ongoing challenge streak.
            let expiredCtx: SessionExpiredContext = challengeRequiredStreak > 0 ? .challenge : .restriction
            await markSessionExpired(context: expiredCtx)
            throw InstagramError.sessionExpired
        }
        
        if httpResponse.statusCode >= 400 {
            // Try to parse error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = errorJson["message"] as? String ?? ""
                // Log full error details for debugging (status ≥ 400)
                if httpResponse.statusCode >= 500 {
                    let errorType    = errorJson["error_type"]        as? String ?? "?"
                    let fbErrorCode  = errorJson["fb_api_error_code"] as? Int    ?? -1
                    let spamBlock    = errorJson["spam"]               as? Bool   ?? false
                    let feedback     = errorJson["feedback_message"]   as? String ?? ""
                    print("❌ [API] 5xx detail — type:\(errorType) fb_code:\(fbErrorCode) spam:\(spamBlock) msg:\(message) feedback:\(feedback)")
                    print("❌ [API] Full 5xx JSON: \((String(data: data, encoding: .utf8) ?? "?").prefix(500))")
                }
                
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
                        await markSessionExpired(context: .challenge)
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
                    // POST challenges (configure, archive, etc.) need a much longer lockdown
                    // so the user has time to open Instagram and complete verification before
                    // the timer expires. 3 minutes was too short — users resumed before verifying.
                    // GET challenges remain short (2 min) since they are usually transient.
                    let lockDuration: TimeInterval
                    if method == "GET" {
                        lockDuration = 120
                    } else if challengeRequiredStreak >= 2 {
                        lockDuration = 1800  // 30 min: repeated challenge = stronger block
                    } else {
                        lockDuration = 900   // 15 min: first POST challenge
                    }
                    let lockMinutes = Int(lockDuration) / 60
                    let lockReason: String
                    if method == "GET" {
                        lockReason = "Instagram ha pedido verificación. Abre la app de Instagram — si ves un aviso de verificación, complétalo. Si no aparece nada, la sesión se reanudará automáticamente en 2 minutos."
                    } else if challengeRequiredStreak >= 2 {
                        lockReason = "Instagram sigue pidiendo verificación (\(challengeRequiredStreak)ª vez). Ve a la app de Instagram o instagram.com, completa la verificación de email/teléfono, espera \(lockMinutes) minutos y luego reanuda manualmente."
                    } else {
                        lockReason = "Instagram ha pedido verificación. Abre la app de Instagram, completa la verificación si aparece un aviso, espera \(lockMinutes) minutos y reanuda manualmente."
                    }
                    print("🚨 [API] challenge_required (\(method)) — streak \(challengeRequiredStreak) — triggering \(lockMinutes)min lockdown")
                    LogManager.shared.warning("challenge_required (\(method)) streak:\(challengeRequiredStreak) — lockdown \(lockMinutes)min", category: .api)
                    await markSessionChallenged(duration: lockDuration)
                    await triggerLockdown(reason: lockReason, duration: lockDuration)
                    // Signal upload manager to require manual resume (not auto-resume)
                    if method != "GET" {
                        await MainActor.run { UploadManager.shared.requiresManualResumeAfterChallenge = true }
                    }
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

        // Log successful response (debug level to avoid flooding)
        let dataSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        print("✅ [API] \(method) \(shortPath) → 200 [\(duration)] [\(dataSize)]")
        
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
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "count", value: "18")]
        if let maxId = maxId, !maxId.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "max_id", value: maxId))
        }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let path = "/feed/user/\(uid)/\(query)"
        
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

        let mediaSafety = InstagramSafetyGate.shared.canArchive(mediaId: mediaId)
        guard mediaSafety.allowed else {
            LogManager.shared.warning("SAFETY BLOCK — archive \(mediaId): \(mediaSafety.reason)", category: .api)
            throw InstagramError.apiError("Safety pause: \(mediaSafety.reason). Wait \(mediaSafety.waitSeconds)s.")
        }
        let archiveSafety = InstagramSafetyGate.shared.decision(for: .archive)
        guard archiveSafety.allowed else {
            LogManager.shared.warning("SAFETY BLOCK — archive budget: \(archiveSafety.reason)", category: .api)
            throw InstagramError.apiError("Safety pause: \(archiveSafety.reason). Wait \(archiveSafety.waitSeconds)s.")
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
                invalidateArchiveCache()
                // ANTI-BOT: drop any cached state-check for this media — a sync
                // happening right after must not return the stale "visible" entry.
                let pk = mediaId.split(separator: "_").first.map(String.init) ?? mediaId
                stateCheckCache.removeValue(forKey: pk)

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

        let unarchiveSafety = InstagramSafetyGate.shared.decision(for: .unarchive)
        guard unarchiveSafety.allowed else {
            LogManager.shared.warning("SAFETY BLOCK — unarchive budget: \(unarchiveSafety.reason)", category: .api)
            throw InstagramError.apiError("Safety pause: \(unarchiveSafety.reason). Wait \(unarchiveSafety.waitSeconds)s.")
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
                invalidateArchiveCache()
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
        // Cold-start guard: ExploreView.updateMaskTextCache() calls this when
        // its onAppear fires. If the mask is configured for "latestFollower"
        // and Explore happens to be touched within the first 45s of launch,
        // this would become the 3rd endpoint of the warmup pattern.
        // Degrade silently (return nil) so the caller does not surface a
        // network/connection error to the user during cold-start.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] getLatestFollower blocked — \(remaining)s remaining")
            LogManager.shared.warning("[COLD-START] getLatestFollower blocked — \(remaining)s", category: .general)
            return nil
        }
        // ANTI-BOT: Burst guard — if 2+ API calls were made in the last 10 seconds
        // (e.g. Performance entry fired current_user + feed/user, then user tapped
        // Explore which triggered topical_explore AND this followers call simultaneously),
        // skip this low-priority call to avoid having 4 different endpoints hit in ~5s.
        if hasRecentApiBurst(threshold: 2, seconds: 10) {
            print("⏳ [FOLLOWER] Burst guard active — getLatestFollower skipped")
            LogManager.shared.warning("[FOLLOWER] Burst guard — skipped", category: .general)
            return nil
        }
        // ANTI-BOT: Heavy operation guard — don't fire a low-priority follower
        // fetch while uploads/sync/reveals are in flight. The mask falls back
        // to a generic value (no UX impact for the magician).
        if isHeavyOperationActive {
            print("⏳ [FOLLOWER] Heavy op active — getLatestFollower skipped")
            LogManager.shared.warning("[FOLLOWER] Heavy op active — skipped", category: .general)
            return nil
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
            
            var follower = InstagramFollower(
                userId: userId,
                username: username,
                fullName: fullName,
                profilePicURL: profilePicURL
            )
            follower.isPrivate = isPrivate
            
            print("✅ [FOLLOWER] Found: @\(follower.username) (\(follower.fullName)) private:\(isPrivate)")
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

            var follower = InstagramFollower(
                userId: userId,
                username: user["username"] as? String ?? "",
                fullName: user["full_name"] as? String ?? "",
                profilePicURL: user["profile_pic_url"] as? String
            )
            follower.isPrivate = user["is_private"] as? Bool ?? false
            followers.append(follower)
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

            var follower = InstagramFollower(
                userId: userId,
                username: user["username"] as? String ?? "",
                fullName: user["full_name"] as? String ?? "",
                profilePicURL: user["profile_pic_url"] as? String
            )
            follower.isPrivate = user["is_private"] as? Bool ?? false
            following.append(follower)
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
            let followerCount = Self.robustInt(user["follower_count"])
            let followingCount = Self.robustInt(user["following_count"])
            let mediaCount = Self.robustInt(user["media_count"])
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

    private func extractProfileUserId(from dict: [String: Any]) -> String {
        if let pkInt64 = dict["pk"] as? Int64 { return String(pkInt64) }
        if let pkString = dict["pk"] as? String { return pkString }
        if let pkInt = dict["pk"] as? Int { return String(pkInt) }
        if let pkId = dict["pk_id"] as? String { return pkId }
        if let idString = dict["id"] as? String { return idString }
        if let idInt = dict["id"] as? Int { return String(idInt) }
        return "0"
    }

    private func fetchWebProfileInfoFallback(username: String) async -> [String: Any]? {
        var components = URLComponents(string: "https://www.instagram.com/api/v1/users/web_profile_info/")
        components?.queryItems = [URLQueryItem(name: "username", value: username)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let headers = buildHeaders()
        for (key, value) in headers where key.lowercased() != "content-type" {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        do {
            let (data, response) = try await getSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.shared.debug("Profile web fallback HTTP \(status) for @\(username)", category: .profile)
            guard status == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let webUser = dataDict["user"] as? [String: Any] else {
                if let raw = String(data: data, encoding: .utf8) {
                    LogManager.shared.warning("Profile web fallback unexpected response: \(String(raw.prefix(180)))", category: .profile)
                }
                return nil
            }

            var merged: [String: Any] = [:]
            merged["username"] = webUser["username"]
            merged["full_name"] = webUser["full_name"]
            merged["biography"] = webUser["biography"]
            merged["external_url"] = webUser["external_url"]
            merged["profile_pic_url"] = webUser["profile_pic_url_hd"] ?? webUser["profile_pic_url"]
            merged["is_private"] = webUser["is_private"]
            merged["is_verified"] = webUser["is_verified"]
            if let id = webUser["id"] { merged["id"] = id; merged["pk"] = id }

            if let followedBy = webUser["edge_followed_by"] as? [String: Any] {
                merged["follower_count"] = followedBy["count"]
            }
            if let follows = webUser["edge_follow"] as? [String: Any] {
                merged["following_count"] = follows["count"]
            }
            if let media = webUser["edge_owner_to_timeline_media"] as? [String: Any] {
                merged["media_count"] = media["count"]
            }

            return merged
        } catch {
            LogManager.shared.warning("Profile web fallback failed: \(error.localizedDescription)", category: .profile)
            return nil
        }
    }

    private func shouldPreferWebCount(api: Int, web: Int) -> Bool {
        guard web > 0 else { return false }
        if api <= 0 { return true }

        let diff = abs(api - web)
        if diff >= 1_000 { return true }

        let larger = max(api, web)
        guard larger > 0 else { return false }
        return Double(diff) / Double(larger) >= 0.05
    }
    
    func getProfileInfo(
        userId: String? = nil,
        usernameHint: String? = nil,
        fullNameHint: String? = nil,
        profilePicURLHint: String? = nil,
        isVerifiedHint: Bool? = nil
    ) async throws -> InstagramProfile? {
        let uid = userId ?? session.userId
        let isOwnProfile = (uid == session.userId)

        if isOwnProfile, usernameHint == nil, fullNameHint == nil, profilePicURLHint == nil, isVerifiedHint == nil {
            if let existing = ownProfileInfoTask {
                print("🔁 [PROFILE] Own profile load already in flight — reusing shared task")
                return try await existing.value
            }

            let task = Task<InstagramProfile?, Error> {
                try await self.fetchProfileInfoUnshared(
                    userId: userId,
                    usernameHint: usernameHint,
                    fullNameHint: fullNameHint,
                    profilePicURLHint: profilePicURLHint,
                    isVerifiedHint: isVerifiedHint
                )
            }
            ownProfileInfoTask = task
            defer { ownProfileInfoTask = nil }
            return try await task.value
        }

        return try await fetchProfileInfoUnshared(
            userId: userId,
            usernameHint: usernameHint,
            fullNameHint: fullNameHint,
            profilePicURLHint: profilePicURLHint,
            isVerifiedHint: isVerifiedHint
        )
    }

    private func fetchProfileInfoUnshared(
        userId: String? = nil,
        usernameHint: String? = nil,
        fullNameHint: String? = nil,
        profilePicURLHint: String? = nil,
        isVerifiedHint: Bool? = nil
    ) async throws -> InstagramProfile? {
        let uid = userId ?? session.userId
        let isOwnProfile = (uid == session.userId)
        print("📊 [PROFILE] Fetching complete profile for user ID: \(uid)")
        print("📊 [PROFILE] Is own profile: \(isOwnProfile)")
        LogManager.shared.info("Profile header fetch started — uid:\(uid) own:\(isOwnProfile)", category: .profile)

        // ── FAST-PATH for accounts/IPs where `/users/{id}/info/` is permanently broken ──
        // Some accounts get this endpoint stuck returning a 25-byte
        // `{"user":{},"status":"ok"}` response. The escalation block below already
        // recovers via `web_profile_info`, but that path costs:
        //   /users/info/  (≈0.5s wasted)  +  /accounts/current_user/ (≈0.5s wasted)  +
        //   /feed/user/?count=1 (≈1s, only to discover username)
        // = ~2 extra seconds on every Performance entry.
        //
        // We track this at two granularities:
        //   • per-uid (`instagram_users_info_broken_<uid>`) — owner-strong signal
        //   • globally (`instagram_users_info_globally_broken_ts`) — IP/account-wide:
        //     the moment we see ANY uid replying with ≤50 B we assume the endpoint
        //     is account-broken (the symptom always affects every uid at once).
        //     Lets us fast-path searched profiles too without having to first call
        //     and waste an action on each new uid we encounter.
        let usersInfoBrokenKey = "instagram_users_info_broken_\(uid)"
        let usersInfoBrokenTs = UserDefaults.standard.double(forKey: usersInfoBrokenKey)
        let usersInfoBrokenIsFresh = usersInfoBrokenTs > 0
            && (Date().timeIntervalSince1970 - usersInfoBrokenTs) < 7 * 24 * 3600  // 7 days

        let usersInfoGloballyBrokenKey = "instagram_users_info_globally_broken_ts"
        let usersInfoGloballyBrokenTs = UserDefaults.standard.double(forKey: usersInfoGloballyBrokenKey)
        let usersInfoGloballyBroken = usersInfoGloballyBrokenTs > 0
            && (Date().timeIntervalSince1970 - usersInfoGloballyBrokenTs) < 24 * 3600  // 1 day

        var user: [String: Any]
        var usedFastPath = false

        if isOwnProfile && usersInfoBrokenIsFresh && !session.username.isEmpty {
            print("⚡ [PROFILE] Fast-path: /users/info marked broken for uid \(uid) — going straight to web_profile_info for @\(session.username)")
            LogManager.shared.info("Profile fast-path: skipping /users/info (cached broken \(Int(Date().timeIntervalSince1970 - usersInfoBrokenTs))s ago) — calling web_profile_info for @\(session.username)", category: .profile)

            if let webUser = await fetchWebProfileInfoFallback(username: session.username) {
                user = webUser
                if extractProfileUserId(from: user) == "0" {
                    user["pk"] = uid
                    user["pk_id"] = uid
                    user["id"] = uid
                }
                usedFastPath = true
                print("⚡ [PROFILE] Fast-path succeeded — header ready in 1 call: followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"])) media:\(Self.robustInt(user["media_count"]))")
                LogManager.shared.success("Profile fast-path web_profile_info OK — @\(user["username"] as? String ?? session.username) followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"]))", category: .profile)
            } else {
                print("⚡ [PROFILE] Fast-path failed — falling back to /users/info chain")
                LogManager.shared.warning("Profile fast-path: web_profile_info returned nil — falling back to /users/info", category: .profile)
                user = [:]
            }
        } else if !isOwnProfile && usersInfoGloballyBroken,
                  let hint = usernameHint?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hint.isEmpty {
            // Searched profile fast-path: we have the username from the search
            // results AND we know /users/info is account-globally broken right
            // now. Skip the inevitable 25-byte response (costs 1 action of our
            // 55/h budget) and ask web_profile_info directly. It returns the
            // complete header + counts in one shot.
            print("⚡ [PROFILE] Fast-path (searched): /users/info globally broken (\(Int(Date().timeIntervalSince1970 - usersInfoGloballyBrokenTs))s ago) — calling web_profile_info for @\(hint)")
            LogManager.shared.info("Searched-profile fast-path: skipping /users/info, calling web_profile_info for @\(hint)", category: .profile)

            if let webUser = await fetchWebProfileInfoFallback(username: hint) {
                user = webUser
                if extractProfileUserId(from: user) == "0" {
                    user["pk"] = uid
                    user["pk_id"] = uid
                    user["id"] = uid
                }
                if let pic = profilePicURLHint, !pic.isEmpty, (user["profile_pic_url"] as? String ?? "").isEmpty {
                    user["profile_pic_url"] = pic
                }
                if let fn = fullNameHint, !fn.isEmpty, (user["full_name"] as? String ?? "").isEmpty {
                    user["full_name"] = fn
                }
                if let v = isVerifiedHint, user["is_verified"] == nil {
                    user["is_verified"] = v
                }
                usedFastPath = true
                print("⚡ [PROFILE] Searched fast-path succeeded — @\(user["username"] as? String ?? hint) followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"])) media:\(Self.robustInt(user["media_count"]))")
                LogManager.shared.success("Searched-profile fast-path OK — @\(user["username"] as? String ?? hint) followers:\(Self.robustInt(user["follower_count"]))", category: .profile)
            } else {
                print("⚡ [PROFILE] Searched fast-path failed — falling back to /users/info chain")
                LogManager.shared.warning("Searched-profile fast-path: web_profile_info nil for @\(hint), reverting to /users/info", category: .profile)
                user = [:]
            }
        } else {
            user = [:]
        }

        if !usedFastPath {
            let data = try await apiRequest(method: "GET", path: "/users/\(uid)/info/")

            // Detect the "endpoint permanently broken" pattern so we can fast-path
            // future calls. The empty-body response is ~25 bytes (`{"user":{},...}`).
            if data.count <= 50 {
                let secsSinceLast = usersInfoBrokenTs > 0 ? (Date().timeIntervalSince1970 - usersInfoBrokenTs) : -1
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: usersInfoBrokenKey)
                // Also bump the global marker so searched profiles can fast-path
                // without paying for their own 25-byte probe.
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: usersInfoGloballyBrokenKey)
                print("🔴 [PROFILE] /users/info returned only \(data.count) bytes for uid \(uid) — caching as broken (last seen broken \(Int(secsSinceLast))s ago)")
                LogManager.shared.warning("/users/{uid}/info/ empty body (\(data.count)B) for uid:\(uid) — marked broken globally; future searches will fast-path through web_profile_info", category: .profile)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [PROFILE] Failed to parse JSON response")
                let rawStr = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
                LogManager.shared.error("getProfileInfo: JSON parse failed — raw: \(rawStr)", category: .api)
                return nil
            }

            guard let u = json["user"] as? [String: Any] else {
                let topKeys = json.keys.sorted().joined(separator: ", ")
                print("❌ [PROFILE] No 'user' key — top-level keys: \(topKeys)")
                LogManager.shared.error("getProfileInfo: missing 'user' key — keys: \(topKeys)", category: .api)
                return nil
            }
            user = u
        }

        // Debug: Print user data
        print("📊 [PROFILE] User data keys: \(user.keys.sorted().joined(separator: ", "))")
        LogManager.shared.debug("Profile user keys: \(user.keys.sorted().joined(separator: ","))", category: .profile)
        if let profilePicUrl = user["profile_pic_url"] as? String {
            print("📊 [PROFILE] Profile pic URL found: \(String(profilePicUrl.prefix(80)))...")
            LogManager.shared.debug("Profile pic URL present: \(String(profilePicUrl.prefix(80)))", category: .profile)
        } else {
            print("⚠️ [PROFILE] No profile_pic_url field found")
            LogManager.shared.warning("Profile pic URL missing in /users/info response", category: .profile)
        }
        
        var extractedUserId = extractProfileUserId(from: user)
        if extractedUserId == "0" {
            print("⚠️ [PROFILE] Could not extract userId before fallback, defaulting to '0'")
            LogManager.shared.warning("Profile userId missing before fallback", category: .profile)
        } else {
            print("📊 [PROFILE] userId extracted: \(extractedUserId)")
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

        // Own-profile /users/{id}/info sometimes returns an empty "user" object while
        // heavier feed endpoints still work. Do not start the expensive chain
        // followers + feed + reels + tagged + highlights until the header is usable:
        // that was causing 7-10 API calls, then rejecting the profile as invalid.
        if isOwnProfile {
            let headerEmptyBeforeMedia = extractedUserId == "0"
                || ((user["username"] as? String ?? "").isEmpty
                    && (user["profile_pic_url"] as? String ?? "").isEmpty
                    && user["follower_count"] == nil
                    && user["following_count"] == nil)

            if headerEmptyBeforeMedia {
                print("⚠️ [PROFILE] Own header empty before media fetch — trying current_user fallback first")
                LogManager.shared.warning("Own profile header empty before media fetch — delaying heavy profile chain", category: .profile)
                do {
                    let currentData = try await apiRequest(method: "GET", path: "/accounts/current_user/?edit=true")
                    if let currentJSON = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any],
                       let currentUser = currentJSON["user"] as? [String: Any] {
                        for (key, value) in currentUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) {
                            user[key] = value
                        }
                        extractedUserId = extractProfileUserId(from: user)
                        print("✅ [PROFILE] Early current_user fallback merged. Keys now: \(user.keys.sorted().joined(separator: ", "))")
                    } else {
                        LogManager.shared.warning("Early current_user fallback returned unexpected structure", category: .profile)
                    }
                } catch {
                    print("⚠️ [PROFILE] Early current_user fallback failed: \(error.localizedDescription)")
                    LogManager.shared.warning("Early current_user fallback failed: \(error.localizedDescription)", category: .profile)
                }
            }

            if extractedUserId == "0",
               !uid.isEmpty,
               (!(user["username"] as? String ?? "").isEmpty
                || !(user["profile_pic_url"] as? String ?? "").isEmpty
                || user["follower_count"] != nil
                || user["following_count"] != nil) {
                extractedUserId = uid
                LogManager.shared.info("Own profile userId recovered from session uid before media fetch: \(uid)", category: .profile)
            }

            let stillInvalidBeforeMedia = extractedUserId == "0"
                || ((user["username"] as? String ?? "").isEmpty
                    && (user["profile_pic_url"] as? String ?? "").isEmpty
                    && user["follower_count"] == nil
                    && user["following_count"] == nil
                    && ProfileCacheService.shared.loadProfile() == nil)

            if stillInvalidBeforeMedia {
                // Some accounts/IPs get `/users/{id}/info/` permanently returning 25-byte
                // empty bodies while `/feed/user/{id}/` and `web_profile_info` keep
                // working (same pattern that recovers Explore'd profiles further below).
                // Before giving up on Performance, replicate that recovery chain:
                //   1. Try to discover a usable username (session → hint → feed probe).
                //   2. Merge `web_profile_info` so header/counts come back.
                // This is what makes Explore'd profiles render even when /users/info
                // is empty — Performance gets exactly the same treatment now.
                print("⚠️ [PROFILE] Own header empty after /users/info + /accounts/current_user — escalating to /feed/user + web_profile_info")
                LogManager.shared.warning("Own profile header empty — escalating to feed/web fallbacks before aborting", category: .profile)

                var discoveredUsername: String? = {
                    if !session.username.isEmpty { return session.username }
                    if let hint = usernameHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty { return hint }
                    return nil
                }()

                if discoveredUsername == nil {
                    // Probe `/feed/user/{uid}/` — its response carries a `user` object
                    // with `username`/`profile_pic_url` even when `/users/info` is empty.
                    do {
                        let feedData = try await apiRequest(method: "GET", path: "/feed/user/\(uid)/?count=1")
                        if let feedJSON = try? JSONSerialization.jsonObject(with: feedData) as? [String: Any],
                           let feedUser = feedJSON["user"] as? [String: Any] {
                            if let uname = feedUser["username"] as? String, !uname.isEmpty {
                                discoveredUsername = uname
                                print("🔎 [PROFILE] Username discovered via /feed/user/: @\(uname)")
                                LogManager.shared.info("Own profile username discovered via /feed/user/: @\(uname)", category: .profile)
                            }
                            for (key, value) in feedUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) {
                                user[key] = value
                            }
                            extractedUserId = extractProfileUserId(from: user)
                            if extractedUserId == "0", !uid.isEmpty { extractedUserId = uid }
                        }
                    } catch {
                        print("⚠️ [PROFILE] /feed/user/ probe failed: \(error.localizedDescription)")
                        LogManager.shared.warning("Own profile /feed/user/ probe failed: \(error.localizedDescription)", category: .profile)
                    }
                }

                if let username = discoveredUsername, !username.isEmpty {
                    if let webUser = await fetchWebProfileInfoFallback(username: username) {
                        for (key, value) in webUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) || Self.robustInt(user[key]) == 0 {
                            user[key] = value
                        }
                        extractedUserId = extractProfileUserId(from: user)
                        if extractedUserId == "0", !uid.isEmpty { extractedUserId = uid }
                        print("✅ [PROFILE] Own header recovered via web_profile_info — followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"]))")
                        LogManager.shared.success("Own profile web fallback merged — @\(user["username"] as? String ?? username) followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"])) posts:\(Self.robustInt(user["media_count"]))", category: .profile)

                        // Persist the discovered username in the session so future
                        // launches don't need the feed probe again.
                        if session.username.isEmpty {
                            await MainActor.run {
                                self.session.username = username
                                KeychainService.shared.saveSession(self.session)
                            }
                        }
                    } else {
                        LogManager.shared.warning("Own profile web fallback returned nil for @\(username)", category: .profile)
                    }
                } else {
                    LogManager.shared.warning("Own profile: no username could be discovered — cannot try web_profile_info", category: .profile)
                }

                // Re-evaluate after both fallbacks.
                let stillInvalidAfterEscalation = extractedUserId == "0"
                    || ((user["username"] as? String ?? "").isEmpty
                        && (user["profile_pic_url"] as? String ?? "").isEmpty
                        && user["follower_count"] == nil
                        && user["following_count"] == nil)

                if stillInvalidAfterEscalation {
                    print("🛡️ [PROFILE] Own header still invalid after /feed/user + web_profile_info — aborting")
                    LogManager.shared.warning("Own profile header invalid after escalation — skipped expensive profile chain", category: .profile)
                    return nil
                }

                print("✅ [PROFILE] Own header recovered — continuing with normal media fetch chain")
            }
        }
        
        // Only fetch followers and media if:
        // 1. It's our own profile, OR
        // 2. Profile is public, OR
        // 3. Profile is private BUT we follow them (NOT just requested)
        // IMPORTANT: Do NOT fetch if only "requested" - this triggers bot detection
        let shouldFetchProtectedData = isOwnProfile || !isPrivate || (isFollowing && !isFollowRequested)
        print("📊 [PROFILE] Should fetch protected data: \(shouldFetchProtectedData)")

        // ── PROGRESSIVE RENDER ─────────────────────────────────────────────────
        // For own profile, the chain below makes 5 sequential API calls with
        // 1.2s anti-bot pauses between each (~10s total). The header is already
        // usable right now, so push it to the UI immediately. PerformanceView
        // listens for `ownProfileHeaderReady` and paints the header + cached
        // grid while reels/tagged/highlights load in the background.
        if isOwnProfile {
            let headerUsername = (user["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let headerPicURL: String = {
                if let hdInfo = user["hd_profile_pic_url_info"] as? [String: Any],
                   let hdUrl = hdInfo["url"] as? String, !hdUrl.isEmpty { return hdUrl }
                if let hdVersions = user["hd_profile_pic_versions"] as? [[String: Any]],
                   let best = hdVersions.last, let url = best["url"] as? String, !url.isEmpty { return url }
                return (user["profile_pic_url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            let headerFollowers  = Self.robustInt(user["follower_count"])
            let headerFollowing  = Self.robustInt(user["following_count"])
            let headerMediaCount = Self.robustInt(user["media_count"])
            let headerUserId = (extractedUserId == "0" || extractedUserId.isEmpty) ? uid : extractedUserId

            // Only emit when we have something worth showing — otherwise the
            // listener would clear an existing valid cache.
            let headerWorthEmitting = !headerUsername.isEmpty
                && (!headerPicURL.isEmpty || headerFollowers > 0 || headerFollowing > 0 || headerMediaCount > 0)

            if headerWorthEmitting {
                // Merge with whatever the cache already has so the grid that the
                // user is looking at (cachedMediaURLs from previous sessions)
                // does not get blown away by an empty header snapshot.
                let existing = ProfileCacheService.shared.loadProfile()
                let snapshot = InstagramProfile(
                    userId: headerUserId,
                    username: headerUsername,
                    fullName: (user["full_name"] as? String ?? ""),
                    biography: (user["biography"] as? String ?? existing?.biography ?? ""),
                    externalUrl: (user["external_url"] as? String) ?? existing?.externalUrl,
                    profilePicURL: headerPicURL.isEmpty ? (existing?.profilePicURL ?? "") : headerPicURL,
                    isVerified: (user["is_verified"] as? Bool) ?? existing?.isVerified ?? false,
                    isPrivate: (user["is_private"] as? Bool) ?? existing?.isPrivate ?? false,
                    followerCount: headerFollowers > 0 ? headerFollowers : (existing?.followerCount ?? 0),
                    followingCount: headerFollowing > 0 ? headerFollowing : (existing?.followingCount ?? 0),
                    mediaCount: headerMediaCount > 0 ? headerMediaCount : (existing?.mediaCount ?? 0),
                    followedBy: existing?.followedBy ?? [],
                    isFollowing: existing?.isFollowing ?? false,
                    isFollowRequested: existing?.isFollowRequested ?? false,
                    cachedAt: Date(),
                    cachedMediaURLs: existing?.cachedMediaURLs ?? [],
                    cachedReelURLs: existing?.cachedReelURLs ?? [],
                    cachedTaggedURLs: existing?.cachedTaggedURLs ?? [],
                    cachedHighlights: existing?.cachedHighlights ?? [],
                    cachedReelItems: existing?.cachedReelItems ?? [],
                    cachedNextMaxId: existing?.cachedNextMaxId
                )
                var snapshotWithItems = snapshot
                snapshotWithItems.cachedMediaItems = existing?.cachedMediaItems ?? []

                // Persist so the next launch can paint instantly even if the
                // user kills the app before the heavy chain finishes.
                ProfileCacheService.shared.saveProfile(snapshotWithItems)
                print("⚡ [PROFILE] Header snapshot emitted early — @\(headerUsername) followers:\(headerFollowers) following:\(headerFollowing) media:\(headerMediaCount) pic:\(headerPicURL.isEmpty ? "EMPTY" : "OK")")
                LogManager.shared.info("Own profile header snapshot broadcast — UI can paint before heavy chain (5 calls / ~10s)", category: .profile)

                let snapshotForNotif = snapshotWithItems
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .ownProfileHeaderReady,
                        object: nil,
                        userInfo: ["snapshot": snapshotForNotif]
                    )
                }
            }
        }
        
        var followedBy: [InstagramFollower] = []
        var mediaURLs: [String] = []
        var reelURLs: [String] = []
        var reelItems: [InstagramMediaItem] = []
        var taggedURLs: [String] = []
        var initialMediaItems: [InstagramMediaItem] = []
        var highlights: [InstagramHighlight] = []
        var initialNextMaxId: String? = nil   // cursor saved so the first pagination skips page 1

        if shouldFetchProtectedData {
            print("✅ [PROFILE] Fetching followers, media, reels, tagged & highlights (profile is accessible)")
            LogManager.shared.info("Profile protected data fetch allowed", category: .profile)

            if isOwnProfile {
                // Own profile refresh is anti-bot sensitive: fetch only the bare
                // minimum to render the visible part of the screen as fast as
                // possible. Reels / tagged / highlights live behind tabs that
                // PerformanceView already loads lazily on first tap (see
                // `fetchReelsIfNeeded`, `fetchTaggedIfNeeded`). Pulling them
                // here too was duplicating ~3 API calls and ~4-5 seconds with
                // no visible payoff — the user can't even see those tabs yet.
                //
                // Progressive render: after each call we broadcast a notification
                // so PerformanceView can paint "Followed by ..." and the post
                // grid as soon as they arrive, without waiting for the full
                // chain to finish (mirrors how a real Instagram profile pops in).
                followedBy = try await getFollowedByUsers(userId: uid, count: 6)
                if !followedBy.isEmpty {
                    let snapshot = followedBy
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .ownProfileFollowedByReady,
                            object: nil,
                            userInfo: ["followedBy": snapshot]
                        )
                    }
                    LogManager.shared.info("Own profile followedBy broadcast (count:\(snapshot.count)) — UI can paint header row", category: .profile)
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)

                let (mediaItems, ownNextId) = try await getUserMediaItems(userId: uid, amount: 18)
                mediaURLs = mediaItems.map { $0.imageURL }
                initialMediaItems = mediaItems
                initialNextMaxId = ownNextId
                if !mediaItems.isEmpty {
                    let snapshotItems = mediaItems
                    let snapshotCursor = ownNextId
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .ownProfileMediaReady,
                            object: nil,
                            userInfo: [
                                "mediaItems": snapshotItems,
                                "nextMaxId": snapshotCursor as Any
                            ]
                        )
                    }
                    print("⚡ [PROFILE] Posts broadcast (\(mediaItems.count) items) — UI can fill grid before chain finishes")
                    LogManager.shared.info("Own profile media broadcast (count:\(mediaItems.count) cursor:\(snapshotCursor != nil ? "saved" : "none"))", category: .profile)
                }
                // Reels / tagged / highlights are intentionally not fetched here.
                // PerformanceView calls `fetchReelsIfNeeded` / `fetchTaggedIfNeeded`
                // when the user taps each tab. Highlights are part of the
                // optional background refresh elsewhere when allowed.
            } else {
                // Searched profiles open like a real Instagram profile: present
                // the partial header (avatar, username, counters) as soon as we
                // have it, then fill in posts and followers progressively.
                //
                // Step 1 — recover the header BEFORE the heavy chain.
                // /users/info on this account permanently returns 25 B empty,
                // so without this step the header would only be reconciled at
                // the very end of getProfileInfo (~6s after entry). Pulling
                // web_profile_info up here lets us broadcast the header in ~1s.
                //
                // Anti-bot: we do NOT add a sleep before this call. The fast
                // path skips /users/info entirely (so this is the first IG
                // call); when /users/info ran, friendships/show already came
                // after it with its own natural ~0.4s gap.
                let earlyHeaderUsername: String? = {
                    let candidates = [
                        user["username"] as? String,
                        usernameHint
                    ]
                    return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                }()

                let earlyHeaderIncomplete =
                    (user["username"] as? String ?? "").isEmpty ||
                    (user["profile_pic_url"] as? String ?? "").isEmpty ||
                    user["follower_count"] == nil ||
                    user["following_count"] == nil ||
                    extractedUserId == "0"

                if earlyHeaderIncomplete, let webUsername = earlyHeaderUsername {
                    LogManager.shared.info("Searched profile early header recovery via web_profile_info for @\(webUsername)", category: .profile)
                    if let webUser = await fetchWebProfileInfoFallback(username: webUsername) {
                        for (key, value) in webUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) || Self.robustInt(user[key]) == 0 {
                            user[key] = value
                        }
                        extractedUserId = extractProfileUserId(from: user)
                        if extractedUserId == "0" { extractedUserId = uid }
                        print("⚡ [PROFILE] Searched header recovered early — @\(user["username"] as? String ?? webUsername) followers:\(Self.robustInt(user["follower_count"]))")
                        LogManager.shared.success("Searched-profile early header OK — @\(user["username"] as? String ?? webUsername) followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"]))", category: .profile)
                    } else {
                        LogManager.shared.warning("Searched-profile early web_profile_info nil for @\(webUsername) — will retry later", category: .profile)
                    }
                }

                // Apply hints to fill anything web_profile_info could not.
                if (user["username"] as? String ?? "").isEmpty, let h = earlyHeaderUsername { user["username"] = h }
                if (user["full_name"] as? String ?? "").isEmpty, let fn = fullNameHint, !fn.isEmpty { user["full_name"] = fn }
                if (user["profile_pic_url"] as? String ?? "").isEmpty, let pic = profilePicURLHint, !pic.isEmpty { user["profile_pic_url"] = pic }
                if user["is_verified"] == nil, let v = isVerifiedHint { user["is_verified"] = v }
                if extractedUserId == "0" { extractedUserId = uid }

                // ── BROADCAST VISITED HEADER ──────────────────────────────────
                // ExploreView listens for this and presents UserProfileView
                // immediately. The Task keeps running below to populate posts
                // and followers progressively (same pattern as own profile).
                let visitedHeaderUsername = (user["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let visitedHeaderPic: String = {
                    if let hdInfo = user["hd_profile_pic_url_info"] as? [String: Any],
                       let hdUrl = hdInfo["url"] as? String, !hdUrl.isEmpty { return hdUrl }
                    return (user["profile_pic_url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }()
                let visitedHeaderFollowers  = Self.robustInt(user["follower_count"])
                let visitedHeaderFollowing  = Self.robustInt(user["following_count"])
                let visitedHeaderMediaCount = Self.robustInt(user["media_count"])

                let visitedHeaderWorthEmitting = !visitedHeaderUsername.isEmpty
                    && (!visitedHeaderPic.isEmpty || visitedHeaderFollowers > 0 || visitedHeaderFollowing > 0 || visitedHeaderMediaCount > 0)

                if visitedHeaderWorthEmitting {
                    let visitedSnapshot = InstagramProfile(
                        userId: extractedUserId,
                        username: visitedHeaderUsername,
                        fullName: user["full_name"] as? String ?? "",
                        biography: user["biography"] as? String ?? "",
                        externalUrl: user["external_url"] as? String,
                        profilePicURL: visitedHeaderPic,
                        isVerified: user["is_verified"] as? Bool ?? false,
                        isPrivate: user["is_private"] as? Bool ?? isPrivate,
                        followerCount: visitedHeaderFollowers,
                        followingCount: visitedHeaderFollowing,
                        mediaCount: visitedHeaderMediaCount,
                        followedBy: [],
                        isFollowing: isFollowing,
                        isFollowRequested: isFollowRequested,
                        cachedAt: Date(),
                        cachedMediaURLs: [],
                        cachedReelURLs: [],
                        cachedTaggedURLs: [],
                        cachedHighlights: [],
                        cachedReelItems: [],
                        cachedNextMaxId: nil
                    )
                    let snapshotUid = extractedUserId
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .visitedProfileHeaderReady,
                            object: nil,
                            userInfo: [
                                "userId": snapshotUid,
                                "snapshot": visitedSnapshot
                            ]
                        )
                    }
                    print("⚡ [PROFILE] Visited header broadcast — @\(visitedHeaderUsername) followers:\(visitedHeaderFollowers)")
                    LogManager.shared.info("Visited profile header broadcast — UI can present before posts/followers (uid:\(snapshotUid))", category: .profile)
                }

                // Step 2 — pacing pause before the posts call (anti-bot, kept identical).
                try? await Task.sleep(nanoseconds: UInt64.random(in: 900_000_000...1_300_000_000))

                let (mediaItems, visitedNextId) = try await getUserMediaItems(userId: uid, amount: 21)
                mediaURLs = mediaItems.map { $0.imageURL }
                initialMediaItems = mediaItems
                initialNextMaxId = visitedNextId

                if !mediaItems.isEmpty {
                    let snapshotItems = mediaItems
                    let snapshotCursor = visitedNextId
                    let snapshotUid = extractedUserId
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .visitedProfileMediaReady,
                            object: nil,
                            userInfo: [
                                "userId": snapshotUid,
                                "mediaItems": snapshotItems,
                                "nextMaxId": snapshotCursor as Any
                            ]
                        )
                    }
                    print("⚡ [PROFILE] Visited posts broadcast (\(mediaItems.count) items) for uid:\(extractedUserId)")
                }

                // Second pause between media fetch and followers fetch (anti-bot, kept identical).
                try? await Task.sleep(nanoseconds: UInt64.random(in: 800_000_000...1_200_000_000))

                do { followedBy = try await getFollowedByUsers(userId: uid, count: 6) }
                catch { print("⚠️ [PROFILE] Followed-by fetch failed (non-critical): \(error)") }

                if !followedBy.isEmpty {
                    let snapshot = followedBy
                    let snapshotUid = extractedUserId
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .visitedProfileFollowedByReady,
                            object: nil,
                            userInfo: [
                                "userId": snapshotUid,
                                "followedBy": snapshot
                            ]
                        )
                    }
                    print("⚡ [PROFILE] Visited followedBy broadcast (\(snapshot.count)) for uid:\(extractedUserId)")
                }
            }

            print("📊 [PROFILE] Posts: \(mediaURLs.count), Reels: \(reelURLs.count), Tagged: \(taggedURLs.count), Highlights: \(highlights.count)")
            let cursorStatus = initialNextMaxId != nil ? "saved" : "none"
            LogManager.shared.info("Profile media loaded — posts:\(mediaURLs.count) reels:\(reelURLs.count) tagged:\(taggedURLs.count) highlights:\(highlights.count) cursor:\(cursorStatus)", category: .profile)
        } else {
            print("⚠️ [PROFILE] Skipping data fetch (private profile, not following)")
            LogManager.shared.warning("Profile protected data skipped — private:\(isPrivate) following:\(isFollowing) requested:\(isFollowRequested)", category: .profile)
        }

        // Some accounts/API buckets return a partial /users/{id}/info payload for the
        // logged-in user while /feed/user still works. In that case the grid has posts
        // but the header loses name, counters, or profile photo. Merge only missing
        // fields from the lightweight current_user endpoint.
        if isOwnProfile {
            let headerLooksIncomplete =
                (user["username"] as? String ?? "").isEmpty ||
                (user["full_name"] as? String ?? "").isEmpty ||
                (user["profile_pic_url"] as? String ?? "").isEmpty ||
                user["follower_count"] == nil ||
                user["following_count"] == nil ||
                user["media_count"] == nil

            if headerLooksIncomplete {
                print("⚠️ [PROFILE] Header fields incomplete — merging /accounts/current_user fallback")
                let missing = [
                    (user["username"] as? String ?? "").isEmpty ? "username" : nil,
                    (user["full_name"] as? String ?? "").isEmpty ? "full_name" : nil,
                    (user["profile_pic_url"] as? String ?? "").isEmpty ? "profile_pic_url" : nil,
                    user["follower_count"] == nil ? "follower_count" : nil,
                    user["following_count"] == nil ? "following_count" : nil,
                    user["media_count"] == nil ? "media_count" : nil
                ].compactMap { $0 }.joined(separator: ",")
                LogManager.shared.warning("Profile header incomplete — missing: \(missing). Trying current_user fallback", category: .profile)
                do {
                    let currentData = try await apiRequest(method: "GET", path: "/accounts/current_user/?edit=true")
                    if let currentJSON = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any],
                       let currentUser = currentJSON["user"] as? [String: Any] {
                        for (key, value) in currentUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) {
                            user[key] = value
                        }
                        print("✅ [PROFILE] Fallback merged. Keys now: \(user.keys.sorted().joined(separator: ", "))")
                        LogManager.shared.success("Profile current_user fallback merged — keys:\(currentUser.keys.sorted().joined(separator: ","))", category: .profile)
                        extractedUserId = extractProfileUserId(from: user)
                        if extractedUserId != "0" {
                            LogManager.shared.info("Profile userId recovered after fallback: \(extractedUserId)", category: .profile)
                        }
                    } else {
                        LogManager.shared.warning("Profile current_user fallback returned unexpected structure", category: .profile)
                    }
                } catch {
                    print("⚠️ [PROFILE] current_user fallback failed: \(error.localizedDescription)")
                    LogManager.shared.warning("Profile current_user fallback failed: \(error.localizedDescription)", category: .profile)
                }
            }
        }

        let fallbackUsername = [
            user["username"] as? String,
            usernameHint
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

        if isOwnProfile,
           (user["follower_count"] == nil || user["following_count"] == nil),
           let username = fallbackUsername {
            LogManager.shared.warning("Profile counts missing after current_user fallback — trying web_profile_info for @\(username)", category: .profile)
            if let webUser = await fetchWebProfileInfoFallback(username: username) {
                for (key, value) in webUser where user[key] == nil || Self.robustInt(user[key]) == 0 {
                    user[key] = value
                }
                extractedUserId = extractProfileUserId(from: user)
                LogManager.shared.success("Profile web fallback merged — followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"])) posts:\(Self.robustInt(user["media_count"]))", category: .profile)
            }
        }

        if !isOwnProfile {
            let headerLooksIncomplete =
                (user["username"] as? String ?? "").isEmpty ||
                (user["profile_pic_url"] as? String ?? "").isEmpty ||
                user["follower_count"] == nil ||
                user["following_count"] == nil ||
                extractedUserId == "0"

            if headerLooksIncomplete, let username = fallbackUsername {
                LogManager.shared.warning("Searched profile header incomplete — trying web_profile_info for @\(username)", category: .profile)
                if let webUser = await fetchWebProfileInfoFallback(username: username) {
                    for (key, value) in webUser where user[key] == nil || ((user[key] as? String)?.isEmpty == true) || Self.robustInt(user[key]) == 0 {
                        user[key] = value
                    }
                    extractedUserId = extractProfileUserId(from: user)
                    LogManager.shared.success("Searched profile web fallback merged — @\(user["username"] as? String ?? username) followers:\(Self.robustInt(user["follower_count"])) following:\(Self.robustInt(user["following_count"])) posts:\(Self.robustInt(user["media_count"]))", category: .profile)
                } else {
                    LogManager.shared.warning("Searched profile web fallback unavailable for @\(username)", category: .profile)
                }
            }

            if (user["username"] as? String ?? "").isEmpty, let username = fallbackUsername {
                user["username"] = username
            }
            if (user["full_name"] as? String ?? "").isEmpty, let fullName = fullNameHint, !fullName.isEmpty {
                user["full_name"] = fullName
            }
            if (user["profile_pic_url"] as? String ?? "").isEmpty, let picURL = profilePicURLHint, !picURL.isEmpty {
                user["profile_pic_url"] = picURL
            }
            if user["is_verified"] == nil, let isVerified = isVerifiedHint {
                user["is_verified"] = isVerified
            }
            if extractedUserId == "0" {
                extractedUserId = uid
                LogManager.shared.info("Searched profile userId recovered from requested uid: \(uid)", category: .profile)
            }
        }

        if let username = fallbackUsername,
           !username.isEmpty,
           (user["follower_count"] != nil || user["following_count"] != nil) {
            let apiFollowers = Self.robustInt(user["follower_count"])
            let apiFollowing = Self.robustInt(user["following_count"])

            // ANTI-BOT: Skip the secondary web_profile_info reconciliation when
            // the API counts already look plausible (both non-zero) and there is
            // a burst or heavy operation in flight. Each call adds an extra HTTP
            // request to the public web endpoint that compounds with the API
            // burst Instagram fingerprints.
            let countsPlausible = apiFollowers > 0 && apiFollowing > 0
            let shouldSkipReconciliation = countsPlausible &&
                (isHeavyOperationActive || hasRecentApiBurst(threshold: 3, seconds: 8))

            if shouldSkipReconciliation {
                LogManager.shared.info(
                    "Profile count reconciliation skipped @\(username) — counts plausible, heavy op or burst active",
                    category: .profile
                )
            } else if let webUser = await fetchWebProfileInfoFallback(username: username) {
                let webFollowers = Self.robustInt(webUser["follower_count"])
                let webFollowing = Self.robustInt(webUser["following_count"])

                LogManager.shared.info(
                    "Profile count sources @\(username) — users/info followers:\(apiFollowers) following:\(apiFollowing) | web followers:\(webFollowers) following:\(webFollowing)",
                    category: .profile
                )

                if shouldPreferWebCount(api: apiFollowers, web: webFollowers) {
                    user["follower_count"] = webFollowers
                    LogManager.shared.warning("Profile follower count corrected from web_profile_info for @\(username): \(apiFollowers) → \(webFollowers)", category: .profile)
                }
                if shouldPreferWebCount(api: apiFollowing, web: webFollowing) {
                    user["following_count"] = webFollowing
                    LogManager.shared.warning("Profile following count corrected from web_profile_info for @\(username): \(apiFollowing) → \(webFollowing)", category: .profile)
                }
            }
        }

        // Robust profile pic: try HD version first, then standard field
        let profilePicURL: String = {
            if let hdInfo = user["hd_profile_pic_url_info"] as? [String: Any],
               let hdUrl = hdInfo["url"] as? String, !hdUrl.isEmpty {
                return hdUrl
            }
            if let hdVersions = user["hd_profile_pic_versions"] as? [[String: Any]],
               let best = hdVersions.last, let url = best["url"] as? String, !url.isEmpty {
                return url
            }
            return user["profile_pic_url"] as? String ?? ""
        }()

        let followerCount  = Self.robustInt(user["follower_count"])
        let followingCount = Self.robustInt(user["following_count"])
        let parsedMediaCount = Self.robustInt(user["media_count"])
        let mediaCount = parsedMediaCount > 0 ? parsedMediaCount : mediaURLs.count
        print("📊 [PROFILE] Parsed counts — followers: \(followerCount), following: \(followingCount), media: \(mediaCount)")
        print("📊 [PROFILE] Profile pic URL resolved: \(profilePicURL.isEmpty ? "EMPTY" : String(profilePicURL.prefix(80)))")
        LogManager.shared.info("Profile header parsed — user:@\(user["username"] as? String ?? "") name:\((user["full_name"] as? String ?? "").isEmpty ? "EMPTY" : "OK") posts:\(mediaCount) followers:\(followerCount) following:\(followingCount) pic:\(profilePicURL.isEmpty ? "EMPTY" : "OK")", category: .profile)

        if isOwnProfile {
            let headerInvalid = extractedUserId == "0"
                || ((user["username"] as? String ?? "").isEmpty
                    && profilePicURL.isEmpty
                    && followerCount == 0
                    && followingCount == 0)
            if headerInvalid {
                print("🛡️ [PROFILE] Own profile header invalid — refusing to build cache entry")
                LogManager.shared.warning("getProfileInfo refused invalid own-profile header (userId=\(extractedUserId), media=\(mediaURLs.count))", category: .profile)
                return nil
            }
        }

        var profile = InstagramProfile(
            userId: extractedUserId,
            username: user["username"] as? String ?? "",
            fullName: user["full_name"] as? String ?? "",
            biography: user["biography"] as? String ?? "",
            externalUrl: user["external_url"] as? String,
            profilePicURL: profilePicURL,
            isVerified: user["is_verified"] as? Bool ?? false,
            isPrivate: user["is_private"] as? Bool ?? false,
            followerCount: followerCount,
            followingCount: followingCount,
            mediaCount: mediaCount,
            followedBy: followedBy,
            isFollowing: isFollowing,
            isFollowRequested: isFollowRequested,
            cachedAt: Date(),
            cachedMediaURLs: mediaURLs,
            cachedReelURLs: reelURLs,
            cachedTaggedURLs: taggedURLs,
            cachedHighlights: highlights,
            cachedReelItems: reelItems,
            cachedNextMaxId: initialNextMaxId
        )
        profile.cachedMediaItems = initialMediaItems

        print("✅ [PROFILE] Profile loaded for @\(profile.username)")
        print("📊 [PROFILE] Profile pic URL: \(profile.profilePicURL.isEmpty ? "EMPTY" : String(profile.profilePicURL.prefix(80)))")
        LogManager.shared.success("Profile loaded — @\(profile.username.isEmpty ? "EMPTY" : profile.username) mediaURLs:\(profile.cachedMediaURLs.count) pic:\(profile.profilePicURL.isEmpty ? "EMPTY" : "OK")", category: .profile)
        return profile
    }
    
    // MARK: - Get Followed By Users
    
    func getFollowedByUsers(userId: String, count: Int) async throws -> [InstagramFollower] {
        print("👥 [FOLLOWERS] Fetching \(count) followers for user ID: \(userId)")
        // Cold-start safety net: even if some unknown code path tries to fetch
        // followers automatically during the first 45s of the app, skip here.
        // This prevents the 3rd endpoint of the warmup pattern from firing.
        // Degrade silently (return empty array) so callers like getProfileInfo
        // can finish without surfacing a connection error to the user.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            print("⏳ [COLD-START] getFollowedByUsers blocked — \(remaining)s remaining")
            LogManager.shared.warning("[COLD-START] getFollowedByUsers blocked for user \(userId) — \(remaining)s", category: .general)
            return []
        }

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
            
            var follower = InstagramFollower(
                userId: userId,
                username: username,
                fullName: fullName,
                profilePicURL: profilePicURL
            )
            follower.isPrivate = user["is_private"] as? Bool ?? false
            followers.append(follower)
        }
        
        print("✅ [FOLLOWERS] Processed \(followers.count) followers")
        return followers
    }
    
    // MARK: - Get User Reels
    
    /// Fetches up to `maxTotal` reels for a user, paginating internally (max 2 pages)
    /// if the first response has `more_available`. Callers get a flat list.
    func getUserReels(userId: String? = nil, amount: Int = 50, maxTotal: Int = 50) async throws -> [InstagramMediaItem] {
        let uid = userId ?? session.userId
        print("🎬 [REELS] Fetching reels for user ID: \(uid)")

        var allItems: [InstagramMediaItem] = []
        var pagingMaxId: String? = nil
        var page = 0
        let maxPages = 2   // never more than 2 API calls for reels

        repeat {
            var body: [String: String] = [
                "target_user_id": uid,
                "page_size": String(amount),
                "include_feed_video": "true"
            ]
            if let cursor = pagingMaxId { body["max_id"] = cursor }

            let data = try await apiRequest(method: "POST", path: "/clips/user/", body: body)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [REELS] Failed to parse reels response")
                break
            }

            if page == 0 {
                print("🎬 [REELS] Top-level keys: \(json.keys.sorted().joined(separator: ", "))")
            }

            // Parse items — API wraps under "items" or "clips_items", each may have nested "media"
            let rawList: [[String: Any]]
            if let items = json["items"] as? [[String: Any]] {
                rawList = items
            } else if let items = json["clips_items"] as? [[String: Any]] {
                rawList = items
            } else {
                print("⚠️ [REELS] No items key found page \(page)")
                break
            }

            print("🎬 [REELS] Page \(page): \(rawList.count) items from API")
            for item in rawList {
                let media = item["media"] as? [String: Any] ?? item
                guard let mediaItem = parseMediaItem(media) else { continue }
                allItems.append(mediaItem)
            }

            // Resolve pagination cursor from paging_info or top-level next_max_id
            let pagingInfo = json["paging_info"] as? [String: Any]
            let moreAvailable = pagingInfo?["more_available"] as? Bool
                             ?? (json["more_available"] as? Bool)
                             ?? false
            let nextCursor = pagingInfo?["max_id"] as? String
                          ?? json["next_max_id"] as? String

            if moreAvailable, let cursor = nextCursor, cursor != pagingMaxId {
                pagingMaxId = cursor
            } else {
                pagingMaxId = nil   // stop pagination
            }

            page += 1

            // Human delay before fetching page 2+
            if pagingMaxId != nil && allItems.count < maxTotal {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...5_000_000_000))
            }

        } while pagingMaxId != nil && allItems.count < maxTotal && page < maxPages

        let result = Array(allItems.prefix(maxTotal))
        print("🎬 [REELS] Total parsed: \(result.count) reels (\(page) page(s))")
        return result
    }
    
    // MARK: - Get User Tagged Posts
    
    /// Fetches up to `maxTotal` tagged posts, paginating internally (max 2 pages)
    /// if the first response has `more_available`. Callers get a flat list.
    func getUserTagged(userId: String? = nil, amount: Int = 50, maxTotal: Int = 50) async throws -> [InstagramMediaItem] {
        let uid = userId ?? session.userId
        print("🏷️ [TAGGED] Fetching tagged posts for user ID: \(uid)")

        var allItems: [InstagramMediaItem] = []
        var nextMaxId: String? = nil
        var page = 0
        let maxPages = 2

        repeat {
            var path = "/usertags/\(uid)/feed/?count=\(amount)"
            if let cursor = nextMaxId { path += "&max_id=\(cursor)" }

            let data = try await apiRequest(method: "GET", path: path)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [TAGGED] Failed to parse tagged response")
                break
            }

            if page == 0 {
                print("🏷️ [TAGGED] Top-level keys: \(json.keys.sorted().joined(separator: ", "))")
            }

            guard let taggedItems = json["items"] as? [[String: Any]] else {
                print("⚠️ [TAGGED] No 'items' key found page \(page)")
                break
            }

            print("🏷️ [TAGGED] Page \(page): \(taggedItems.count) items from API")
            for item in taggedItems {
                guard let mediaItem = parseMediaItem(item) else { continue }
                allItems.append(mediaItem)
            }

            let moreAvailable = json["more_available"] as? Bool ?? false
            let cursor = json["next_max_id"] as? String

            if moreAvailable, let c = cursor, c != nextMaxId {
                nextMaxId = c
            } else {
                nextMaxId = nil
            }

            page += 1

            if nextMaxId != nil && allItems.count < maxTotal {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...5_000_000_000))
            }

        } while nextMaxId != nil && allItems.count < maxTotal && page < maxPages

        let result = Array(allItems.prefix(maxTotal))
        print("🏷️ [TAGGED] Total parsed: \(result.count) tagged posts (\(page) page(s))")
        return result
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
        
        // For videos/reels, also get video URL and aspect ratio
        var videoURL: String? = nil
        var videoAspectRatio: CGFloat? = nil
        if mediaType == 2 {
            if let videoVersions = media["video_versions"] as? [[String: Any]],
               let first = videoVersions.first,
               let url = first["url"] as? String {
                videoURL = url
            }
            // Derive aspect ratio from original dimensions (Instagram returns these at media root)
            if let w = media["original_width"] as? Int,
               let h = media["original_height"] as? Int, h > 0 {
                videoAspectRatio = CGFloat(w) / CGFloat(h)
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
        let carouselURLs = extractCarouselImageURLs(from: media, fallbackCoverURL: imageURL)
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
            carouselImageURLs: carouselURLs,
            ownerUsername: ownerUsername,
            videoAspectRatio: videoAspectRatio
        )
    }

    private func extractCarouselImageURLs(from media: [String: Any], fallbackCoverURL: String) -> [String] {
        guard let children = media["carousel_media"] as? [[String: Any]], !children.isEmpty else {
            return []
        }

        var urls: [String] = []
        for child in children {
            if let imageVersions = child["image_versions2"] as? [String: Any],
               let candidates = imageVersions["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let url = first["url"] as? String,
               !url.isEmpty {
                urls.append(url)
            }
        }

        if urls.isEmpty, !fallbackCoverURL.isEmpty {
            urls.append(fallbackCoverURL)
        }

        return Array(urls.prefix(10))
    }
    
    // MARK: - Get User Media Items (Extended with metadata)
    
    func getUserMediaItems(userId: String? = nil, amount: Int = 18, maxId: String? = nil) async throws -> ([InstagramMediaItem], String?) {
        let uid = userId ?? session.userId
        print("📷 [MEDIA] Fetching \(amount) media items for user ID: \(uid), maxId: \(maxId ?? "none")")
        
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "count", value: String(amount))]
        if let maxId = maxId, !maxId.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "max_id", value: maxId))
        }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let path = "/feed/user/\(uid)/\(query)"
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
            let carouselURLs = extractCarouselImageURLs(from: item, fallbackCoverURL: imageUrl)
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
                carouselImageURLs: carouselURLs
            )
            mediaItems.append(mediaItem)
        }
        
        // Get next_max_id for pagination. Instagram may return this as String or NSNumber.
        let nextMaxId: String?
        if let s = json["next_max_id"] as? String, !s.isEmpty {
            nextMaxId = s
        } else if let n = json["next_max_id"] as? NSNumber {
            nextMaxId = n.stringValue
        } else {
            nextMaxId = nil
        }
        
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
            let carouselURLs = extractCarouselImageURLs(from: item, fallbackCoverURL: imageUrl)
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
                carouselImageURLs: carouselURLs,
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

        try await waitForUploadSafetyWindow(label: photoDesc)
        
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
        guard let profile = try await getProfileInfo(
            userId: exactMatch.userId,
            usernameHint: exactMatch.username,
            fullNameHint: exactMatch.fullName,
            profilePicURLHint: exactMatch.profilePicURL,
            isVerifiedHint: exactMatch.isVerified
        ) else {
            print("❌ [SEARCH] Failed to load profile for user ID: \(exactMatch.userId)")
            throw InstagramError.apiError("Error al cargar el perfil")
        }

        let headerIsEmpty = profile.username.isEmpty ||
            profile.userId == "0" ||
            profile.profilePicURL.isEmpty ||
            profile.followerCount == 0 && profile.followingCount == 0

        guard headerIsEmpty else { return profile }

        LogManager.shared.warning("Search profile header empty for @\(exactMatch.username) — rebuilding from search/web fallback", category: .profile)

        let webUser = await fetchWebProfileInfoFallback(username: exactMatch.username)
        let webUsername = webUser?["username"] as? String
        let webFullName = webUser?["full_name"] as? String
        let webPicURL = webUser?["profile_pic_url"] as? String
        let webUserId = extractProfileUserId(from: webUser ?? [:])

        let rebuilt = InstagramProfile(
            userId: webUserId != "0" ? webUserId : exactMatch.userId,
            username: !(webUsername ?? "").isEmpty ? webUsername! : exactMatch.username,
            fullName: !(webFullName ?? "").isEmpty ? webFullName! : exactMatch.fullName,
            biography: webUser?["biography"] as? String ?? profile.biography,
            externalUrl: webUser?["external_url"] as? String ?? profile.externalUrl,
            profilePicURL: !(webPicURL ?? "").isEmpty ? webPicURL! : exactMatch.profilePicURL,
            isVerified: webUser?["is_verified"] as? Bool ?? exactMatch.isVerified,
            isPrivate: webUser?["is_private"] as? Bool ?? profile.isPrivate,
            followerCount: Self.robustInt(webUser?["follower_count"]),
            followingCount: Self.robustInt(webUser?["following_count"]),
            mediaCount: max(Self.robustInt(webUser?["media_count"]), profile.mediaCount, profile.cachedMediaURLs.count),
            followedBy: profile.followedBy,
            isFollowing: profile.isFollowing,
            isFollowRequested: profile.isFollowRequested,
            cachedAt: Date(),
            cachedMediaURLs: profile.cachedMediaURLs,
            cachedReelURLs: profile.cachedReelURLs,
            cachedTaggedURLs: profile.cachedTaggedURLs,
            cachedHighlights: profile.cachedHighlights,
            cachedMediaItems: profile.cachedMediaItems,
            cachedReelItems: profile.cachedReelItems,
            cachedNextMaxId: profile.cachedNextMaxId
        )

        LogManager.shared.success("Search profile rebuilt — @\(rebuilt.username) id:\(rebuilt.userId) followers:\(rebuilt.followerCount) following:\(rebuilt.followingCount) pic:\(rebuilt.profilePicURL.isEmpty ? "EMPTY" : "OK")", category: .profile)
        return rebuilt
    }
    
    // MARK: - Amnesia Carousel (sidecar upload)

    /// Step 1 of carousel upload: upload a single image for use in a sidecar/carousel post.
    /// Unlike uploadPhoto(), this does NOT call /media/configure/ — it only pushes the bytes
    /// and returns the raw upload_id, which will later be collected into configure_sidecar().
    ///
    /// - Parameters:
    ///   - imageData: JPEG data of the image.
    ///   - stepLabel: Human-readable label used in logs (e.g. "A-1/4").
    /// - Returns: The upload_id string needed by configure_sidecar.
    func uploadPhotoForSidecar(imageData: Data, stepLabel: String = "", clientSidecarId: String) async throws -> String {
        guard !isLocked else { throw InstagramError.apiError("Lockdown activo. Espera antes de subir.") }

        let label = stepLabel.isEmpty ? "sidecar" : stepLabel
        print("📤 [AMNESIA] Uploading \(label) (\(imageData.count / 1024) KB)…")

        let timestampMs  = Int(Date().timeIntervalSince1970 * 1000) + Int.random(in: -300...300)
        let uploadId     = String(timestampMs)
        let uploadName   = "\(uploadId)_0_\(Int.random(in: 1_000_000_000...9_999_999_999))"
        let waterfallId  = UUID().uuidString

        // Album uploads only mark each photo as sidecar. The final carousel id is
        // generated later in configure_sidecar; it is not sent in rupload params.
        var ruploadParams: [String: Any] = [
            "retry_context":      "{\"num_step_auto_retry\":0,\"num_reupload\":0,\"num_step_manual_retry\":0}",
            "media_type":         "1",
            "xsharing_user_ids":  "[]",
            "upload_id":          uploadId,
            "is_sidecar":         "1",
            "image_compression":  "{\"lib_name\":\"moz\",\"lib_version\":\"3.1.m\",\"quality\":\"80\"}"
        ]
        _ = clientSidecarId
        guard let paramsData   = try? JSONSerialization.data(withJSONObject: ruploadParams),
              let paramsString = String(data: paramsData, encoding: .utf8),
              let uploadURL    = URL(string: "https://i.instagram.com/rupload_igphoto/\(uploadName)")
        else { throw InstagramError.uploadFailed }

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        let base = buildHeaders()
        for (k, v) in base where k != "Content-Type" { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(String(imageData.count),     forHTTPHeaderField: "Content-Length")
        req.setValue(paramsString,                forHTTPHeaderField: "X-Instagram-Rupload-Params")
        req.setValue(waterfallId,                 forHTTPHeaderField: "X_FB_PHOTO_WATERFALL_ID")
        req.setValue("image/jpeg",                forHTTPHeaderField: "X-Entity-Type")
        req.setValue(uploadName,                  forHTTPHeaderField: "X-Entity-Name")
        req.setValue(String(imageData.count),     forHTTPHeaderField: "X-Entity-Length")
        req.setValue("0",                         forHTTPHeaderField: "Offset")
        req.httpBody = imageData

        try await InstagramSafetyGate.shared.waitForApiSlot(method: "POST", path: "/rupload_igphoto/")
        InstagramSafetyGate.shared.recordApiRequest(method: "POST", path: "/rupload_igphoto/")
        let (data, response) = try await postSession.data(for: req)
        if let http = response as? HTTPURLResponse {
            print("   [AMNESIA] Upload HTTP \(http.statusCode) for \(label)")
            // Capture fresh www-claim from upload response so configure_sidecar uses latest token
            if let claim = (http.allHeaderFields as? [String: String])?
                .first(where: { $0.key.lowercased() == "x-ig-set-www-claim" })?.value {
                await MainActor.run {
                    self.wwwClaim = claim
                    UserDefaults.standard.set(claim, forKey: "ig_www_claim")
                }
                print("   [AMNESIA] Updated wwwClaim from upload response (\(label))")
            }
            if let raw = String(data: data, encoding: .utf8) {
                print("   [AMNESIA] Upload response for \(label): \(raw.prefix(300))")
            }
            guard http.statusCode == 200 else {
                throw InstagramError.apiError("Upload HTTP \(http.statusCode) for \(label)")
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let returnedId = json["upload_id"] as? String ?? (json["upload_id"] as? Int).map(String.init)
        else {
            let raw = String(data: data, encoding: .utf8) ?? "?"
            print("   [AMNESIA] Unexpected upload response for \(label): \(raw.prefix(200))")
            // Instagram sometimes returns the upload_id we sent — fall back to it
            return uploadId
        }
        print("✅ [AMNESIA] Upload OK \(label) → upload_id=\(returnedId)")
        return returnedId
    }

    /// Step 2 of carousel upload: call configure_sidecar to create the final carousel post
    /// from the previously uploaded images.
    ///
    /// - Parameters:
    ///   - uploadIds: Array of upload_ids returned by uploadPhotoForSidecar(), in display order.
    ///   - caption:   Post caption (default empty).
    /// - Returns: The media_id of the newly created carousel post.
    func configureSidecar(uploadIds: [String], caption: String = "", clientSidecarId: String) async throws -> String {
        guard !uploadIds.isEmpty else { throw InstagramError.apiError("No upload IDs provided") }
        print("📋 [AMNESIA] configure_sidecar with \(uploadIds.count) images (sidecarId=\(clientSidecarId))…")

        let tzOffset = String(TimeZone.current.secondsFromGMT())
        let devicePayload: [String: Any] = [
            "device_id": deviceId,
            "uuid": clientUUID,
            "phone_id": clientUUID,
            "manufacturer": "Apple",
            "model": DeviceInfo.shared.modelName
        ]
        let editsString = "{\"crop_original_size\":[864.0,1080.0],\"crop_center\":[0.0,0.0],\"crop_zoom\":1.0}"
        let extraString = "{\"source_width\":864,\"source_height\":1080}"

        // Match instagrapi's album children: include edits/extra/dimensions metadata.
        let children: [[String: Any]] = uploadIds.map { id in
            [
                "upload_id":          id,
                "source_type":        "4",
                "timezone_offset":    tzOffset,
                "device":             devicePayload,
                "edits":              editsString,
                "extra":              extraString,
                "scene_capture_type": "",
                "scene_type":         NSNull()
            ] as [String: Any]
        }
        guard let childrenData   = try? JSONSerialization.data(withJSONObject: children),
              let childrenString = String(data: childrenData, encoding: .utf8)
        else { throw InstagramError.apiError("Failed to serialise children_metadata") }

        // instagrapi generates a fresh carousel upload_id at configure time.
        let carouselUploadId = String(Int(Date().timeIntervalSince1970 * 1000))

        let bodyDict: [String: Any] = [
            "_csrftoken": session.csrfToken,
            "_uid": session.userId,
            "_uuid": clientUUID,
            "timezone_offset": tzOffset,
            "caption": caption,
            "client_sidecar_id": carouselUploadId,
            "upload_id": carouselUploadId,
            "source_type": "4",
            "creation_logger_session_id": pigeonSessionId,
            "suggested_venue_position": -1,
            "is_suggested_venue": false,
            "device": devicePayload,
            "children_metadata": children
        ]
        guard let bodyJSONData = try? JSONSerialization.data(withJSONObject: bodyDict),
              let bodyJSONString = String(data: bodyJSONData, encoding: .utf8) else {
            throw InstagramError.apiError("Failed to serialise signed configure_sidecar body")
        }
        let signature = generateSignature(data: bodyJSONString)
        let rawBodyString = "signed_body=\(signature).\(bodyJSONString)&ig_sig_key_version=\(sigKeyVersion)"
        print("📋 [AMNESIA] Using carousel upload_id=\(carouselUploadId) (fresh configure id)")

        print("📋 [AMNESIA] configure_sidecar children_metadata: \(childrenString.prefix(200))")
        print("📋 [AMNESIA] configure_sidecar signed JSON: \(bodyJSONString.prefix(800))")
        print("📋 [AMNESIA] configure_sidecar signed body prefix: \(rawBodyString.prefix(300))")

        // Warm-up GET to refresh the www-claim token immediately before posting.
        // configure_sidecar is strict about having a fresh, valid X-IG-WWW-Claim.
        print("📋 [AMNESIA] Warming up session before configure_sidecar…")
        if let warmUrl = URL(string: "https://i.instagram.com/api/v1/accounts/current_user/?edit=true") {
            var warmReq = URLRequest(url: warmUrl)
            warmReq.httpMethod = "GET"
            warmReq.timeoutInterval = 10
            let warmHeaders = buildHeaders()
            for (k, v) in warmHeaders { warmReq.setValue(v, forHTTPHeaderField: k) }
            do {
                try await InstagramSafetyGate.shared.waitForApiSlot(method: "GET", path: "/accounts/current_user/")
                if let (_, warmResp) = try? await getSession.data(for: warmReq),
                   let warmHttp = warmResp as? HTTPURLResponse,
                   let hdrs = warmHttp.allHeaderFields as? [String: String],
                   let claim = hdrs.first(where: { $0.key.lowercased() == "x-ig-set-www-claim" })?.value {
                    await MainActor.run {
                        self.wwwClaim = claim
                        UserDefaults.standard.set(claim, forKey: "ig_www_claim")
                    }
                    print("📋 [AMNESIA] Fresh wwwClaim captured from warm-up GET")
                }
            } catch {
                LogManager.shared.warning("SAFETY BLOCK — configure_sidecar warm-up skipped: \(error.localizedDescription)", category: .api)
            }
        }

        var data: Data
        var lastError: Error?

        // Retry up to 2 times on HTTP 500 (Instagram transient server errors)
        for attempt in 1...3 {
            do {
                let configURL = URL(string: "https://i.instagram.com/api/v1/media/configure_sidecar/")!
                var configReq = URLRequest(url: configURL)
                configReq.httpMethod = "POST"
                configReq.timeoutInterval = 30
                let hdrs = buildHeaders()
                for (k, v) in hdrs { configReq.setValue(v, forHTTPHeaderField: k) }
                configReq.httpBody = rawBodyString.data(using: .utf8)
                configReq.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                print("📋 [AMNESIA] POSTing signed configure_sidecar to i.instagram.com (attempt \(attempt))…")
                try await InstagramSafetyGate.shared.waitForApiSlot(method: "POST", path: "/media/configure_sidecar/")
                InstagramSafetyGate.shared.recordApiRequest(method: "POST", path: "/media/configure_sidecar/")
                let (rawData, rawResp) = try await postSession.data(for: configReq)
                let httpResp = rawResp as? HTTPURLResponse
                let statusCode = httpResp?.statusCode ?? 0
                print("📋 [AMNESIA] configure_sidecar HTTP \(statusCode)")
                // Log ALL response headers for diagnosis
                if let hdrsResp = httpResp?.allHeaderFields as? [String: String] {
                    let interesting = hdrsResp.filter { k, _ in
                        let kl = k.lowercased()
                        return kl.hasPrefix("x-ig") || kl.hasPrefix("x-fb") || kl == "www-authenticate"
                            || kl == "content-type" || kl.hasPrefix("x-bloks") || kl == "location"
                    }
                    for (k, v) in interesting.sorted(by: { $0.key < $1.key }) {
                        print("   [AMNESIA] resp-header: \(k): \(v)")
                    }
                    // Always capture fresh www-claim (even from 500 responses)
                    if let claim = hdrsResp.first(where: { $0.key.lowercased() == "x-ig-set-www-claim" })?.value {
                        await MainActor.run {
                            self.wwwClaim = claim
                            UserDefaults.standard.set(claim, forKey: "ig_www_claim")
                        }
                        print("   [AMNESIA] Updated wwwClaim from configure_sidecar response")
                    }
                }
                if let raw = String(data: rawData, encoding: .utf8) {
                    print("   [AMNESIA] configure_sidecar response: \(raw.prefix(600))")
                }
                if statusCode == 500 {
                    throw InstagramError.apiError("HTTP 500: Unknown Server Error.")
                }
                data = rawData

                if let raw = String(data: data, encoding: .utf8) {
                    print("   [AMNESIA] configure_sidecar response (attempt \(attempt)): \(raw.prefix(300))")
                }

                guard let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let media = json["media"] as? [String: Any]
                else {
                    let raw = String(data: data, encoding: .utf8) ?? "?"
                    throw InstagramError.apiError("configure_sidecar: unexpected response — \(raw.prefix(200))")
                }

                let mediaId: String?
                if let s = media["pk"] as? String       { mediaId = s }
                else if let i = media["pk"] as? Int64   { mediaId = String(i) }
                else if let i = media["pk"] as? Int     { mediaId = String(i) }
                else                                     { mediaId = nil }

                guard let id = mediaId else {
                    throw InstagramError.apiError("configure_sidecar: no media pk in response")
                }
                print("✅ [AMNESIA] Carousel created — mediaId=\(id) (\(uploadIds.count) images)")
                return id
            } catch {
                lastError = error
                let desc = error.localizedDescription
                print("⚠️ [AMNESIA] configure_sidecar attempt \(attempt) failed: \(desc)")
                LogManager.shared.warning("configure_sidecar attempt \(attempt) failed: \(desc)", category: .api)
                if attempt < 3 {
                    let wait = UInt64.random(in: 5_000_000_000...10_000_000_000)
                    print("   [AMNESIA] Retrying in \(wait / 1_000_000_000)s…")
                    try? await Task.sleep(nanoseconds: wait)
                }
            }
        }
        throw lastError ?? InstagramError.apiError("configure_sidecar failed after 3 attempts")
    }

    /// Full Amnesia Carousel upload flow:
    /// Uploads two carousel posts (4-image and 5-image) and archives the 5-image one.
    ///
    /// Progress is reported via the `onProgress` closure:
    ///   - step 1-4:  uploading images for the short carousel (A)
    ///   - step 5:    configuring short carousel
    ///   - step 6-10: uploading images for the full carousel (B)
    ///   - step 11:   configuring full carousel
    ///   - step 12:   archiving full carousel
    ///
    /// On success sets `AmnesiaCarouselSettings.shared.shortCarouselMediaId` and `fullCarouselMediaId`.
    func uploadAmnesiaCarousels(
        images: [UIImage],           // must be exactly 5
        onProgress: @escaping (Int, Int) -> Void
    ) async throws {
        guard images.count == 5 else {
            throw InstagramError.apiError("Se necesitan exactamente 5 imágenes")
        }
        guard !isLocked else {
            throw InstagramError.apiError("Lockdown activo. Espera antes de subir.")
        }

        let total = 12  // 4 uploads + 1 configure + 5 uploads + 1 configure + 1 archive
        var step  = 0
        func advance() { step += 1; onProgress(step, total) }

        // Prepare all carousel images with the same exact aspect ratio.
        // Instagram carousels are strict: mixing 4:5 and 1:1 items can make
        // configure_sidecar fail with a generic HTTP 500.
        func jpeg(_ img: UIImage, index: Int) throws -> Data {
            let normalized = InstagramService.normalizeImageOrientation(img)
            print("📐 [AMNESIA] Image #\(index + 1) input: \(Int(normalized.size.width))x\(Int(normalized.size.height)) @\(normalized.scale)x")

            let targetSize = CGSize(width: 864, height: 1080) // exact 4:5 portrait
            let targetRatio = targetSize.width / targetSize.height
            let sourceRatio = normalized.size.width / normalized.size.height
            let cropSize: CGSize

            if sourceRatio > targetRatio {
                let cropWidth = normalized.size.height * targetRatio
                cropSize = CGSize(width: cropWidth, height: normalized.size.height)
            } else {
                let cropHeight = normalized.size.width / targetRatio
                cropSize = CGSize(width: normalized.size.width, height: cropHeight)
            }

            let cropOrigin = CGPoint(
                x: (normalized.size.width - cropSize.width) / 2,
                y: (normalized.size.height - cropSize.height) / 2
            )
            let drawScale = targetSize.width / cropSize.width
            let drawRect = CGRect(
                x: -cropOrigin.x * drawScale,
                y: -cropOrigin.y * drawScale,
                width: normalized.size.width * drawScale,
                height: normalized.size.height * drawScale
            )

            UIGraphicsBeginImageContextWithOptions(targetSize, true, 1.0)
            normalized.draw(in: drawRect)
            guard let preparedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                throw InstagramError.apiError("No se pudo preparar la imagen")
            }
            UIGraphicsEndImageContext()

            guard let finalData = preparedImage.jpegData(compressionQuality: 0.88) else {
                throw InstagramError.apiError("No se pudo comprimir la imagen")
            }

            print("📦 [AMNESIA] Image #\(index + 1) final: 864x1080 (4:5), \(finalData.count / 1024)KB")
            return finalData
        }

        // ── Carousel A (images 0-3, 4 images) — will be visible ─────────────────
        // Upload first image without a pre-set client_sidecar_id.
        // Its returned upload_id becomes the client_sidecar_id for all remaining uploads
        // and for configure_sidecar — this is the pattern used by instagrapi.
        print("🎭 [AMNESIA] Phase 1: uploading short carousel (4 images)…")
        var uploadIdsA: [String] = []
        for i in 0..<4 {
            let imgData = try jpeg(images[i], index: i)
            // For the first image, use its own upload_id as the sidecar ID.
            // For subsequent images, use the first image's upload_id.
            let sidecarId = uploadIdsA.first ?? ""
            let id = try await uploadPhotoForSidecar(imageData: imgData, stepLabel: "A-\(i+1)/4", clientSidecarId: sidecarId)
            uploadIdsA.append(id)
            advance()
            if i < 3 {
                let gap = UInt64.random(in: 2_000_000_000...4_000_000_000)
                try await Task.sleep(nanoseconds: gap)
            }
        }
        let sidecarIdA = uploadIdsA[0]
        print("🎭 [AMNESIA] Carousel A sidecarId (= first upload_id): \(sidecarIdA)")

        // Anti-bot: 4-7s before configure
        print("   [AMNESIA] Waiting before configure_sidecar A…")
        try await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000...7_000_000_000))
        let mediaIdA = try await configureSidecar(uploadIds: uploadIdsA, caption: "", clientSidecarId: sidecarIdA)
        advance()
        trackAction()

        // Anti-bot: 5-8s before starting carousel B
        try await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...8_000_000_000))

        // ── Carousel B (all 5 images) — will be archived immediately ────────────
        print("🎭 [AMNESIA] Phase 2: uploading full carousel (5 images)…")
        var uploadIdsB: [String] = []
        for i in 0..<5 {
            let imgData = try jpeg(images[i], index: i)
            let sidecarId = uploadIdsB.first ?? ""
            let id = try await uploadPhotoForSidecar(imageData: imgData, stepLabel: "B-\(i+1)/5", clientSidecarId: sidecarId)
            uploadIdsB.append(id)
            advance()
            if i < 4 {
                let gap = UInt64.random(in: 2_000_000_000...4_000_000_000)
                try await Task.sleep(nanoseconds: gap)
            }
        }
        let sidecarIdB = uploadIdsB[0]
        print("🎭 [AMNESIA] Carousel B sidecarId (= first upload_id): \(sidecarIdB)")

        // Anti-bot: 4-7s before configure
        print("   [AMNESIA] Waiting before configure_sidecar B…")
        try await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000...7_000_000_000))
        let mediaIdB = try await configureSidecar(uploadIds: uploadIdsB, caption: "", clientSidecarId: sidecarIdB)
        advance()
        trackAction()

        // Anti-bot: 5-9s before archiving carousel B
        try await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000_000...9_000_000_000))
        print("🎭 [AMNESIA] Archiving full carousel B (mediaId=\(mediaIdB))…")
        _ = try await archivePhoto(mediaId: mediaIdB, skipPreCheck: true)
        advance()

        // Persist both IDs
        await MainActor.run {
            AmnesiaCarouselSettings.shared.shortCarouselMediaId = mediaIdA
            AmnesiaCarouselSettings.shared.fullCarouselMediaId  = mediaIdB
            AmnesiaCarouselSettings.shared.isRevealed           = false
            AmnesiaCarouselSettings.shared.uploadState          = .ready
        }
        print("✅ [AMNESIA] Both carousels ready — A=\(mediaIdA) B=\(mediaIdB)")
        LogManager.shared.success("Amnesia Carousel preparado — A:\(mediaIdA) B:\(mediaIdB)", category: .upload)
    }

    /// Swaps the two Amnesia Carousel posts:
    ///   - If not yet revealed: archives short (A), unarchives full (B)  → spectator sees 5 images
    ///   - If already revealed: reverses the swap (reset for next performance)
    func swapAmnesiaCarousels(settings: AmnesiaCarouselSettings) async throws {
        guard let shortId = settings.shortCarouselMediaId,
              let fullId  = settings.fullCarouselMediaId
        else { throw InstagramError.apiError("Carruseles de Amnesia no preparados") }

        guard !isLocked else { throw InstagramError.apiError("Lockdown activo") }

        if !settings.isRevealed {
            // Reveal: archive short (4-img), unarchive full (5-img)
            print("🎭 [AMNESIA] Swap → REVEAL (archive A, unarchive B)…")
            LogManager.shared.info("Amnesia Carousel → Reveal iniciado", category: .api)
            _ = try await archivePhoto(mediaId: shortId, skipPreCheck: true)
            // Anti-bot: brief gap between the two operations
            try await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...5_000_000_000))
            _ = try await unarchivePhoto(mediaId: fullId, skipPreCheck: true)
            await MainActor.run { settings.isRevealed = true }
            print("✅ [AMNESIA] Reveal complete — spectator now sees 5 images")
            LogManager.shared.success("Amnesia Carousel revelado (5 imágenes visibles)", category: .api)
        } else {
            // Reset: archive full (5-img), unarchive short (4-img)
            print("🎭 [AMNESIA] Swap → RESET (archive B, unarchive A)…")
            LogManager.shared.info("Amnesia Carousel → Reset iniciado", category: .api)
            _ = try await archivePhoto(mediaId: fullId, skipPreCheck: true)
            try await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...5_000_000_000))
            _ = try await unarchivePhoto(mediaId: shortId, skipPreCheck: true)
            await MainActor.run { settings.isRevealed = false }
            print("✅ [AMNESIA] Reset complete — ready for next performance")
            LogManager.shared.success("Amnesia Carousel reseteado (4 imágenes visibles)", category: .api)
        }
    }

    // MARK: - Instagram Notes
    //
    // ── ENDPOINT HISTORY (update this when Instagram breaks Notes) ────────────────
    //
    // v1 (original)  — https://i.instagram.com/api/v1/notes/create_note/
    //   → worked initially.
    //
    // v2 (mid-2025)  — switched to https://www.instagram.com/api/v1/notes/create_note/
    //   → reason: i.instagram.com started returning CORS-style errors for Notes.
    //   → worked for a while.
    //
    // v3 (May-2026)  — rewrote Notes to use apiRequest() (same path as Bio/deleteNote).
    //   + wwwClaim now persisted to UserDefaults ("ig_www_claim") and restored on init.
    //   → root cause: manual request building called removeValue(forKey:"Cookie") to
    //     "let URLSession handle cookies". After a Keychain-restore restart,
    //     HTTPCookieStorage.shared is empty, so URLSession sent ZERO cookies → 403.
    //     buildCookieHeader() printed "Sending N cookies" before the removal, hiding
    //     the bug. Bio worked because apiRequest() never removes the Cookie header.
    //   → if Notes fails again: check [COOKIE] log line count and wwwClaim value.
    //     If cookies=0 or claim=0 something is stripping the Cookie header again.
    //   → if 403 persists with correct cookies: Instagram changed the endpoint.
    //     Check the Notes endpoint path and required headers in a fresh Instagram APK.
    //
    // v4 (May-2026)  — removed a premature InstagramSafetyGate.record(.note) before
    //   POST /notes/create_note/. apiRequest() already gates and records the action.
    //   The extra manual record made the create call block itself with "note too soon"
    //   right after the warm-up succeeded, then restarted the 150s timer on retry.
    //   Diagnostic signal: warm-up HTTP 200, then SAFETY BLOCK create_note note too soon.
    //
    // v5 (May-2026, late) — added a defensive GET /accounts/current_user/?edit=true
    //   pre-warm-up that ONLY runs when wwwClaim == "0". When a fresh install or wiped
    //   UserDefaults leaves the in-memory claim at "0", both the POST warm-up and the
    //   POST create_note silently fail with HTTP 200 + body status:fail because the
    //   Notes endpoint refuses claim=0. The POST warm-up cannot self-heal because IG
    //   does not return a Set-Claim header on a failed POST. A single GET to
    //   current_user always returns a fresh claim, which apiRequest() persists.
    //   Diagnostic signal: `[NOTE] wwwClaim=0` followed by `Warm-up status=fail`
    //   followed by `Raw response: ... "status":"fail" ... "We're sorry..."`.
    //
    // ── HOW TO DIAGNOSE IF NOTES BREAKS AGAIN ────────────────────────────────────
    //
    // 1. Check `[NOTE] wwwClaim=0` in logs:
    //    → If 0, the claim was never refreshed. Try a GET warm-up to /accounts/current_user/
    //      on the same base URL before the POST to get a fresh claim.
    //
    // 2. Check the HTTP status of the warm-up POST (update_notes_last_seen_timestamp):
    //    → 403 login_required → wrong domain; switch between i.* and www.*
    //    → 200 ok            → domain is correct, problem is elsewhere (headers, body params)
    //
    // 3. Check response body for clues:
    //    → "login_required" + logout_reason:2  → domain/cookie mismatch
    //    → "checkpoint_required"               → bot detection; add delay before retry
    //    → "media_id_not_found"                → note feature disabled for account temporarily
    //    → "Please wait a few minutes"         → rate limited; back off
    //
    // 4. Instagram sometimes requires `x-ig-app-id` header to be present; verify buildHeaders()
    //    includes it. Also check that `X-IG-WWW-Claim` is sent with a non-zero value.
    //
    // 5. Body param changes Instagram has made historically:
    //    → Added `note_style` (required, value "0")
    //    → Added `device_id` (required)
    //    → audience: 0=close friends+followers, 2=close friends only
    // ─────────────────────────────────────────────────────────────────────────────

    /// Diagnostic GET that dumps the full response (status, all headers, raw body) and
    /// attempts to capture a fresh X-IG-WWW-Claim. Used by Notes flow when the in-memory
    /// claim is "0" and we need maximum visibility into why a refresh GET keeps failing.
    /// Routes through the shared `getSession`/header builder to stay identical to
    /// normal traffic, but does NOT go through apiRequest() so we can log headers/body
    /// even when the safety gate would normally hide them.
    private func diagnosticGetForClaim(path: String, label: String) async {
        guard let url = URL(string: "\(baseURL)\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        for (k, v) in buildHeaders() { req.setValue(v, forHTTPHeaderField: k) }

        print("🔬 \(label) — sending GET \(path)")
        print("🔬 \(label) — outgoing X-IG-WWW-Claim header: \(req.value(forHTTPHeaderField: "X-IG-WWW-Claim") ?? "<missing>")")
        print("🔬 \(label) — outgoing Cookie length: \(req.value(forHTTPHeaderField: "Cookie")?.count ?? 0) chars")

        let start = CFAbsoluteTimeGetCurrent()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await getSession.data(for: req)
        } catch {
            print("🔬 \(label) — network error: \(error.localizedDescription)")
            return
        }
        let ms = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            print("🔬 \(label) — not an HTTPURLResponse")
            return
        }
        print("🔬 \(label) — HTTP \(http.statusCode) [\(ms)] body=\(data.count) bytes")

        // Dump ALL response headers — Instagram's actual claim header name has changed
        // historically (Set-WWW-Claim, ig-set-www-claim, ig-u-rur, …). Logging everything
        // means future breakage shows up immediately with the real header name.
        print("🔬 \(label) — response headers:")
        for (k, v) in http.allHeaderFields {
            if let key = k as? String, let val = v as? String {
                let preview = val.count > 80 ? "\(val.prefix(80))…(+\(val.count - 80))" : val
                print("🔬   \(key): \(preview)")
            }
        }

        // Dump body — usually JSON. Short bodies (<300 bytes) are almost always
        // soft-fail responses ({"status":"fail","message":"We're sorry…"}). Long
        // bodies are real profile data — useful to confirm the session is valid.
        if let s = String(data: data, encoding: .utf8) {
            let preview = s.count > 600 ? "\(s.prefix(600))…(+\(s.count - 600))" : s
            print("🔬 \(label) — body: \(preview)")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "fail" {
                print("🔬 \(label) — IG returned status:fail on what should be a public read endpoint.")
                print("🔬 \(label) — This is a soft-block. The Set-Claim header will NOT be present, so the warm-up cannot self-heal.")
                LogManager.shared.error("\(label) status:fail — IG soft-blocked the claim-refresh GET", category: .api)
            }
        }

        // Run the same case-insensitive claim capture as apiRequest, so this
        // diagnostic GET also updates the in-memory + persisted claim on success.
        var foundClaim: String? = nil
        for name in ["X-IG-Set-WWW-Claim", "x-ig-set-www-claim", "X-IG-WWW-Claim"] {
            if let v = http.value(forHTTPHeaderField: name), !v.isEmpty, v != "0" {
                foundClaim = v
                break
            }
        }
        if foundClaim == nil {
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String,
                   k.lowercased().contains("www-claim") || k.lowercased().contains("ig-claim"),
                   !v.isEmpty, v != "0" {
                    foundClaim = v
                    break
                }
            }
        }
        if let claim = foundClaim {
            print("🔬 \(label) — captured fresh claim: \(claim.prefix(20))…")
            await MainActor.run {
                self.wwwClaim = claim
                UserDefaults.standard.set(claim, forKey: "ig_www_claim")
            }
        } else {
            print("🔬 \(label) — NO claim header found in response. IG did not send one.")
        }
    }

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
        
        // ANTI-BOT: Detect duplicate text (prevent spam).
        // Only block within 24 h — notes expire after 24 h so resending the same text
        // after that is legitimate (e.g. performing the same trick in a new show).
        if let lastNote = UserDefaults.standard.string(forKey: "last_note_text"),
           lastNote == text {
            let lastSent = UserDefaults.standard.double(forKey: "last_note_sent_timestamp")
            let elapsed  = lastSent > 0 ? Date().timeIntervalSince1970 - lastSent : 0
            if elapsed < 86400 {   // 24 h window — same as note expiry on Instagram
                throw InstagramError.apiError("You already sent this note. Instagram may flag duplicate notes as spam.\n\nPlease write something different.")
            }
        }

        let noteSafety = InstagramSafetyGate.shared.decision(for: .note)
        guard noteSafety.allowed else {
            LogManager.shared.warning("SAFETY BLOCK — note: \(noteSafety.reason)", category: .api)
            throw InstagramError.apiError("Safety pause: \(noteSafety.reason). Wait \(noteSafety.waitSeconds)s.")
        }
        
        // ANTI-BOT: Wait if network changed recently
        try await waitForNetworkStability()

        // ANTI-BOT: Human delay (1-3 seconds) - longer than before
        let delay = UInt64.random(in: 1_000_000_000...3_000_000_000)
        print("   Waiting \(delay / 1_000_000_000)s (human delay)...")
        try await Task.sleep(nanoseconds: delay)

        print("   [NOTE] csrfToken=\(String(session.csrfToken.prefix(8)))... len=\(session.csrfToken.count) audience=\(audience)")
        print("   [NOTE] wwwClaim=\(String(wwwClaim.prefix(20)))")

        // ── CRITICAL LESSON (May-2026 root-cause analysis) ──────────────────────────────
        // Earlier versions built requests manually and called:
        //   headers.removeValue(forKey: "Cookie")   // "let URLSession handle cookies"
        // After a Keychain-restore restart, HTTPCookieStorage.shared is empty, so
        // URLSession sends ZERO cookies → Instagram returns 403 login_required.
        // buildCookieHeader() still printed "Sending N cookies" because it was called
        // before the removal — a misleading log that hid the real cause.
        // Bio (POST /accounts/edit_profile/) worked because it routes through apiRequest(),
        // which keeps the explicit Cookie header built from the in-memory session values.
        // FIX: route ALL Notes calls through apiRequest() — identical code path to Bio.
        // ────────────────────────────────────────────────────────────────────────────────

        // ── REGRESSION FIX (May-2026, second pass) ──────────────────────────────────────
        // Symptom: HTTP 200 + body `{"status":"fail","message":"We're sorry..."}` on every
        // Notes call, plus 400/fail on bio after the GET /accounts/current_user/ also
        // returned status:fail. wwwClaim stuck at 0 even after a GET warm-up.
        //
        // Root cause: a previous "fix" had introduced (a) a diagnostic GET warm-up to
        // /accounts/current_user/?edit=true before the notes POST, (b) a warm-up POST
        // to /notes/update_notes_last_seen_timestamp/, and (c) the body params
        // `device_id` + `note_style` instead of the canonical `uuid` token. The combined
        // effect was a 3-call burst that Instagram flagged as automation + a body shape
        // that wasn't accepted, so the actual create_note POST always got soft-fail.
        // The reference mentalgramold implementation does ONE direct POST with the
        // canonical body and it works. Match that pattern exactly.
        //
        // Diagnostic: If Notes breaks AGAIN:
        //   • wwwClaim is sent on EVERY request as "X-IG-WWW-Claim: <value>" (or "0"
        //     for fresh installs). Never omit the header.
        //   • Body must include `uuid` (fresh UUID per call) — it acts as the IG
        //     idempotency token. Without it IG returns generic soft-fail.
        //   • Do NOT chain extra warm-ups before the POST. One direct call.
        //   • If status:fail persists even with a single canonical POST, the account
        //     is most likely soft-blocked by IG and only IG can clear that flag.
        // ────────────────────────────────────────────────────────────────────────────────

        // ── Direct create_note POST (matches mentalgramold's proven pattern) ────────────
        let body: [String: String] = [
            "audience":    String(audience),
            "text":        text,
            "_csrftoken":  session.csrfToken,
            "_uid":        session.userId,
            "_uuid":       clientUUID,
            // `uuid` is a per-call idempotency token (fresh UUID, NOT the persistent
            // clientUUID). IG requires it; without it create_note silently soft-fails.
            "uuid":        UUID().uuidString
        ]
        print("   [NOTE] Body params: \(body.keys.sorted().joined(separator: ", "))")
        // Do NOT call InstagramSafetyGate.record(.note) here. apiRequest() checks and
        // records /notes/create_note/ internally after the request is allowed. Recording
        // before apiRequest makes this very call fail with "note too soon".
        let data = try await apiRequest(method: "POST", path: "/notes/create_note/", body: body)

        if let rawResponse = String(data: data, encoding: .utf8) {
            print("   [NOTE] Raw response: \(rawResponse.prefix(400))")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let status = json["status"] as? String, status == "ok" {
                print("✅ [NOTE] Note created successfully")

                UserDefaults.standard.set(text, forKey: "last_note_text")
                UserDefaults.standard.set(Date(), forKey: "last_note_sent_date")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_note_sent_timestamp")
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

        let bioSafety = InstagramSafetyGate.shared.decision(for: .biography)
        guard bioSafety.allowed else {
            LogManager.shared.warning("SAFETY BLOCK — biography: \(bioSafety.reason)", category: .api)
            throw InstagramError.apiError("Safety pause: \(bioSafety.reason). Wait \(bioSafety.waitSeconds)s.")
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
                        cachedHighlights: cached.cachedHighlights,
                        cachedReelItems: cached.cachedReelItems,
                        cachedNextMaxId: cached.cachedNextMaxId
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
        guard let uiImage = UIImage(data: imageData) else {
            print("❌ [PROFILE PIC] Failed to decode image")
            throw InstagramError.apiError("Failed to process image")
        }

        // Instagram profile pictures must be square (1:1).
        // Center-crop any aspect ratio and resize to ≤1080 px using UIGraphicsImageRenderer
        // which handles all EXIF orientations transparently.
        let srcW = uiImage.size.width
        let srcH = uiImage.size.height
        let side = min(srcW, srcH)
        let targetSide = min(side, 1080)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
        let squareImage = renderer.image { _ in
            let scale = targetSide / side
            let drawX = -((srcW - side) / 2) * scale
            let drawY = -((srcH - side) / 2) * scale
            uiImage.draw(in: CGRect(x: drawX, y: drawY, width: srcW * scale, height: srcH * scale))
        }

        guard let jpegData = squareImage.jpegData(compressionQuality: 0.9) else {
            print("❌ [PROFILE PIC] Failed to convert image to JPEG")
            throw InstagramError.apiError("Failed to process image")
        }

        print("   Image size: \(jpegData.count / 1024) KB (cropped to \(Int(targetSide))×\(Int(targetSide))px square)")
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
    
    // MARK: - Robust JSON Parsing

    /// Safely extracts an Int from any numeric JSON value (Int, Int64, Double, NSNumber, String).
    static func robustInt(_ value: Any?) -> Int {
        if let i = value as? Int    { return i }
        if let i = value as? Int64  { return Int(i) }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return 0
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

    // MARK: - Paginated Archived Photos Fetch

    /// Fetches ALL archived photos from `feed/only_me_feed/` with rate-limit awareness and caching.
    ///
    /// **Anti-bot measures:**
    /// - Results are cached for 10 minutes ONLY when the scan completed fully (not aborted).
    /// - Maximum 50 pages (≈1000 photos). Keeps large archives accessible.
    /// - 3–5 s human delay between pages.
    /// - Hard stop when `actionsThisHour >= 45` to leave headroom for reveals and uploads.
    /// - Aborts immediately if session expires or lockdown activates mid-scan.
    ///
    /// - Parameter forceRefresh: When true, bypass the cache and do a fresh network scan.
    func getAllArchivedPhotos(forceRefresh: Bool = false) async throws -> [(mediaId: String, imageURL: String, timestamp: Date?, isVideo: Bool, videoURL: String?, videoAspectRatio: CGFloat?)] {
        // ANTI-BOT: Do not start a full archive scan while a Sync & Archive or
        // upload operation is active. Running /feed/only_me_feed/ in parallel
        // with POST /media/.../only_me/ requests from the same session doubles
        // the API footprint and has been observed to cause Instagram 403s. If
        // the caller needs fresh data, they must wait until the heavy op ends.
        if isHeavyOperationActive {
            print("⏳ [ARCHIVE SCAN] Skipped — heavy operation active (S&A or upload)")
            LogManager.shared.info("Archive scan deferred: heavy operation active", category: .api)
            // Return cached data if available so the UI isn't left empty.
            if let cached = archivedPhotoCache {
                return cached
            }
            return []
        }
        // Cache hit — return immediately without any network calls
        if !forceRefresh,
           let cached = archivedPhotoCache,
           let cacheDate = archivedPhotoCacheDate,
           Date().timeIntervalSince(cacheDate) < archivedPhotoCacheTTL {
            let age = Int(Date().timeIntervalSince(cacheDate))
            lastArchiveScanCompleted = true
            lastArchiveScanStopReason = nil
            print("📦 [ARCHIVE CACHE] Hit — \(cached.count) photos, age \(age)s")
            LogManager.shared.info("Archive cache hit: \(cached.count) photos (\(age)s old)", category: .api)
            return cached
        }

        var allPhotos: [(mediaId: String, imageURL: String, timestamp: Date?, isVideo: Bool, videoURL: String?, videoAspectRatio: CGFloat?)] = []
        var nextMaxId: String? = nil
        let maxPages = 50  // ≈1000 photos max — increased to reach older archives
        var scanWasAborted = false  // Track if scan ended early (rate limit / session)
        var stopReason: String? = nil
        var reachedMaxPagesWithMoreAvailable = false
        var seenMediaIds = Set<String>()
        var seenCursors = Set<String>()

        print("📦 [ARCHIVE] Starting fresh scan (forceRefresh=\(forceRefresh))...")
        lastArchiveScanCompleted = false
        lastArchiveScanStopReason = nil

        for page in 0..<maxPages {
            // Hard stop: session expired or lockdown activated between pages
            guard !isSessionExpired else {
                print("🔴 [ARCHIVE] Scan aborted — session expired")
                LogManager.shared.warning("Archive scan aborted: session expired", category: .api)
                scanWasAborted = true
                stopReason = "session expired"
                break
            }
            guard !isLocked else {
                print("🚨 [ARCHIVE] Scan aborted — lockdown active")
                LogManager.shared.warning("Archive scan aborted: lockdown active", category: .api)
                scanWasAborted = true
                stopReason = "lockdown active"
                break
            }

            // Hard stop: near rate limit — leave headroom for actual reveal/archive actions
            let rateInfo = checkRateLimit()
            if rateInfo.actionsUsed >= archiveScanRateLimitThreshold {
                print("⚠️ [ARCHIVE] Scan stopped early — rate limit threshold (\(rateInfo.actionsUsed)/\(maxActionsPerHour)). Got \(allPhotos.count) photos so far.")
                LogManager.shared.warning("Archive scan paused at \(rateInfo.actionsUsed)/\(maxActionsPerHour) — too close to rate limit", category: .api)
                scanWasAborted = true
                stopReason = "rate limit threshold \(rateInfo.actionsUsed)/\(maxActionsPerHour)"
                break
            }

            // Human-like delay between pages (longer than before to reduce request density)
            if page > 0 {
                let delay = UInt64.random(in: 3_000_000_000...5_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "count", value: "18")]
            if let cursor = nextMaxId {
                components.queryItems?.append(URLQueryItem(name: "max_id", value: cursor))
            }
            let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            let path = "/feed/only_me_feed/\(query)"

            print("📦 [ARCHIVE] Fetching page \(page + 1)/\(maxPages) from \(path)")
            let data = try await apiRequest(method: "GET", path: path)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstagramError.apiError("Could not parse archive feed response")
            }

            // Parse items — same logic as testGetArchivedPhotos
            let items = json["items"] as? [[String: Any]] ?? []
            for item in items {
                let mediaItem = item["media"] as? [String: Any] ?? item

                // pk can be Int64, NSNumber, or String depending on API version
                var resolvedId: String? = nil
                if let s = mediaItem["pk"] as? String, !s.isEmpty {
                    resolvedId = s
                } else if let n = mediaItem["pk"] as? NSNumber {
                    resolvedId = n.stringValue
                } else if let s = mediaItem["id"] as? String, !s.isEmpty {
                    resolvedId = s
                } else if let n = mediaItem["id"] as? NSNumber {
                    resolvedId = n.stringValue
                }
                guard let mediaId = resolvedId else {
                    print("⚠️ [ARCHIVE] Skipping item — could not parse pk/id: \(mediaItem.keys.sorted())")
                    continue
                }
                guard !seenMediaIds.contains(mediaId) else { continue }
                seenMediaIds.insert(mediaId)

                // Image URL: try direct, then carousel first child
                var imageURL = ""
                if let iv = mediaItem["image_versions2"] as? [String: Any],
                   let candidates = iv["candidates"] as? [[String: Any]],
                   let url = candidates.first?["url"] as? String {
                    imageURL = url
                } else if let carousel = mediaItem["carousel_media"] as? [[String: Any]],
                          let first = carousel.first,
                          let iv = first["image_versions2"] as? [String: Any],
                          let candidates = iv["candidates"] as? [[String: Any]],
                          let url = candidates.first?["url"] as? String {
                    imageURL = url
                }

                let takenAt: Date?
                if let t = mediaItem["taken_at"] as? NSNumber {
                    takenAt = Date(timeIntervalSince1970: t.doubleValue)
                } else {
                    takenAt = nil
                }

                // Parse video info (media_type 2 = video)
                let itemMediaType = mediaItem["media_type"] as? Int ?? 1
                let isVideo = itemMediaType == 2
                var itemVideoURL: String? = nil
                var itemVideoAspectRatio: CGFloat? = nil
                if isVideo {
                    if let vv = mediaItem["video_versions"] as? [[String: Any]],
                       let url = vv.first?["url"] as? String {
                        itemVideoURL = url
                    }
                    if let w = mediaItem["original_width"] as? Int,
                       let h = mediaItem["original_height"] as? Int, h > 0 {
                        itemVideoAspectRatio = CGFloat(w) / CGFloat(h)
                    }
                }

                allPhotos.append((mediaId: mediaId, imageURL: imageURL, timestamp: takenAt,
                                  isVideo: isVideo, videoURL: itemVideoURL,
                                  videoAspectRatio: itemVideoAspectRatio))
            }

            print("📦 [ARCHIVE] Page \(page + 1): \(items.count) items (total: \(allPhotos.count))")

            // Check pagination — next_max_id can be String or large NSNumber
            let topLevelMoreAvailable = json["more_available"] as? Bool
            let pagingInfo = json["paging_info"] as? [String: Any]
            let pagingMoreAvailable = pagingInfo?["more_available"] as? Bool
            let moreAvailable = topLevelMoreAvailable ?? pagingMoreAvailable ?? false
            if let cursor = json["next_max_id"] as? String, !cursor.isEmpty {
                nextMaxId = cursor
            } else if let cursor = json["next_max_id"] as? NSNumber {
                nextMaxId = cursor.stringValue
            } else if let cursor = pagingInfo?["max_id"] as? String,
                      !cursor.isEmpty {
                nextMaxId = cursor
            } else if let cursor = pagingInfo?["next_max_id"] as? String,
                      !cursor.isEmpty {
                nextMaxId = cursor
            } else {
                nextMaxId = nil
            }

            print("📦 [ARCHIVE] more_available=\(moreAvailable) nextMaxId=\(nextMaxId ?? "nil")")
            if let cursor = nextMaxId {
                guard !seenCursors.contains(cursor) else {
                    print("⚠️ [ARCHIVE] Repeated cursor detected — stopping to avoid loop")
                    LogManager.shared.warning("Archive scan stopped: repeated cursor after \(allPhotos.count) photos", category: .api)
                    nextMaxId = nil
                    break
                }
                seenCursors.insert(cursor)
            }
            if page == maxPages - 1 && moreAvailable && nextMaxId != nil {
                reachedMaxPagesWithMoreAvailable = true
            }
            if !moreAvailable || nextMaxId == nil { break }
        }

        if reachedMaxPagesWithMoreAvailable {
            scanWasAborted = true
            stopReason = "max page limit \(maxPages) reached"
            LogManager.shared.warning("Archive scan reached maxPages=\(maxPages) with more pages available", category: .api)
        }

        // Only cache if the scan completed normally (not aborted by rate limit/session).
        // Aborted scans return partial results without caching so the next call retries fully.
        if scanWasAborted {
            lastArchiveScanCompleted = false
            lastArchiveScanStopReason = stopReason ?? "scan aborted"
            LogManager.shared.warning("Archive scan incomplete (\(allPhotos.count) photos) — \(lastArchiveScanStopReason ?? "unknown"). NOT cached, will retry next time", category: .api)
        } else {
            lastArchiveScanCompleted = true
            lastArchiveScanStopReason = nil
            archivedPhotoCache = allPhotos
            archivedPhotoCacheDate = Date()
            LogManager.shared.info("Archive scan complete: \(allPhotos.count) photos (cached for \(Int(archivedPhotoCacheTTL/60)) min)", category: .api)
        }
        return allPhotos
    }

    // MARK: - Diagnostics

    /// Summarises the current Instagram cookies stored by URLSession.
    /// Used by session diagnostics so log exports show whether the auth cookies
    /// were present at the time of a "logged-out" response.
    fileprivate func currentCookieSummary() -> String {
        guard let allCookies = HTTPCookieStorage.shared.cookies else {
            return "<none>"
        }
        let igCookies = allCookies.filter { $0.domain.contains("instagram.com") }
        guard !igCookies.isEmpty else { return "<no-ig-cookies>" }

        let sessionId = igCookies.first { $0.name == "sessionid" }?.value ?? ""
        let userId    = igCookies.first { $0.name == "ds_user_id"  }?.value ?? ""
        let csrf      = igCookies.first { $0.name == "csrftoken"   }?.value ?? ""
        return "sessionid:\(sessionId.isEmpty ? "missing" : "len=\(sessionId.count)") ds_user_id:\(userId.isEmpty ? "missing" : userId) csrftoken:\(csrf.isEmpty ? "missing" : "set") total:\(igCookies.count)"
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

// MARK: - Instagram Safety Gate

final class InstagramSafetyGate {
    static let shared = InstagramSafetyGate()

    enum Action: String {
        case performanceEntry
        case pullRefresh
        case entryRefresh
        case silentGridRefresh
        case biography
        case note
        case noteDelete
        case archive
        case unarchive
        case reveal
        case upload
        case ownProfilePagination
        case exploreRefresh
        case explorePagination
        case searchUsers
        case visitedProfileOpen
        case visitedProfilePagination
        case visitedProfileRefresh
        case apiRead
        case apiWrite
        case probe
    }

    struct Decision {
        let allowed: Bool
        let waitSeconds: Int
        let reason: String

        static let allowed = Decision(allowed: true, waitSeconds: 0, reason: "")
    }

    struct PerformanceEntryDecision {
        let allowRemoteCalls: Bool
        let waitSeconds: Int
        let reason: String
    }

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private let prefix = "instagram_safety_gate_"

    // MARK: - Cold-Start Guard
    /// Marked when the app launches. During the cold-start window we block every
    /// automatic API call that is not strictly required, to break the 3-endpoint
    /// warmup pattern Instagram fingerprints as a bot.
    private var appLaunchTime: Date? = nil
    /// Seconds after app launch during which silent / auto API calls are blocked.
    /// Tuned to be longer than the typical "Performance entry" burst observed
    /// in logs (≈15s) so the pattern is fully broken.
    private let coldStartWindow: TimeInterval = 45
    private var coldStartCloseLogged: Bool = false

    // MARK: - Warm-Resume Guard
    /// Shorter cold-start used when the app comes back to foreground after a long
    /// pause in background. Same idea as cold-start, but with a smaller window
    /// because the process did not restart — only the user-facing scene.
    private var warmResumeTime: Date? = nil
    private let warmResumeWindow: TimeInterval = 25
    private var warmResumeCloseLogged: Bool = false

    private init() {}

    /// Called once on app launch to start the cold-start window.
    /// Safe to call multiple times; only the first call is honored.
    /// IMPORTANT: do not call LogManager from here — this is invoked during
    /// LogManager's own init, which would deadlock the singleton.
    func markAppLaunch() {
        lock.lock()
        defer { lock.unlock() }
        if appLaunchTime == nil {
            appLaunchTime = Date()
            print("⏳ [COLD-START] Window opened — \(Int(coldStartWindow))s of automatic-call lockdown")
        }
    }

    /// Called when the app returns to foreground after being in background for a
    /// long time (>5 min). Opens a shorter "warm resume" lockdown window so the
    /// app doesn't immediately fire its automatic-call pattern as if it had just
    /// been launched fresh.
    func markWarmResume() {
        lock.lock()
        defer { lock.unlock() }
        warmResumeTime = Date()
        warmResumeCloseLogged = false
        print("⏳ [WARM-RESUME] Window opened — \(Int(warmResumeWindow))s of automatic-call lockdown")
        LogManager.shared.info("[WARM-RESUME] Window opened — automatic IG calls blocked for ~\(Int(warmResumeWindow))s", category: .general)
    }

    /// True if we are still inside the cold-start OR warm-resume window.
    var isInColdStartWindow: Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let coldActive: Bool = {
            guard let t = appLaunchTime else { return false }
            return now.timeIntervalSince(t) < coldStartWindow
        }()
        let warmActive: Bool = {
            guard let t = warmResumeTime else { return false }
            return now.timeIntervalSince(t) < warmResumeWindow
        }()
        // First query after each window closes logs a notice so it's visible
        // in TestFlight logs that the lockdown ended.
        if !coldActive && appLaunchTime != nil && !coldStartCloseLogged {
            coldStartCloseLogged = true
            LogManager.shared.info("[COLD-START] Window closed — automatic IG calls re-enabled", category: .general)
        }
        if !warmActive && warmResumeTime != nil && !warmResumeCloseLogged {
            warmResumeCloseLogged = true
            LogManager.shared.info("[WARM-RESUME] Window closed — automatic IG calls re-enabled", category: .general)
        }
        return coldActive || warmActive
    }

    /// Seconds remaining in whichever window is active (0 if none).
    var coldStartSecondsRemaining: Int {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        var remaining = 0
        if let t = appLaunchTime {
            remaining = max(remaining, Int(coldStartWindow - now.timeIntervalSince(t)))
        }
        if let t = warmResumeTime {
            remaining = max(remaining, Int(warmResumeWindow - now.timeIntervalSince(t)))
        }
        return max(0, remaining)
    }

    /// Blocks a specific auto-call kind during the cold-start window.
    /// Returns true when the caller should proceed, false when it must skip.
    func allowAutoCall(_ label: String) -> Bool {
        let inWindow = isInColdStartWindow
        if inWindow {
            let remaining = coldStartSecondsRemaining
            LogManager.shared.warning("[COLD-START] \(label) blocked — \(remaining)s remaining", category: .general)
            return false
        }
        return true
    }

    // MARK: - Performance entry

    /// Wipes all performance-entry throttle state from UserDefaults.
    /// Call on login so stale counters from a previous session (which can survive
    /// iCloud-restore or incomplete uninstall) don't block the new session.
    func resetPerformanceThrottle() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key("performance_pause_until"))
        defaults.removeObject(forKey: key("timestamps_\(Action.performanceEntry.rawValue)"))
        defaults.removeObject(forKey: key("last_heavy_archive_at"))
        print("🔓 [SAFETY-GATE] Performance throttle reset on login")
    }

    func markHeavyArchiveCompleted(photoCount: Int) {
        guard photoCount >= 5 else { return }
        lock.lock()
        defer { lock.unlock() }
        defaults.set(Date().timeIntervalSince1970, forKey: key("last_heavy_archive_at"))
        LogManager.shared.info("Performance cooldown armed after S&A archived \(photoCount) photos", category: .upload)
    }

    func peekPerformanceEntry() -> PerformanceEntryDecision {
        lock.lock()
        defer { lock.unlock() }
        return performanceEntryDecisionLocked(recordEntry: false)
    }

    func recordPerformanceEntry() -> PerformanceEntryDecision {
        lock.lock()
        defer { lock.unlock() }
        return performanceEntryDecisionLocked(recordEntry: true)
    }

    private func performanceEntryDecisionLocked(recordEntry: Bool) -> PerformanceEntryDecision {
        let now = Date().timeIntervalSince1970
        if let circuit = activeChallengeCircuit(now: now) {
            logBlock("performance entry blocked — challenge circuit active (\(circuit.waitSeconds)s)")
            return PerformanceEntryDecision(
                allowRemoteCalls: false,
                waitSeconds: circuit.waitSeconds,
                reason: "challenge circuit active"
            )
        }

        if let heavyArchiveAt = defaults.object(forKey: key("last_heavy_archive_at")) as? Double {
            let elapsed = now - heavyArchiveAt
            if elapsed < 180 {
                let wait = max(1, Int(180 - elapsed))
                logBlock("performance entry blocked — post-archive cooldown \(wait)s")
                return PerformanceEntryDecision(
                    allowRemoteCalls: false,
                    waitSeconds: wait,
                    reason: "post-archive cooldown"
                )
            }
            defaults.removeObject(forKey: key("last_heavy_archive_at"))
        }

        // Check existing pause BEFORE recording a new entry — otherwise a user
        // repeatedly tapping Performance during a pause keeps inflating the counter,
        // which cascades into progressively longer blocks.
        if let pauseUntil = defaults.object(forKey: key("performance_pause_until")) as? Double,
           pauseUntil > now {
            let wait = Int(pauseUntil - now)
            logBlock("performance pause active — cache-only \(wait)s")
            return PerformanceEntryDecision(
                allowRemoteCalls: false,
                waitSeconds: wait,
                reason: "Performance safety pause"
            )
        }

        var entries = timestamps(for: .performanceEntry)
            .filter { now - $0 < 300 }

        // Only count this entry if we are NOT inside the cold-start / warm-resume window.
        // During those windows ALL remote calls are already blocked by a separate guard,
        // so penalising the user for opening Performance at that moment (e.g. because
        // they restarted the app) would unfairly inflate the re-entry counter and cause
        // cascading 120 s blocks even though no API calls were ever attempted.
        // NOTE: we check the raw backing vars instead of calling isInColdStartWindow()
        //       because that property also acquires `lock` and we already hold it here.
        let nowDate = Date()
        let duringColdStart: Bool = {
            let coldActive = appLaunchTime.map { nowDate.timeIntervalSince($0) < coldStartWindow } ?? false
            let warmActive = warmResumeTime.map { nowDate.timeIntervalSince($0) < warmResumeWindow } ?? false
            return coldActive || warmActive
        }()
        if recordEntry && !duringColdStart {
            entries.append(now)
            setTimestamps(entries, for: .performanceEntry)
        }

        // Re-entry penalties: throttle truly rapid re-opens only.
        if entries.count >= 5 {
            let pauseUntil = now + 120
            defaults.set(pauseUntil, forKey: key("performance_pause_until"))
            logBlock("performance re-entry \(entries.count)/5min — cache-only for 120s")
            return PerformanceEntryDecision(
                allowRemoteCalls: false,
                waitSeconds: 120,
                reason: "too many Performance entries"
            )
        }

        if entries.count >= 2, let previous = entries.dropLast().last, now - previous < 30 {
            let wait = max(1, Int(30 - (now - previous)))
            logBlock("performance re-entry too soon — cache-only \(wait)s")
            return PerformanceEntryDecision(
                allowRemoteCalls: false,
                waitSeconds: wait,
                reason: "recent Performance entry"
            )
        }

        return PerformanceEntryDecision(allowRemoteCalls: true, waitSeconds: 0, reason: "")
    }

    // MARK: - Request budgets

    func decision(for action: Action) -> Decision {
        lock.lock()
        defer { lock.unlock() }

        let now = Date().timeIntervalSince1970
        if let circuit = activeChallengeCircuit(now: now) {
            return circuit
        }

        if action == .archive, isPostRevealProtected(now: now) {
            return Decision(
                allowed: false,
                waitSeconds: postRevealRemaining(now: now),
                reason: "recent reveal protection"
            )
        }

        switch action {
        case .biography:
            return minGapDecision(action: action, now: now, minGap: 180)
        case .note:
            return minGapDecision(action: action, now: now, minGap: 150)
        case .reveal:
            return minGapDecision(action: action, now: now, minGap: 150)
        case .pullRefresh:
            return minGapDecision(action: action, now: now, minGap: 600)
        case .entryRefresh:
            return minGapDecision(action: action, now: now, minGap: 90)
        case .silentGridRefresh:
            if let recentPagination = recentActionDecision(
                actions: [.ownProfilePagination, .visitedProfilePagination],
                now: now,
                minGap: 20,
                reason: "recent feed pagination"
            ) {
                return recentPagination
            }
            return minGapDecision(action: action, now: now, minGap: 30)
        case .ownProfilePagination:
            if let recentRefresh = recentActionDecision(
                actions: [.silentGridRefresh, .entryRefresh, .pullRefresh],
                now: now,
                // 6s gap: enough to separate the entry burst from the first user-triggered
                // pagination, but short enough that scrolling down immediately after
                // the grid appears doesn't stall. Pagination is a GET to the same
                // endpoint that already ran during the refresh, so the pattern looks
                // like organic browsing (not a warmup burst) at this spacing.
                minGap: 6,
                reason: "recent feed refresh"
            ) {
                return recentRefresh
            }
            return pacedWindowDecision(action: action, now: now, minGap: 4, maxCount: 10, window: 600)
        case .exploreRefresh:
            return minGapDecision(action: action, now: now, minGap: 900)
        case .explorePagination:
            return pacedWindowDecision(action: action, now: now, minGap: 15, maxCount: 8, window: 600)
        case .searchUsers:
            return minGapDecision(action: action, now: now, minGap: 20)
        case .visitedProfileOpen:
            return minGapDecision(action: action, now: now, minGap: 3)
        case .visitedProfilePagination:
            if let recentRefresh = recentActionDecision(
                actions: [.silentGridRefresh, .entryRefresh, .pullRefresh],
                now: now,
                minGap: 6,
                reason: "recent feed refresh"
            ) {
                return recentRefresh
            }
            return pacedWindowDecision(action: action, now: now, minGap: 3, maxCount: 10, window: 600)
        case .visitedProfileRefresh:
            return minGapDecision(action: action, now: now, minGap: 900)
        case .archive:
            return windowDecision(action: action, now: now, maxCount: 8, window: 600)
        case .unarchive:
            return windowDecision(action: action, now: now, maxCount: 15, window: 600)
        case .upload, .apiWrite:
            return windowDecision(action: action, now: now, maxCount: 18, window: 600)
        case .noteDelete, .probe:
            return minGapDecision(action: action, now: now, minGap: 60)
        case .performanceEntry, .apiRead:
            return .allowed
        }
    }

    func record(_ action: Action) {
        lock.lock()
        defer { lock.unlock() }
        recordLocked(action, at: Date().timeIntervalSince1970)
    }

    func waitForApiSlot(method: String, path: String) async throws {
        let action = actionFor(method: method, path: path)
        let decision = self.decision(for: action)
        guard decision.allowed else {
            logBlock("\(method) \(short(path)) blocked — \(decision.reason) (\(decision.waitSeconds)s)")
            throw InstagramError.apiError("Safety pause: \(decision.reason). Wait \(decision.waitSeconds)s.")
        }

        let minGap: TimeInterval = method == "GET" ? 0.35 : 1.25
        let wait = reserveApiGap(minGap: minGap)
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func recordApiRequest(method: String, path: String) {
        record(actionFor(method: method, path: path))
    }

    // MARK: - Challenge circuit

    func markChallenge(duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let until = Date().timeIntervalSince1970 + duration
        defaults.set(until, forKey: key("challenge_until"))
        logBlock("challenge circuit active for \(Int(duration))s")
    }

    func clearChallenge() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key("challenge_until"))
        defaults.removeObject(forKey: key("probe_fail_count"))
    }

    func canProbeSession() -> Decision {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        let lastProbe = defaults.double(forKey: key("last_probe"))
        let minGap = min(300.0, 60.0 * pow(2.0, Double(defaults.integer(forKey: key("probe_fail_count")))))
        if lastProbe > 0, now - lastProbe < minGap {
            let wait = Int(minGap - (now - lastProbe))
            return Decision(allowed: false, waitSeconds: wait, reason: "probe cooldown")
        }
        defaults.set(now, forKey: key("last_probe"))
        return .allowed
    }

    func recordProbeResult(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if success {
            defaults.removeObject(forKey: key("probe_fail_count"))
            defaults.removeObject(forKey: key("challenge_until"))
        } else {
            defaults.set(defaults.integer(forKey: key("probe_fail_count")) + 1, forKey: key("probe_fail_count"))
        }
    }

    // MARK: - Post reveal protection

    func markPostReveal(mediaIds: [String], holdSeconds: TimeInterval = 300) {
        guard !mediaIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        defaults.set(now + holdSeconds, forKey: key("post_reveal_protected_until"))
        defaults.set(Array(Set(mediaIds)), forKey: key("post_reveal_media_ids"))
        LogManager.shared.info("SAFETY: post-reveal protection active for \(mediaIds.count) media item(s)", category: .api)
        scheduleArchiveReadyNotification(after: holdSeconds)
    }

    // Schedules a local notification reminding the user they can re-archive photos.
    // Cancelled automatically if called again (new reveal resets the timer).
    private func scheduleArchiveReadyNotification(after delay: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["archiveReady"])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notif.archive_ready.title", value: "Ready to archive", comment: "")
        content.body  = NSLocalizedString("notif.archive_ready.body",  value: "You can now safely archive your photos again.", comment: "")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request  = UNNotificationRequest(identifier: "archiveReady", content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                print("⚠️ [NOTIF] Failed to schedule archive-ready notification: \(error.localizedDescription)")
            } else {
                print("🔔 [NOTIF] Archive-ready notification scheduled in \(Int(delay))s")
            }
        }
    }

    func canArchive(mediaId: String) -> Decision {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        if let protected = defaults.stringArray(forKey: key("post_reveal_media_ids")),
           protected.contains(mediaId),
           isPostRevealProtected(now: now) {
            return Decision(
                allowed: false,
                waitSeconds: postRevealRemaining(now: now),
                reason: "recently revealed media"
            )
        }
        return .allowed
    }

    /// Public, read-only check used by state-sync (`getMediaIsArchived`) to skip
    /// /media/{pk}/info/ for media that are within the post-reveal hold window.
    /// Returns true only if BOTH the global hold is active AND the mediaId was
    /// in the most recent reveal batch.
    func isMediaPostRevealProtected(mediaId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        guard isPostRevealProtected(now: now) else { return false }
        guard let protected = defaults.stringArray(forKey: key("post_reveal_media_ids")) else { return false }
        return protected.contains(mediaId)
    }

    /// Seconds left on the global post-reveal hold (0 if not active).
    /// Used by the Sync & Archive UI to render a countdown that explains *why*
    /// the button is gated, so the magician doesn't reach for a "bypass".
    var postRevealSecondsRemaining: Int {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        return postRevealRemaining(now: now)
    }

    // MARK: - Per-set Sync cooldown
    /// Minimum spacing between two full state-syncs of the same Set. Prevents
    /// the magician from pressing "Sync & Archive" repeatedly on the same 10
    /// photos within minutes — the exact double-sync pattern that surfaced as
    /// HTTP 403 in the May 15 bot detection log.
    private let setSyncMinGap: TimeInterval = 300 // 5 minutes

    func canSyncSet(setId: String) -> Decision {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        let key = self.key("set_sync_at_\(setId)")
        let last = defaults.double(forKey: key)
        guard last > 0 else { return .allowed }
        let elapsed = now - last
        guard elapsed < setSyncMinGap else { return .allowed }
        let wait = max(1, Int(setSyncMinGap - elapsed))
        return Decision(allowed: false, waitSeconds: wait, reason: "same set synced recently")
    }

    func markSetSyncStarted(setId: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(Date().timeIntervalSince1970, forKey: key("set_sync_at_\(setId)"))
    }

    // MARK: - Private helpers

    private func minGapDecision(action: Action, now: Double, minGap: TimeInterval) -> Decision {
        guard let last = timestamps(for: action).last else { return .allowed }
        let elapsed = now - last
        guard elapsed < minGap else { return .allowed }
        return Decision(allowed: false, waitSeconds: Int(minGap - elapsed), reason: "\(action.rawValue) too soon")
    }

    private func windowDecision(action: Action, now: Double, maxCount: Int, window: TimeInterval) -> Decision {
        let recent = timestamps(for: action).filter { now - $0 < window }
        guard recent.count >= maxCount else { return .allowed }
        let oldest = recent.first ?? now
        let wait = max(1, Int(window - (now - oldest)))
        return Decision(allowed: false, waitSeconds: wait, reason: "\(action.rawValue) budget exceeded")
    }

    private func pacedWindowDecision(action: Action, now: Double, minGap: TimeInterval, maxCount: Int, window: TimeInterval) -> Decision {
        let gap = minGapDecision(action: action, now: now, minGap: minGap)
        guard gap.allowed else { return gap }
        return windowDecision(action: action, now: now, maxCount: maxCount, window: window)
    }

    private func recentActionDecision(actions: [Action], now: Double, minGap: TimeInterval, reason: String) -> Decision? {
        let last = actions
            .compactMap { timestamps(for: $0).last }
            .max()
        guard let last else { return nil }
        let elapsed = now - last
        guard elapsed < minGap else { return nil }
        return Decision(allowed: false, waitSeconds: Int(minGap - elapsed), reason: reason)
    }

    private func activeChallengeCircuit(now: Double) -> Decision? {
        guard let until = defaults.object(forKey: key("challenge_until")) as? Double,
              until > now else { return nil }
        return Decision(allowed: false, waitSeconds: Int(until - now), reason: "Instagram verification pending")
    }

    private func isPostRevealProtected(now: Double) -> Bool {
        guard let until = defaults.object(forKey: key("post_reveal_protected_until")) as? Double else { return false }
        if until <= now {
            defaults.removeObject(forKey: key("post_reveal_protected_until"))
            defaults.removeObject(forKey: key("post_reveal_media_ids"))
            return false
        }
        return true
    }

    private func postRevealRemaining(now: Double) -> Int {
        guard let until = defaults.object(forKey: key("post_reveal_protected_until")) as? Double else { return 0 }
        return max(0, Int(until - now))
    }

    private func reserveApiGap(minGap: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        let reservedAt = defaults.double(forKey: key("last_api_slot"))
        let earliest = reservedAt + minGap
        let wait = max(0, earliest - now)
        defaults.set(now + wait, forKey: key("last_api_slot"))
        return wait
    }

    private func actionFor(method: String, path: String) -> Action {
        guard method != "GET" else { return .apiRead }
        if path.contains("/accounts/edit_profile/") { return .biography }
        if path.contains("/notes/create_note/") { return .note }
        if path.contains("/notes/delete_note/") { return .noteDelete }
        if path.contains("/undo_only_me/") { return .unarchive }
        if path.contains("/only_me/") { return .archive }
        if path.contains("upload") || path.contains("configure") || path.contains("sidecar") { return .upload }
        return .apiWrite
    }

    private func recordLocked(_ action: Action, at now: Double) {
        var values = timestamps(for: action).filter { now - $0 < 3600 }
        values.append(now)
        setTimestamps(values, for: action)
    }

    private func timestamps(for action: Action) -> [Double] {
        defaults.array(forKey: key("timestamps_\(action.rawValue)")) as? [Double] ?? []
    }

    private func setTimestamps(_ timestamps: [Double], for action: Action) {
        defaults.set(timestamps, forKey: key("timestamps_\(action.rawValue)"))
    }

    private func key(_ name: String) -> String {
        "\(prefix)\(name)"
    }

    private func short(_ path: String) -> String {
        path.components(separatedBy: "?").first ?? path
    }

    private func logBlock(_ message: String) {
        LogManager.shared.warning("SAFETY BLOCK — \(message)", category: .api)
    }
}
