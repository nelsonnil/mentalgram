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

    /// Master switch: enables the unarchiving reveal feature for all input methods.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "forceNumberRevealEnabled") }
    }

    /// Controls whether the digit grid swipe input is active.
    /// Requires `isEnabled = true` to trigger a reveal.
    @Published var gridSwipeEnabled: Bool {
        didSet { UserDefaults.standard.set(gridSwipeEnabled, forKey: "forceNumberRevealGridSwipeEnabled") }
    }

    /// When enabled, OCR camera starts on Performance open and auto-reveals
    /// the recognized word (word set) or number (number set).
    @Published var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrEnabled, forKey: "forceNumberRevealOcrEnabled") }
    }

    /// Runtime flag: set to `true` when a URL scheme reveal is pending so the
    /// OCR onChange handler skips the `ocrEnabled` guard for that single trigger.
    @Published var urlRevealActive: Bool = false

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

    // MARK: - Runtime state

    /// Tracks the pending re-archive task so it can be cancelled if a new reveal fires first
    private var reArchiveTask: Task<Void, Never>?
    /// Hard lock: prevents duplicate restored/scheduled tasks from archiving the
    /// same mediaIds in parallel after fast app resume/scene changes.
    private var isExecutingReArchive = false

    /// Prevents restoreIfNeeded from creating duplicate tasks when called
    /// multiple times (init + scenePhase .active + rapid app switches).
    private var restoreAlreadyScheduled = false

    /// When the scheduled re-archive will fire (used for UI countdown)
    @Published private(set) var reArchiveScheduledAt: Date? = nil

    // MARK: - Init

    private init() {
        isEnabled            = UserDefaults.standard.bool(forKey: "forceNumberRevealEnabled")
        gridSwipeEnabled     = UserDefaults.standard.bool(forKey: "forceNumberRevealGridSwipeEnabled")
        ocrEnabled           = UserDefaults.standard.bool(forKey: "forceNumberRevealOcrEnabled")
        autoReArchiveEnabled = UserDefaults.standard.bool(forKey: "forceNumberAutoReArchiveEnabled")
        let savedMinutes     = UserDefaults.standard.integer(forKey: "forceNumberAutoReArchiveMinutes")
        autoReArchiveMinutes = savedMinutes > 0 ? savedMinutes : 15
        // restoreIfNeeded is called from scenePhase .active on first launch — no need here
    }

    // MARK: - Schedule re-archive (call after successful reveal)

    /// Call after a successful reveal with the mediaIds that were unarchived.
    /// Schedules a re-archive after the configured delay, persisted to survive app restarts.
    func scheduleReArchive(mediaIds: [String]) {
        let mediaIds = uniqueMediaIds(mediaIds)
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
    /// Safe to call multiple times (init, scenePhase .active, rapid app switches) —
    /// double-guarded by both `restoreAlreadyScheduled` flag and `reArchiveTask != nil`.
    func restoreIfNeeded() {
        // Primary guard: flag prevents re-entry even on concurrent/rapid calls
        guard !restoreAlreadyScheduled, reArchiveTask == nil else {
            print("⏱️ [RE-ARCHIVE] restoreIfNeeded skipped (already scheduled or running)")
            return
        }

        guard let rawIds = UserDefaults.standard.stringArray(forKey: pendingIdsKey) else { return }
        let ids = uniqueMediaIds(rawIds)
        guard !ids.isEmpty else {
            clearPersisted()
            return
        }

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
        let ids = uniqueMediaIds(ids)
        guard !ids.isEmpty else {
            clearPersisted()
            return
        }
        restoreAlreadyScheduled = true  // block any further restoreIfNeeded calls
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
        UserDefaults.standard.set(uniqueMediaIds(ids), forKey: pendingIdsKey)
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

    private func mediaIdKey(_ mediaId: String) -> String {
        mediaId.split(separator: "_").first.map(String.init) ?? mediaId
    }

    private func uniqueMediaIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = mediaIdKey(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: pendingIdsKey)
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        restoreAlreadyScheduled = false  // allow future restores after a clean slate
        reArchiveTask = nil
    }

    @MainActor
    private func deferReArchiveForSafety(mediaIds: [String], minimumSeconds: Int, reason: String) {
        let seconds = max(60, minimumSeconds)
        let retryDate = Date().addingTimeInterval(TimeInterval(seconds))
        reArchiveScheduledAt = retryDate
        persistPending(ids: mediaIds, deadline: retryDate)
        scheduleTask(ids: mediaIds, afterSeconds: TimeInterval(seconds), deadline: retryDate)
        print("⏸️ [RE-ARCHIVE] Deferred \(seconds)s — \(reason)")
        LogManager.shared.warning("Auto re-archive deferred \(seconds)s: \(reason)", category: .upload)
    }

    // MARK: - Execute re-archive

    @MainActor
    private func executeReArchive(mediaIds: [String]) async {
        let mediaIds = uniqueMediaIds(mediaIds)
        guard !mediaIds.isEmpty else {
            clearPersisted()
            return
        }
        guard !isExecutingReArchive else {
            print("⏱️ [RE-ARCHIVE] Execution already active — ignoring duplicate trigger")
            LogManager.shared.warning("Auto re-archive duplicate trigger ignored", category: .upload)
            return
        }
        isExecutingReArchive = true
        defer { isExecutingReArchive = false }

        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        print("⏱️ [RE-ARCHIVE] ══════════════════════════════════════════")
        print("⏱️ [RE-ARCHIVE] Starting re-archive of \(mediaIds.count) photo(s)")
        LogManager.shared.info("Auto re-archive starting: \(mediaIds.count) photo(s)", category: .upload)

        reArchiveScheduledAt = nil

        // ── COLD-START / WARM-RESUME LOCK ─────────────────────────────────────
        // Restored auto tasks are invisible to the performer. If a pending deadline
        // lands during app launch / foreground warm-up, do NOT fire a POST. The
        // tester log showed POST /only_me/ inside cold-start, which can look like
        // bot activity because the user did not touch anything.
        if InstagramSafetyGate.shared.isInColdStartWindow {
            deferReArchiveForSafety(
                mediaIds: mediaIds,
                minimumSeconds: InstagramSafetyGate.shared.coldStartSecondsRemaining + Int.random(in: 25...45),
                reason: "cold-start/warm-resume active"
            )
            return
        }

        // ── SYNC & ARCHIVE LOCK ────────────────────────────────────────────────
        // Defer if user triggered a unified Sync & Archive operation to avoid parallel API calls.
        if UploadManager.shared.isSyncArchiveActive {
            print("⏸️ [RE-ARCHIVE] Sync & Archive is active — deferring auto re-archive by 5 min")
            LogManager.shared.warning("Auto re-archive deferred: Sync & Archive in progress", category: .upload)
            let retryDate = Date().addingTimeInterval(5 * 60)
            reArchiveScheduledAt = retryDate
            // BUG-FIX: Previously this branch only set the in-memory date and
            // returned. If the app was killed before the 5-min retry, the
            // re-archive job was silently lost. Persist + reschedule the task
            // so the retry actually fires after the deferral window.
            persistPending(ids: mediaIds, deadline: retryDate)
            scheduleTask(ids: mediaIds, afterSeconds: 5 * 60, deadline: retryDate)
            return
        }

        // ── UPLOAD LOCK ───────────────────────────────────────────────────────
        // Never mix auto re-archive with an active upload/auto-archive pipeline.
        // Both use sensitive POST /only_me/ calls and sharing the same session can
        // look like bot-like parallel mutation traffic to Instagram.
        if UploadManager.shared.activeTask != nil || UploadManager.shared.isUploading {
            print("⏸️ [RE-ARCHIVE] Upload is active — deferring auto re-archive by 5 min")
            LogManager.shared.warning("Auto re-archive deferred: upload in progress", category: .upload)
            let retryDate = Date().addingTimeInterval(5 * 60)
            reArchiveScheduledAt = retryDate
            persistPending(ids: mediaIds, deadline: retryDate)
            scheduleTask(ids: mediaIds, afterSeconds: 5 * 60, deadline: retryDate)
            return
        }

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

            if InstagramSafetyGate.shared.isInColdStartWindow {
                updatePersisted(remaining: remaining)
                deferReArchiveForSafety(
                    mediaIds: remaining,
                    minimumSeconds: InstagramSafetyGate.shared.coldStartSecondsRemaining + Int.random(in: 25...45),
                    reason: "cold-start/warm-resume became active mid-run"
                )
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

            let archiveSafety = InstagramSafetyGate.shared.canArchive(mediaId: mediaId)
            if !archiveSafety.allowed {
                print("🛡️ [RE-ARCHIVE] Safety pause — \(archiveSafety.reason), retry in \(archiveSafety.waitSeconds)s")
                LogManager.shared.warning("SAFETY BLOCK — auto re-archive postponed: \(archiveSafety.reason)", category: .upload)
                updatePersisted(remaining: remaining)
                let retryDate = Date().addingTimeInterval(TimeInterval(max(archiveSafety.waitSeconds, 60)))
                reArchiveScheduledAt = retryDate
                persistPending(ids: remaining, deadline: retryDate)
                scheduleTask(ids: remaining, afterSeconds: TimeInterval(max(archiveSafety.waitSeconds, 60)), deadline: retryDate)
                return
            }

            // Anti-bot: auto re-archive is not performer-visible. Use a much
            // slower human cadence than reveal calls to avoid POST bursts.
            let delay = UInt64.random(in: 35_000_000_000...70_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                updatePersisted(remaining: remaining)
                return
            }

            do {
                let archived = try await instagram.archivePhoto(mediaId: mediaId, skipPreCheck: true)
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
                    let key = mediaIdKey(mediaId)
                    remaining.removeAll { mediaIdKey($0) == key }
                    updatePersisted(remaining: remaining)
                    ProfileCacheService.shared.removeMediaEverywhere(mediaId: mediaId)
                    InstagramSafetyGate.shared.markPostMutationQuietWindow(action: .archive)

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
                let msg = error.localizedDescription.lowercased()
                if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                    UploadManager.shared.sendSessionExpiredNotification()
                }
            }
        }

        // ── DONE ───────────────────────────────────────────────────────────────
        clearPersisted()
        print("⏱️ [RE-ARCHIVE] ✅ Done — \(successCount) archived, \(failCount) failed")
        LogManager.shared.info("Auto re-archive complete: \(successCount) ok, \(failCount) failed", category: .upload)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
