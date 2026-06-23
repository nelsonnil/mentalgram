import Foundation
import UIKit
import Combine

/// Service to cache Instagram profile data and images.
/// ObservableObject so PerformanceView can react to local updates without extra API calls.
class ProfileCacheService: ObservableObject {
    static let shared = ProfileCacheService()

    /// In-memory copy of the cached profile.
    /// Updated whenever saveProfile / updateMediaURLs is called.
    @Published private(set) var cachedProfile: InstagramProfile?

    /// Local UIImage set immediately after a successful profile-picture upload.
    /// PerformanceView observes this to show the new pic instantly, without waiting
    /// for Instagram to return the new CDN URL on the next profile refresh.
    /// Cleared automatically once a real profile refresh completes.
    @Published var pendingProfilePic: UIImage?

    private let fileManager = FileManager.default

    /// Where `profile.json` lives. We use `Application Support/` because iOS
    /// guarantees it is NOT purged by the system under low-disk pressure.
    /// Loosing a user's cached profile-header forces a heavy re-fetch (followers,
    /// grid, reels, tagged, highlights) which counts against the safety budget
    /// and shows an empty header in the Performance view for several minutes.
    private let profileDirectory: URL

    /// Legacy Caches location kept only for one-shot migration/cleanup.
    /// Current thumbnails live under `profileDirectory/<userId>/images` in
    /// Application Support so Performance visuals survive iOS cache purges.
    private let imageDirectory: URL

    private init() {
        let supportPaths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        profileDirectory = supportPaths[0].appendingPathComponent("ProfileCache", isDirectory: true)

        // imageDirectory kept for the one-shot migration below; images now live
        // inside profileDirectory (Application Support) so iOS never purges them.
        let cachesPaths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        imageDirectory = cachesPaths[0].appendingPathComponent("ProfileCache", isDirectory: true)

        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        // Exclude from iCloud/iTunes backup — rebuildable data.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = profileDirectory
        try? url.setResourceValues(values)

        migrateLegacyProfilesFromCachesIfNeeded()
        migrateImagesToAppSupportIfNeeded()

        // Warm the in-memory copy from disk on launch.
        cachedProfile = loadProfile()
    }

    /// One-time migration: move existing `.jpg` thumbnails from `Caches/ProfileCache/`
    /// into `Application Support/ProfileCache/<userId>/images/` so they are never
    /// purged by iOS under low-disk pressure.
    private func migrateImagesToAppSupportIfNeeded() {
        let migrationKey = "profileImagesCacheMigrated_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        guard let userFolders = try? fileManager.contentsOfDirectory(
            at: imageDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        var moved = 0
        for folder in userFolders {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let userId = folder.lastPathComponent
            let destDir = userImageDirectory(for: userId)
            try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

            guard let files = try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where file.pathExtension == "jpg" {
                let dest = destDir.appendingPathComponent(file.lastPathComponent)
                guard !fileManager.fileExists(atPath: dest.path) else { continue }
                try? fileManager.copyItem(at: file, to: dest)
                moved += 1
            }
        }
        if moved > 0 {
            print("🗂️ [CACHE] Migrated \(moved) image(s) from Caches → Application Support")
        }
    }

    /// One-time migration: older builds stored `profile.json` inside `Caches/`.
    /// Move any leftover JSON to `Application Support/` so existing users do not
    /// lose their cached header on first launch of this build.
    private func migrateLegacyProfilesFromCachesIfNeeded() {
        let legacyRoot = imageDirectory // same folder name in Caches
        guard fileManager.fileExists(atPath: legacyRoot.path),
              let entries = try? fileManager.contentsOfDirectory(at: legacyRoot,
                                                                 includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }

        for entry in entries {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let folderName = entry.lastPathComponent

            // Drop legacy stub folders from old builds (pre-isCacheable):
            // empty folder name, "0", or anything that decodes back to "0" / "".
            let decoded = folderName.removingPercentEncoding ?? folderName
            if folderName.isEmpty || decoded.isEmpty || decoded == "0" {
                try? fileManager.removeItem(at: entry)
                continue
            }

            let legacyJSON = entry.appendingPathComponent("profile.json")
            guard fileManager.fileExists(atPath: legacyJSON.path) else { continue }

            let newUserDir = profileDirectory.appendingPathComponent(folderName, isDirectory: true)
            let newJSON = newUserDir.appendingPathComponent("profile.json")

            // Never overwrite a fresh profile.json that already lives in the new location.
            guard !fileManager.fileExists(atPath: newJSON.path) else {
                try? fileManager.removeItem(at: legacyJSON)
                continue
            }

            try? fileManager.createDirectory(at: newUserDir, withIntermediateDirectories: true)
            do {
                try fileManager.moveItem(at: legacyJSON, to: newJSON)
                print("🗂️ [CACHE] Migrated legacy profile.json → Application Support for \(folderName)")
            } catch {
                // Fall back to copy if move failed across filesystems (rare on iOS).
                try? fileManager.copyItem(at: legacyJSON, to: newJSON)
                try? fileManager.removeItem(at: legacyJSON)
            }
        }

        // Also purge any pre-existing stub folders in the new Application Support
        // location that were migrated by an earlier build of this code.
        if let supportEntries = try? fileManager.contentsOfDirectory(at: profileDirectory,
                                                                     includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in supportEntries {
                let name = entry.lastPathComponent
                let decoded = name.removingPercentEncoding ?? name
                if name.isEmpty || decoded.isEmpty || decoded == "0" {
                    try? fileManager.removeItem(at: entry)
                    print("🧹 [CACHE] Removed legacy stub folder userId='\(decoded)'")
                }
            }
        }
    }
    
    // MARK: - Profile Cache
    
    func saveProfile(_ profile: InstagramProfile) {
        // Merge with the previously cached version (same userId) so a partial
        // response from Instagram never downgrades good data we already had.
        // This protects against the soft-block pattern where /users/{id}/info
        // returns a 200 with an empty user object.
        let merged = sanitizeProfileSnapshot(mergeWithCachedIfNeeded(profile))

        guard isCacheable(merged) else {
            print("🛡️ [CACHE] Refusing to cache invalid profile userId=\(merged.userId) username='\(merged.username)' picURL.isEmpty=\(merged.profilePicURL.isEmpty)")
            LogManager.shared.warning("Profile cache rejected invalid profile userId=\(merged.userId)", category: .profile)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(merged) {
            let directory = userProfileDirectory(for: merged.userId)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("profile.json")
            try? data.write(to: fileURL)
            print("✅ Profile cached for userId=\(merged.userId)")
        }
        // Always update in-memory so observers react immediately
        DispatchQueue.main.async { self.cachedProfile = merged }
    }

    /// Saves a profile directly to disk and memory WITHOUT calling mergeWithCachedIfNeeded.
    /// Use this for explicit item removals and authoritative replacements where the incoming
    /// profile already represents the definitive state — merging would re-add removed items.
    private func saveProfileStrict(_ profile: InstagramProfile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(profile) {
            let directory = userProfileDirectory(for: profile.userId)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("profile.json"))
            print("✅ Profile strictly saved (no merge) for userId=\(profile.userId)")
        }
        DispatchQueue.main.async { self.cachedProfile = profile }
    }

    /// Public strict save for full authoritative refreshes. Unlike `saveProfile`, this does
    /// not preserve the old media tail, so posts deleted on Instagram disappear locally too.
    func saveProfileAuthoritative(_ profile: InstagramProfile) {
        let sanitized = sanitizeProfileSnapshot(profile)
        guard isCacheable(sanitized) else {
            print("🛡️ [CACHE] Refusing to strictly cache invalid authoritative profile userId=\(sanitized.userId)")
            LogManager.shared.warning("Authoritative profile cache rejected invalid profile userId=\(sanitized.userId)", category: .profile)
            return
        }
        saveProfileStrict(sanitized)
    }

    /// Returns the incoming profile after copying any non-empty header / counts
    /// fields from `cachedProfile` when the incoming one has them blank or zero.
    /// Media arrays are also preserved when the incoming side is empty — this
    /// prevents transient API failures from wiping our local snapshot.
    private func mergeWithCachedIfNeeded(_ incoming: InstagramProfile) -> InstagramProfile {
        guard let existing = cachedProfile, existing.userId == incoming.userId else {
            return incoming
        }

        let mergedUsername      = incoming.username.isEmpty       ? existing.username       : incoming.username
        let mergedFullName      = incoming.fullName.isEmpty       ? existing.fullName       : incoming.fullName
        let mergedBio           = incoming.biography.isEmpty      ? existing.biography      : incoming.biography
        let incomingExt         = incoming.externalUrl ?? ""
        let mergedExternalUrl   = incomingExt.isEmpty             ? existing.externalUrl    : incoming.externalUrl
        let mergedProfilePicURL = incoming.profilePicURL.isEmpty  ? existing.profilePicURL  : incoming.profilePicURL
        let mergedFollowerCount = incoming.followerCount  > 0     ? incoming.followerCount  : existing.followerCount
        let mergedFollowingCount = incoming.followingCount > 0    ? incoming.followingCount : existing.followingCount
        let mergedMediaCount    = incoming.mediaCount     > 0     ? incoming.mediaCount     : existing.mediaCount
        let mergedFollowedBy    = incoming.followedBy.isEmpty     ? existing.followedBy     : incoming.followedBy
        let mergedHighlights    = incoming.cachedHighlights.isEmpty ? existing.cachedHighlights : incoming.cachedHighlights
        let mergedReelURLs      = incoming.cachedReelURLs.isEmpty   ? existing.cachedReelURLs   : incoming.cachedReelURLs
        let mergedReelItems     = incoming.cachedReelItems.isEmpty  ? existing.cachedReelItems  : incoming.cachedReelItems
        let mergedTaggedURLs    = incoming.cachedTaggedURLs.isEmpty ? existing.cachedTaggedURLs : incoming.cachedTaggedURLs
        let mergedTaggedItems   = incoming.cachedTaggedItems.isEmpty ? existing.cachedTaggedItems : incoming.cachedTaggedItems
        let mergedMediaItems    = mergedMediaItemsPreservingTail(incoming: incoming.cachedMediaItems, existing: existing.cachedMediaItems)
        let mergedMediaURLs     = mergedMediaURLsPreservingTail(incomingURLs: incoming.cachedMediaURLs, mergedItems: mergedMediaItems, existingURLs: existing.cachedMediaURLs)

        return InstagramProfile(
            userId: incoming.userId,
            username: mergedUsername,
            fullName: mergedFullName,
            biography: mergedBio,
            externalUrl: mergedExternalUrl,
            profilePicURL: mergedProfilePicURL,
            isVerified: incoming.isVerified || existing.isVerified,
            isPrivate: incoming.isPrivate,
            followerCount: mergedFollowerCount,
            followingCount: mergedFollowingCount,
            mediaCount: mergedMediaCount,
            followedBy: mergedFollowedBy,
            isFollowing: incoming.isFollowing,
            isFollowRequested: incoming.isFollowRequested,
            cachedAt: incoming.cachedAt,
            cachedMediaURLs: mergedMediaURLs,
            cachedReelURLs: mergedReelURLs,
            cachedTaggedURLs: mergedTaggedURLs,
            cachedHighlights: mergedHighlights,
            cachedMediaItems: mergedMediaItems,
            cachedReelItems: mergedReelItems,
            cachedTaggedItems: mergedTaggedItems,
            cachedNextMaxId: incoming.cachedNextMaxId ?? existing.cachedNextMaxId
        )
    }

    private func sanitizeProfileSnapshot(_ profile: InstagramProfile) -> InstagramProfile {
        let remoteItems = deduplicatedMediaItems(profile.cachedMediaItems)
        let remoteURLs = profile.cachedMediaURLs.filter { !$0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }
        let filteredURLs = deduplicatedURLs(remoteURLs, items: remoteItems)
        return rebuildProfile(profile, mediaURLs: filteredURLs, mediaItems: remoteItems)
    }

    private func mergedMediaItemsPreservingTail(incoming: [InstagramMediaItem], existing: [InstagramMediaItem]) -> [InstagramMediaItem] {
        guard !incoming.isEmpty else { return existing }
        guard existing.count > incoming.count else { return deduplicatedMediaItems(incoming) }

        var seen = Set<String>()
        var merged: [InstagramMediaItem] = []
        for item in incoming + existing {
            let key = item.mediaId.isEmpty ? item.imageURL : mediaIdKey(item.mediaId)
            guard seen.insert(key).inserted else { continue }
            merged.append(item)
        }
        if merged.count > incoming.count {
            print("📦 [CACHE] Preserved media tail during partial refresh: \(incoming.count) fresh + \(merged.count - incoming.count) cached")
        }
        return merged
    }

    private func mergedMediaURLsPreservingTail(incomingURLs: [String], mergedItems: [InstagramMediaItem], existingURLs: [String]) -> [String] {
        guard !incomingURLs.isEmpty else { return existingURLs }
        let byMediaId = Dictionary(grouping: mergedItems, by: { mediaIdKey($0.mediaId) })
        var urls = incomingURLs
        var seenKeys = Set<String>()

        for url in incomingURLs {
            if let item = mergedItems.first(where: { $0.imageURL == url }), !item.mediaId.isEmpty {
                seenKeys.insert(mediaIdKey(item.mediaId))
            } else {
                seenKeys.insert(url)
            }
        }

        for item in mergedItems where !item.imageURL.isEmpty {
            let key = item.mediaId.isEmpty ? item.imageURL : mediaIdKey(item.mediaId)
            guard !seenKeys.contains(key) else { continue }
            urls.append(item.imageURL)
            seenKeys.insert(key)
        }

        for url in existingURLs where !urls.contains(url) {
            guard let item = mergedItems.first(where: { $0.imageURL == url }) else { continue }
            let key = item.mediaId.isEmpty ? url : mediaIdKey(item.mediaId)
            guard !seenKeys.contains(key), byMediaId[key] != nil else { continue }
            urls.append(url)
            seenKeys.insert(key)
        }

        return urls
    }

    private func isCacheable(_ profile: InstagramProfile) -> Bool {
        let userId = profile.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userId.isEmpty, userId != "0" else { return false }

        // Visible identity is required: a profile with only mediaCount > 0 but no
        // username AND no profilePicURL is useless to the UI and would show an
        // empty Instagram header. Reject those — let the caller retry later.
        let hasVisibleIdentity = !profile.username.isEmpty || !profile.profilePicURL.isEmpty
        guard hasVisibleIdentity else { return false }

        // Also require at least one stat to ensure this isn't a stub from a
        // failed /users/{id}/info call (where IG returned just username).
        let hasStats = profile.followerCount > 0
            || profile.followingCount > 0
            || profile.mediaCount > 0
            || !profile.cachedMediaURLs.isEmpty
        return hasStats
    }

    /// A Performance entry may show secret fullscreen input only when this is true.
    /// After the input closes, the fake Instagram profile must paint immediately from
    /// disk, without depending on a live Instagram request.
    func isUsableForPerformance(_ profile: InstagramProfile, userId: String? = nil) -> Bool {
        let expectedUserId = (userId ?? activeUserId() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedUserId.isEmpty || profile.userId == expectedUserId else { return false }
        guard isCacheable(profile) else { return false }
        guard !profile.cachedMediaURLs.isEmpty, !profile.cachedMediaItems.isEmpty else { return false }
        return true
    }

    func hasUsablePerformanceCache(userId: String? = nil) -> Bool {
        guard let profile = loadProfile() else { return false }
        return isUsableForPerformance(profile, userId: userId)
    }

    func requiredPerformancePreloadPosts(
        for profile: InstagramProfile,
        targetPosts: Int = 45,
        maxPosts: Int = 100
    ) -> Int {
        let expected = profile.mediaCount > 0 ? profile.mediaCount : targetPosts
        return min(targetPosts, expected, maxPosts)
    }

    /// "Usable" means the fake profile can paint from disk. "Complete" means the
    /// first-install Performance cache has enough posts to avoid the 12/45 or 23/45
    /// partial-grid state. Keep these separate so a partial cache can render while the
    /// blocking/continue loader finishes the remaining pages.
    func hasCompletePerformancePreloadCache(
        _ profile: InstagramProfile,
        userId: String? = nil,
        targetPosts: Int = 45,
        maxPosts: Int = 100
    ) -> Bool {
        let expectedUserId = (userId ?? activeUserId() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedUserId.isEmpty || profile.userId == expectedUserId else { return false }
        guard isUsableForPerformance(profile, userId: expectedUserId) else { return false }

        let noMoreKey = "perf_no_more_pages_\(profile.userId)"
        if UserDefaults.standard.bool(forKey: noMoreKey), profile.cachedNextMaxId == nil {
            return true
        }

        let required = requiredPerformancePreloadPosts(for: profile, targetPosts: targetPosts, maxPosts: maxPosts)
        return profile.cachedMediaURLs.count >= required && profile.cachedMediaItems.count >= required
    }

    func hasCompletePerformancePreloadCache(
        userId: String? = nil,
        targetPosts: Int = 45,
        maxPosts: Int = 100
    ) -> Bool {
        guard let profile = loadProfile() else { return false }
        return hasCompletePerformancePreloadCache(profile, userId: userId, targetPosts: targetPosts, maxPosts: maxPosts)
    }

    func performancePreloadSnapshot(userId: String? = nil) -> String {
        let expectedUserId = (userId ?? activeUserId() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = loadProfile() else {
            return "userId=\(expectedUserId.isEmpty ? "unknown" : expectedUserId) cache=nil"
        }
        let required = requiredPerformancePreloadPosts(for: profile)
        let fullKey = "perf_fully_preloaded_\(profile.userId)"
        let optionalKey = "perf_optional_preloaded_\(profile.userId)"
        let noMoreKey = "perf_no_more_pages_\(profile.userId)"
        let reasonKey = "perf_last_preload_exit_reason_\(profile.userId)"
        let usable = isUsableForPerformance(profile, userId: expectedUserId)
        let complete = hasCompletePerformancePreloadCache(profile, userId: expectedUserId)
        let optionalValue = UserDefaults.standard.object(forKey: optionalKey).map { "\($0)" } ?? "nil"
        let lastReason = UserDefaults.standard.string(forKey: reasonKey) ?? "nil"
        return "userId=\(profile.userId) urls=\(profile.cachedMediaURLs.count) items=\(profile.cachedMediaItems.count) mediaCount=\(profile.mediaCount) required=\(required) cursor=\(profile.cachedNextMaxId == nil ? "nil" : "saved") usable=\(usable) complete=\(complete) fullFlag=\(UserDefaults.standard.bool(forKey: fullKey)) noMoreFlag=\(UserDefaults.standard.bool(forKey: noMoreKey)) optionalFlag=\(optionalValue) lastReason=\(lastReason)"
    }

    func recordPerformancePreloadExit(
        reason: String,
        userId: String,
        cachedCount: Int,
        requiredCount: Int,
        retrySeconds: Int? = nil,
        context: String = ""
    ) {
        guard !userId.isEmpty else { return }
        var value = "\(reason)|cached=\(cachedCount)/\(requiredCount)"
        if let retrySeconds { value += "|retry=\(retrySeconds)s" }
        if !context.isEmpty { value += "|\(context)" }
        UserDefaults.standard.set(value, forKey: "perf_last_preload_exit_reason_\(userId)")
        print("📦 [PRELOAD-STATE] \(value)")
        LogManager.shared.info("Performance preload exit: \(value)", category: .general)
    }

    /// Returns true when the profile currently in memory is missing the visible
    /// identity fields (header username + pic) needed to render the fake IG view.
    /// PerformanceView reads this on entry and triggers a background rebuild.
    var hasBrokenHeader: Bool {
        guard let p = cachedProfile else { return false }
        return p.username.isEmpty || p.profilePicURL.isEmpty
    }

    // MARK: - Local media list updates (no API call needed)

    /// Removes a CDN thumbnail URL from the cached media list immediately.
    /// Call after successfully archiving a photo from within the app.
    func removeMediaURL(_ url: String) {
        guard var p = cachedProfile else { return }
        guard p.cachedMediaURLs.contains(url) else { return }
        var urls = p.cachedMediaURLs
        urls.removeAll { $0 == url }
        p = rebuildProfile(p, mediaURLs: urls)
        saveProfile(p)
        print("🗂️ [CACHE] Removed media URL from local grid (no refresh needed)")
    }

    /// Inserts a CDN thumbnail URL at the front of the cached media list immediately.
    /// Call after successfully unarchiving a photo from within the app.
    func insertMediaURL(_ url: String) {
        guard var p = cachedProfile else { return }
        guard !p.cachedMediaURLs.contains(url) else { return }
        var urls = p.cachedMediaURLs
        urls.insert(url, at: 0)
        p = rebuildProfile(p, mediaURLs: urls)
        saveProfile(p)
        print("🗂️ [CACHE] Inserted media URL into local grid (no refresh needed)")
    }

    /// Replaces the media URL list without touching any other profile data.
    func updateMediaURLs(_ urls: [String]) {
        guard let p = cachedProfile else { return }
        let updated = rebuildProfile(p, mediaURLs: urls)
        saveProfile(updated)
    }

    /// Replaces both the URL list and the full items list atomically.
    /// Call from refreshMediaGridSilently so mediaId→URL mapping stays fresh
    /// and removeMediaItem(byMediaId:) can resolve the correct URL to remove.
    func updateMediaURLsAndItems(_ urls: [String], items: [InstagramMediaItem]) {
        guard let p = cachedProfile else { return }
        let remoteURLs = urls.filter { !$0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }
        let remoteItems = mergedMediaItemsPreservingTail(incoming: items, existing: p.cachedMediaItems)
        let mergedURLs = mergedMediaURLsPreservingTail(incomingURLs: remoteURLs, mergedItems: remoteItems, existingURLs: p.cachedMediaURLs)
        let filteredURLs = deduplicatedURLs(mergedURLs, items: remoteItems)
        let updated = rebuildProfile(p, mediaURLs: filteredURLs, mediaItems: remoteItems)
        saveProfile(updated)
        print("🗂️ [CACHE] updateMediaURLsAndItems: \(filteredURLs.count) URLs, \(remoteItems.count) items saved")
    }

    /// Authoritative replacement: saves exactly what Instagram returned, no tail preservation.
    /// Use this for full-grid refreshes and archive-sync so removed/archived posts do not
    /// linger in the local cache. `updateMediaURLsAndItems` (tail-preserving) is for
    /// background partial refreshes where pagination has not returned all pages yet.
    func replaceMediaURLsAndItems(_ urls: [String], items: [InstagramMediaItem]) {
        guard let p = cachedProfile else { return }
        let strictURLs = urls.filter { !$0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }
        let strictItems = deduplicatedMediaItems(items)
        let filteredURLs = deduplicatedURLs(strictURLs, items: strictItems)
        let updated = rebuildProfile(p, mediaURLs: filteredURLs, mediaItems: strictItems)
        // Use strict save: no merge so archived posts are not re-added from the old cache tail.
        saveProfileStrict(updated)
        print("🗂️ [CACHE] replaceMediaURLsAndItems (authoritative): \(filteredURLs.count) URLs, \(strictItems.count) items saved")
    }

    /// Removes a photo by mediaId from both the URL list and the full items list.
    /// Call after successfully archiving a photo — PerformanceView reacts instantly via onChange.
    func removeMediaItem(byMediaId mediaId: String) {
        guard var p = cachedProfile else {
            print("❌ [CACHE] removeMediaItem: no cachedProfile in memory — cannot remove \(mediaId)")
            return
        }
        print("🔍 [CACHE] removeMediaItem: searching for \(mediaId) among \(p.cachedMediaItems.count) cached items, \(p.cachedMediaURLs.count) cached URLs")

        let targetKeys = mediaIdKeys(mediaId)
        let urlsForMediaId = Set(p.cachedMediaItems.compactMap { item -> String? in
            guard targetKeys.contains(mediaIdKey(item.mediaId)) else { return nil }
            return item.imageURL
        })

        var urls = p.cachedMediaURLs
        let beforeURLCount = urls.count
        urls.removeAll { url in
            if url.hasPrefix("reveal://") {
                let raw = String(url.dropFirst("reveal://".count))
                return targetKeys.contains(mediaIdKey(raw))
            }
            return urlsForMediaId.contains(url)
        }

        var items = p.cachedMediaItems
        let beforeItemCount = items.count
        items.removeAll { targetKeys.contains(mediaIdKey($0.mediaId)) }

        p = rebuildProfile(p, mediaURLs: urls, mediaItems: items)
        // Use strict save to prevent mergeWithCachedIfNeeded re-adding the removed item.
        // The standard saveProfile merge would see existing.count > incoming.count and
        // append the just-removed item back as "tail", defeating the removal entirely.
        saveProfileStrict(p)
        let removedURLs = beforeURLCount - urls.count
        let removedItems = beforeItemCount - items.count
        if removedURLs == 0 && removedItems == 0 {
            print("⚠️ [CACHE] removeMediaItem: \(mediaId) not found, but cache was re-saved to keep observers consistent")
        } else {
            print("✅ [CACHE] removeMediaItem done — removed \(removedURLs) URL(s), \(removedItems) item(s)")
        }
    }

    /// Removes a mediaId from the persisted reveal overlay file as well as the
    /// profile snapshot. Use after any successful archive/re-archive.
    func removeMediaEverywhere(mediaId: String, userId: String? = nil) {
        removeMediaItem(byMediaId: mediaId)
        let resolvedUserId = userId ?? cachedProfile?.userId ?? activeUserId()
        guard let resolvedUserId, let revealState = loadRevealState(userId: resolvedUserId) else { return }
        let targetKeys = mediaIdKeys(mediaId)
        let urls = revealState.urls.filter { url in
            guard url.hasPrefix("reveal://"), !url.hasPrefix("reveal://test-") else { return true }
            let raw = String(url.dropFirst("reveal://".count))
            return !targetKeys.contains(mediaIdKey(raw))
        }
        let dates = revealState.dates.filter { key, _ in
            guard key.hasPrefix("reveal://"), !key.hasPrefix("reveal://test-") else { return true }
            let raw = String(key.dropFirst("reveal://".count))
            return !targetKeys.contains(mediaIdKey(raw))
        }
        saveRevealState(urls: urls, dates: dates, userId: resolvedUserId)
        print("🧹 [CACHE] Removed mediaId \(mediaId) from profile + reveal state")
    }

    private func mediaIdKey(_ mediaId: String) -> String {
        mediaId.split(separator: "_").first.map(String.init) ?? mediaId
    }

    private func mediaIdKeys(_ mediaId: String) -> Set<String> {
        [mediaId, mediaIdKey(mediaId)]
    }

    private func deduplicatedMediaItems(_ items: [InstagramMediaItem]) -> [InstagramMediaItem] {
        var seen = Set<String>()
        var result: [InstagramMediaItem] = []
        for item in items {
            let key = item.mediaId.isEmpty ? item.imageURL : mediaIdKey(item.mediaId)
            guard seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result
    }

    private func deduplicatedURLs(_ urls: [String], items: [InstagramMediaItem]) -> [String] {
        var itemByURL: [String: InstagramMediaItem] = [:]
        for item in items where itemByURL[item.imageURL] == nil {
            itemByURL[item.imageURL] = item
        }
        var seen = Set<String>()
        var result: [String] = []
        for url in urls {
            let key: String
            if let mediaId = itemByURL[url]?.mediaId, !mediaId.isEmpty {
                key = mediaIdKey(mediaId)
            } else {
                key = url
            }
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }

    private func rebuildProfile(_ p: InstagramProfile,
                                mediaURLs: [String],
                                mediaItems: [InstagramMediaItem]? = nil) -> InstagramProfile {
        InstagramProfile(
            userId: p.userId, username: p.username, fullName: p.fullName,
            biography: p.biography, externalUrl: p.externalUrl,
            profilePicURL: p.profilePicURL, isVerified: p.isVerified,
            isPrivate: p.isPrivate, followerCount: p.followerCount,
            followingCount: p.followingCount, mediaCount: p.mediaCount,
            followedBy: p.followedBy, isFollowing: p.isFollowing,
            isFollowRequested: p.isFollowRequested, cachedAt: p.cachedAt,
            cachedMediaURLs: mediaURLs,
            cachedReelURLs: p.cachedReelURLs,
            cachedTaggedURLs: p.cachedTaggedURLs,
            cachedHighlights: p.cachedHighlights,
            cachedMediaItems: mediaItems ?? p.cachedMediaItems,
            cachedReelItems: p.cachedReelItems,
            cachedTaggedItems: p.cachedTaggedItems,
            cachedNextMaxId: p.cachedNextMaxId
        )
    }
    
    func loadProfile() -> InstagramProfile? {
        guard let userId = activeUserId() else {
            return nil
        }

        if let cachedProfile, cachedProfile.userId == userId {
            return cachedProfile
        }
        if let cachedProfile, cachedProfile.userId != userId {
            print("🗂️ [CACHE] Ignoring in-memory cache for previous userId=\(cachedProfile.userId)")
            DispatchQueue.main.async { self.cachedProfile = nil }
        }

        let fileURL = userProfileDirectory(for: userId).appendingPathComponent("profile.json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let profile = try? decoder.decode(InstagramProfile.self, from: data) {
            print("✅ Profile loaded from cache for userId=\(profile.userId)")
            DispatchQueue.main.async { self.cachedProfile = profile }
            return profile
        }
        
        return nil
    }
    
    func clearProfile() {
        guard let userId = activeUserId() else { return }
        let fileURL = userProfileDirectory(for: userId).appendingPathComponent("profile.json")
        try? fileManager.removeItem(at: fileURL)
        DispatchQueue.main.async { self.cachedProfile = nil }
        print("🗑️ Profile cache cleared for userId=\(userId)")
    }
    
    // MARK: - Image Cache
    
    func saveImage(_ image: UIImage, forURL urlString: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        guard let userId = activeUserId() else { return }
        let filename = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let directory = userImageDirectory(for: userId)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(filename).jpg"))
    }

    func loadImage(forURL urlString: String) -> UIImage? {
        guard let userId = activeUserId() else { return nil }
        let filename = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let fileURL = userImageDirectory(for: userId).appendingPathComponent("\(filename).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Save an image keyed by stable mediaId (e.g. Instagram post pk).
    /// CDN URLs rotate between sessions; mediaId never changes, so this
    /// survives URL rotation without needing a new network request.
    func saveImage(_ image: UIImage, forMediaId mediaId: String) {
        guard !mediaId.isEmpty else { return }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        guard let userId = activeUserId() else { return }
        let safe = mediaId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? mediaId
        let directory = userImageDirectory(for: userId)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("mid_\(safe).jpg"))
    }

    func loadImage(forMediaId mediaId: String) -> UIImage? {
        guard !mediaId.isEmpty else { return nil }
        guard let userId = activeUserId() else { return nil }
        let safe = mediaId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? mediaId
        let fileURL = userImageDirectory(for: userId).appendingPathComponent("mid_\(safe).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    func clearAllImages() {
        guard let userId = activeUserId() else { return }
        let directory = userImageDirectory(for: userId)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "jpg" {
            try? fileManager.removeItem(at: file)
        }
        
        print("🗑️ All images cleared from cache for userId=\(userId)")
    }
    
    // MARK: - Clear All Cache
    
    func clearAll() {
        try? fileManager.removeItem(at: profileDirectory)
        try? fileManager.removeItem(at: imageDirectory)
        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        DispatchQueue.main.async { self.cachedProfile = nil }
        print("🗑️ All profile caches cleared (profile.json + images)")
    }

    private func activeUserId() -> String? {
        if let saved = KeychainService.shared.loadSession(), saved.isLoggedIn, !saved.userId.isEmpty {
            return saved.userId
        }
        if let cachedProfile, !cachedProfile.userId.isEmpty {
            return cachedProfile.userId
        }
        return nil
    }

    /// Per-user folder inside Application Support — holds only `profile.json`.
    /// Survives iOS low-disk purges.
    private func userProfileDirectory(for userId: String) -> URL {
        let safeUserId = userId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userId
        return profileDirectory.appendingPathComponent(safeUserId, isDirectory: true)
    }

    /// Per-user folder inside Application Support — holds `.jpg` thumbnails.
    /// Lives next to `profile.json`; never purged by iOS under low-disk pressure.
    private func userImageDirectory(for userId: String) -> URL {
        let safeUserId = userId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userId
        return profileDirectory.appendingPathComponent("\(safeUserId)/images", isDirectory: true)
    }

    // MARK: - Reveal State Persistence

    private struct RevealState: Codable {
        var revealURLs: [String]
        var revealDates: [String: Date]
    }

    private func revealStateFileURL(for userId: String) -> URL? {
        guard !userId.isEmpty, userId != "0" else { return nil }
        return userProfileDirectory(for: userId).appendingPathComponent("reveal_state.json")
    }

    /// Persists the list of reveal:// URLs and their dates so they survive app restarts.
    func saveRevealState(urls: [String], dates: [String: Date], userId: String) {
        let revealURLs = urls.filter { $0.hasPrefix("reveal://") && !$0.hasPrefix("reveal://test-") }
        guard !revealURLs.isEmpty else {
            clearRevealState(userId: userId)
            return
        }
        let revealDates = dates.filter { $0.key.hasPrefix("reveal://") && !$0.key.hasPrefix("reveal://test-") }
        let state = RevealState(revealURLs: revealURLs, revealDates: revealDates)
        guard let fileURL = revealStateFileURL(for: userId) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL)
        print("💾 [REVEAL] Saved \(revealURLs.count) reveal URL(s) to disk")
    }

    /// Loads persisted reveal state, or nil if none exists.
    func loadRevealState(userId: String) -> (urls: [String], dates: [String: Date])? {
        guard let fileURL = revealStateFileURL(for: userId),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(RevealState.self, from: data) else { return nil }
        print("💾 [REVEAL] Loaded \(state.revealURLs.count) reveal URL(s) from disk")
        return (state.revealURLs, state.revealDates)
    }

    /// Removes the persisted reveal state (called after a successful profile refresh).
    func clearRevealState(userId: String) {
        guard let fileURL = revealStateFileURL(for: userId) else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
        print("💾 [REVEAL] Cleared reveal state from disk")
    }
}
