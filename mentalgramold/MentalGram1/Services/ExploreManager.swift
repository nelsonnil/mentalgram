import Foundation
import UIKit
import Combine

/// Manager for Instagram Explore Feed with background loading and caching
class ExploreManager: ObservableObject {
    static let shared = ExploreManager()
    
    @Published var exploreMedia: [InstagramMediaItem] = []
    @Published var cachedImages: [String: UIImage] = [:]
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var loadError: String? = nil
    @Published var isBackgroundRefreshing = false
    
    private var nextMaxId: String?
    private var hasPreloaded = false
    private var hasMorePages = true
    private var itemBuffer: [InstagramMediaItem] = [] // Buffer para items que no caben en grid de 3
    private var lastBackgroundRefresh: Date? = nil

    // UserDefaults keys for persisting scroll cursor across launches
    private static let udKeyNextMaxId   = "explore_nextMaxId"
    private static let udKeyHasMore     = "explore_hasMorePages"
    private static let backgroundRefreshMinInterval: TimeInterval = 30 * 60 // 30 min
    private static let startupDelay: TimeInterval = 12 // seconds to wait after app start
    
    private init() {
        // Load from cache on init
        loadFromCache()
    }
    
    // MARK: - Preload in Background
    
    func preloadExploreInBackground() {
        guard !hasPreloaded else {
            print("🔍 [EXPLORE] Already preloaded, skipping")
            return
        }
        
        print("🔍 [EXPLORE] Starting background preload...")
        
        Task.detached(priority: .background) {
            await self.loadExploreInternal()
            await MainActor.run {
                self.hasPreloaded = true
            }
        }
    }
    
    // MARK: - Load Explore
    
    func loadExplore() {
        guard !isLoading else { return }
        guard !InstagramService.shared.isSessionChallenged else {
            print("🚫 [EXPLORE] Load skipped — session in challenged state (anti-bot)")
            return
        }
        
        isLoading = true
        loadError = nil

        Task {
            await loadExploreInternal()
            await MainActor.run {
                isLoading = false
            }
        }
    }

    /// Silently fetches fresh data from the API while already showing cached content.
    /// Does NOT touch isLoading — the grid stays visible and URLs are refreshed in place.
    /// Throttled to once per 30 minutes. Delayed 12s after startup to avoid competing
    /// with profile supplementary fetch.
    func backgroundRefresh() {
        guard !isLoading, !isBackgroundRefreshing else { return }

        // Anti-bot: check lockdown or challenged session
        guard !InstagramService.shared.isLocked else {
            print("🚫 [EXPLORE] Background refresh skipped — lockdown active")
            return
        }
        guard !InstagramService.shared.isSessionChallenged else {
            print("🚫 [EXPLORE] Background refresh skipped — session in challenged state")
            return
        }

        // Anti-bot: throttle — no refresh if done recently
        if let last = lastBackgroundRefresh,
           Date().timeIntervalSince(last) < ExploreManager.backgroundRefreshMinInterval {
            let waited = Int(Date().timeIntervalSince(last) / 60)
            print("🚫 [EXPLORE] Background refresh throttled — last refresh \(waited)m ago (min 30m)")
            return
        }

        isBackgroundRefreshing = true
        print("🔄 [EXPLORE] Background refresh queued (12s startup delay)...")

        Task {
            // Anti-bot: delay startup burst — wait for profile supplementary fetch to finish
            try? await Task.sleep(nanoseconds: UInt64(ExploreManager.startupDelay * 1_000_000_000))

            // Re-check lockdown after delay
            guard !InstagramService.shared.isLocked else {
                await MainActor.run { self.isBackgroundRefreshing = false }
                print("🚫 [EXPLORE] Background refresh cancelled — lockdown activated during delay")
                return
            }

            await MainActor.run { self.lastBackgroundRefresh = Date() }
            print("🔄 [EXPLORE] Background refresh started (keeping cached content visible)...")
            await loadExploreInternal()
            await MainActor.run {
                self.isBackgroundRefreshing = false
                print("✅ [EXPLORE] Background refresh complete")
            }
        }
    }
    
    /// Async entry point for pull-to-refresh (awaitable by SwiftUI .refreshable)
    func refreshAsync() async {
        guard !isLoading, !isBackgroundRefreshing else { return }
        guard !InstagramService.shared.isLocked else { return }
        guard !InstagramService.shared.isSessionChallenged else {
            print("🚫 [EXPLORE] Refresh skipped — session in challenged state")
            return
        }
        await MainActor.run { isLoading = true }
        await loadExploreInternal()
        await MainActor.run { isLoading = false }
    }

    private func loadExploreInternal() async {
        do {
            // ANTI-BOT: Wait if network changed recently
            try await InstagramService.shared.waitForNetworkStability()
            
            print("🔍 [EXPLORE] Fetching from API...")
            let (items, maxId) = try await InstagramService.shared.getExploreFeed()
            
            print("🔍 [EXPLORE] Received \(items.count) items from API")
            
            // GRID FIX: Show only multiples of 3 (complete rows)
            // Save extras to buffer for next load
            let multipleOf3 = (items.count / 3) * 3
            let itemsToShow = Array(items.prefix(multipleOf3))
            let itemsToBuffer = Array(items.suffix(items.count - multipleOf3))
            
            print("🔍 [EXPLORE] Showing \(itemsToShow.count) items (\(itemsToShow.count / 3) complete rows)")
            if !itemsToBuffer.isEmpty {
                print("🔍 [EXPLORE] Buffering \(itemsToBuffer.count) extra items for next load")
            }

            await MainActor.run {
                self.exploreMedia = itemsToShow
                self.itemBuffer = itemsToBuffer
                self.nextMaxId = maxId
                self.hasMorePages = maxId != nil

                // Save item list and cursor permanently
                saveToCache()

                print("✅ [EXPLORE] Loaded \(itemsToShow.count) items into UI")
                print("🔍 [EXPLORE] Has more pages: \(self.hasMorePages)")
            }

            // Download new thumbnails FIRST, then clear stale ones.
            // Doing it in this order ensures that if the download fails (offline, CDN error),
            // the old thumbnails on disk are still shown rather than a blank grid.
            await downloadThumbnails(items: itemsToShow)
            clearPermanentThumbnails(except: Set(itemsToShow.map { $0.imageURL }))
            
        } catch {
            print("❌ [EXPLORE] Error loading: \(error)")
            await MainActor.run {
                if self.exploreMedia.isEmpty {
                    print("🔍 [EXPLORE] No items in cache after error — showing retry UI")
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Download Thumbnails
    
    private func downloadThumbnails(items: [InstagramMediaItem]) async {
        print("🖼️ [EXPLORE] Downloading \(items.count) thumbnails...")

        var successCount = 0
        var failCount = 0

        for (index, item) in items.enumerated() {
            guard !item.imageURL.isEmpty else { continue }

            if cachedImages[item.imageURL] != nil {
                successCount += 1
                continue
            }

            if let image = await downloadImage(from: item.imageURL) {
                // Save permanently to Application Support (survives iOS cache clearing)
                saveThumbnailPermanently(image, forURL: item.imageURL)
                await MainActor.run {
                    cachedImages[item.imageURL] = image
                }
                successCount += 1
                if (index + 1) % 10 == 0 {
                    print("🖼️ [EXPLORE] Downloaded \(successCount)/\(items.count)")
                }
            } else {
                failCount += 1
                print("⚠️ [EXPLORE] Thumbnail download failed (\(failCount) so far): \(item.imageURL.prefix(80))")
            }
        }

        if failCount == 0 {
            print("✅ [EXPLORE] All \(successCount) thumbnails downloaded successfully")
        } else {
            print("⚠️ [EXPLORE] Thumbnails done: \(successCount) OK, \(failCount) FAILED (likely expired CDN URLs)")
            // If most downloads failed, the cache is stale — clear it so next open forces a fresh API fetch
            if failCount > items.count / 2 {
                print("🗑️ [EXPLORE] >50% failed — clearing stale cache")
                await MainActor.run { clearCache() }
            }
        }
    }
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    // MARK: - Permanent Storage (Application Support — never cleared by iOS)

    /// Root directory for all Explore persistent data.
    private static var permanentDir: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ExplorePermanent", isDirectory: true)
    }

    /// Sub-directory holding one JPEG per thumbnail URL.
    private static var thumbnailDir: URL? {
        permanentDir?.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    private static func ensureDirs() {
        [permanentDir, thumbnailDir]
            .compactMap { $0 }
            .forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
    }

    /// Stable filename derived from the URL (avoids special characters in filenames).
    private static func thumbnailFilename(for urlString: String) -> String {
        // Use a simple DJB2 hash — short, collision-resistant enough for ~100 files
        var hash: UInt64 = 5381
        for char in urlString.unicodeScalars {
            hash = (hash &* 31) &+ UInt64(char.value)
        }
        return String(format: "%016llx.jpg", hash)
    }

    private func saveThumbnailPermanently(_ image: UIImage, forURL urlString: String) {
        Self.ensureDirs()
        guard let dir = Self.thumbnailDir,
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileURL = dir.appendingPathComponent(Self.thumbnailFilename(for: urlString))
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadThumbnailPermanently(forURL urlString: String) -> UIImage? {
        guard let dir = Self.thumbnailDir else { return nil }
        let fileURL = dir.appendingPathComponent(Self.thumbnailFilename(for: urlString))
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Deletes stored thumbnails that are NOT in `keep`.
    /// Pass an empty set to delete everything (used by clearCache).
    /// Pass the current batch of URLs to remove only orphaned/stale files.
    private func clearPermanentThumbnails(except keep: Set<String> = []) {
        guard let dir = Self.thumbnailDir else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        let keepFilenames = Set(keep.map { Self.thumbnailFilename(for: $0) })
        var removed = 0
        for file in files {
            guard !keepFilenames.contains(file.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            print("🗑️ [EXPLORE] Removed \(removed) stale thumbnails, kept \(files.count - removed)")
        }
    }

    // MARK: - Cache Management (JSON stored in Application Support too)

    private func saveToCache() {
        Self.ensureDirs()
        guard let dir = Self.permanentDir,
              let data = try? JSONEncoder().encode(exploreMedia) else { return }
        let fileURL = dir.appendingPathComponent("explore_items.json")
        try? data.write(to: fileURL, options: .atomic)

        // Persist scroll cursor so infinite scroll works after app re-launch (weeks later)
        if let cursor = nextMaxId {
            UserDefaults.standard.set(cursor, forKey: Self.udKeyNextMaxId)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.udKeyNextMaxId)
        }
        UserDefaults.standard.set(hasMorePages, forKey: Self.udKeyHasMore)

        print("💾 [EXPLORE] Items + cursor saved (nextMaxId: \(nextMaxId?.prefix(20) ?? "nil"))")
    }

    private func loadFromCache() {
        Self.ensureDirs()

        // --- Try permanent location first ---
        var items: [InstagramMediaItem]? = nil

        if let dir = Self.permanentDir {
            let fileURL = dir.appendingPathComponent("explore_items.json")
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode([InstagramMediaItem].self, from: data) {
                items = decoded
            }
        }

        // --- Legacy fallback: old cachesDirectory file ---
        if items == nil,
           let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let legacyURL = cacheDir.appendingPathComponent("explore_cache.json")
            if let data = try? Data(contentsOf: legacyURL),
               let decoded = try? JSONDecoder().decode([InstagramMediaItem].self, from: data) {
                items = decoded
                // Migrate to permanent location
                try? FileManager.default.removeItem(at: legacyURL)
                print("📦 [EXPLORE] Migrated legacy cache to permanent storage")
            }
        }

        guard let loadedItems = items else {
            print("📦 [EXPLORE] No cached items found")
            return
        }

        self.exploreMedia = loadedItems

        // Restore scroll cursor so infinite scroll works immediately on re-launch
        self.nextMaxId   = UserDefaults.standard.string(forKey: Self.udKeyNextMaxId)
        self.hasMorePages = UserDefaults.standard.object(forKey: Self.udKeyHasMore) != nil
            ? UserDefaults.standard.bool(forKey: Self.udKeyHasMore)
            : self.nextMaxId != nil
        print("✅ [EXPLORE] Loaded \(loadedItems.count) items from permanent storage (cursor: \(self.nextMaxId?.prefix(20) ?? "nil"), hasMore: \(self.hasMorePages))")

        // Load thumbnails from permanent storage; collect any missing ones
        var missingItems: [InstagramMediaItem] = []
        for item in loadedItems {
            guard !item.imageURL.isEmpty,
                  !item.imageURL.hasPrefix("forced_reel_local") else { continue }
            if let image = loadThumbnailPermanently(forURL: item.imageURL) {
                cachedImages[item.imageURL] = image
            } else {
                missingItems.append(item)
            }
        }

        print("📦 [EXPLORE] Loaded \(cachedImages.count) thumbnails from disk, \(missingItems.count) missing")

        if !missingItems.isEmpty {
            Task { await downloadThumbnails(items: missingItems) }
        }
    }
    
    // MARK: - Load More (Scroll Infinite)
    
    func loadMoreIfNeeded(currentItem: InstagramMediaItem?) {
        guard let currentItem = currentItem else { return }
        
        // Don't load if already loading or no more pages
        guard !isLoading, !isLoadingMore, hasMorePages else { return }
        
        // Check if we're near the end (80% threshold)
        guard let currentIndex = exploreMedia.firstIndex(where: { $0.id == currentItem.id }) else { return }
        
        let thresholdIndex = exploreMedia.count - (exploreMedia.count / 5) // 80%
        
        if currentIndex >= thresholdIndex {
            print("📜 [EXPLORE] User reached 80% - loading more...")
            loadMore()
        }
    }
    
    func loadMore() {
        guard !isLoadingMore, hasMorePages else {
            print("⚠️ [EXPLORE] Cannot load more: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }
        guard !InstagramService.shared.isLocked, !InstagramService.shared.isSessionChallenged else {
            print("🚫 [EXPLORE] Load more skipped — locked or challenged")
            return
        }
        
        isLoadingMore = true
        
        Task {
            do {
                // Start with buffered items from previous load
                var allNewItems = itemBuffer
                print("📜 [EXPLORE] Starting with \(allNewItems.count) buffered items")
                
                // ANTI-BOT: Wait if network changed recently
                try await InstagramService.shared.waitForNetworkStability()
                
                // Load next page if we have maxId
                if let maxId = nextMaxId {
                    print("📜 [EXPLORE] Loading more items (maxId: \(String(maxId.prefix(20)))...)")
                    let (newItems, newMaxId) = try await InstagramService.shared.getExploreFeed(maxId: maxId)
                    
                    print("📜 [EXPLORE] Received \(newItems.count) more items from API")
                    allNewItems.append(contentsOf: newItems)
                    
                    // GRID FIX: Show only multiples of 3 (complete rows)
                    let multipleOf3 = (allNewItems.count / 3) * 3
                    let itemsToShow = Array(allNewItems.prefix(multipleOf3))
                    let itemsToBuffer = Array(allNewItems.suffix(allNewItems.count - multipleOf3))
                    
                    print("📜 [EXPLORE] Total available: \(allNewItems.count)")
                    print("📜 [EXPLORE] Adding \(itemsToShow.count) items (\(itemsToShow.count / 3) rows)")
                    if !itemsToBuffer.isEmpty {
                        print("📜 [EXPLORE] Buffering \(itemsToBuffer.count) items for next load")
                    }
                    
                    await MainActor.run {
                        self.exploreMedia.append(contentsOf: itemsToShow)
                        self.itemBuffer = itemsToBuffer
                        self.nextMaxId = newMaxId
                        self.hasMorePages = newMaxId != nil
                        self.isLoadingMore = false
                        
                        print("✅ [EXPLORE] Now have \(self.exploreMedia.count) total items")
                        print("🔍 [EXPLORE] Has more pages: \(self.hasMorePages)")
                        
                        // Save to cache
                        saveToCache()
                    }
                    
                    // Download thumbnails for new items in background
                    await downloadThumbnails(items: itemsToShow)
                } else {
                    // No more pages, but we might have buffered items
                    if !allNewItems.isEmpty {
                        let multipleOf3 = (allNewItems.count / 3) * 3
                        let itemsToShow = Array(allNewItems.prefix(multipleOf3))
                        
                        if !itemsToShow.isEmpty {
                            print("📜 [EXPLORE] Adding final \(itemsToShow.count) buffered items")
                            await MainActor.run {
                                self.exploreMedia.append(contentsOf: itemsToShow)
                                self.itemBuffer = []
                                self.isLoadingMore = false
                                self.hasMorePages = false
                                saveToCache()
                            }
                            await downloadThumbnails(items: itemsToShow)
                        } else {
                            await MainActor.run {
                                self.isLoadingMore = false
                                self.hasMorePages = false
                            }
                        }
                    } else {
                        await MainActor.run {
                            self.isLoadingMore = false
                            self.hasMorePages = false
                        }
                    }
                }
                
            } catch {
                print("❌ [EXPLORE] Error loading more: \(error)")
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    // MARK: - Force Reel injection

    /// Returns `exploreMedia` with forced reels injected at positions based on
    /// `ForceReelSettings.pendingPosition` (1-based). Multiple reels are spaced
    /// 3 cells apart so they look naturally distributed in the grid.
    func exploreMediaWithForce() -> [InstagramMediaItem] {
        let forceSettings = ForceReelSettings.shared
        guard forceSettings.isEnabled,
              forceSettings.pendingPosition > 0 else {
            return exploreMedia
        }

        let fakeItems = forceSettings.allFakeMediaItems()
        guard !fakeItems.isEmpty else { return exploreMedia }

        var result = exploreMedia
        let basePos = forceSettings.pendingPosition

        for (offset, entry) in fakeItems.enumerated() {
            let pos = basePos + (offset * 3)
            let insertIndex = min(pos - 1 + offset, result.count)
            result.insert(entry.item, at: insertIndex)

            let cacheKey = entry.slot.localCacheKey
            if cachedImages[cacheKey] == nil {
                if let localImage = forceSettings.thumbnailImages[entry.slot.id] {
                    cachedImages[cacheKey] = localImage
                } else if !entry.slot.thumbnailURL.isEmpty {
                    let url = entry.slot.thumbnailURL
                    Task {
                        if let u = URL(string: url),
                           let (data, _) = try? await URLSession.shared.data(from: u),
                           let img = UIImage(data: data) {
                            await MainActor.run { self.cachedImages[cacheKey] = img }
                        }
                    }
                }
            }
        }

        print("🎭 [FORCE] Injected \(fakeItems.count) reel(s) starting at position \(basePos) in Explore grid")
        return result
    }

    func clearCache() {
        exploreMedia.removeAll()
        cachedImages.removeAll()
        itemBuffer.removeAll()
        hasPreloaded = false
        hasMorePages = true
        nextMaxId = nil

        // Delete permanent items JSON
        if let dir = Self.permanentDir {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("explore_items.json"))
        }

        // Delete permanent thumbnails
        clearPermanentThumbnails()

        // Also remove legacy cache file if it still exists
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("explore_cache.json"))
        }

        print("🗑️ [EXPLORE] Cache cleared (permanent + legacy)")
    }
}
