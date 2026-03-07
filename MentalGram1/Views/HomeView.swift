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
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    
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
                    
                    // Active set toggle (word / number / custom — only one active per type)
                    let isActive = activeSetSettings.isActive(set.id, type: set.type)
                    Button(action: {
                        if isActive {
                            activeSetSettings.setActive(nil, for: set.type)
                        } else {
                            activeSetSettings.setActive(set.id, for: set.type)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundColor(isActive ? VaultTheme.Colors.success : VaultTheme.Colors.textTertiary)
                            Text(isActive ? "Active set" : "Set as active")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(isActive ? VaultTheme.Colors.success : VaultTheme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

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
    @ObservedObject var instagram      = InstagramService.shared
    @ObservedObject var backup         = CloudBackupService.shared
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
    @AppStorage("autoProfilePicOnPerformance") private var autoProfilePicOnPerformance = false
    
    // Instagram Notes
    @State private var noteText: String = ""
    @State private var isSendingNote = false
    @State private var noteMessage: String?
    @State private var showingNoteAlert = false

    // Clipboard auto-mode: "" = off, "note" = send as note, "bio" = update biography
    // Only one can be active at a time.
    @AppStorage("clipboardAutoMode") private var clipboardAutoMode: String = ""

    // Biography
    @State private var bioText: String = ""
    @State private var isSendingBio = false
    @State private var bioMessage: String?
    @State private var showingBioAlert = false
    @FocusState private var bioFieldFocused: Bool
    
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
                    
                    // MARK: - iCloud Backup
                    BackupCard(backup: backup)

                    // Profile Picture Change
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.lg) {
                            Text("Profile Picture")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)

                            // Auto upload toggle
                            HStack(spacing: VaultTheme.Spacing.sm) {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(VaultTheme.Colors.primary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto on Performance")
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Text("Uploads the latest gallery photo as profile picture each time you open Performance.")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $autoProfilePicOnPerformance)
                                    .labelsHidden()
                            }

                            Divider()

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

                                Divider()

                                // Clipboard auto-mode toggle (mutually exclusive with Bio)
                                HStack(spacing: VaultTheme.Spacing.sm) {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Auto-Note from clipboard")
                                            .font(VaultTheme.Typography.bodyBold())
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                        Text("On Performance open, reads clipboard and sends it as a Note automatically")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { clipboardAutoMode == "note" },
                                        set: { clipboardAutoMode = $0 ? "note" : "" }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                    .alert(noteMessage ?? "", isPresented: $showingNoteAlert) {
                        Button("OK") { noteMessage = nil }
                    } message: {
                        Text(noteMessage ?? "")
                    }

                    // MARK: - Biography
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            Text("Biography")
                                .font(VaultTheme.Typography.titleSmall())
                                .foregroundColor(VaultTheme.Colors.textPrimary)

                            VStack(spacing: VaultTheme.Spacing.md) {
                                HStack(spacing: VaultTheme.Spacing.sm) {
                                    Image(systemName: "text.alignleft")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                    Text("Appears on your Instagram profile page")
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }

                                // Show current biography from cache as placeholder
                                let currentBio = ProfileCacheService.shared.cachedProfile?.biography ?? ""

                                VStack(alignment: .trailing, spacing: VaultTheme.Spacing.xs) {
                                    ZStack(alignment: .topLeading) {
                                        if bioText.isEmpty {
                                            Text(currentBio.isEmpty ? "Write your biography…" : currentBio)
                                                .font(VaultTheme.Typography.body())
                                                .foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.6))
                                                .padding(.horizontal, VaultTheme.Spacing.md)
                                                .padding(.vertical, VaultTheme.Spacing.md)
                                                .allowsHitTesting(false)
                                        }
                                        TextEditor(text: $bioText)
                                            .font(VaultTheme.Typography.body())
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                            .frame(minHeight: 80, maxHeight: 120)
                                            .padding(.horizontal, VaultTheme.Spacing.sm)
                                            .padding(.vertical, VaultTheme.Spacing.xs)
                                            .scrollContentBackground(.hidden)
                                            .background(Color.clear)
                                            .focused($bioFieldFocused)
                                            .disabled(isSendingBio)
                                            .onChange(of: bioText) { newValue in
                                                if newValue.count > 150 {
                                                    bioText = String(newValue.prefix(150))
                                                }
                                            }
                                    }
                                    .background(VaultTheme.Colors.backgroundSecondary)
                                    .cornerRadius(VaultTheme.CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                            .stroke(VaultTheme.Colors.cardBorder, lineWidth: 1)
                                    )

                                    Text("\(bioText.count)/150")
                                        .font(VaultTheme.Typography.captionSmall())
                                        .foregroundColor(bioText.count > 130 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
                                }

                                Button(action: {
                                    bioFieldFocused = false
                                    sendBiography()
                                }) {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        if isSendingBio {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)
                                            Text("Updating…")
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Update Biography")
                                        }
                                    }
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, VaultTheme.Spacing.md)
                                    .background(bioText.isEmpty || isSendingBio || instagram.isLocked
                                                ? VaultTheme.Colors.textDisabled
                                                : VaultTheme.Colors.primary)
                                    .cornerRadius(VaultTheme.CornerRadius.md)
                                }
                                .disabled(bioText.isEmpty || isSendingBio || instagram.isLocked)

                                if instagram.isLocked {
                                    HStack(spacing: VaultTheme.Spacing.sm) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(VaultTheme.Colors.error)
                                        Text("Lockdown active")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.error)
                                    }
                                }

                                Divider()

                                // Clipboard auto-mode toggle (mutually exclusive with Note)
                                HStack(spacing: VaultTheme.Spacing.sm) {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(VaultTheme.Colors.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Auto-Bio from clipboard")
                                            .font(VaultTheme.Typography.bodyBold())
                                            .foregroundColor(VaultTheme.Colors.textPrimary)
                                        Text("On Performance open, reads clipboard and updates Biography automatically")
                                            .font(VaultTheme.Typography.caption())
                                            .foregroundColor(VaultTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { clipboardAutoMode == "bio" },
                                        set: { clipboardAutoMode = $0 ? "bio" : "" }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                    .alert(bioMessage ?? "", isPresented: $showingBioAlert) {
                        Button("OK") { bioMessage = nil }
                    } message: {
                        Text(bioMessage ?? "")
                    }

                    // MARK: - Force Reel

                    ForceReelSettingsCard()

                    // MARK: - Force Number Reveal

                    ForceNumberRevealSettingsCard()

                    // MARK: - Following Counter Magic

                    FollowingMagicSettingsCard()

                    // MARK: - Date Force (El Oráculo Social)

                    DateForceSettingsCard()

                    // MARK: - Secret Input
                    
                    VaultCard {
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                            HStack(spacing: VaultTheme.Spacing.sm) {
                                Image(systemName: "eye.slash.fill")
                                    .foregroundColor(VaultTheme.Colors.primary)
                                Text("Secret Input")
                                    .font(VaultTheme.Typography.titleSmall())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Spacer()
                                Toggle("", isOn: $secretInputSettings.isEnabled)
                                    .labelsHidden()
                            }
                            
                            Text("Masks what you type in Explore so spectators see a different word. Pressing SPACE triggers the word reveal (unarchive).")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                                .padding(.bottom, VaultTheme.Spacing.xs)

                            if secretInputSettings.isEnabled {
                            
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
                            } // end if isEnabled
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
    
    // MARK: - Biography

    private func sendBiography() {
        guard !bioText.isEmpty else { return }
        isSendingBio = true
        let textToSend = bioText

        Task {
            do {
                let success = try await instagram.changeBiography(text: textToSend)
                await MainActor.run {
                    isSendingBio = false
                    if success {
                        bioMessage = "✅ Biography updated!\n\nYour Instagram profile now shows:\n\"\(textToSend)\""
                        showingBioAlert = true
                        bioText = ""
                    }
                }
            } catch {
                await MainActor.run {
                    isSendingBio = false
                    bioMessage = "❌ Failed to update biography\n\n\(error.localizedDescription)"
                    showingBioAlert = true
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
                        // Show new profile pic instantly in the fake Instagram view —
                        // no need to wait for Instagram's CDN URL from the next refresh.
                        if let image = UIImage(data: imageData) {
                            ProfileCacheService.shared.pendingProfilePic = image
                            print("⚡️ [UI] Profile pic override set — will appear instantly in Performance view")
                        }
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

// MARK: - Force Reel Settings Card

struct ForceReelSettingsCard: View {
    @ObservedObject private var settings = ForceReelSettings.shared
    @State private var showingPicker = false
    @State private var previewImage: UIImage?

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                // Header
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "hand.point.up.left.fill")
                        .foregroundColor(VaultTheme.Colors.primary)
                    Text("Force Reel")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                }

                Text("Pre-select a reel from any profile. In Performance, swipe the grid to set a position, then open Explore — the reel will appear at that exact slot.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    if settings.hasReel {
                        // Show selected reel preview
                        HStack(spacing: VaultTheme.Spacing.md) {
                            ZStack(alignment: .bottomLeading) {
                                if let img = previewImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(4/5, contentMode: .fill)
                                        .frame(width: 64, height: 80)
                                        .clipped()
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.25))
                                        .frame(width: 64, height: 80)
                                        .overlay(ProgressView().scaleEffect(0.7))
                                }
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(4)
                            }
                            .onAppear { loadPreview() }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reel selected")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("from @\(settings.sourceUsername)")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                Text("ID: \(String(settings.mediaId.prefix(16)))…")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Button(action: { showingPicker = true }) {
                                Label("Change Reel", systemImage: "arrow.triangle.2.circlepath")
                                    .font(VaultTheme.Typography.body())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive, action: { settings.clearReel() }) {
                                Label("Remove", systemImage: "trash")
                                    .font(VaultTheme.Typography.body())
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    } else {
                        // No reel selected yet
                        Button(action: { showingPicker = true }) {
                            Label("Select Reel", systemImage: "play.rectangle.on.rectangle.fill")
                                .font(VaultTheme.Typography.body())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, VaultTheme.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ForceReelPickerView()
        }
        .onChange(of: settings.thumbnailURL) { _ in loadPreview() }
    }

    private func loadPreview() {
        guard !settings.thumbnailURL.isEmpty else { previewImage = nil; return }
        if let cached = ProfileCacheService.shared.loadImage(forURL: settings.thumbnailURL) {
            previewImage = cached; return
        }
        Task {
            guard let url = URL(string: settings.thumbnailURL),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { return }
            await MainActor.run { previewImage = img }
            ProfileCacheService.shared.saveImage(img, forURL: settings.thumbnailURL)
        }
    }
}

// MARK: - Force Number Reveal Settings Card

struct ForceNumberRevealSettingsCard: View {
    @ObservedObject private var settings        = ForceNumberRevealSettings.shared
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    @ObservedObject private var dataManager     = DataManager.shared

    private var activeNumberSet: PhotoSet? {
        guard let id = activeSetSettings.activeNumberSetId else { return nil }
        return dataManager.sets.first { $0.id == id && $0.type == .number }
    }

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {

                // ── Header ───────────────────────────────────────────────
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(VaultTheme.Colors.secondary)
                    Text("Force Number Reveal")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                }
                Text("Swipe the grid to build a number, then tap the Posts icon to unarchive the matching photo in each bank of the active number set.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    // ── Active set info ───────────────────────────────────
                    if let set = activeNumberSet {
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(VaultTheme.Colors.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active set: \(set.name)")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("\(set.banks.count) banks · \(set.totalPhotos) photos")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                    } else {
                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(VaultTheme.Colors.warning)
                            Text("No active number set selected. Go to your sets and mark one as active.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }

                    Divider()

                    // ── Auto Re-archive ───────────────────────────────────
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(VaultTheme.Colors.primary)
                        Text("Auto Re-archive")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                        Toggle("", isOn: $settings.autoReArchiveEnabled)
                            .labelsHidden()
                    }

                    if settings.autoReArchiveEnabled {
                        Text("After the reveal, photos are automatically re-archived one by one with random delays to avoid detection.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)

                        // Time picker
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Re-archive after")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ForceNumberRevealSettings.timeOptions, id: \.self) { minutes in
                                        let isSelected = settings.autoReArchiveMinutes == minutes
                                        Button(action: { settings.autoReArchiveMinutes = minutes }) {
                                            Text("\(minutes) min")
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                                .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                            }
                        }

                        // Pending re-archive indicator
                        if settings.reArchiveScheduledAt != nil {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Re-archive pending…")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                Spacer()
                                Button("Cancel") {
                                    settings.cancelPendingReArchive()
                                }
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.error)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Following Counter Magic Settings Card

struct FollowingMagicSettingsCard: View {
    @ObservedObject private var settings = FollowingMagicSettings.shared

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {

                // ── Header ───────────────────────────────────────────────
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(VaultTheme.Colors.primary)
                    Text("Following Counter Magic")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                }
                Text("Swipe the grid to secretly build a number (1–100), then open Explore. When you visit an audience member's profile their \"Following\" count appears inflated. Press a volume button to start the countdown back to the real number.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    // ── Glitch effect ─────────────────────────────────────
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(VaultTheme.Colors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signal interference")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text("Full-screen glitch effect plays just before the countdown.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.glitchEnabled)
                            .labelsHidden()
                    }

                    Divider()

                    // ── Trigger delay ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        HStack {
                            Text("Delay before countdown")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            Spacer()
                            Text(settings.triggerDelay == 0 ? "Instant" : "\(settings.triggerDelay)s")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.primary)
                        }
                        Text("Time between pressing the volume button and the numbers starting to decrease.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FollowingMagicSettings.delayOptions, id: \.self) { seconds in
                                    let isSelected = settings.triggerDelay == seconds
                                    Button(action: { settings.triggerDelay = seconds }) {
                                        Text(seconds == 0 ? "0s" : "\(seconds)s")
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // ── Countdown duration ────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        HStack {
                            Text("Countdown duration")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            Spacer()
                            Text("\(settings.countdownDuration)s")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.primary)
                        }
                        HStack(spacing: 8) {
                            ForEach(FollowingMagicSettings.durationOptions, id: \.self) { seconds in
                                let isSelected = settings.countdownDuration == seconds
                                Button(action: { settings.countdownDuration = seconds }) {
                                    Text("\(seconds)s")
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Date Force Settings Card (El Oráculo Social)

struct DateForceSettingsCard: View {
    @ObservedObject private var settings = DateForceSettings.shared
    @State private var showingHelp = false

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {

                // Header
                HStack(spacing: VaultTheme.Spacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(VaultTheme.Colors.primary)
                    Text("Date Force")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                    }
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                }
                Text("Search spectators in Explore, tap their profile pic to register. Then any Explore post shows forced followers/following that subtract to today's date & time.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)

                if settings.isEnabled {
                    Divider()

                    // Date format + time offset (grouped together — both affect the target numbers)
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                        // Date format
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            Text("Date format")
                                .font(VaultTheme.Typography.captionSmall())
                                .foregroundColor(VaultTheme.Colors.textTertiary)
                            HStack(spacing: 8) {
                                ForEach(DateForceFormat.allCases, id: \.rawValue) { fmt in
                                    let isSelected = settings.dateFormat == fmt
                                    Button(action: { settings.dateFormat = fmt }) {
                                        Text(fmt.displayName)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }

                        // Time offset
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Add minutes to time")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text(settings.timeOffsetMinutes == 0 ? "Off" : "+\(settings.timeOffsetMinutes) min")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(0...5, id: \.self) { n in
                                        let isSelected = settings.timeOffsetMinutes == n
                                        Button(action: { settings.timeOffsetMinutes = n }) {
                                            Text(n == 0 ? "Off" : "+\(n)m")
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                                .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Mode selector
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Mode")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        HStack(spacing: 8) {
                            let modes: [(DateForceMode, String)] = [
                                (.simple, "Simple"),
                                (.dual, "Dual"),
                                (.auto, "Auto")
                            ]
                            ForEach(modes, id: \.0.rawValue) { mode, label in
                                let isSelected = settings.mode == mode
                                Button(action: { settings.mode = mode }) {
                                    Text(label)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        Group {
                            switch settings.mode {
                            case .simple:
                                Text("All spectators → date. Time shows directly on Explore post.")
                            case .dual:
                                Text("First group → date, second group → time. Both use subtraction.")
                            case .auto:
                                Text("In Performance, tap the 'Followed by' area to auto-capture the latest followers. Tap again to toggle between date/time groups.")
                            }
                        }
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                    }

                    if settings.mode == .dual {
                        Divider()

                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Spectators for date")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("\(settings.dateGroupSize)")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            HStack(spacing: 8) {
                                ForEach(2...5, id: \.self) { n in
                                    let isSelected = settings.dateGroupSize == n
                                    Button(action: { settings.dateGroupSize = n }) {
                                        Text("\(n)")
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            Text("Remaining spectators go to the time group.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }

                    if settings.mode == .auto {
                        Divider()

                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Max followers to capture")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("\(settings.autoMaxFollowers)")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }
                            HStack(spacing: 8) {
                                ForEach(2...6, id: \.self) { n in
                                    let isSelected = settings.autoMaxFollowers == n
                                    Button(action: { settings.autoMaxFollowers = n }) {
                                        Text("\(n)")
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? VaultTheme.Colors.primary : VaultTheme.Colors.backgroundSecondary)
                                            .foregroundColor(isSelected ? .white : VaultTheme.Colors.textPrimary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            let total = settings.autoMaxFollowers
                            let dateCount = (total + 1) / 2
                            let timeCount = total / 2
                            Text("Date group: \(dateCount) follower\(dateCount == 1 ? "" : "s")  ·  Time group: \(timeCount) follower\(timeCount == 1 ? "" : "s")")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                    }

                    Divider()

                    // Live preview
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Live preview")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)

                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("Target")
                                    .font(.system(size: 10))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Text("\(settings.previewDateString) \(settings.previewTimeString)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.primary)
                            }

                            VStack(spacing: 2) {
                                Text("Followers")
                                    .font(.system(size: 10))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Text(DateForceSettings.formatExact(settings.overrideFollowers))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }

                            VStack(spacing: 2) {
                                Text("Following")
                                    .font(.system(size: 10))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Text(DateForceSettings.formatExact(settings.overrideFollowing))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(VaultTheme.Colors.backgroundSecondary)
                        .cornerRadius(8)
                    }

                    // Registered spectators list
                    if !settings.spectators.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Spectators (\(settings.spectators.count))")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Button(action: { settings.resetSpectators() }) {
                                    Text("Reset")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(VaultTheme.Colors.error)
                                }
                            }

                            ForEach(settings.spectators) { spec in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(spec.group == .date ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                                        .frame(width: 8, height: 8)
                                    Text("@\(spec.username)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Spacer()
                                    Text("\(spec.rawFollowingCount)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                    Text("\(spec.effectiveValue)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(VaultTheme.Colors.primary)
                                    Text(spec.group == .date ? "📅" : "🕐")
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            DateForceHelpView(onClose: { showingHelp = false })
        }
    }
}

// MARK: - Backup Card

private struct BackupCard: View {
    @ObservedObject var backup: CloudBackupService

    private var lastBackupText: String {
        guard let date = backup.lastBackupDate else {
            return "Never"
        }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 {
            let m = Int(diff / 60)
            return "\(m) min ago"
        }
        if diff < 86400 {
            let h = Int(diff / 3600)
            return "\(h) h ago"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                    Text("iCloud Backup")
                        .font(VaultTheme.Typography.titleSmall())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    if !backup.iCloudAvailable {
                        Text("Not available")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }
                }

                HStack {
                    Text("Last backup")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Text(lastBackupText)
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }

                HStack {
                    Text("Status")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(backup.iCloudAvailable ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(backup.iCloudAvailable ? "Active" : "Inactive")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                }

                Button(action: { backup.syncToCloud() }) {
                    HStack {
                        if backup.isSyncing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.clockwise.icloud")
                        }
                        Text(backup.isSyncing ? "Saving…" : "Back up now")
                            .font(VaultTheme.Typography.body().weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(backup.iCloudAvailable ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!backup.iCloudAvailable || backup.isSyncing)

                Text("Backup runs automatically when the app is closed. Includes all your sets and images.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
