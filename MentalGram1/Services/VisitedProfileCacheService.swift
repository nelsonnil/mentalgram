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
    // Caché permanente para la máscara de cover typing (sin TTL — se invalida manualmente)
    private let maskSearchesDirectory: URL
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
        maskSearchesDirectory = rootDirectory.appendingPathComponent("MaskSearches", isDirectory: true)
        [rootDirectory, profilesDirectory, imagesDirectory, searchesDirectory, maskSearchesDirectory].forEach {
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

    // MARK: - Mask Search Cache (permanente, sin TTL)

    /// Guarda los resultados de búsqueda para el nombre de máscara configurado.
    /// Sin expiración — dura indefinidamente hasta que el usuario refresca manualmente
    /// o cambia el nombre.
    func saveMaskSearchResults(_ results: [UserSearchResult], forUsername username: String) {
        let normalized = normalize(username)
        guard !normalized.isEmpty else { return }
        let entry = SearchCacheEntry(query: normalized, cachedAt: Date(), results: results)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: maskSearchURL(for: normalized), options: .atomic)
        print("💾 [MASK CACHE] Guardados \(results.count) perfiles para '\(normalized)'")
    }

    /// Carga los resultados de máscara desde disco. Sin comprobación de TTL.
    func loadMaskSearchResults(forUsername username: String) -> [UserSearchResult]? {
        let normalized = normalize(username)
        guard !normalized.isEmpty,
              let data = try? Data(contentsOf: maskSearchURL(for: normalized)),
              let entry = try? JSONDecoder().decode(SearchCacheEntry.self, from: data),
              !entry.results.isEmpty else { return nil }
        print("📦 [MASK CACHE] Cargados \(entry.results.count) perfiles para '\(normalized)'")
        return entry.results
    }

    /// Número de perfiles guardados para un username. 0 si no hay caché.
    func maskSearchResultsCount(forUsername username: String) -> Int {
        loadMaskSearchResults(forUsername: username)?.count ?? 0
    }

    /// Elimina el caché de máscara para un username concreto.
    func clearMaskSearchResults(forUsername username: String) {
        let normalized = normalize(username)
        try? fileManager.removeItem(at: maskSearchURL(for: normalized))
        print("🗑️ [MASK CACHE] Eliminado caché para '\(normalized)'")
    }

    /// Hace 2-3 llamadas API según la longitud del nombre, fusiona los resultados
    /// con los exactos al principio, y guarda en disco de forma permanente.
    /// Devuelve el número total de perfiles guardados.
    @discardableResult
    func prefetchAndCacheMaskResults(username: String) async -> Int {
        let clean = normalize(username)
        guard !clean.isEmpty else { return 0 }

        let prefixes = maskSearchPrefixes(for: clean)
        print("🔍 [MASK CACHE] Pre-fetch '\(clean)' con prefijos: \(prefixes)")

        // Resultado del nombre completo primero (para garantizar el perfil exacto)
        var fullNameResults: [UserSearchResult] = []
        var prefixResults:   [UserSearchResult] = []

        for (idx, prefix) in prefixes.enumerated() {
            guard let results = try? await InstagramService.shared.searchUsers(query: prefix) else {
                print("⚠️ [MASK CACHE] Fallo al buscar '\(prefix)'")
                continue
            }
            if prefix == clean {
                fullNameResults = results
            } else {
                prefixResults.append(contentsOf: results)
            }
            if idx < prefixes.count - 1 {
                // Pausa anti-bot entre llamadas
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        // Fusionar: nombre completo primero, luego prefijos sin duplicar
        var seenIds: Set<String> = []
        var merged:  [UserSearchResult] = []
        for r in fullNameResults  where seenIds.insert(r.userId).inserted { merged.append(r) }
        for r in prefixResults    where seenIds.insert(r.userId).inserted { merged.append(r) }

        saveMaskSearchResults(merged, forUsername: clean)
        print("✅ [MASK CACHE] '\(clean)': \(merged.count) perfiles guardados (\(prefixes.count) llamadas)")
        return merged.count
    }

    /// Devuelve los prefijos a buscar según la longitud del nombre:
    /// ≤5 chars → [nombre]  (ya es corto, 1 llamada)
    /// 6-8 chars → [prefix3, nombre]  (2 llamadas)
    /// ≥9 chars  → [prefix3, prefijomedio, nombre]  (3 llamadas)
    private func maskSearchPrefixes(for username: String) -> [String] {
        guard !username.isEmpty else { return [] }
        if username.count <= 2 { return [username] }

        let prefix3 = String(username.prefix(3))

        if username.count <= 5 {
            return username == prefix3 ? [username] : [prefix3, username]
        }
        if username.count <= 8 {
            return [prefix3, username]
        }
        // ≥9 chars: añadir punto medio
        let midCount  = username.count / 2
        let midPrefix = String(username.prefix(midCount))
        return [prefix3, midPrefix, username].reduce(into: [String]()) { acc, p in
            if !acc.contains(p) { acc.append(p) }
        }
    }

    private func maskSearchURL(for username: String) -> URL {
        maskSearchesDirectory.appendingPathComponent("\(safeFilename(username))_mask.json")
    }

    // MARK: - Image cache

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
