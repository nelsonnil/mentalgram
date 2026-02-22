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
    
    private var nextMaxId: String?
    private var hasPreloaded = false
    private var hasMorePages = true
    private var itemBuffer: [InstagramMediaItem] = [] // Buffer para items que no caben en grid de 3
    
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
        
        isLoading = true
        
        Task {
            await loadExploreInternal()
            await MainActor.run {
                isLoading = false
            }
        }
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
                
                // Save to cache
                saveToCache()
                
                print("✅ [EXPLORE] Loaded \(itemsToShow.count) items into UI")
                print("🔍 [EXPLORE] Has more pages: \(self.hasMorePages)")
            }
            
            // Download thumbnails in background
            await downloadThumbnails(items: itemsToShow)
            
        } catch {
            print("❌ [EXPLORE] Error loading: \(error)")
            await MainActor.run {
                // Try loading from cache on error
                if self.exploreMedia.isEmpty {
                    print("🔍 [EXPLORE] Trying to load from cache after error...")
                }
            }
        }
    }
    
    // MARK: - Download Thumbnails
    
    private func downloadThumbnails(items: [InstagramMediaItem]) async {
        print("🖼️ [EXPLORE] Downloading \(items.count) thumbnails...")
        
        for (index, item) in items.enumerated() {
            guard !item.imageURL.isEmpty else { continue }
            
            // Check if already cached
            if cachedImages[item.imageURL] != nil {
                continue
            }
            
            if let image = await downloadImage(from: item.imageURL) {
                await MainActor.run {
                    cachedImages[item.imageURL] = image
                    ProfileCacheService.shared.saveImage(image, forURL: item.imageURL)
                }
                
                if (index + 1) % 10 == 0 {
                    print("🖼️ [EXPLORE] Downloaded \(index + 1)/\(items.count)")
                }
            }
        }
        
        print("✅ [EXPLORE] All thumbnails downloaded")
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
    
    // MARK: - Cache Management
    
    private func saveToCache() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(exploreMedia),
           let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileURL = cacheDir.appendingPathComponent("explore_cache.json")
            try? data.write(to: fileURL)
            print("💾 [EXPLORE] Saved to cache")
        }
    }
    
    private func loadFromCache() {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        let fileURL = cacheDir.appendingPathComponent("explore_cache.json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            print("📦 [EXPLORE] No cache found")
            return
        }
        
        let decoder = JSONDecoder()
        if let items = try? decoder.decode([InstagramMediaItem].self, from: data) {
            self.exploreMedia = items
            print("✅ [EXPLORE] Loaded \(items.count) items from cache")
            
            // Load cached images + detect missing ones
            var missingItems: [InstagramMediaItem] = []
            for item in items {
                if let image = ProfileCacheService.shared.loadImage(forURL: item.imageURL) {
                    cachedImages[item.imageURL] = image
                } else if !item.imageURL.isEmpty {
                    missingItems.append(item)
                }
            }
            
            print("📦 [EXPLORE] Loaded \(cachedImages.count) images from cache, \(missingItems.count) missing")
            
            // Download missing thumbnails in background
            if !missingItems.isEmpty {
                Task {
                    await downloadThumbnails(items: missingItems)
                }
            }
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

    /// Returns `exploreMedia` with the forced reel injected at the position
    /// stored in `ForceReelSettings.pendingPosition` (1-based, consumed once).
    /// If Force Reel is disabled or no position/reel is set, returns the array unchanged.
    func exploreMediaWithForce() -> [InstagramMediaItem] {
        let forceSettings = ForceReelSettings.shared
        guard forceSettings.isEnabled,
              forceSettings.pendingPosition > 0,
              let forcedItem = forceSettings.asFakeMediaItem() else {
            return exploreMedia
        }

        let pos = forceSettings.pendingPosition          // 1-based
        let insertIndex = min(pos - 1, exploreMedia.count)   // clamp to array bounds

        var result = exploreMedia
        result.insert(forcedItem, at: insertIndex)

        // Pre-cache the forced reel thumbnail so it shows immediately
        if cachedImages[forcedItem.imageURL] == nil {
            Task {
                if let url = URL(string: forcedItem.imageURL),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let img = UIImage(data: data) {
                    await MainActor.run { cachedImages[forcedItem.imageURL] = img }
                }
            }
        }

        print("🎭 [FORCE] Injected reel at position \(pos) (index \(insertIndex)) in Explore grid (\(result.count) total items)")
        return result
    }

    func clearCache() {
        exploreMedia.removeAll()
        cachedImages.removeAll()
        itemBuffer.removeAll()
        hasPreloaded = false
        hasMorePages = true
        nextMaxId = nil
        
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileURL = cacheDir.appendingPathComponent("explore_cache.json")
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        print("🗑️ [EXPLORE] Cache cleared")
    }
}
