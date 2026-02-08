import Foundation
import UIKit

/// Service to cache Instagram profile data and images
class ProfileCacheService {
    static let shared = ProfileCacheService()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Get cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ProfileCache", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
