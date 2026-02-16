import SwiftUI

// MARK: - Main Home View

struct HomeView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @State private var selectedTab = 1 // Start on Sets tab
    @State private var showingCreateSet = false
    @State private var showingExplore = false
    @State private var showingChallengeAlert = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Performance Tab - MUST stay light (Instagram replica)
            Group {
                if instagram.isLoggedIn {
                    PerformanceView(selectedTab: $selectedTab, showingExplore: $showingExplore)
                } else {
                    // Blank dark view when not logged in
                    VaultTheme.Colors.background
                        .ignoresSafeArea()
                }
            }
            .tabItem {
                Label("Performance", systemImage: "chart.bar.fill")
            }
            .tag(0)
            
            // Sets Tab - dark theme
            NavigationView {
                SetsListView()
            }
            .tabItem {
                Label("Sets", systemImage: "square.grid.2x2.fill")
            }
            .tag(1)
            
            // Settings Tab - dark theme
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .accentColor(selectedTab == 0 ? .primary : VaultTheme.Colors.primary)
        .onChange(of: selectedTab) { newTab in
            // Dynamically update tab bar appearance based on selected tab
            updateTabBarAppearance(forTab: newTab)
        }
        .onAppear {
            // Set initial tab bar appearance
            updateTabBarAppearance(forTab: selectedTab)
        }
        .fullScreenCover(isPresented: $showingExplore) {
            ExploreView(selectedTab: $selectedTab, showingExplore: $showingExplore)
                .preferredColorScheme(.light) // CRITICAL: Explore must look like Instagram (light)
        }
    }
    
    /// Update tab bar appearance based on which tab is active
    /// Performance tab = Instagram-style (light), Sets/Settings = Vault dark theme
    private func updateTabBarAppearance(forTab tab: Int) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        if tab == 0 {
            // Performance: Instagram-style white tab bar
            appearance.backgroundColor = .white
            appearance.stackedLayoutAppearance.selected.iconColor = .black
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.black
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = .gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.gray
            ]
        } else {
            // Sets/Settings: Vault dark theme
            appearance.backgroundColor = UIColor(VaultTheme.Colors.backgroundSecondary)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(VaultTheme.Colors.primary)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(VaultTheme.Colors.primary)
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(VaultTheme.Colors.textSecondary)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(VaultTheme.Colors.textSecondary)
            ]
        }
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Sets List View

struct SetsListView: View {
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var instagram = InstagramService.shared
    @State private var showingCreateSet = false
    @State private var newlyCreatedSet: PhotoSet? = nil
    @State private var navigateToNewSet = false
    
    var body: some View {
        ZStack {
            // Dark background
            VaultTheme.Colors.background
                .ignoresSafeArea()
            
            // Hidden NavigationLink for programmatic navigation to newly created set
            if let newSet = newlyCreatedSet {
                NavigationLink(
                    destination: SetDetailView(set: newSet),
                    isActive: $navigateToNewSet
                ) {
                    EmptyView()
                }
                .hidden()
            }
            
            if dataManager.sets.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash.fill",
                    title: "No Sets Yet",
                    message: "Create your first photo set to get started with magic performances",
                    actionTitle: "Create Set",
                    action: { showingCreateSet = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: VaultTheme.Spacing.md) {
                        ForEach(dataManager.sets) { set in
                            NavigationLink(destination: SetDetailView(set: set)) {
                                SetRowView(set: set, isLoggedIn: instagram.isLoggedIn)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation {
                                        dataManager.deleteSet(id: set.id)
                                    }
                                } label: {
                                    Label("Delete Set", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(VaultTheme.Spacing.lg)
                }
            }
        }
        .navigationTitle("My Sets")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSet = true }) {
                    ZStack {
                        Circle()
                            .fill(VaultTheme.Colors.gradientPrimary)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingCreateSet) {
            CreateSetView(isPresented: $showingCreateSet) { createdSet in
                // Callback when set is created: navigate to it automatically
                newlyCreatedSet = createdSet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToNewSet = true
                }
            }
        }
        .preferredColorScheme(.dark)
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
    let isLoggedIn: Bool
    
    private var statusBadgeStyle: StatusBadge.BadgeStyle {
        switch set.status {
        case .ready: return .info
        case .uploading: return .warning
        case .paused: return .pending
        case .completed: return .success
        case .error: return .error
        }
    }
    
    private var typeGradient: [Color] {
        switch set.type {
        case .word: return [VaultTheme.Colors.primary, VaultTheme.Colors.primaryDark]
        case .number: return [VaultTheme.Colors.secondary, VaultTheme.Colors.secondaryDark]
        case .custom: return [VaultTheme.Colors.info, Color(hex: "6366F1")]
        }
    }
    
    var body: some View {
        VaultCard {
            HStack(spacing: VaultTheme.Spacing.md) {
                // Type icon with gradient
                IconBadge(icon: set.type.icon, colors: typeGradient, size: 56)
                
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                    // Title + Status Badge
                    HStack {
                        Text(set.name)
                            .font(VaultTheme.Typography.title())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Only show status badge when logged in
                        if isLoggedIn {
                            StatusBadge(text: set.status.rawValue, style: statusBadgeStyle)
                        }
                    }
                    
                    // Stats row
                    HStack(spacing: VaultTheme.Spacing.md) {
                        // Type label
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10))
                            Text(set.type.title)
                        }
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                        Text("•")
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                        // Banks
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 10))
                            Text("\(set.banks.isEmpty ? 1 : set.banks.count)")
                        }
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                        Text("•")
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                        // Photos
                        HStack(spacing: 4) {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 10))
                            Text("\(set.totalPhotos)")
                        }
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textTertiary)
                        
                        // Only show completion date when logged in
                        if isLoggedIn && set.status == .completed, let completedDate = set.completedAt {
                            Text("•")
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text(completedDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    }
                    
                    // Progress bar for uploading - ONLY VISIBLE WHEN LOGGED IN
                    if isLoggedIn && (set.status == .uploading || set.status == .paused) {
                        VStack(spacing: 6) {
                            ProgressBar(
                                progress: set.totalPhotos > 0 ? Double(set.uploadedPhotos) / Double(set.totalPhotos) : 0,
                                height: 6,
                                gradient: set.status == .paused 
                                    ? LinearGradient(colors: [VaultTheme.Colors.textSecondary], startPoint: .leading, endPoint: .trailing)
                                    : VaultTheme.Colors.gradientWarning
                            )
                            
                            HStack {
                                Text("\(set.uploadedPhotos) / \(set.totalPhotos)")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                
                                Spacer()
                                
                                let percentage = set.totalPhotos > 0 ? Int((Double(set.uploadedPhotos) / Double(set.totalPhotos)) * 100) : 0
                                Text("\(percentage)%")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .fontWeight(.bold)
                                    .foregroundColor(set.status == .paused ? VaultTheme.Colors.textSecondary : VaultTheme.Colors.warning)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .glowEffect(color: isLoggedIn && set.status == .uploading ? VaultTheme.Colors.warning : .clear, radius: 8)
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
    @State private var showingResetDeviceAlert = false
    @State private var showingFollowerData = false
    @State private var latestFollower: InstagramFollower?
    @State private var followerFullInfo: [String: Any]?
    @State private var isLoadingFollower = false
    
    // Profile Picture Change
    @State private var showingImagePicker = false
    @State private var selectedImageData: Data?
    @State private var isUploadingProfilePic = false
    @State private var uploadMessage: String?
    @State private var showingUploadAlert = false
    
    // Instagram Notes
    @State private var noteText: String = ""
    @State private var isSendingNote = false
    @State private var noteMessage: String?
    @State private var showingNoteAlert = false
    
    // Hidden Login (easter egg)
    @State private var showingLogin = false
    @State private var developerMode = false
    
    // Secret Input - Observing to update example
    @ObservedObject var secretInputSettings = SecretInputSettings.shared
    
    // TEST: Archive access
    @State private var isTestingArchive = false
    @State private var archiveTestResult: String?
    
    private var exampleMaskOutput: String {
        let word = "coche"
        let maskText = secretInputSettings.mode == .customUsername
            ? secretInputSettings.customUsername.lowercased()
            : "user"
        
        if maskText.isEmpty {
            return "user"
        }
        
        var result = ""
        for i in 0..<word.count {
            let maskIndex = i % maskText.count
            result.append(maskText[maskText.index(maskText.startIndex, offsetBy: maskIndex)])
        }
        return result
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: VaultTheme.Spacing.lg) {
                // MARK: About - Always visible at top
                VaultCard {
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                        Text("About")
                            .font(VaultTheme.Typography.titleSmall())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        
                        HStack {
                            Text("Version")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Spacer()
                            Text("1.0.0")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .onLongPressGesture(minimumDuration: 2.0) {
                                    // Easter egg: long press 2 seconds to reveal developer mode
                                    withAnimation { developerMode = true }
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                }
                        }
                        
                        HStack {
                            Text("Build")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Spacer()
                            Text("1")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        
                        // Hidden login button (only visible after long press on version)
                        if developerMode && !instagram.isLoggedIn {
                            OutlineButton(
                                title: "Connect Account",
                                icon: "link.badge.plus",
                                action: { showingLogin = true }
                            )
                        }
                    }
                }
                
                // MARK: - Everything below only visible when logged in
                
                if instagram.isLoggedIn {
                    // MARK: - Developer Tools (only when logged in)
                    
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            Text("Developer")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            NavigationLink(destination: LogsView()) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                        .frame(width: 24)
                                    Text("View App Logs")
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Spacer()
                                    Text("\(LogManager.shared.logs.count)")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                }
                                .padding(.vertical, VaultTheme.Spacing.sm)
                            }
                            
                            // TEST BUTTON: Check if we can access archived photos
                            Button(action: { testArchiveAccess() }) {
                                HStack {
                                    Image(systemName: "archivebox.circle.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 24)
                                    Text("TEST: Check Archived Photos")
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Spacer()
                                    if isTestingArchive {
                                        ProgressView()
                                            .tint(.orange)
                                    } else {
                                        Image(systemName: "play.circle.fill")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.vertical, VaultTheme.Spacing.sm)
                            }
                            .disabled(isTestingArchive)
                            
                            if let testResult = archiveTestResult {
                                Text(testResult)
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(testResult.contains("✅") ? .green : .red)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            Text("Account")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            HStack {
                                Text("Logged in as")
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Spacer()
                                Text("@\(instagram.session.username)")
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            
                            GradientButton(
                                title: "Logout",
                                icon: nil,
                                action: { showingLogoutAlert = true },
                                style: .destructive
                            )
                        }
                    }
                    
                    // Profile Picture Change
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
                            Text("Profile Picture")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            VStack(spacing: VaultTheme.Spacing.lg) {
                                // Preview
                                if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                                    VStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(VaultTheme.Colors.primary, lineWidth: 2))
                                        
                                        Text("Ready to upload")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, VaultTheme.Spacing.sm)
                                }
                                
                                OutlineButton(
                                    title: selectedImageData == nil ? "Select from Gallery" : "Change Selection",
                                    icon: "photo.on.rectangle.angled",
                                    action: { showingImagePicker = true },
                                    isEnabled: !isUploadingProfilePic
                                )
                                
                                // Upload Button (only show if image selected)
                                if selectedImageData != nil {
                                    Button(action: uploadProfilePicture) {
                                        HStack(spacing: VaultTheme.Spacing.sm) {
                                            if isUploadingProfilePic {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .tint(.white)
                                                Text("Uploading...")
                                            } else {
                                                Image(systemName: "arrow.up.circle.fill")
                                                Text("Upload Profile Picture")
                                            }
                                        }
                                        .font(VaultTheme.Typography.bodyBold())
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, VaultTheme.Spacing.md)
                                        .background(canUpload() ? VaultTheme.Colors.primary : VaultTheme.Colors.textDisabled)
                                        .cornerRadius(VaultTheme.CornerRadius.md)
                                    }
                                    .disabled(!canUpload() || isUploadingProfilePic)
                                }
                                
                                // Status messages
                                if let cooldown = getCooldownMessage() {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(VaultTheme.Colors.warning)
                                        Text(cooldown)
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.warning)
                                    }
                                }
                                
                                if instagram.isLocked {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(VaultTheme.Colors.error)
                                        Text("Lockdown active - cannot upload")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.error)
                                    }
                                }
                                
                                if instagram.isNetworkStabilizing {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .tint(VaultTheme.Colors.textSecondary)
                                        Text("Network stabilizing...")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showingImagePicker) {
                        ImagePicker(selectedImageData: $selectedImageData)
                    }
                    .alert(uploadMessage ?? "Upload Complete", isPresented: $showingUploadAlert) {
                        Button("OK") {
                            uploadMessage = nil
                            if uploadMessage?.contains("success") == true {
                                selectedImageData = nil // Clear selection on success
                            }
                        }
                    } message: {
                        Text(uploadMessage ?? "")
                    }
                    
                    // Instagram Notes
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            Text("Note")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            VStack(spacing: VaultTheme.Spacing.md) {
                                HStack(spacing: VaultTheme.Spacing.sm) {
                                    Image(systemName: "bubble.left.fill")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                    Text("Appears above your profile pic in DMs")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                
                                // Text field + character count
                                VStack(alignment: .trailing, spacing: VaultTheme.Spacing.xs) {
                                    TextField("Write a note...", text: $noteText)
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                        .padding(VaultTheme.Spacing.md)
                                        .background(VaultTheme.Colors.backgroundSecondary)
                                        .cornerRadius(VaultTheme.CornerRadius.sm)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                                .stroke(VaultTheme.Colors.cardBorder, lineWidth: 1)
                                        )
                                        .disabled(isSendingNote)
                                        .onChange(of: noteText) { newValue in
                                            if newValue.count > 60 {
                                                noteText = String(newValue.prefix(60))
                                            }
                                        }
                                    
                                    Text("\(noteText.count)/60")
                                        .font(VaultTheme.Typography.captionSmall())
                                        .foregroundColor(noteText.count > 50 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
                                }
                                
                                Button(action: sendNote) {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        if isSendingNote {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)
                                            Text("Sending...")
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                            Text("Send Note")
                                        }
                                    }
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, VaultTheme.Spacing.md)
                                    .background(noteText.isEmpty || isSendingNote || instagram.isLocked ? VaultTheme.Colors.textDisabled : VaultTheme.Colors.primary)
                                    .cornerRadius(VaultTheme.CornerRadius.md)
                                }
                                .disabled(noteText.isEmpty || isSendingNote || instagram.isLocked || getNoteCooldownSeconds() > 0)
                                
                                // Status messages
                                if let cooldownMsg = getNoteCooldownMessage() {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(VaultTheme.Colors.warning)
                                        Text(cooldownMsg)
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.warning)
                                    }
                                }
                                
                                if instagram.isLocked {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(VaultTheme.Colors.error)
                                        Text("Lockdown active")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.error)
                                    }
                                }
                                
                                if instagram.isNetworkStabilizing {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .tint(VaultTheme.Colors.textSecondary)
                                        Text("Network stabilizing...")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .alert(noteMessage ?? "", isPresented: $showingNoteAlert) {
                        Button("OK") { noteMessage = nil }
                    } message: {
                        Text(noteMessage ?? "")
                    }
                    
                    // MARK: - Secret Input
                    
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            HStack(spacing: VaultTheme.Spacing.sm) {
                                Image(systemName: "eye.slash.fill")
                                    .foregroundColor(VaultTheme.Colors.primary)
                                Text("Secret Input")
                                    .font(VaultTheme.Typography.titleSmall())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                            
                            Text("Secret Input is used in Performance mode to hide your input from spectators")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .padding(.bottom, VaultTheme.Spacing.xs)
                            
                            // Mode selector
                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                                Text("Mask Mode")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                
                                ForEach(MaskInputMode.allCases, id: \.self) { maskMode in
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            secretInputSettings.mode = maskMode
                                        }
                                    }) {
                                        HStack(spacing: VaultTheme.Spacing.md) {
                                            Image(systemName: maskMode.icon)
                                                .frame(width: 24)
                                                .foregroundColor(VaultTheme.Colors.primary)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(maskMode.displayName)
                                                    .font(VaultTheme.Typography.body())
                                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                                
                                                Text(maskMode == .latestFollower ? "Uses your latest follower's username" : "Uses a custom username you set")
                                                    .font(VaultTheme.Typography.caption())
                                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if secretInputSettings.mode == maskMode {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(VaultTheme.Colors.primary)
                                            }
                                        }
                                        .padding(.vertical, VaultTheme.Spacing.sm)
                                        .padding(.horizontal, VaultTheme.Spacing.md)
                                        .background(
                                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                                                .fill(secretInputSettings.mode == maskMode ? VaultTheme.Colors.primary.opacity(0.1) : VaultTheme.Colors.backgroundSecondary)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                                                .stroke(secretInputSettings.mode == maskMode ? VaultTheme.Colors.primary : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // Custom username field (only show if custom mode selected)
                            if secretInputSettings.mode == .customUsername {
                                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                    Text("Custom Username")
                                        .font(VaultTheme.Typography.bodyBold())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    
                                    TextField("Enter username (e.g. magonil1)", text: $secretInputSettings.customUsername)
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                    .padding(VaultTheme.Spacing.md)
                                    .background(VaultTheme.Colors.backgroundSecondary)
                                    .cornerRadius(VaultTheme.CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                            .stroke(VaultTheme.Colors.cardBorder, lineWidth: 1)
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    
                                    if !secretInputSettings.customUsername.isEmpty {
                                        Text("Mask text: \(secretInputSettings.customUsername.lowercased())")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.success)
                                            .padding(VaultTheme.Spacing.xs)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(VaultTheme.Colors.success.opacity(0.1))
                                            .cornerRadius(VaultTheme.CornerRadius.sm)
                                    }
                                }
                            }
                            
                            // Preview/Example
                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                Text("Example")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                
                                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Text("You type:")
                                            .font(VaultTheme.Typography.captionBold())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                        Text("coche")
                                            .font(VaultTheme.Typography.caption())
                                            .monospaced()
                                            .padding(.horizontal, VaultTheme.Spacing.xs)
                                            .padding(.vertical, 2)
                                            .background(VaultTheme.Colors.info.opacity(0.2))
                                            .cornerRadius(VaultTheme.CornerRadius.sm)
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                    }
                                    
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Text("Spectator sees:")
                                            .font(VaultTheme.Typography.captionBold())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                        Text(exampleMaskOutput)
                                            .font(VaultTheme.Typography.caption())
                                            .monospaced()
                                            .padding(.horizontal, VaultTheme.Spacing.xs)
                                            .padding(.vertical, 2)
                                            .background(VaultTheme.Colors.primary.opacity(0.2))
                                            .cornerRadius(VaultTheme.CornerRadius.sm)
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                    }
                                }
                                .padding(VaultTheme.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(VaultTheme.Colors.backgroundSecondary)
                                .cornerRadius(VaultTheme.CornerRadius.sm)
                            }
                            
                            // Instructions
                            VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                HStack(spacing: VaultTheme.Spacing.xs) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(VaultTheme.Colors.warning)
                                        .font(VaultTheme.Typography.caption())
                                    Text("How to use")
                                        .font(VaultTheme.Typography.captionBold())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                }
                                
                                VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
                                    Text("1. Create a Word Reveal set with enough banks (5 banks = 5-letter words)")
                                    Text("2. In Performance → Explore, tap the search bar")
                                    Text("3. Type your secret word (spectator sees mask text)")
                                    Text("4. Press SPACE to reveal the word automatically")
                                }
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            .padding(VaultTheme.Spacing.sm)
                            .background(VaultTheme.Colors.warning.opacity(0.1))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                            
                            Text("Used in Performance mode to secretly type words that get auto-revealed from your Word Reveal sets.")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                        }
                    }
                    
                    // Debug section
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            Text("Debug & Testing")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            
                            Button(action: fetchLatestFollower) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                        .frame(width: 24)
                                    Text("Get Latest Follower Data")
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Spacer()
                                    if isLoadingFollower {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(VaultTheme.Colors.textSecondary)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textTertiary)
                                    }
                                }
                                .padding(.vertical, VaultTheme.Spacing.sm)
                            }
                            .disabled(isLoadingFollower)
                            .buttonStyle(.plain)
                            
                            GradientButton(
                                title: "Reset Device ID (Emergency)",
                                icon: "exclamationmark.triangle.fill",
                                action: { showingResetDeviceAlert = true },
                                style: .destructive
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.vertical, VaultTheme.Spacing.lg)
        }
        .background(VaultTheme.Colors.background)
        .navigationTitle("Settings")
        .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert("Logout", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                instagram.logout()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .alert("Reset Device ID", isPresented: $showingResetDeviceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Logout", role: .destructive) {
                instagram.resetDeviceIdentifiers()
                instagram.logout()
            }
        } message: {
            Text("Esto reseteará tu Device ID y cerrará sesión. Úsalo SOLO si tu cuenta fue bloqueada por cambio de dispositivo. Tendrás que volver a hacer login.")
        }
        .sheet(isPresented: $showingFollowerData) {
            FollowerDataSheet(follower: latestFollower, fullInfo: followerFullInfo)
        }
        .sheet(isPresented: $showingLogin) {
            InstagramWebLoginView(isPresented: $showingLogin)
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
    
    // MARK: - Profile Picture Upload Helpers
    
    private func canUpload() -> Bool {
        // Check all anti-bot conditions
        guard selectedImageData != nil else { return false }
        guard !instagram.isLocked else { return false }
        guard !instagram.isNetworkStabilizing else { return false }
        
        let (onCooldown, _) = instagram.isProfilePicOnCooldown()
        guard !onCooldown else { return false }
        
        return true
    }
    
    private func getCooldownMessage() -> String? {
        let (onCooldown, remaining) = instagram.isProfilePicOnCooldown()
        if onCooldown {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return "Wait \(minutes)m \(seconds)s before next upload"
        }
        return nil
    }
    
    // MARK: - Instagram Notes Helpers
    
    private func getNoteCooldownSeconds() -> Int {
        guard let cooldownUntil = UserDefaults.standard.object(forKey: "note_cooldown_until") as? Date else {
            return 0
        }
        let remaining = Int(cooldownUntil.timeIntervalSinceNow)
        return max(0, remaining)
    }
    
    private func getNoteCooldownMessage() -> String? {
        let remaining = getNoteCooldownSeconds()
        if remaining > 0 {
            return "Wait \(remaining)s before next note"
        }
        return nil
    }
    
    private func sendNote() {
        guard !noteText.isEmpty else { return }
        
        isSendingNote = true
        let textToSend = noteText
        
        Task {
            do {
                let success = try await instagram.createNote(text: textToSend)
                
                await MainActor.run {
                    isSendingNote = false
                    if success {
                        noteMessage = "✅ Note sent!\n\nYour note \"\(textToSend)\" is now visible above your profile picture in DMs for 24 hours."
                        showingNoteAlert = true
                        noteText = "" // Clear field
                    }
                }
            } catch {
                await MainActor.run {
                    isSendingNote = false
                    noteMessage = "❌ Failed to send note\n\n\(error.localizedDescription)"
                    showingNoteAlert = true
                }
            }
        }
    }
    
    // MARK: - Profile Picture Upload
    
    private func uploadProfilePicture() {
        guard let imageData = selectedImageData else { return }
        
        isUploadingProfilePic = true
        
        Task {
            do {
                print("🖼️ [UI] Starting profile picture upload...")
                
                // Upload with all anti-bot protections
                let success = try await instagram.changeProfilePicture(imageData: imageData)
                
                await MainActor.run {
                    isUploadingProfilePic = false
                    
                    if success {
                        uploadMessage = "✅ Profile picture updated successfully!\n\nYour Instagram profile picture has been changed. Wait 5 minutes before changing again."
                        showingUploadAlert = true
                        selectedImageData = nil // Clear selection
                    } else {
                        uploadMessage = "❌ Upload failed. Please try again later."
                        showingUploadAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isUploadingProfilePic = false
                    
                    let errorMessage = error.localizedDescription
                    if errorMessage.contains("already your profile picture") {
                        uploadMessage = "⚠️ This is already your profile picture.\n\nPlease select a different image."
                    } else if errorMessage.contains("Lockdown") {
                        uploadMessage = "🚨 Lockdown active\n\nInstagram detected unusual activity. Wait for lockdown to clear before uploading."
                    } else if errorMessage.contains("cooldown") || errorMessage.contains("Wait") {
                        uploadMessage = "⏱️ Please wait\n\n\(errorMessage)"
                    } else {
                        uploadMessage = "❌ Upload failed\n\n\(errorMessage)"
                    }
                    showingUploadAlert = true
                }
            }
        }
    }
    
    // MARK: - TEST Archive Access
    
    private func testArchiveAccess() {
        // Warn if upload is active - API calls could trigger rate limiting
        if UploadManager.shared.isUploading {
            archiveTestResult = "⚠️ Cannot test while upload is active. Pause upload first."
            return
        }
        
        isTestingArchive = true
        archiveTestResult = nil
        
        Task {
            do {
                let archivedPhotos = try await instagram.testGetArchivedPhotos()
                
                await MainActor.run {
                    isTestingArchive = false
                    archiveTestResult = "✅ Found \(archivedPhotos.count) archived photos!\nCheck logs for details."
                    LogManager.shared.success("Archive test: Found \(archivedPhotos.count) photos", category: .api)
                    
                    // Log first 5 for preview
                    for (index, photo) in archivedPhotos.prefix(5).enumerated() {
                        LogManager.shared.info("Archived #\(index + 1): ID=\(photo.mediaId), Date=\(photo.timestamp?.description ?? "unknown")", category: .api)
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingArchive = false
                    archiveTestResult = "❌ Could not access archived photos\n\(error.localizedDescription)\nCheck logs for details."
                    LogManager.shared.error("Archive test failed: \(error.localizedDescription)", category: .api)
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
