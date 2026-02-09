import SwiftUI

/// Vista de perfil de usuario buscado (similar a PerformanceView pero con botón de cerrar)
struct UserProfileView: View {
    let profile: InstagramProfile
    let onClose: () -> Void
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isLoadingImages = true
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // White background
            Color.white.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Text(profile.username)
                            .font(.system(size: 16, weight: .semibold))
                        
                        Spacer()
                        
                        // Placeholder for symmetry
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    // Profile info
                    VStack(spacing: 16) {
                        // Profile picture
                        if !profile.profilePicURL.isEmpty,
                           let image = cachedImages[profile.profilePicURL] {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 86, height: 86)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 86, height: 86)
                        }
                        
                        // Name
                        Text(profile.fullName)
                            .font(.system(size: 14, weight: .semibold))
                        
                        // Stats
                        HStack(spacing: 40) {
                            UserStatView(number: profile.mediaCount, label: "publicaciones")
                            UserStatView(number: profile.followerCount, label: "seguidores")
                            UserStatView(number: profile.followingCount, label: "seguidos")
                        }
                        .padding(.horizontal, 32)
                        
                        // Bio
                        if !profile.biography.isEmpty {
                            Text(profile.biography)
                                .font(.system(size: 14))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        // URL
                        if let url = profile.externalUrl, !url.isEmpty {
                            Text(url)
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 16)
                    
                    Divider()
                    
                    // Grid tabs
                    HStack(spacing: 0) {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(height: 1),
                                alignment: .bottom
                            )
                    }
                    
                    // Photo grid
                    LazyVStack(spacing: 2) {
                        ForEach(0..<((profile.cachedMediaURLs.count + 2) / 3), id: \.self) { rowIndex in
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { colIndex in
                                    let index = rowIndex * 3 + colIndex
                                    if index < profile.cachedMediaURLs.count {
                                        let imageURL = profile.cachedMediaURLs[index]
                                        if let image = cachedImages[imageURL] {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: UIScreen.main.bounds.width / 3 - 1.33, height: UIScreen.main.bounds.width / 3 - 1.33)
                                                .clipped()
                                        } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: UIScreen.main.bounds.width / 3 - 1.33, height: UIScreen.main.bounds.width / 3 - 1.33)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            print("🎨 [UI] UserProfileView appeared for @\(profile.username)")
            print("🎨 [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
            print("🎨 [UI] Profile pic URL: \(profile.profilePicURL)")
            loadImages()
        }
    }
    
    private func loadImages() {
        print("🖼️ [UI] Starting to load images...")
        
        Task {
            // Load profile pic
            print("🖼️ [UI] Loading profile pic: \(profile.profilePicURL)")
            if !profile.profilePicURL.isEmpty,
               let url = URL(string: profile.profilePicURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    cachedImages[profile.profilePicURL] = image
                    print("✅ [UI] Profile pic loaded and cached")
                }
            } else {
                print("❌ [UI] Failed to load profile pic")
            }
            
            // Load follower pics
            for follower in profile.followedBy {
                if let picURL = follower.profilePicURL,
                   !picURL.isEmpty,
                   let url = URL(string: picURL),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        cachedImages[picURL] = image
                    }
                }
            }
            
            // Load media thumbnails
            for mediaURL in profile.cachedMediaURLs {
                guard !mediaURL.isEmpty,
                      let url = URL(string: mediaURL),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { continue }
                
                await MainActor.run {
                    cachedImages[mediaURL] = image
                }
            }
            
            await MainActor.run {
                isLoadingImages = false
            }
        }
    }
}

private struct UserStatView: View {
    let number: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(formatCount(number))")
                .font(.system(size: 16, weight: .semibold))
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}
