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

    /// Where the `.jpg` thumbnails live. We keep these in `Caches/` because
    /// iOS may purge them — and that is fine: thumbnails are cheap to re-download
    /// from the CDN URLs that live inside `profile.json`, no Instagram API call
    /// is needed.
    private let imageDirectory: URL

    private init() {
        let supportPaths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        profileDirectory = supportPaths[0].appendingPathComponent("ProfileCache", isDirectory: true)

        let cachesPaths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        imageDirectory = cachesPaths[0].appendingPathComponent("ProfileCache", isDirectory: true)

        try? fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        // Application Support is included in iCloud / iTunes backups by default.
        // The profile cache is rebuildable from the API, so excluding it keeps
        // user backups small and avoids syncing transient data across devices.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = profileDirectory
        try? url.setResourceValues(values)

        migrateLegacyProfilesFromCachesIfNeeded()

        // Warm the in-memory copy from disk on launch. This uses the Keychain
        // session if one exists; otherwise it returns nil without touching disk.
        cachedProfile = loadProfile()
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
        let merged = mergeWithCachedIfNeeded(profile)

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
        let mergedMediaURLs     = incoming.cachedMediaURLs.isEmpty  ? existing.cachedMediaURLs  : incoming.cachedMediaURLs
        let mergedMediaItems    = incoming.cachedMediaItems.isEmpty ? existing.cachedMediaItems : incoming.cachedMediaItems

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
            cachedNextMaxId: incoming.cachedNextMaxId ?? existing.cachedNextMaxId
        )
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
        let updated = rebuildProfile(p, mediaURLs: urls, mediaItems: items)
        saveProfile(updated)
        print("🗂️ [CACHE] updateMediaURLsAndItems: \(urls.count) URLs, \(items.count) items saved")
    }

    /// Removes a photo by mediaId from both the URL list and the full items list.
    /// Call after successfully archiving a photo — PerformanceView reacts instantly via onChange.
    func removeMediaItem(byMediaId mediaId: String) {
        guard var p = cachedProfile else {
            print("❌ [CACHE] removeMediaItem: no cachedProfile in memory — cannot remove \(mediaId)")
            return
        }
        print("🔍 [CACHE] removeMediaItem: searching for \(mediaId) among \(p.cachedMediaItems.count) cached items, \(p.cachedMediaURLs.count) cached URLs")

        guard let item = p.cachedMediaItems.first(where: { $0.mediaId == mediaId }) else {
            print("⚠️ [CACHE] removeMediaItem: mediaId \(mediaId) NOT in cachedMediaItems")
            print("⚠️ [CACHE]   Known mediaIds: \(p.cachedMediaItems.map { $0.mediaId }.joined(separator: ", "))")
            // Fallback: try direct scan if the items list is stale (no silent refresh happened)
            // We can't remove without knowing the URL — log and bail.
            return
        }

        let url = item.imageURL
        let urlWasPresent = p.cachedMediaURLs.contains(url)
        print("🔍 [CACHE] removeMediaItem: found item, imageURL=\(url.suffix(60))")
        print("🔍 [CACHE]   URL present in cachedMediaURLs: \(urlWasPresent)")

        var urls  = p.cachedMediaURLs;  urls.removeAll  { $0 == url }
        var items = p.cachedMediaItems; items.removeAll { $0.mediaId == mediaId }
        p = rebuildProfile(p, mediaURLs: urls, mediaItems: items)
        saveProfile(p)
        print("✅ [CACHE] removeMediaItem done — \(urlWasPresent ? "removed" : "URL not in list (stale?)") — remaining: \(urls.count) URLs, \(items.count) items")
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
        let fileURL = directory.appendingPathComponent("\(filename).jpg")
        
        try? data.write(to: fileURL)
    }
    
    func loadImage(forURL urlString: String) -> UIImage? {
        guard let userId = activeUserId() else { return nil }
        let filename = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let fileURL = userImageDirectory(for: userId).appendingPathComponent("\(filename).jpg")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
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

    /// Per-user folder inside Caches — holds `.jpg` thumbnails only.
    /// Safe to be purged; we re-download from CDN URLs on demand.
    private func userImageDirectory(for userId: String) -> URL {
        let safeUserId = userId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? userId
        return imageDirectory.appendingPathComponent(safeUserId, isDirectory: true)
    }
}
