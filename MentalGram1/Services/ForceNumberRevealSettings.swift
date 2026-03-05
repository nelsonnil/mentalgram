import Foundation
import Combine
import UIKit

/// Manages the "Force Number Reveal" feature including optional auto re-archive.
/// The pending re-archive is persisted to UserDefaults so it survives:
///   - App kill (iOS memory pressure)
///   - User force-quit
///   - App backgrounding + iOS suspend
///   - App crashes
/// On the next app launch it resumes from where it stopped, accounting for elapsed time.
class ForceNumberRevealSettings: ObservableObject {
    static let shared = ForceNumberRevealSettings()

    // MARK: - Persisted settings

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceNumberRevealEnabled") }
    }

    @Published var autoReArchiveEnabled: Bool {
        didSet { UserDefaults.standard.set(autoReArchiveEnabled, forKey: "forceNumberAutoReArchiveEnabled") }
    }

    /// Minutes to wait before auto re-archiving (5, 10, 15, 20, 30, 45, 60)
    @Published var autoReArchiveMinutes: Int {
        didSet { UserDefaults.standard.set(autoReArchiveMinutes, forKey: "forceNumberAutoReArchiveMinutes") }
    }

    static let timeOptions = [5, 10, 15, 20, 30, 45, 60]

    // MARK: - Persistence keys (surviving app kill / force-quit)

    private let pendingIdsKey  = "reArchive_pendingIds"
    private let deadlineKey    = "reArchive_deadline"
    private let maxOverdueSecs = 3600.0  // discard if overdue >1h

    // MARK: - Runtime state

    /// Tracks the pending re-archive task so it can be cancelled if a new reveal fires first
    private var reArchiveTask: Task<Void, Never>?

    /// When the scheduled re-archive will fire (used for UI countdown)
    @Published private(set) var reArchiveScheduledAt: Date? = nil

    // MARK: - Init

    private init() {
        isEnabled            = UserDefaults.standard.bool(forKey: "forceNumberRevealEnabled")
        autoReArchiveEnabled = UserDefaults.standard.bool(forKey: "forceNumberAutoReArchiveEnabled")
        let savedMinutes     = UserDefaults.standard.integer(forKey: "forceNumberAutoReArchiveMinutes")
        autoReArchiveMinutes = savedMinutes > 0 ? savedMinutes : 15

        // Restore any interrupted re-archive from a previous session
        restoreIfNeeded()
    }

    // MARK: - Schedule re-archive (call after successful reveal)

    /// Call after a successful reveal with the mediaIds that were unarchived.
    /// Schedules a re-archive after the configured delay, persisted to survive app restarts.
    func scheduleReArchive(mediaIds: [String]) {
        guard autoReArchiveEnabled, !mediaIds.isEmpty else { return }

        // Cancel any previous pending re-archive
        reArchiveTask?.cancel()

        let fireDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
        reArchiveScheduledAt = fireDate

        // Persist so it survives app kill / force-quit
        persistPending(ids: mediaIds, deadline: fireDate)

        print("⏱️ [RE-ARCHIVE] Scheduled \(mediaIds.count) photo(s) in \(autoReArchiveMinutes) min (persisted)")
        LogManager.shared.info("Auto re-archive scheduled: \(mediaIds.count) photo(s) in \(autoReArchiveMinutes) min", category: .upload)

        scheduleTask(ids: mediaIds, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: fireDate)
    }

    // MARK: - Cancel

    func cancelPendingReArchive() {
        reArchiveTask?.cancel()
        reArchiveTask = nil
        reArchiveScheduledAt = nil
        clearPersisted()
        print("⏱️ [RE-ARCHIVE] Pending re-archive cancelled + persisted state cleared")
    }

    // MARK: - Restore after app restart / wake from kill

    /// Checks if there was an interrupted re-archive and resumes it.
    /// Safe to call multiple times — exits immediately if a task is already running.
    func restoreIfNeeded() {
        // Prevent double-restore: if a task is already scheduled/running, do nothing
        guard reArchiveTask == nil else {
            print("⏱️ [RE-ARCHIVE] restoreIfNeeded: task already active — skipping duplicate call")
            return
        }

        guard let ids = UserDefaults.standard.stringArray(forKey: pendingIdsKey),
              !ids.isEmpty else { return }

        let rawDeadline = UserDefaults.standard.double(forKey: deadlineKey)
        guard rawDeadline > 0 else { clearPersisted(); return }

        let fireDate = Date(timeIntervalSinceReferenceDate: rawDeadline)
        let now = Date()
        let overdue = now.timeIntervalSince(fireDate)

        if fireDate > now {
            // Deadline still in the future — resume countdown for remaining time
            let remaining = fireDate.timeIntervalSince(now)
            print("⏱️ [RE-ARCHIVE] Restored: \(ids.count) photo(s), fires in \(Int(remaining))s")
            LogManager.shared.info("Auto re-archive restored: \(ids.count) photo(s), \(Int(remaining))s remaining", category: .upload)
            reArchiveScheduledAt = fireDate
            scheduleTask(ids: ids, afterSeconds: remaining, deadline: fireDate)

        } else if overdue < maxOverdueStecs {
            // Deadline just passed (< 1h ago) — fire with a short grace delay for session warmup
            let grace = 30.0
            print("⏱️ [RE-ARCHIVE] Restored: \(ids.count) photo(s) overdue by \(Int(overdue))s — firing in \(Int(grace))s")
            LogManager.shared.info("Auto re-archive restored (overdue \(Int(overdue))s): firing in \(Int(grace))s", category: .upload)
            let newFireDate = Date().addingTimeInterval(grace)
            reArchiveScheduledAt = newFireDate
            persistPending(ids: ids, deadline: newFireDate) // update deadline
            scheduleTask(ids: ids, afterSeconds: grace, deadline: newFireDate)

        } else {
            // Way overdue — too risky to fire now, discard
            print("⏱️ [RE-ARCHIVE] Restored: deadline passed \(Int(overdue / 60)) min ago — discarding (too old)")
            LogManager.shared.warning("Auto re-archive discarded: overdue \(Int(overdue / 60)) min", category: .upload)
            clearPersisted()
        }
    }

    // MARK: - Internal helpers

    private var maxOverdueStecs: TimeInterval { maxOverdueStecs_ }
    private let maxOverdueStecs_: TimeInterval = 3600.0

    private func scheduleTask(ids: [String], afterSeconds: TimeInterval, deadline: Date) {
        reArchiveTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0, afterSeconds) * 1_000_000_000))
            guard !Task.isCancelled else {
                print("⏱️ [RE-ARCHIVE] Task cancelled before execution")
                return
            }
            await self.executeReArchive(mediaIds: ids)
        }
    }

    private func persistPending(ids: [String], deadline: Date) {
        UserDefaults.standard.set(ids, forKey: pendingIdsKey)
        UserDefaults.standard.set(deadline.timeIntervalSinceReferenceDate, forKey: deadlineKey)
    }

    private func updatePersisted(remaining: [String]) {
        if remaining.isEmpty {
            clearPersisted()
        } else {
            UserDefaults.standard.set(remaining, forKey: pendingIdsKey)
            // Deadline stays the same — just fewer IDs to process
        }
    }

    private func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: pendingIdsKey)
        UserDefaults.standard.removeObject(forKey: deadlineKey)
    }

    // MARK: - Execute re-archive

    @MainActor
    private func executeReArchive(mediaIds: [String]) async {
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        print("⏱️ [RE-ARCHIVE] ══════════════════════════════════════════")
        print("⏱️ [RE-ARCHIVE] Starting re-archive of \(mediaIds.count) photo(s)")
        LogManager.shared.info("Auto re-archive starting: \(mediaIds.count) photo(s)", category: .upload)

        reArchiveScheduledAt = nil

        // ── SESSION CHECK ──────────────────────────────────────────────────────
        guard instagram.isLoggedIn else {
            print("⚠️ [RE-ARCHIVE] Session not active — persisting and skipping until next launch")
            LogManager.shared.warning("Auto re-archive deferred: session not active", category: .upload)
            // Keep persisted — will retry on next launch
            let retryDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
            reArchiveScheduledAt = retryDate
            persistPending(ids: mediaIds, deadline: retryDate)
            scheduleTask(ids: mediaIds, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: retryDate)
            return
        }

        // ── LOCKDOWN CHECK ────────────────────────────────────────────────────
        if instagram.isLocked {
            print("🚨 [RE-ARCHIVE] Instagram lockdown active — retrying in \(autoReArchiveMinutes) min")
            LogManager.shared.warning("Auto re-archive deferred: lockdown active", category: .upload)
            let retryDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
            reArchiveScheduledAt = retryDate
            persistPending(ids: mediaIds, deadline: retryDate)
            scheduleTask(ids: mediaIds, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: retryDate)
            return
        }

        // ── RATE LIMIT GUARD ─────────────────────────────────────────────────
        let rateCheck = instagram.checkRateLimit()
        let needed = mediaIds.count + 3
        if rateCheck.remaining < needed {
            let postponeMin = autoReArchiveMinutes
            print("⚠️ [RE-ARCHIVE] Rate limit too low (\(rateCheck.remaining) remaining, need \(needed)) — postponing \(postponeMin) min")
            LogManager.shared.warning(
                "Auto re-archive postponed: \(rateCheck.remaining) actions remaining (need \(needed)) — retry in \(postponeMin) min",
                category: .upload
            )
            let retryDate = Date().addingTimeInterval(Double(postponeMin) * 60)
            reArchiveScheduledAt = retryDate
            persistPending(ids: mediaIds, deadline: retryDate)
            scheduleTask(ids: mediaIds, afterSeconds: Double(postponeMin) * 60, deadline: retryDate)
            return
        }

        // ── EXECUTE ────────────────────────────────────────────────────────────
        // Work on a mutable copy so we can track remaining IDs
        var remaining = mediaIds
        var successCount = 0
        var failCount    = 0

        for mediaId in mediaIds {
            // Re-check session (could expire mid-run)
            guard instagram.isLoggedIn else {
                print("⚠️ [RE-ARCHIVE] Session expired mid-run — saving \(remaining.count) remaining IDs")
                LogManager.shared.warning("Auto re-archive interrupted: session expired. \(remaining.count) IDs saved.", category: .upload)
                updatePersisted(remaining: remaining)
                let retryDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
                reArchiveScheduledAt = retryDate
                scheduleTask(ids: remaining, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: retryDate)
                return
            }

            // Re-check lockdown
            guard !instagram.isLocked else {
                print("🚨 [RE-ARCHIVE] Lockdown activated mid-run — saving \(remaining.count) remaining IDs")
                LogManager.shared.warning("Auto re-archive interrupted: lockdown. \(remaining.count) IDs saved.", category: .upload)
                updatePersisted(remaining: remaining)
                let retryDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
                reArchiveScheduledAt = retryDate
                scheduleTask(ids: remaining, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: retryDate)
                return
            }

            guard !Task.isCancelled else {
                print("⏱️ [RE-ARCHIVE] Task cancelled mid-run — saving \(remaining.count) remaining IDs")
                updatePersisted(remaining: remaining)
                return
            }

            // Re-check rate limit before each call
            let midCheck = instagram.checkRateLimit()
            if midCheck.remaining < 2 {
                print("⚠️ [RE-ARCHIVE] Rate limit reached mid-run — saving \(remaining.count) remaining IDs")
                LogManager.shared.warning("Auto re-archive paused mid-run: rate limit. \(remaining.count) IDs saved.", category: .upload)
                updatePersisted(remaining: remaining)
                let retryDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
                reArchiveScheduledAt = retryDate
                scheduleTask(ids: remaining, afterSeconds: Double(autoReArchiveMinutes) * 60, deadline: retryDate)
                return
            }

            // Anti-bot: random human-like delay between each call
            let delay = UInt64.random(in: 800_000_000...2_200_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                updatePersisted(remaining: remaining)
                return
            }

            do {
                let archived = try await instagram.archivePhoto(mediaId: mediaId)
                if archived {
                    // Update local state
                    for set in dataManager.sets {
                        if let photo = set.photos.first(where: { $0.mediaId == mediaId }) {
                            dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                                    isArchived: true, uploadStatus: .completed,
                                                    errorMessage: nil)
                            break
                        }
                    }
                    // Remove from remaining and update persisted IDs (partial progress saved)
                    remaining.removeAll { $0 == mediaId }
                    updatePersisted(remaining: remaining)

                    print("✅ [RE-ARCHIVE] Re-archived (\(mediaId)) — \(remaining.count) remaining")
                    LogManager.shared.success("Auto re-archived (\(mediaId))", category: .upload)
                    successCount += 1
                } else {
                    print("⚠️ [RE-ARCHIVE] Archive returned false (\(mediaId))")
                    failCount += 1
                }
            } catch {
                print("❌ [RE-ARCHIVE] Error (\(mediaId)): \(error)")
                LogManager.shared.error("Auto re-archive error (\(mediaId)): \(error.localizedDescription)", category: .upload)
                failCount += 1
            }
        }

        // ── DONE ───────────────────────────────────────────────────────────────
        clearPersisted()
        print("⏱️ [RE-ARCHIVE] ✅ Done — \(successCount) archived, \(failCount) failed")
        LogManager.shared.info("Auto re-archive complete: \(successCount) ok, \(failCount) failed", category: .upload)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
