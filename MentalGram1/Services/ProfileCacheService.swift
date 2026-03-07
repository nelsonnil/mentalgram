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
    private let cacheDirectory: URL
    
    private init() {
        // Get cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ProfileCache", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Warm the in-memory copy from disk on launch
        cachedProfile = loadProfile()
    }
    
    // MARK: - Profile Cache
    
    func saveProfile(_ profile: InstagramProfile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(profile) {
            let fileURL = cacheDirectory.appendingPathComponent("profile.json")
            try? data.write(to: fileURL)
            print("✅ Profile cached")
        }
        // Always update in-memory so observers react immediately
        DispatchQueue.main.async { self.cachedProfile = profile }
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

    private func rebuildProfile(_ p: InstagramProfile, mediaURLs: [String]) -> InstagramProfile {
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
            cachedHighlights: p.cachedHighlights
        )
    }
    
    func loadProfile() -> InstagramProfile? {
        let fileURL = cacheDirectory.appendingPathComponent("profile.json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let profile = try? decoder.decode(InstagramProfile.self, from: data) {
            print("✅ Profile loaded from cache")
            return profile
        }
        
        return nil
    }
    
    func clearProfile() {
        let fileURL = cacheDirectory.appendingPathComponent("profile.json")
        try? fileManager.removeItem(at: fileURL)
        print("🗑️ Profile cache cleared")
    }
    
    // MARK: - Image Cache
    
    func saveImage(_ image: UIImage, forURL urlString: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let filename = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileURL = cacheDirectory.appendingPathComponent("\(filename).jpg")
        
        try? data.write(to: fileURL)
    }
    
    func loadImage(forURL urlString: String) -> UIImage? {
        let filename = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let fileURL = cacheDirectory.appendingPathComponent("\(filename).jpg")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return UIImage(data: data)
    }
    
    func clearAllImages() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "jpg" {
            try? fileManager.removeItem(at: file)
        }
        
        print("🗑️ All images cleared from cache")
    }
    
    // MARK: - Clear All Cache
    
    func clearAll() {
        clearProfile()
        clearAllImages()
    }
}
