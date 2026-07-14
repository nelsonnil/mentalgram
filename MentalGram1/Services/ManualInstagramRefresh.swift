import Foundation

/// Headless "Refresh from Instagram" used as a fallback when `PerformanceView` is
/// not mounted/subscribed (e.g. the user taps the button from Settings/Sets before
/// ever opening the Performance tab in this session).
///
/// The rich, reveal-aware refresh lives inside `PerformanceView` and runs whenever
/// that view is on screen. This service does NOT try to duplicate the reveal
/// reconciliation — it performs the safe data refresh (profile + note + gate reset)
/// and lets `PerformanceView` reconcile reveal overlays from the persisted
/// `reveal_state` the next time it paints. Its only job is to guarantee the cache is
/// updated even when no live listener exists, so the sync button is never a no-op.
@MainActor
enum ManualInstagramRefresh {

    struct Result {
        let success: Bool
        let message: String?
        let retrySeconds: Int?
    }

    /// Performs a headless refresh. Returns a typed result with a user-facing reason
    /// on failure so the button can show exactly why (cooldown seconds, budget, etc.)
    /// instead of a generic "Sync failed".
    ///
    /// - Parameter postPages: Number of post pages to fetch (1 = first page only,
    ///   2 = first + one extra, etc.). Pages 2+ are fetched with anti-bot pacing.
    static func run(postPages: Int = 1, repairMode: Bool = false) async -> Result {
        let instagram = InstagramService.shared
        let clampedPages = max(1, postPages)

        // ── Up-front guards (mirror PerformanceView's manual_remote guards) ──────
        guard instagram.isLoggedIn else {
            return Result(success: false, message: "Not logged in to Instagram", retrySeconds: nil)
        }
        if PostPredictionTestMode.shared.isActive {
            return Result(success: false, message: "Refresh disabled in test mode", retrySeconds: nil)
        }
        if instagram.isRevealOperationActive {
            return Result(success: false, message: "Reveal in progress — try again in a moment", retrySeconds: nil)
        }
        if instagram.isUploadingProfilePic {
            return Result(success: false, message: "Profile photo update in progress", retrySeconds: nil)
        }
        if instagram.isLocked || instagram.isSessionChallenged {
            return Result(success: false, message: "Instagram needs attention in the official app, then try again", retrySeconds: nil)
        }
        if instagram.shouldUseCacheOnlyForOptionalCalls {
            let rate = instagram.checkRateLimit()
            return Result(success: false,
                          message: "Instagram cooldown: API budget is low (\(rate.actionsUsed)/55 used). Try later.",
                          retrySeconds: nil)
        }

        let decision = InstagramSafetyGate.shared.decision(for: .pullRefresh)
        guard decision.allowed else {
            print("🛡️ [HEADLESS REFRESH] blocked — \(decision.reason) (\(decision.waitSeconds)s)")
            LogManager.shared.warning("Headless manual refresh blocked: \(decision.reason)", category: .general)
            return Result(success: false,
                          message: "Instagram cooldown: \(decision.reason). Wait \(decision.waitSeconds)s.",
                          retrySeconds: decision.waitSeconds)
        }
        InstagramSafetyGate.shared.record(.pullRefresh)

        do {
            try await instagram.waitForNetworkStability()
            let previousProfile: InstagramProfile?
            if repairMode {
                ProfileCacheService.shared.preparePublicReplicaRebuild()
                previousProfile = nil
                print("🧹 [HEADLESS REPAIR] Public replica cleared before rebuild")
            } else {
                previousProfile = ProfileCacheService.shared.loadProfile()
            }
            guard let fetched = try await instagram.getProfileInfo() else {
                LogManager.shared.error("Headless manual refresh: getProfileInfo returned nil", category: .general)
                return Result(success: false, message: "Instagram did not return profile data. Try again.", retrySeconds: nil)
            }

            // getProfileInfo() already persisted the merged profile (fresh first page +
            // preserved tail) to disk. Reset the secondary-surface gates so any newly
            // added reels/tagged/highlights or extra posts get re-discovered next entry.
            let uid = fetched.userId
            if !uid.isEmpty {
                UserDefaults.standard.removeObject(forKey: "highlights_checked_at_\(uid)")
                UserDefaults.standard.removeObject(forKey: "reels_checked_at_\(uid)")
                UserDefaults.standard.removeObject(forKey: "tagged_checked_at_\(uid)")
                UserDefaults.standard.removeObject(forKey: "perf_no_more_pages_\(uid)")
            }

            if let previousProfile, previousProfile.userId == uid {
                let previousItemsByURL = previousProfile.cachedMediaItems.reduce(into: [String: InstagramMediaItem]()) {
                    $0[$1.imageURL] = $1
                }
                let page1Ids = Set(fetched.cachedMediaItems.map { $0.mediaId })
                let page1Result = ProfileMediaReconciler.applyAuthoritativePageRange(
                    currentURLs: previousProfile.cachedMediaURLs,
                    currentItemsByURL: previousItemsByURL,
                    freshItems: fetched.cachedMediaItems,
                    startCursor: nil,
                    endCursor: fetched.cachedNextMaxId,
                    protectedMediaIds: page1Ids
                )
                var authoritative = fetched
                authoritative.cachedMediaURLs = page1Result.urls
                authoritative.cachedMediaItems = page1Result.urls.compactMap { page1Result.itemsByURL[$0] }
                authoritative.cachedNextMaxId = fetched.cachedNextMaxId
                ProfileCacheService.shared.saveProfileAuthoritative(authoritative)
                print("🧭 [HEADLESS REFRESH] Page 1 reconciled — +\(page1Result.appendedCount), -\(page1Result.removedCount), url↻\(page1Result.replacedURLCount)")
            } else {
                ProfileCacheService.shared.saveProfileAuthoritative(fetched)
            }

            // ── Extra-page deep refresh ───────────────────────────────────────────
            if clampedPages > 1, !uid.isEmpty {
                let page1Ids = Set(fetched.cachedMediaItems.map { $0.mediaId })
                await fetchExtraPages(
                    instagram: instagram,
                    userId: uid,
                    firstProfile: fetched,
                    page1MediaIds: page1Ids,
                    pagesToFetch: clampedPages - 1
                )
            }

            if repairMode, !uid.isEmpty, let rebuilt = ProfileCacheService.shared.loadProfile() {
                let required = ProfileCacheService.shared.requiredPerformancePreloadPosts(for: rebuilt)
                let complete = rebuilt.cachedMediaURLs.count >= required || rebuilt.cachedNextMaxId == nil
                UserDefaults.standard.set(complete, forKey: "perf_fully_preloaded_\(uid)")
                ProfileCacheService.shared.recordPerformancePreloadExit(
                    reason: complete ? "headless_repair_complete" : "headless_repair_partial",
                    userId: uid,
                    cachedCount: rebuilt.cachedMediaURLs.count,
                    requiredCount: required,
                    context: "headless_manual_repair"
                )
            } else if !uid.isEmpty {
                UserDefaults.standard.set(true, forKey: "perf_manual_depth_synced_\(uid)")
            }

            await syncActiveNote(instagram: instagram)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "perf_lastRefreshTimestamp")
            print("✅ [HEADLESS REFRESH] Completed — profile + note synced for @\(fetched.username) (pages=\(clampedPages), repair=\(repairMode))")
            LogManager.shared.info("Headless manual refresh completed for @\(fetched.username) (pages=\(clampedPages), repair=\(repairMode))", category: .general)
            return Result(success: true, message: nil, retrySeconds: nil)
        } catch {
            let raw = error.localizedDescription
            print("⚠️ [HEADLESS REFRESH] failed — \(raw)")
            LogManager.shared.warning("Headless manual refresh failed: \(raw)", category: .general)
            return Result(success: false, message: friendlyMessage(from: raw), retrySeconds: waitSeconds(from: raw))
        }
    }

    /// Fetches additional post pages and applies them authoritatively to the on-disk
    /// profile cache.  Posts that were in the cached tail but are NOT returned by
    /// Instagram for their chronological range (i.e. deleted/archived) are removed.
    /// The safety gate is waited out (up to 30 s) instead of immediately failing.
    private static func fetchExtraPages(
        instagram: InstagramService,
        userId: String,
        firstProfile: InstagramProfile,
        page1MediaIds: Set<String>,
        pagesToFetch: Int
    ) async {
        guard pagesToFetch > 0 else { return }

        var cursor = firstProfile.cachedNextMaxId
        var fetchedCount = 0

        guard var cached = ProfileCacheService.shared.loadProfile(), cached.userId == userId else { return }

        for _ in 0..<pagesToFetch {
            guard let activeCursor = cursor, !activeCursor.isEmpty else {
                print("📄 [HEADLESS EXTRA] No cursor — stopping at page \(fetchedCount + 1)")
                break
            }

            // ── Safety gate with patient wait (mirrors PerformanceView logic) ────
            let gateMaxWaitNs: UInt64 = 30_000_000_000
            var gateWaited: UInt64 = 0
            var gate = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
            while !gate.allowed, gateWaited < gateMaxWaitNs {
                let sliceNs: UInt64 = 2_000_000_000
                print("⏳ [HEADLESS EXTRA] Gate blocked (\(gate.reason)) — waiting 2s…")
                try? await Task.sleep(nanoseconds: sliceNs)
                gateWaited += sliceNs
                gate = InstagramSafetyGate.shared.decision(for: .ownProfilePagination)
            }
            guard gate.allowed else {
                print("🛡️ [HEADLESS EXTRA] Gate timed out — stopping after \(fetchedCount) page(s)")
                LogManager.shared.warning("Headless extra-page gate timed out", category: .general)
                break
            }
            InstagramSafetyGate.shared.record(.ownProfilePagination)

            let humanDelay = UInt64.random(in: 1_500_000_000...2_800_000_000)
            try? await Task.sleep(nanoseconds: humanDelay)

            do {
                let (newItems, newCursor) = try await instagram.getUserMediaItems(
                    userId: userId,
                    amount: 18,
                    maxId: activeCursor
                )
                guard !newItems.isEmpty else {
                    print("📄 [HEADLESS EXTRA] Empty page — no more posts")
                    break
                }

                fetchedCount += 1
                cursor = newCursor

                let itemsByURL = cached.cachedMediaItems.reduce(into: [String: InstagramMediaItem]()) {
                    $0[$1.imageURL] = $1
                }
                let pageResult = ProfileMediaReconciler.applyAuthoritativePageRange(
                    currentURLs: cached.cachedMediaURLs,
                    currentItemsByURL: itemsByURL,
                    freshItems: newItems,
                    startCursor: activeCursor,
                    endCursor: newCursor,
                    protectedMediaIds: page1MediaIds
                )
                cached.cachedMediaURLs = pageResult.urls
                cached.cachedMediaItems = pageResult.urls.compactMap { pageResult.itemsByURL[$0] }
                cached.cachedNextMaxId = newCursor
                ProfileCacheService.shared.saveProfileAuthoritative(cached)

                print("📄 [HEADLESS EXTRA] Page \(fetchedCount + 1): +\(pageResult.appendedCount) new, -\(pageResult.removedCount) deleted, url↻\(pageResult.replacedURLCount)")
                LogManager.shared.info("Headless extra page \(fetchedCount + 1): +\(pageResult.appendedCount) new, -\(pageResult.removedCount) deleted", category: .general)
            } catch {
                print("⚠️ [HEADLESS EXTRA] Page fetch failed: \(error.localizedDescription)")
                LogManager.shared.warning("Headless extra page failed: \(error.localizedDescription)", category: .general)
                break
            }
        }

        print("📄 [HEADLESS EXTRA] Done — fetched \(fetchedCount) extra page(s)")
    }

    /// Reads the active own-note from Instagram and mirrors it into the same
    /// UserDefaults keys `PerformanceView` uses, so the note bubble is correct on the
    /// next paint. Mirrors `syncCurrentNoteFromInstagramAfterManualRefresh`.
    private static func syncActiveNote(instagram: InstagramService) async {
        guard !instagram.isLocked,
              !instagram.isSessionChallenged,
              !instagram.shouldUseCacheOnlyForOptionalCalls,
              !InstagramSafetyGate.shared.isInColdStartWindow else {
            print("📝 [HEADLESS NOTE] skipped — safety/session guard")
            return
        }
        do {
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_400_000_000...2_400_000_000))
            let remoteNote = try await instagram.getCurrentNoteText()
            if let remoteNote, !remoteNote.isEmpty {
                UserDefaults.standard.set(remoteNote, forKey: "last_note_text")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_note_sent_timestamp")
                UserDefaults.standard.set(remoteNote, forKey: "last_note_sent_text")
                print("📝 [HEADLESS NOTE] Refreshed active Instagram note")
            } else {
                UserDefaults.standard.set("", forKey: "last_note_text")
                UserDefaults.standard.set(0.0, forKey: "last_note_sent_timestamp")
                UserDefaults.standard.removeObject(forKey: "last_note_sent_text")
                UserDefaults.standard.removeObject(forKey: "note_duplicate_warning_text")
                print("📝 [HEADLESS NOTE] No active Instagram note — local bubble cleared")
            }
        } catch {
            // Only a successful read that finds no note clears the bubble; on failure
            // keep the local state untouched.
            print("⚠️ [HEADLESS NOTE] refresh failed — keeping local state: \(error.localizedDescription)")
        }
    }

    private static func waitSeconds(from message: String) -> Int? {
        let pattern = #"Wait\s+(\d+)s"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, options: [], range: range),
              match.numberOfRanges > 1,
              let secondsRange = Range(match.range(at: 1), in: message) else { return nil }
        return Int(message[secondsRange])
    }

    private static func friendlyMessage(from message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("cancel") {
            return "Network interrupted. Try again."
        }
        if lower.contains("cooldown") || lower.contains("wait") || lower.contains("budget") {
            return message
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("connection") || lower.contains("timed out") {
            return "No internet connection. Check your network and try again."
        }
        return "Couldn't reach Instagram. Try again."
    }
}
