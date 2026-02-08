import SwiftUI

// MARK: - Main Home View

struct HomeView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @State private var selectedTab = 1 // Start on Sets tab
    @State private var showingCreateSet = false
    @State private var showingExplore = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Performance Tab (Instagram Replica)
            PerformanceView(selectedTab: $selectedTab, showingExplore: $showingExplore)
                .tabItem {
                    Label("Performance", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            // Sets Tab
            NavigationView {
                SetsListView()
            }
            .tabItem {
                Label("Sets", systemImage: "square.grid.2x2")
            }
            .tag(1)
            
            // Quick Reveal Tab
            NavigationView {
                QuickRevealView()
            }
            .tabItem {
                Label("Reveal", systemImage: "wand.and.stars")
            }
            .tag(2)
            
            // Settings Tab
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(3)
        }
        .accentColor(.purple)
        .fullScreenCover(isPresented: $showingExplore) {
            ExploreView(selectedTab: $selectedTab, showingExplore: $showingExplore)
        }
        .onAppear {
            // Preload explore feed in background when app launches
            ExploreManager.shared.preloadExploreInBackground()
        }
    }
}

// MARK: - Sets List View

struct SetsListView: View {
    @ObservedObject var dataManager = DataManager.shared
    @State private var showingCreateSet = false
    
    var body: some View {
        ZStack {
            if dataManager.sets.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("No Sets Yet")
                        .font(.title2.bold())
                    
                    Text("Create your first photo set")
                        .foregroundColor(.secondary)
                    
                    Button(action: { showingCreateSet = true }) {
                        Label("Create Set", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                }
            } else {
                List {
                    ForEach(dataManager.sets) { set in
                        NavigationLink(destination: SetDetailView(set: set)) {
                            SetRowView(set: set)
                        }
                    }
                    .onDelete(perform: deleteSets)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Sets")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSet) {
            CreateSetView(isPresented: $showingCreateSet)
        }
    }
    
    private func deleteSets(at offsets: IndexSet) {
        for index in offsets {
            let set = dataManager.sets[index]
            dataManager.deleteSet(id: set.id)
        }
    }
}

// MARK: - Set Row View

struct SetRowView: View {
    let set: PhotoSet
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: set.type.icon)
                    .foregroundColor(.purple)
                
                Text(set.name)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: set.status.icon)
                    .foregroundColor(set.status.color)
            }
            
            HStack {
                Text("\(set.banks.isEmpty ? "1" : "\(set.banks.count)") banks")
                Text("•")
                Text("\(set.totalPhotos) photos")
                
                if set.status == .completed {
                    Text("•")
                    Text(set.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Progress bar for uploading
            if set.status == .uploading || set.status == .paused {
                ProgressView(value: Double(set.uploadedPhotos), total: Double(set.totalPhotos))
                    .tint(.purple)
                
                Text("\(set.uploadedPhotos) / \(set.totalPhotos)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var dataManager = DataManager.shared
    
    var body: some View {
        List {
            ForEach(dataManager.logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.action)
                            .font(.headline)
                        Spacer()
                        Text(log.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(log.details)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Activity")
        .listStyle(.insetGrouped)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var showingLogoutAlert = false
    @State private var showingFollowerData = false
    @State private var latestFollower: InstagramFollower?
    @State private var followerFullInfo: [String: Any]?
    @State private var isLoadingFollower = false
    
    var body: some View {
        List {
            Section("Account") {
                if instagram.isLoggedIn {
                    HStack {
                        Text("Logged in as")
                        Spacer()
                        Text("@\(instagram.session.username)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive, action: { showingLogoutAlert = true }) {
                        Text("Logout")
                    }
                } else {
                    Text("Not logged in")
                        .foregroundColor(.secondary)
                }
            }
            
            // Nueva sección Debug
            if instagram.isLoggedIn {
                Section("Debug & Testing") {
                    Button(action: fetchLatestFollower) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(.purple)
                            Text("Get Latest Follower Data")
                            Spacer()
                            if isLoadingFollower {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .disabled(isLoadingFollower)
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text("1")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Logout", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                instagram.logout()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .sheet(isPresented: $showingFollowerData) {
            FollowerDataSheet(follower: latestFollower, fullInfo: followerFullInfo)
        }
    }
    
    private func fetchLatestFollower() {
        isLoadingFollower = true
        
        Task {
            do {
                // Step 1: Get latest follower
                let follower = try await instagram.getLatestFollower()
                
                // Step 2: Get full info if we have a follower
                var fullInfo: [String: Any]?
                if let follower = follower {
                    fullInfo = try await instagram.getUserFullInfo(userId: follower.userId)
                }
                
                await MainActor.run {
                    latestFollower = follower
                    followerFullInfo = fullInfo
                    showingFollowerData = true
                    isLoadingFollower = false
                }
            } catch {
                print("❌ Error fetching follower: \(error)")
                await MainActor.run {
                    isLoadingFollower = false
                }
            }
        }
    }
}

// MARK: - Follower Data Sheet

struct FollowerDataSheet: View {
    let follower: InstagramFollower?
    let fullInfo: [String: Any]?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                if let follower = follower {
                    VStack(spacing: 24) {
                        // Profile Picture
                        if let picURL = follower.profilePicURL,
                           let url = URL(string: picURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: 3))
                        }
                        
                        // User Info
                        VStack(spacing: 12) {
                            Text("@\(follower.username)")
                                .font(.title2.bold())
                            
                            if !follower.fullName.isEmpty {
                                Text(follower.fullName)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Stats (si tenemos fullInfo)
                        if let info = fullInfo {
                            HStack(spacing: 20) {
                                if let posts = info["media_count"] as? Int {
                                    StatBadge(label: "Posts", value: "\(posts)")
                                }
                                if let followers = info["follower_count"] as? Int {
                                    StatBadge(label: "Followers", value: formatCount(followers))
                                }
                                if let following = info["following_count"] as? Int {
                                    StatBadge(label: "Following", value: formatCount(following))
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Bio (si existe)
                        if let info = fullInfo,
                           let bio = info["biography"] as? String,
                           !bio.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Bio")
                                    .font(.headline)
                                
                                Text(bio)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        
                        // Data Cards
                        VStack(alignment: .leading, spacing: 16) {
                            DataRow(label: "User ID", value: follower.userId)
                            DataRow(label: "Username", value: "@\(follower.username)")
                            DataRow(label: "Full Name", value: follower.fullName.isEmpty ? "N/A" : follower.fullName)
                            
                            // Datos adicionales de fullInfo
                            if let info = fullInfo {
                                if let isVerified = info["is_verified"] as? Bool {
                                    DataRow(label: "Verified", value: isVerified ? "✓ Yes" : "✗ No")
                                }
                                if let isPrivate = info["is_private"] as? Bool {
                                    DataRow(label: "Private Account", value: isPrivate ? "✓ Yes" : "✗ No")
                                }
                                if let externalURL = info["external_url"] as? String, !externalURL.isEmpty {
                                    DataRow(label: "Website", value: externalURL)
                                }
                            }
                            
                            if let picURL = follower.profilePicURL {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Profile Picture URL")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Text(picURL)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .textSelection(.enabled)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Preview Comment
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comment Preview")
                                .font(.headline)
                            
                            Text("\(follower.fullName.isEmpty ? follower.username : follower.fullName), this was written for you")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(10)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No follower data")
                            .font(.headline)
                        
                        Text("Unable to fetch latest follower")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Latest Follower")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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

struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.purple)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 12)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}
