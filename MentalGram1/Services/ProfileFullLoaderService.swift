import Foundation
import Combine
import SwiftUI

// MARK: - Load Phase

enum FullLoadPhase: String, Codable {
    case idle
    case warmingUp      // Post-login safety delay before first API call
    case grid           // Paginating grid posts
    case reels          // Loading reels
    case tagged         // Loading tagged posts
    case completed
}

// MARK: - ProfileFullLoaderService

/// Loads the complete profile (grid + reels + tagged) in the background after login.
/// Persists progress to UserDefaults so it can resume after a crash, minimise, or relaunch.
/// Each new account (userId) resets all state automatically.
class ProfileFullLoaderService: ObservableObject {
    static let shared = ProfileFullLoaderService()

    private enum FullLoadTimeout: Error {
        case timedOut
    }

    // MARK: Published state (drives the UI overlay)
    @Published private(set) var phase: FullLoadPhase = .idle
    @Published private(set) var gridPagesLoaded: Int  = 0
    @Published private(set) var gridItemsLoaded: Int  = 0
    @Published private(set) var reelsLoaded:    Bool  = false
    @Published private(set) var taggedLoaded:   Bool  = false
    /// Seconds remaining in the warm-up countdown (shown in the overlay).
    @Published private(set) var warmupSecondsRemaining: Int = 0

    // MARK: Persistence keys
    private let kAccountId  = "fullLoad_accountId"
    private let kPhase      = "fullLoad_phase"
    private let kGridCursor = "fullLoad_gridCursor"
    private let kGridPages  = "fullLoad_gridPages"
    private let kGridItems  = "fullLoad_gridItems"

    private var loadTask:   Task<Void, Never>?
    private var warmupTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    // Warmup duration in seconds
    private let warmupDuration: Int = 90

    private init() {
        // The background full-loader is deprecated. PerformanceView now loads its
        // profile via a single getProfileInfo() call (same pattern as Explore →
        // UserProfileView), so this service is intentionally kept dormant.
        // Purge any persisted state from previous builds so no warmup is "resumed"
        // at the next app launch.
        defaults.removeObject(forKey: kPhase)
        defaults.removeObject(forKey: kGridCursor)
        defaults.removeObject(forKey: kGridPages)
        defaults.removeObject(forKey: kGridItems)
        phase = .completed
        gridPagesLoaded = 0
        gridItemsLoaded = 0
        reelsLoaded = false
        taggedLoaded = false
        warmupSecondsRemaining = 0
    }

    // MARK: - Public API

    /// DEPRECATED — kept only for binary compatibility with any caller that still
    /// references it. PerformanceView fetches its profile directly. This is a no-op.
    func notifyLoggedIn(userId: String) {
        print("⏭️ [FULL LOAD] notifyLoggedIn ignored — service deprecated")
    }

    /// Reset all state (called on new account or manual reset).
    func reset(forNewAccount newId: String? = nil) {
        loadTask?.cancel();   loadTask   = nil
        warmupTask?.cancel(); warmupTask = nil
        gridPagesLoaded = 0
        gridItemsLoaded = 0
        reelsLoaded     = false
        taggedLoaded    = false
        warmupSecondsRemaining = 0
        setPhase(.idle)
        defaults.removeObject(forKey: kGridCursor)
        defaults.set(0,   forKey: kGridPages)
        defaults.set(0,   forKey: kGridItems)
        if let id = newId { defaults.set(id, forKey: kAccountId) }
        print("🔄 [FULL LOAD] State reset\(newId.map { " for \($0)" } ?? "")")
    }

    /// Pause all loading (app going to background).
    func pause() {
        loadTask?.cancel();   loadTask   = nil
        warmupTask?.cancel(); warmupTask = nil
        print("⏸️ [FULL LOAD] Paused at phase: \(phase.rawValue)")
    }

    /// DEPRECATED — kept as no-op so existing callers (e.g. scenePhase changes)
    /// continue to compile and run safely.
    func startOrResume() {
        return
    }

    /// Skip the remaining loading and mark the profile as completed immediately.
    /// Used by the "Skip" button after the timeout.
    func skipToCompleted() {
        pause()
        setPhase(.completed)
        print("⏭️ [FULL LOAD] Skipped by user — marked completed")
    }

    // MARK: - Computed helpers

    var isBlockingPerformance: Bool {
        phase != .completed && phase != .idle
    }

    var progressDescription: String {
        switch phase {
        case .idle:      return ""
        case .warmingUp: return String(format: NSLocalizedString("fullload.warming_up", comment: ""), warmupSecondsRemaining)
        case .grid:      return String(format: NSLocalizedString("fullload.grid", comment: ""), gridItemsLoaded)
        case .reels:     return NSLocalizedString("fullload.reels", comment: "")
        case .tagged:    return NSLocalizedString("fullload.tagged", comment: "")
        case .completed: return NSLocalizedString("fullload.done", comment: "")
        }
    }

    // MARK: - Private loading sequence

    private func runLoadSequence() async {
        let ig = InstagramService.shared
        guard ig.isLoggedIn else { return }

        // ── Warm-up delay ────────────────────────────────────────────────────
        if phase == .idle || phase == .warmingUp {
            setPhase(.warmingUp)
            print("⏳ [FULL LOAD] Warming up — waiting \(warmupDuration)s before first call…")
            var remaining = warmupDuration
            await MainActor.run { warmupSecondsRemaining = remaining }
            while remaining > 0 {
                guard !Task.isCancelled else { return }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                remaining -= 1
                await MainActor.run { warmupSecondsRemaining = remaining }
            }
            await MainActor.run { warmupSecondsRemaining = 0 }
        }

        guard !Task.isCancelled, ig.isLoggedIn else { return }

        // ── Grid ─────────────────────────────────────────────────────────────
        if phase == .warmingUp || phase == .grid {
            setPhase(.grid)
            await loadGridPages()
        }
        guard !Task.isCancelled else { return }

        // ── Inter-phase pause ────────────────────────────────────────────────
        let pause1 = UInt64.random(in: 30_000_000_000...45_000_000_000)
        do { try await Task.sleep(nanoseconds: pause1) } catch { return }

        // ── Reels ─────────────────────────────────────────────────────────────
        if phase == .grid {
            setPhase(.reels)
            await loadReels()
        }
        guard !Task.isCancelled else { return }

        let pause2 = UInt64.random(in: 25_000_000_000...40_000_000_000)
        do { try await Task.sleep(nanoseconds: pause2) } catch { return }

        // ── Tagged ────────────────────────────────────────────────────────────
        if phase == .reels {
            setPhase(.tagged)
            await loadTagged()
        }
        guard !Task.isCancelled else { return }

        // ── Done ──────────────────────────────────────────────────────────────
        setPhase(.completed)
        print("🎉 [FULL LOAD] Profile fully cached!")
        LogManager.shared.success("Full profile load completed", category: .profile)
    }

    private func loadGridPages() async {
        let ig  = InstagramService.shared
        let max = 8  // 8 × 21 = 168 posts cap
        var cursor: String? = defaults.string(forKey: kGridCursor)

        while gridPagesLoaded < max {
            guard !Task.isCancelled, ig.isLoggedIn, !ig.isLocked else { break }
            guard !ig.shouldUseCacheOnlyForOptionalCalls else {
                let rate = ig.checkRateLimit()
                print("🛡️ [FULL LOAD] Grid pagination paused near rate budget (\(rate.actionsUsed)/55)")
                break
            }

            // Human-like inter-page delay (skip on first page — the warmup was enough)
            if gridPagesLoaded > 0 {
                let delay = UInt64.random(in: 15_000_000_000...25_000_000_000)
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }

            do {
                let (items, nextCursor) = try await ig.getUserMediaItems(amount: 21, maxId: cursor)
                await MainActor.run {
                    self.mergeMediaPageIntoProfileCache(items: items, nextCursor: nextCursor)
                }
                let page = gridPagesLoaded + 1
                await MainActor.run {
                    self.gridPagesLoaded = page
                    self.gridItemsLoaded += items.count
                }
                defaults.set(gridPagesLoaded, forKey: kGridPages)
                defaults.set(gridItemsLoaded, forKey: kGridItems)
                print("📜 [FULL LOAD] Grid page \(page): +\(items.count) (total \(gridItemsLoaded))")

                if let next = nextCursor, !next.isEmpty, next != cursor {
                    cursor = next
                    defaults.set(next, forKey: kGridCursor)
                } else {
                    print("📜 [FULL LOAD] Grid exhausted after \(page) pages")
                    break
                }
            } catch {
                print("⚠️ [FULL LOAD] Grid page error: \(error) — will resume next launch")
                break
            }
        }
    }

    private func loadReels() async {
        let ig = InstagramService.shared
        guard ig.isLoggedIn, !ig.isLocked else { return }
        guard !ig.shouldUseCacheOnlyForOptionalCalls else {
            let rate = ig.checkRateLimit()
            print("🛡️ [FULL LOAD] Reels skipped near rate budget (\(rate.actionsUsed)/55)")
            return
        }
        do {
            let items = try await withTimeout(seconds: 35) {
                try await ig.getUserReels(amount: 18)
            }
            await MainActor.run {
                reelsLoaded = true
                mergeReelsIntoProfileCache(items)
            }
            print("🎬 [FULL LOAD] Reels: \(items.count) items cached")
        } catch {
            print("⚠️ [FULL LOAD] Reels skipped: \(error)")
        }
    }

    private func loadTagged() async {
        let ig = InstagramService.shared
        guard ig.isLoggedIn, !ig.isLocked else { return }
        guard !ig.shouldUseCacheOnlyForOptionalCalls else {
            let rate = ig.checkRateLimit()
            print("🛡️ [FULL LOAD] Tagged skipped near rate budget (\(rate.actionsUsed)/55)")
            return
        }
        do {
            let items = try await withTimeout(seconds: 35) {
                try await ig.getUserTagged(amount: 18)
            }
            await MainActor.run {
                taggedLoaded = true
                mergeTaggedIntoProfileCache(items)
            }
            print("🏷️ [FULL LOAD] Tagged: \(items.count) items cached")
        } catch {
            print("⚠️ [FULL LOAD] Tagged skipped: \(error)")
        }
    }

    @MainActor
    private func mergeMediaPageIntoProfileCache(items: [InstagramMediaItem], nextCursor: String?) {
        guard !items.isEmpty else { return }
        let ig = InstagramService.shared
        let existing = ProfileCacheService.shared.loadProfile()
        var profile = existing ?? InstagramProfile(
            userId: ig.session.userId,
            username: ig.session.username,
            fullName: "",
            biography: "",
            externalUrl: nil,
            profilePicURL: "",
            isVerified: false,
            isPrivate: false,
            followerCount: 0,
            followingCount: 0,
            mediaCount: items.count,
            followedBy: [],
            isFollowing: false,
            isFollowRequested: false,
            cachedAt: Date(),
            cachedMediaURLs: [],
            cachedMediaItems: []
        )

        let existingIds = Set(profile.cachedMediaItems.map(\.mediaId))
        let freshItems = items.filter { !existingIds.contains($0.mediaId) }
        guard !freshItems.isEmpty || profile.cachedNextMaxId != nextCursor else { return }

        profile.cachedMediaItems += freshItems
        profile.cachedMediaURLs += freshItems.map { $0.imageURL }
        profile.cachedNextMaxId = nextCursor
        profile.cachedAt = Date()
        ProfileCacheService.shared.saveProfile(profile)
    }

    @MainActor
    private func mergeReelsIntoProfileCache(_ items: [InstagramMediaItem]) {
        guard var profile = ProfileCacheService.shared.loadProfile() else { return }
        profile.cachedReelItems = items
        profile.cachedReelURLs = items.map { $0.imageURL }
        profile.cachedAt = Date()
        ProfileCacheService.shared.saveProfile(profile)
    }

    @MainActor
    private func mergeTaggedIntoProfileCache(_ items: [InstagramMediaItem]) {
        guard var profile = ProfileCacheService.shared.loadProfile() else { return }
        profile.cachedTaggedURLs = items.map { $0.imageURL }
        profile.cachedAt = Date()
        ProfileCacheService.shared.saveProfile(profile)
    }

    // MARK: - Helpers

    private func setPhase(_ p: FullLoadPhase) {
        if Thread.isMainThread {
            phase = p
        } else {
            DispatchQueue.main.sync { self.phase = p }
        }
        defaults.set(p.rawValue, forKey: kPhase)
    }

    /// Reels/tagged are secondary cache warmups. They must not leave the
    /// Performance preparation overlay stuck if Instagram stalls mid-request.
    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw FullLoadTimeout.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func restorePersistedState() {
        if let raw = defaults.string(forKey: kPhase),
           let p = FullLoadPhase(rawValue: raw) {
            phase = p
        }
        gridPagesLoaded = defaults.integer(forKey: kGridPages)
        gridItemsLoaded = defaults.integer(forKey: kGridItems)
        print("🔁 [FULL LOAD] Restored state: phase=\(phase.rawValue) gridPages=\(gridPagesLoaded)")
    }
}
