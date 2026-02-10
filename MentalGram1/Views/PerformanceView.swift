import SwiftUI

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content (Instagram replica)
            ZStack {
                if let profile = profile {
                    InstagramProfileView(
                        profile: profile,
                        cachedImages: $cachedImages,
                        onRefresh: loadProfile,
                        onPlusPress: {
                            // Back to Sets tab
                            selectedTab = 1
                        }
                    )
                } else {
                    // Show skeleton UI (like Instagram real)
                    // Shown when: loading, network stabilizing, or no data
                    InstagramProfileSkeleton()
                }
            }
            .padding(.bottom, 65) // Space for Instagram bottom bar (matches bar height)
            
            // Instagram-style bottom bar (white bar with icons)
            InstagramBottomBar(
                profileImageURL: profile?.profilePicURL,
                cachedImage: profile?.profilePicURL != nil ? cachedImages[profile!.profilePicURL] : nil,
                isHome: true,
                isSearch: false,
                onHomePress: {
                    // Already on home/profile, do nothing
                },
                onSearchPress: {
                    // Open Explore view
                    showingExplore = true
                },
                onReelsPress: {
                    // Reels action (disabled for now)
                },
                onMessagesPress: {
                    // Messages action (disabled for now)
                },
                onProfilePress: {
                    // Already on profile, do nothing
                }
            )
        }
        .toolbar(.hidden, for: .tabBar) // HIDE native TabBar in Performance
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(true)
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        .onAppear {
            checkAndLoadProfile()
        }
    }
    
    private func checkAndLoadProfile() {
        // ALWAYS try to load from cache first (anti-bot: no automatic requests)
        if let cached = ProfileCacheService.shared.loadProfile() {
            print("📦 [CACHE] Loading profile from cache (no auto-request)")
            self.profile = cached
            loadCachedImages()
            // DON'T make automatic request - user can pull-to-refresh if needed
        } else {
            // Only if NO cache, load fresh (with network stability check)
            print("📦 [CACHE] No cached profile found, loading fresh")
            loadProfile()
        }
    }
    
    private func loadProfile() {
        guard instagram.isLoggedIn else { return }
        
        isLoading = true
        
        // Clear old cache first
        print("🗑️ [CACHE] Clearing old cache before fresh load")
        ProfileCacheService.shared.clearAll()
        cachedImages.removeAll()
        
        Task {
            do {
                // ANTI-BOT: Wait if network changed recently
                try await instagram.waitForNetworkStability()
                
                let fetchedProfile = try await instagram.getProfileInfo()
                
                await MainActor.run {
                    if let fetchedProfile = fetchedProfile {
                        self.profile = fetchedProfile
                        ProfileCacheService.shared.saveProfile(fetchedProfile)
                        downloadAndCacheImages(profile: fetchedProfile)
                    }
                    isLoading = false
                }
            } catch let error as InstagramError {
                print("⚠️ Instagram error detected: \(error)")
                await MainActor.run {
                    isLoading = false
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ Error loading profile: \(error)")
                await MainActor.run {
                    isLoading = false
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }
    
    private func loadCachedImages() {
        guard let profile = profile else { return }
        
        print("📦 [CACHE] Loading cached images...")
        
        // Load profile pic
        print("📦 [CACHE] Looking for profile pic: \(String(profile.profilePicURL.prefix(80)))")
        if let image = ProfileCacheService.shared.loadImage(forURL: profile.profilePicURL) {
            cachedImages[profile.profilePicURL] = image
            print("✅ [CACHE] Profile pic loaded from cache")
        } else {
            print("⚠️ [CACHE] Profile pic not found in cache, will download")
            // If not in cache, download it now
            Task {
                if let image = await downloadImage(from: profile.profilePicURL) {
                    await MainActor.run {
                        cachedImages[profile.profilePicURL] = image
                        ProfileCacheService.shared.saveImage(image, forURL: profile.profilePicURL)
                        print("✅ [CACHE] Profile pic downloaded and cached")
                    }
                }
            }
        }
        
        // Load media thumbnails
        var loadedCount = 0
        for url in profile.cachedMediaURLs {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                loadedCount += 1
            }
        }
        print("📦 [CACHE] Loaded \(loadedCount)/\(profile.cachedMediaURLs.count) media thumbnails from cache")
        
        // Load followed by profile pics
        var followerPicsLoaded = 0
        for follower in profile.followedBy {
            if let picURL = follower.profilePicURL,
               let image = ProfileCacheService.shared.loadImage(forURL: picURL) {
                cachedImages[picURL] = image
                followerPicsLoaded += 1
            }
        }
        print("📦 [CACHE] Loaded \(followerPicsLoaded)/\(profile.followedBy.count) follower pics from cache")
        
        print("📦 [CACHE] Total cached images loaded: \(cachedImages.count)")
    }
    
    private func downloadAndCacheImages(profile: InstagramProfile) {
        Task {
            // Download profile pic
            print("🖼️ [CACHE] Downloading profile pic: \(String(profile.profilePicURL.prefix(80)))...")
            if let image = await downloadImage(from: profile.profilePicURL) {
                await MainActor.run {
                    cachedImages[profile.profilePicURL] = image
                    ProfileCacheService.shared.saveImage(image, forURL: profile.profilePicURL)
                    print("✅ [CACHE] Profile pic downloaded and cached")
                }
            } else {
                print("❌ [CACHE] Failed to download profile pic")
            }
            
            // Download media thumbnails
            print("🖼️ [CACHE] Downloading \(profile.cachedMediaURLs.count) media thumbnails...")
            for (index, url) in profile.cachedMediaURLs.enumerated() {
                if let image = await downloadImage(from: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                        ProfileCacheService.shared.saveImage(image, forURL: url)
                    }
                    print("✅ [CACHE] Media \(index + 1)/\(profile.cachedMediaURLs.count) downloaded")
                } else {
                    print("❌ [CACHE] Failed to download media \(index + 1)")
                }
            }
            
            // Download followed by profile pics
            print("🖼️ [CACHE] Downloading \(profile.followedBy.count) follower profile pics...")
            for (index, follower) in profile.followedBy.enumerated() {
                if let picURL = follower.profilePicURL {
                    print("🖼️ [CACHE] Downloading follower \(index + 1) pic: \(String(picURL.prefix(60)))...")
                    if let image = await downloadImage(from: picURL) {
                        await MainActor.run {
                            cachedImages[picURL] = image
                            ProfileCacheService.shared.saveImage(image, forURL: picURL)
                            print("✅ [CACHE] Follower \(index + 1) pic downloaded")
                        }
                    } else {
                        print("❌ [CACHE] Failed to download follower \(index + 1) pic")
                    }
                } else {
                    print("⚠️ [CACHE] Follower \(index + 1) has no profile pic URL")
                }
            }
            
            print("✅ [CACHE] All images download process completed")
        }
    }
    
    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else {
            print("⚠️ [DOWNLOAD] Empty URL string")
            return nil
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ [DOWNLOAD] Invalid URL: \(urlString)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 [DOWNLOAD] HTTP \(httpResponse.statusCode) for: \(String(urlString.prefix(60)))...")
                
                if httpResponse.statusCode != 200 {
                    print("❌ [DOWNLOAD] Non-200 status code")
                    return nil
                }
            }
            
            guard let image = UIImage(data: data) else {
                print("❌ [DOWNLOAD] Failed to create UIImage from data")
                return nil
            }
            
            return image
        } catch {
            print("❌ [DOWNLOAD] Error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Instagram Profile View

struct InstagramProfileView: View {
    let profile: InstagramProfile
    @Binding var cachedImages: [String: UIImage]
    let onRefresh: () -> Void
    let onPlusPress: () -> Void
    @State private var selectedTab = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                InstagramHeaderView(username: profile.username, isVerified: profile.isVerified, onRefresh: onRefresh, onPlusPress: onPlusPress)
                
                // Profile Info
                VStack(spacing: 16) {
                    // Profile Picture + Stats
                    HStack(alignment: .center, spacing: 0) {
                        // Profile Picture
                        ZStack(alignment: .bottomTrailing) {
                            if let image = cachedImages[profile.profilePicURL] {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 86, height: 86)
                                    .clipShape(Circle())
                                    .onAppear {
                                        print("✅ [UI] Profile pic image displayed")
                                    }
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 86, height: 86)
                                    .overlay(
                                        VStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Cargando...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                                    .onAppear {
                                        print("⚠️ [UI] Profile pic not in cache")
                                        print("⚠️ [UI] Looking for URL: \(String(profile.profilePicURL.prefix(80)))")
                                        print("⚠️ [UI] Available cached URLs: \(cachedImages.keys.map { String($0.prefix(40)) }.joined(separator: ", "))")
                                    }
                            }
                            
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .padding(.leading, UIScreen.main.bounds.width * 0.04)
                        
                        Spacer(minLength: 8)
                        
                        // Stats
                        HStack(spacing: 0) {
                            StatView(number: profile.mediaCount, label: "publicaciones")
                            StatView(number: profile.followerCount, label: "seguidores")
                            StatView(number: profile.followingCount, label: "seguidos")
                        }
                        .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                    }
                    
                    // Name + Bio
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.fullName)
                            .font(.system(size: 14, weight: .semibold))
                        
                        if !profile.biography.isEmpty {
                            Text(profile.biography)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if let url = profile.externalUrl {
                            Link(url, destination: URL(string: "https://\(url)")!)
                                .font(.system(size: 14))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .responsiveHorizontalPadding()
                    
                    // Followed by
                    if !profile.followedBy.isEmpty {
                        FollowedByView(followers: profile.followedBy, cachedImages: cachedImages)
                            .responsiveHorizontalPadding()
                    }
                    
                    // Edit Profile + Share Profile buttons
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Text("Editar perfil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Text("Compartir perfil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                    }
                    .responsiveHorizontalPadding()
                    
                    // Story Highlights (placeholder)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.primary)
                                    )
                                Text("Nuevo")
                                    .font(.system(size: 12))
                            }
                            
                            // Placeholder highlights
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 64, height: 64)
                                    Text("Historia")
                                        .font(.system(size: 12))
                                }
                            }
                        }
                        .responsiveHorizontalPadding()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.vertical, 12)
                
                // Tabs
                HStack(spacing: 0) {
                    TabButton(icon: "square.grid.3x3", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabButton(icon: "play.rectangle", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabButton(icon: "person.crop.square", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                }
                .frame(height: 44)
                
                Divider()
                
                // Photos Grid
                if selectedTab == 0 {
                    if profile.cachedMediaURLs.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            
                            Text("No hay publicaciones")
                                .font(.headline)
                            
                            Text("Las fotos pueden estar archivadas")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button("Recargar Perfil") {
                                onRefresh()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        PhotosGridView(mediaURLs: profile.cachedMediaURLs, cachedImages: cachedImages)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Instagram Header

struct InstagramHeaderView: View {
    let username: String
    let isVerified: Bool
    let onRefresh: () -> Void
    let onPlusPress: () -> Void
    
    var body: some View {
        HStack {
            // Plus button (closes Performance and goes to Sets)
            Button(action: onPlusPress) {
                Image(systemName: "plus.app")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Username with dropdown
            HStack(spacing: 4) {
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                Text(username)
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                // At symbol button (refresh)
                Button(action: onRefresh) {
                    Image(systemName: "at")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                // Menu button
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                }
            }
        }
        .responsiveHorizontalPadding()
        .frame(height: 44)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Stat View

struct StatView: View {
    let number: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatNumber(number))
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1f M", Double(num) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        } else if num >= 1_000 {
            return String(format: "%.1f K", Double(num) / 1_000).replacingOccurrences(of: ".", with: ",")
        } else {
            return "\(num)"
        }
    }
}

// MARK: - Followed By View

struct FollowedByView: View {
    let followers: [InstagramFollower]
    let cachedImages: [String: UIImage]
    
    var body: some View {
        HStack(spacing: 4) {
            // Profile pictures
            HStack(spacing: -8) {
                ForEach(followers.prefix(3), id: \.userId) { follower in
                    if let picURL = follower.profilePicURL,
                       let image = cachedImages[picURL] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    }
                }
            }
            
            // Text
            if followers.count >= 2 {
                Text("Seguido/a por ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text(followers[0].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                + Text(", ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text(followers[1].username)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                + Text(" y ")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                + Text("\(max(0, followers.count - 2)) más")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(
                    Rectangle()
                        .fill(isSelected ? Color.primary : Color.clear)
                        .frame(height: 1),
                    alignment: .bottom
                )
        }
    }
}

// MARK: - Photos Grid

struct PhotosGridView: View {
    let mediaURLs: [String]
    let cachedImages: [String: UIImage]
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(mediaURLs, id: \.self) { url in
                if let image = cachedImages[url] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(4/5, contentMode: .fill) // Instagram aspect ratio (más alto que ancho)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(4/5, contentMode: .fill) // Instagram aspect ratio
                }
            }
        }
    }
}

// MARK: - Instagram Bottom Bar

struct InstagramBottomBar: View {
    let profileImageURL: String?
    let cachedImage: UIImage?
    let isHome: Bool
    let isSearch: Bool
    let onHomePress: () -> Void
    let onSearchPress: () -> Void
    let onReelsPress: () -> Void
    let onMessagesPress: () -> Void
    let onProfilePress: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            // White background with top border
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 0, x: 0, y: -0.33)
            
            // Icons aligned to top
            HStack(spacing: 0) {
                // Home button (house outline)
                Button(action: onHomePress) {
                    Image(systemName: isHome ? "house.fill" : "house")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Search button (magnifying glass)
                Button(action: onSearchPress) {
                    Image(systemName: isSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Reels button (play in rounded rectangle)
                Button(action: onReelsPress) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Messages button (paper plane with red dot)
                Button(action: onMessagesPress) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.black)
                        
                        // Red notification dot
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 6, y: -3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                
                // Profile button (circular profile pic)
                Button(action: onProfilePress) {
                    if let image = cachedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 1.5)
                            )
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 26))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .frame(height: 65) // Taller bar
        }
        .frame(height: 65)
    }
}
