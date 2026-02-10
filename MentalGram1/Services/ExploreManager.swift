import Foundation
import UIKit
import Combine

/// Manager for Instagram Explore Feed with background loading and caching
class ExploreManager: ObservableObject {
    static let shared = ExploreManager()
    
    @Published var exploreMedia: [InstagramMediaItem] = []
    @Published var cachedImages: [String: UIImage] = [:]
    @Published var isLoading = false
    
    private var nextMaxId: String?
    private var hasPreloaded = false
    
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
            // TODO: getExploreFeed() needs to be implemented in InstagramService
            // let (items, maxId) = try await InstagramService.shared.getExploreFeed()
            let items: [InstagramMediaItem] = [] // Temporary: empty for now
            let maxId: String? = nil
            
            print("🔍 [EXPLORE] Received \(items.count) items from API")
            
            await MainActor.run {
                self.exploreMedia = items
                self.nextMaxId = maxId
                
                // Save to cache
                saveToCache()
                
                print("✅ [EXPLORE] Loaded \(items.count) items into UI")
            }
            
            // Download thumbnails in background
            await downloadThumbnails(items: items)
            
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
            
            // Load cached images
            for item in items {
                if let image = ProfileCacheService.shared.loadImage(forURL: item.imageURL) {
                    cachedImages[item.imageURL] = image
                }
            }
        }
    }
    
    func clearCache() {
        exploreMedia.removeAll()
        cachedImages.removeAll()
        hasPreloaded = false
        
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fileURL = cacheDir.appendingPathComponent("explore_cache.json")
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        print("🗑️ [EXPLORE] Cache cleared")
    }
}
