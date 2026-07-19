import Foundation
import UIKit
import Combine

/// Stores the user's "real" Instagram profile picture, biography, and note so Vault can
/// detect when predictions changed them and offer a one-tap reset.
final class ProfileResetSettings: ObservableObject {
    static let shared = ProfileResetSettings()

    @Published private(set) var baselineBiography: String = ""
    @Published private(set) var baselineNote: String = ""
    @Published private(set) var baselineProfilePic: UIImage? = nil
    @Published private(set) var needsBioReset: Bool = false
    @Published private(set) var needsNoteReset: Bool = false
    @Published private(set) var needsProfilePicReset: Bool = false

    private let bioKey = "reset_baseline_biography"
    private let noteKey = "reset_baseline_note"
    private let picDataKey = "reset_baseline_profile_pic_data"
    private let picHashKey = "reset_baseline_profile_pic_hash"
    private let picEnabledKey = "reset_baseline_profile_pic_enabled"
    private let bioEnabledKey = "reset_baseline_bio_enabled"
    private let noteEnabledKey = "reset_baseline_note_enabled"

    private init() {
        reloadFromStorage()
        refreshDriftState()
    }

    var hasBaselineBio: Bool {
        UserDefaults.standard.bool(forKey: bioEnabledKey) && !baselineBiography.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasBaselineProfilePic: Bool {
        UserDefaults.standard.bool(forKey: picEnabledKey) && baselineProfilePic != nil
    }

    var hasBaselineNote: Bool {
        UserDefaults.standard.bool(forKey: noteEnabledKey) && !baselineNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAnyDrift: Bool {
        (hasBaselineBio && needsBioReset)
        || (hasBaselineNote && needsNoteReset)
        || (hasBaselineProfilePic && needsProfilePicReset)
    }

    // MARK: - Persistence

    func reloadFromStorage() {
        baselineBiography = UserDefaults.standard.string(forKey: bioKey) ?? ""
        baselineNote = UserDefaults.standard.string(forKey: noteKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: picDataKey) {
            baselineProfilePic = UIImage(data: data)
        } else {
            baselineProfilePic = nil
        }
    }

    func saveBaselineNote(_ text: String) {
        let trimmed = String(text.prefix(60))
        baselineNote = trimmed
        UserDefaults.standard.set(trimmed, forKey: noteKey)
        UserDefaults.standard.set(!trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, forKey: noteEnabledKey)
        refreshDriftState()
        print("🔄 [RESET] Baseline note saved (\(trimmed.count) chars)")
    }

    func clearBaselineNote() {
        baselineNote = ""
        UserDefaults.standard.removeObject(forKey: noteKey)
        UserDefaults.standard.set(false, forKey: noteEnabledKey)
        refreshDriftState()
    }

    func saveBaselineBiography(_ text: String) {
        let trimmed = String(text.prefix(150))
        baselineBiography = trimmed
        UserDefaults.standard.set(trimmed, forKey: bioKey)
        UserDefaults.standard.set(!trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, forKey: bioEnabledKey)
        refreshDriftState()
        print("🔄 [RESET] Baseline biography saved (\(trimmed.count) chars)")
    }

    func saveBaselineProfilePic(_ imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        let jpeg = image.jpegData(compressionQuality: 0.9) ?? imageData
        baselineProfilePic = UIImage(data: jpeg)
        UserDefaults.standard.set(jpeg, forKey: picDataKey)
        let hash = InstagramService.shared.hashImageData(jpeg)
        UserDefaults.standard.set(hash, forKey: picHashKey)
        UserDefaults.standard.set(true, forKey: picEnabledKey)
        refreshDriftState()
        print("🔄 [RESET] Baseline profile pic saved (\(jpeg.count / 1024) KB, hash=\(hash.prefix(8)))")
    }

    func clearBaselineBiography() {
        baselineBiography = ""
        UserDefaults.standard.removeObject(forKey: bioKey)
        UserDefaults.standard.set(false, forKey: bioEnabledKey)
        refreshDriftState()
    }

    func clearBaselineProfilePic() {
        baselineProfilePic = nil
        UserDefaults.standard.removeObject(forKey: picDataKey)
        UserDefaults.standard.removeObject(forKey: picHashKey)
        UserDefaults.standard.set(false, forKey: picEnabledKey)
        refreshDriftState()
    }

    // MARK: - Drift detection

    func refreshDriftState() {
        needsBioReset = evaluateBioDrift()
        needsNoteReset = evaluateNoteDrift()
        needsProfilePicReset = evaluateProfilePicDrift()
    }

    private func evaluateBioDrift() -> Bool {
        guard hasBaselineBio else { return false }
        let current = currentBiographyText()
        return normalizedBiography(current) != normalizedBiography(baselineBiography)
    }

    private func evaluateProfilePicDrift() -> Bool {
        guard hasBaselineProfilePic else { return false }
        // Photo was replaced in the real Instagram app (CDN asset path changed).
        if UserDefaults.standard.bool(forKey: "profile_pic_external_change") {
            return true
        }
        guard let baselineHash = UserDefaults.standard.string(forKey: picHashKey),
              !baselineHash.isEmpty else { return false }
        guard let currentHash = UserDefaults.standard.string(forKey: "last_profile_pic_hash"),
              !currentHash.isEmpty else { return false }
        return currentHash != baselineHash
    }

    private func evaluateNoteDrift() -> Bool {
        guard hasBaselineNote else { return false }
        let current = currentNoteText()
        return normalizedNote(current) != normalizedNote(baselineNote)
    }

    private func currentNoteText() -> String {
        if let last = UserDefaults.standard.string(forKey: "last_note_sent_text"),
           !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return last
        }
        return UserDefaults.standard.string(forKey: "last_note_text") ?? ""
    }

    private func normalizedNote(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentBiographyText() -> String {
        if let last = UserDefaults.standard.string(forKey: "last_biography_text"),
           !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return last
        }
        return ProfileCacheService.shared.cachedProfile?.biography ?? ""
    }

    private func normalizedBiography(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    // MARK: - Reset actions (respect Instagram safety/cooldowns)

    @discardableResult
    func resetNoteToBaseline() async throws -> Bool {
        guard hasBaselineNote else {
            throw InstagramError.apiError("No reset note configured in Settings.")
        }
        let text = baselineNote
        let ok = try await InstagramService.shared.createNote(text: text, userInitiated: true)
        if ok {
            await MainActor.run { refreshDriftState() }
            print("✅ [RESET] Note restored to baseline")
            LogManager.shared.info("Note reset to baseline", category: .general)
        }
        return ok
    }

    @discardableResult
    func resetBiographyToBaseline() async throws -> Bool {
        guard hasBaselineBio else {
            throw InstagramError.apiError("No reset biography configured in Settings.")
        }
        let text = baselineBiography
        // bypassCooldown=true: explicit user restore must never be blocked by anti-bot
        // cooldowns set by a previous automatic or performance-triggered biography change.
        // Lockdown (isLocked) is still respected.
        let ok = try await InstagramService.shared.changeBiography(text: text, userInitiated: true, bypassCooldown: true)
        if ok {
            await MainActor.run {
                if let current = ProfileCacheService.shared.cachedProfile {
                    let updated = profileWithBiography(current, biography: text)
                    ProfileCacheService.shared.saveProfile(updated)
                }
                refreshDriftState()
            }
            print("✅ [RESET] Biography restored to baseline")
            LogManager.shared.info("Biography reset to baseline", category: .general)
        }
        return ok
    }

    @discardableResult
    func resetProfilePicToBaseline() async throws -> Bool {
        guard hasBaselineProfilePic,
              let data = UserDefaults.standard.data(forKey: picDataKey) else {
            throw InstagramError.apiError("No reset profile picture configured in Settings.")
        }
        do {
            let ok = try await InstagramService.shared.changeProfilePicture(imageData: data, userInitiated: true)
            if ok, let image = UIImage(data: data) {
                await MainActor.run {
                    paintBaselineProfilePicLocally(image)
                    refreshDriftState()
                }
                print("✅ [RESET] Profile picture restored to baseline")
                LogManager.shared.info("Profile picture reset to baseline", category: .general)
            }
            return ok
        } catch {
            // Instagram already has this exact image — not a failure. Refresh local
            // display cache so Performance stops spinning on a rotated CDN URL.
            let message = error.localizedDescription.lowercased()
            if message.contains("already your profile picture") {
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        UserDefaults.standard.set(false, forKey: "profile_pic_external_change")
                        paintBaselineProfilePicLocally(image)
                        refreshDriftState()
                    }
                }
                print("✅ [RESET] Baseline already on Instagram — local profile pic cache refreshed")
                LogManager.shared.info("Reset profile pic skipped (already on Instagram); local cache refreshed", category: .general)
                return true
            }
            throw error
        }
    }

    /// Paints the baseline reset photo into Performance cache under the current CDN
    /// URL and the stable own-profile-pic disk key.
    @MainActor
    private func paintBaselineProfilePicLocally(_ image: UIImage) {
        ProfileCacheService.shared.pendingProfilePic = image
        if let url = ProfileCacheService.shared.cachedProfile?.profilePicURL, !url.isEmpty {
            ProfileCacheService.shared.saveOwnProfilePic(image, cdnURL: url)
            ProfileCacheService.shared.saveImage(image, forURL: url)
        } else {
            ProfileCacheService.shared.saveOwnProfilePic(image)
        }
    }
}

private func profileWithBiography(_ current: InstagramProfile, biography: String) -> InstagramProfile {
    InstagramProfile(
        userId: current.userId, username: current.username,
        fullName: current.fullName, biography: biography,
        externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
        isVerified: current.isVerified, isPrivate: current.isPrivate,
        followerCount: current.followerCount, followingCount: current.followingCount,
        mediaCount: current.mediaCount, followedBy: current.followedBy,
        isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
        cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
        cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
        cachedHighlights: current.cachedHighlights,
        cachedMediaItems: current.cachedMediaItems,
        cachedReelItems: current.cachedReelItems,
        cachedTaggedItems: current.cachedTaggedItems,
        cachedNextMaxId: current.cachedNextMaxId
    )
}
