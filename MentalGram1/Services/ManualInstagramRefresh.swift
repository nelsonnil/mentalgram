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
    static func run() async -> Result {
        let instagram = InstagramService.shared

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

            await syncActiveNote(instagram: instagram)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "perf_lastRefreshTimestamp")
            print("✅ [HEADLESS REFRESH] Completed — profile + note synced for @\(fetched.username)")
            LogManager.shared.info("Headless manual refresh completed for @\(fetched.username)", category: .general)
            return Result(success: true, message: nil, retrySeconds: nil)
        } catch {
            let raw = error.localizedDescription
            print("⚠️ [HEADLESS REFRESH] failed — \(raw)")
            LogManager.shared.warning("Headless manual refresh failed: \(raw)", category: .general)
            return Result(success: false, message: friendlyMessage(from: raw), retrySeconds: waitSeconds(from: raw))
        }
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
