import Foundation
import Combine
import UIKit

/// Manages the "Force Number Reveal" feature including optional auto re-archive.
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

    // MARK: - Runtime state

    /// Tracks the pending re-archive task so it can be cancelled if a new reveal fires first
    private var reArchiveTask: Task<Void, Never>?

    /// When the scheduled re-archive will fire (used for UI countdown, optional)
    @Published private(set) var reArchiveScheduledAt: Date? = nil

    private init() {
        isEnabled              = UserDefaults.standard.bool(forKey: "forceNumberRevealEnabled")
        autoReArchiveEnabled   = UserDefaults.standard.bool(forKey: "forceNumberAutoReArchiveEnabled")
        let savedMinutes       = UserDefaults.standard.integer(forKey: "forceNumberAutoReArchiveMinutes")
        autoReArchiveMinutes   = savedMinutes > 0 ? savedMinutes : 15
    }

    // MARK: - Schedule re-archive

    /// Call this after a successful reveal with the mediaIds that were unarchived.
    /// If auto re-archive is enabled, waits the configured time then re-archives each one
    /// sequentially with random anti-bot delays.
    func scheduleReArchive(mediaIds: [String]) {
        guard autoReArchiveEnabled, !mediaIds.isEmpty else { return }

        // Cancel any previous pending re-archive
        reArchiveTask?.cancel()

        let fireDate = Date().addingTimeInterval(Double(autoReArchiveMinutes) * 60)
        reArchiveScheduledAt = fireDate

        print("⏱️ [RE-ARCHIVE] Scheduled re-archive of \(mediaIds.count) photo(s) in \(autoReArchiveMinutes) min")
        LogManager.shared.info("Auto re-archive scheduled: \(mediaIds.count) photo(s) in \(autoReArchiveMinutes) min", category: .upload)

        reArchiveTask = Task.detached(priority: .background) { [weak self, autoReArchiveMinutes] in
            guard let self else { return }

            // Wait for the configured duration
            let nanoseconds = UInt64(autoReArchiveMinutes) * 60 * 1_000_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                print("⏱️ [RE-ARCHIVE] Task cancelled before execution")
                return
            }

            await self.executeReArchive(mediaIds: mediaIds)
        }
    }

    /// Cancel any pending re-archive (e.g. if the user triggers a new reveal)
    func cancelPendingReArchive() {
        reArchiveTask?.cancel()
        reArchiveTask = nil
        reArchiveScheduledAt = nil
        print("⏱️ [RE-ARCHIVE] Pending re-archive cancelled")
    }

    // MARK: - Execute re-archive

    @MainActor
    private func executeReArchive(mediaIds: [String]) async {
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        print("⏱️ [RE-ARCHIVE] ═══════════════════════════════════════")
        print("⏱️ [RE-ARCHIVE] Starting re-archive of \(mediaIds.count) photo(s)")
        LogManager.shared.info("Auto re-archive starting: \(mediaIds.count) photo(s)", category: .upload)

        reArchiveScheduledAt = nil

        // RATE LIMIT GUARD: ensure we have enough budget before starting.
        // Each archive call uses 1 action. Reserve 3 extra as safety margin.
        let rateCheck = instagram.checkRateLimit()
        let needed = mediaIds.count + 3
        if rateCheck.remaining < needed {
            let postponeMin = autoReArchiveMinutes
            print("⚠️ [RE-ARCHIVE] Rate limit too low (\(rateCheck.remaining) remaining, need \(needed)) — postponing \(postponeMin) min")
            LogManager.shared.warning(
                "Auto re-archive postponed: only \(rateCheck.remaining) actions remaining (need \(needed)) — rescheduling in \(postponeMin) min",
                category: .upload
            )
            let fireDate = Date().addingTimeInterval(Double(postponeMin) * 60)
            reArchiveScheduledAt = fireDate
            reArchiveTask = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                let ns = UInt64(postponeMin) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                await self.executeReArchive(mediaIds: mediaIds)
            }
            return
        }

        var successCount = 0
        var failCount    = 0

        for mediaId in mediaIds {
            // Respect lockdown
            guard !instagram.isLocked else {
                print("🚨 [RE-ARCHIVE] Lockdown active — stopping")
                break
            }
            guard !Task.isCancelled else { break }

            // Re-check rate limit before each individual call (operations take time)
            let midCheck = instagram.checkRateLimit()
            if midCheck.remaining < 2 {
                print("⚠️ [RE-ARCHIVE] Rate limit reached mid-operation — stopping (will retry remaining \(mediaIds.count - successCount - failCount) later)")
                LogManager.shared.warning("Re-archive stopped mid-run: rate limit reached", category: .upload)
                break
            }

            // Anti-bot: random human-like delay between each archive call
            let delay = UInt64.random(in: 800_000_000...2_200_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { break }

            do {
                let archived = try await instagram.archivePhoto(mediaId: mediaId)
                if archived {
                    // Update local state: find photo by mediaId and mark as archived
                    for set in dataManager.sets {
                        if let photo = set.photos.first(where: { $0.mediaId == mediaId }) {
                            dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                                    isArchived: true, uploadStatus: .completed,
                                                    errorMessage: nil)
                            break
                        }
                    }
                    print("✅ [RE-ARCHIVE] Re-archived (ID: \(mediaId))")
                    LogManager.shared.success("Auto re-archived (ID: \(mediaId))", category: .upload)
                    successCount += 1
                } else {
                    print("⚠️ [RE-ARCHIVE] Archive returned false (ID: \(mediaId))")
                    failCount += 1
                }
            } catch {
                print("❌ [RE-ARCHIVE] Error (ID: \(mediaId)): \(error)")
                LogManager.shared.error("Auto re-archive error (ID: \(mediaId)): \(error.localizedDescription)", category: .upload)
                failCount += 1
            }
        }

        print("⏱️ [RE-ARCHIVE] Done — \(successCount) ok, \(failCount) failed")
        // Subtle haptic to confirm completion (magician only feels it)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
