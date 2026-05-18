import Foundation
import UIKit

final class VisitedProfileCacheService {
    static let shared = VisitedProfileCacheService()

    private struct SearchCacheEntry: Codable {
        let query: String
        let cachedAt: Date
        let results: [UserSearchResult]
    }

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let profilesDirectory: URL
    private let imagesDirectory: URL
    private let searchesDirectory: URL
    private let maxSearchAge: TimeInterval = 10 * 60

    /// Max cache age for visited profile data before we refuse to serve it.
    /// Older than this and we return nil so the caller does a fresh fetch.
    /// 24h covers same-day show cycles (the common case) while preventing
    /// weeks-old stale data from leaking into a magic effect that reads counts.
    /// Anti-bot benefit: revisits within this window skip the 4-endpoint burst.
    private let maxProfileAge: TimeInterval = 24 * 60 * 60

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("VisitedProfileCache", isDirectory: true)
        profilesDirectory = rootDirectory.appendingPathComponent("Profiles", isDirectory: true)
        imagesDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)
        searchesDirectory = rootDirectory.appendingPathComponent("Searches", isDirectory: true)
        [rootDirectory, profilesDirectory, imagesDirectory, searchesDirectory].forEach {
            try? fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    func saveProfile(_ profile: InstagramProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: profileURL(for: profile.userId), options: .atomic)
        print("💾 [VISITED CACHE] Saved @\(profile.username)")
    }

    func loadProfile(userId: String) -> InstagramProfile? {
        let url = profileURL(for: userId)
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(InstagramProfile.self, from: data) else {
            return nil
        }
        // Honor TTL using file modification date (set by atomic write on saveProfile).
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age > maxProfileAge {
                print("⏳ [VISITED CACHE] @\(profile.username) cache too old (\(Int(age/3600))h) — refetching")
                return nil
            }
        }
        print("📦 [VISITED CACHE] Loaded @\(profile.username)")
        return profile
    }

    /// Returns the age of the cached profile in seconds, or nil if not cached.
    func profileCacheAge(forUserId userId: String) -> TimeInterval? {
        let url = profileURL(for: userId)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return Date().timeIntervalSince(modDate)
    }

    func saveSearchResults(_ results: [UserSearchResult], for query: String) {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return }
        let entry = SearchCacheEntry(query: normalized, cachedAt: Date(), results: results)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: searchURL(for: normalized), options: .atomic)
    }

    func loadSearchResults(for query: String) -> [UserSearchResult]? {
        let normalized = normalize(query)
        guard !normalized.isEmpty,
              let data = try? Data(contentsOf: searchURL(for: normalized)),
              let entry = try? JSONDecoder().decode(SearchCacheEntry.self, from: data),
              Date().timeIntervalSince(entry.cachedAt) <= maxSearchAge else {
            return nil
        }
        print("📦 [SEARCH CACHE] Loaded \(entry.results.count) result(s) for \(normalized)")
        return entry.results
    }

    func saveImage(_ image: UIImage, forURL urlString: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: imageURL(for: urlString), options: .atomic)
    }

    func loadImage(forURL urlString: String) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL(for: urlString)) else { return nil }
        return UIImage(data: data)
    }

    private func profileURL(for userId: String) -> URL {
        profilesDirectory.appendingPathComponent("\(safeFilename(userId)).json")
    }

    private func searchURL(for query: String) -> URL {
        searchesDirectory.appendingPathComponent("\(safeFilename(query)).json")
    }

    private func imageURL(for urlString: String) -> URL {
        imagesDirectory.appendingPathComponent("\(hashedFilename(urlString)).jpg")
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func safeFilename(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? hashedFilename(value)
    }

    private func hashedFilename(_ value: String) -> String {
        var hash: UInt64 = 5381
        for scalar in value.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return String(format: "%016llx", hash)
    }
}
