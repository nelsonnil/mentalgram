import SwiftUI

// MARK: - Main Home View

struct HomeView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject private var urlAction = URLActionManager.shared
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    @State private var selectedTab = 1 // Start on Sets tab
    @State private var showingCreateSet = false
    @State private var showingExplore = false
    @State private var showingChallengeAlert = false

    // Pre-performance visible photos check
    @State private var showVisiblePhotosAlert = false
    @State private var visiblePhotosToArchive: [SetPhoto] = []
    @State private var isArchivingBeforePerformance = false
    @State private var archiveProgress: (done: Int, total: Int) = (0, 0)
    @State private var showArchiveProgressSheet = false
    
    /// Custom binding that intercepts tab switches to Performance (0)
    /// and shows the pre-check alert if there are visible photos.
    private var tabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 0 && instagram.isLoggedIn {
                    let visible = visiblePhotosInActiveSets()
                    if !visible.isEmpty {
                        visiblePhotosToArchive = visible
                        showVisiblePhotosAlert = true
                        return  // block the tab switch
                    }
                }
                selectedTab = newValue
                updateTabBarAppearance(forTab: newValue)
            }
        )
    }

    var body: some View {
        TabView(selection: tabBinding) {
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
            updateTabBarAppearance(forTab: newTab)
        }
        // URL scheme: bypass the check and go directly to Performance
        .onChange(of: urlAction.pendingMode) { mode in
            guard !mode.isEmpty else { return }
            print("📲 [URL] Switching to Performance tab for action: \(mode)")
            selectedTab = 0
            updateTabBarAppearance(forTab: 0)
        }
        .onAppear {
            updateTabBarAppearance(forTab: selectedTab)
        }
        .alert("Visible Photos Detected", isPresented: $showVisiblePhotosAlert) {
            Button("Continue Anyway") {
                selectedTab = 0
                updateTabBarAppearance(forTab: 0)
            }
            Button("Verify & Archive") {
                showArchiveProgressSheet = true
                Task { await archiveVisiblePhotosAndEnter() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let sets = activeSetNames()
            Text("\(visiblePhotosToArchive.count) photo(s) from your active sets are still visible on Instagram.\n\nActive sets: \(sets)\n\nArchive them before performing?")
        }
        .sheet(isPresented: $showArchiveProgressSheet) {
            archiveProgressView
        }
        .fullScreenCover(isPresented: $showingExplore) {
            ExploreView(selectedTab: $selectedTab, showingExplore: $showingExplore)
                .preferredColorScheme(.light)
        }
    }

    // MARK: - Pre-Performance Check

    private func visiblePhotosInActiveSets() -> [SetPhoto] {
        var result: [SetPhoto] = []
        let activeIds = [activeSetSettings.activeWordSetId,
                         activeSetSettings.activeNumberSetId].compactMap { $0 }
        print("🔍 [PRE-PERF] Checking \(activeIds.count) active set(s) for visible photos")
        for setId in activeIds {
            guard let photoSet = dataManager.sets.first(where: { $0.id == setId }) else {
                print("⚠️ [PRE-PERF] Active set \(setId) not found in dataManager")
                continue
            }
            let visible = photoSet.photos.filter {
                $0.mediaId != nil && !$0.isArchived
            }
            let byStatus = Dictionary(grouping: photoSet.photos.filter { $0.mediaId != nil }, by: { $0.uploadStatus.rawValue })
            print("🔍 [PRE-PERF] Set '\(photoSet.name)': \(visible.count) visible photo(s) of \(photoSet.photos.count) total — by status: \(byStatus.mapValues { $0.count })")
            result.append(contentsOf: visible)
        }
        print("🔍 [PRE-PERF] Total visible photos found: \(result.count)")
        return result
    }

    private func activeSetNames() -> String {
        let activeIds = [activeSetSettings.activeWordSetId,
                         activeSetSettings.activeNumberSetId].compactMap { $0 }
        let names = activeIds.compactMap { id in
            dataManager.sets.first(where: { $0.id == id })?.name
        }
        return names.joined(separator: ", ")
    }

    @MainActor
    private func archiveVisiblePhotosAndEnter() async {
        let photos = visiblePhotosToArchive
        archiveProgress = (0, photos.count)
        isArchivingBeforePerformance = true

        for (i, photo) in photos.enumerated() {
            guard let mediaId = photo.mediaId else { continue }
            do {
                let archived = try await InstagramService.shared.archivePhoto(mediaId: mediaId, skipPreCheck: false)
                if archived {
                    dataManager.updatePhoto(photoId: photo.id, isArchived: true, uploadStatus: .completed)
                    // Remove from ProfileCache so PerformanceView grid is already clean on entry
                    ProfileCacheService.shared.removeMediaItem(byMediaId: mediaId)
                }
            } catch {
                print("⚠️ [PRE-PERF] Failed to archive \(mediaId): \(error.localizedDescription)")
            }
            archiveProgress = (i + 1, photos.count)
        }

        isArchivingBeforePerformance = false
        showArchiveProgressSheet = false
        visiblePhotosToArchive = []
        selectedTab = 0
        updateTabBarAppearance(forTab: 0)
    }

    private var archiveProgressView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: archiveProgress.total > 0
                          ? CGFloat(archiveProgress.done) / CGFloat(archiveProgress.total) : 0)
                    .stroke(Color(hex: "7C3AED"), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: archiveProgress.done)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            VStack(spacing: 6) {
                Text("Archiving photos…")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(archiveProgress.done) / \(archiveProgress.total)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            Text("Please wait. Do not close the app.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "111111").ignoresSafeArea())
        .interactiveDismissDisabled(isArchivingBeforePerformance)
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
    // Rename state
    @State private var setToRename: PhotoSet? = nil
    @State private var renameText = ""
    @State private var showRenameAlert = false
    // Delete confirmation state
    @State private var setToDelete: PhotoSet? = nil
    @State private var showDeleteAlert = false
    
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
            
            ScrollView {
                LazyVStack(spacing: VaultTheme.Spacing.md) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "7C3AED"), Color(hex: "0EA5E9")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Sets")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("Post Prediction · Old Date")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                            }
                            Spacer()
                        }
                        Text("Each set groups photo banks used to unarchive posts during your performance.")
                            .font(.system(size: 12))
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    .padding(.top, VaultTheme.Spacing.md)
                    .padding(.bottom, VaultTheme.Spacing.sm)

                    if dataManager.sets.isEmpty {
                        EmptyStateView(
                            icon: "square.stack.3d.up.slash.fill",
                            title: "No Sets Yet",
                            message: "Create your first photo set to get started with magic performances",
                            actionTitle: "Create Set",
                            action: { showingCreateSet = true }
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(dataManager.sets) { set in
                            NavigationLink(destination: SetDetailView(set: set)) {
                                SetRowView(
                                    set: set,
                                    isLoggedIn: instagram.isLoggedIn,
                                    onRename: {
                                        setToRename = set
                                        renameText = set.name
                                        showRenameAlert = true
                                    },
                                    onDelete: {
                                        setToDelete = set
                                        showDeleteAlert = true
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                        }
                        .padding(.bottom, VaultTheme.Spacing.lg)
                    }
                }
            }
        }
        .navigationTitle("My Sets")
        .navigationBarTitleDisplayMode(.inline)
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
                newlyCreatedSet = createdSet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToNewSet = true
                }
            }
        }
        .alert("Rename Set", isPresented: $showRenameAlert) {
            TextField("Set name", text: $renameText)
            Button("Rename") {
                if let s = setToRename {
                    dataManager.renameSet(id: s.id, newName: renameText)
                }
                setToRename = nil
            }
            Button("Cancel", role: .cancel) { setToRename = nil }
        } message: {
            Text("Enter a new name for \"\(setToRename?.name ?? "")\"")
        }
        .alert("Delete Set", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let s = setToDelete {
                    withAnimation { dataManager.deleteSet(id: s.id) }
                }
                setToDelete = nil
            }
            Button("Cancel", role: .cancel) { setToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(setToDelete?.name ?? "")\"? This cannot be undone.")
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
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared

    // Per-type accent colors
    private var typeAccent: Color {
        switch set.type {
        case .word:   return Color(hex: "7C3AED")  // purple
        case .number: return Color(hex: "0EA5E9")  // sky blue
        case .custom: return Color(hex: "F97316")  // orange
        }
    }

    private var typeGradient: [Color] {
        switch set.type {
        case .word:   return [Color(hex: "7C3AED"), Color(hex: "6D28D9")]
        case .number: return [Color(hex: "0EA5E9"), Color(hex: "0369A1")]
        case .custom: return [Color(hex: "F97316"), Color(hex: "EA580C")]
        }
    }

    private var typeIcon: String {
        switch set.type {
        case .word:   return "textformat.abc"
        case .number: return "123.rectangle.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }

    private var statusBadgeStyle: StatusBadge.BadgeStyle {
        switch set.status {
        case .ready:     return .info
        case .uploading: return .warning
        case .paused:    return .pending
        case .completed: return .success
        case .error:     return .error
        }
    }

    var body: some View {
        let isActive = activeSetSettings.isActive(set.id, type: set.type)

        ZStack(alignment: .leading) {
            // Active left accent bar
            if isActive {
                RoundedRectangle(cornerRadius: 3)
                    .fill(typeAccent)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 10)
            }

            VaultCard {
                VStack(spacing: 0) {
                    HStack(spacing: VaultTheme.Spacing.md) {
                        // Type icon
                        IconBadge(icon: typeIcon, colors: typeGradient, size: 52)

                        VStack(alignment: .leading, spacing: 5) {
                            // Name row
                            HStack(alignment: .center, spacing: 6) {
                                Text(set.name)
                                    .font(VaultTheme.Typography.title())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                    .lineLimit(1)

                                if isActive {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(typeAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(typeAccent.opacity(0.15))
                                        .cornerRadius(4)
                                }

                                Spacer()

                                if isLoggedIn {
                                    StatusBadge(text: set.status.rawValue, style: statusBadgeStyle)
                                }

                                // ··· menu
                                Menu {
                                    Button { onRename?() } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { onDelete?() } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(VaultTheme.Colors.textTertiary)
                                        .frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            // Stats row
                            HStack(spacing: 8) {
                                Label(set.type.title, systemImage: "tag.fill")
                                Text("·").foregroundColor(VaultTheme.Colors.textTertiary)
                                Label("\(set.banks.isEmpty ? 1 : set.banks.count) banks",
                                      systemImage: "square.stack.3d.up.fill")
                                Text("·").foregroundColor(VaultTheme.Colors.textTertiary)
                                Label("\(set.totalPhotos) photos",
                                      systemImage: "photo.stack.fill")
                            }
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)

                            // Completed date
                            if isLoggedIn && set.status == .completed,
                               let completedDate = set.completedAt {
                                Label(completedDate.formatted(date: .abbreviated, time: .omitted),
                                      systemImage: "calendar")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                    .padding(.top, 1)
                            }
                        }
                    }

                    // Upload progress bar
                    if isLoggedIn && (set.status == .uploading || set.status == .paused) {
                        VStack(spacing: 4) {
                            ProgressBar(
                                progress: set.totalPhotos > 0
                                    ? Double(set.uploadedPhotos) / Double(set.totalPhotos) : 0,
                                height: 5,
                                gradient: set.status == .paused
                                    ? LinearGradient(colors: [VaultTheme.Colors.textSecondary],
                                                     startPoint: .leading, endPoint: .trailing)
                                    : VaultTheme.Colors.gradientWarning
                            )
                            HStack {
                                Text("\(set.uploadedPhotos) / \(set.totalPhotos)")
                                Spacer()
                                let pct = set.totalPhotos > 0
                                    ? Int((Double(set.uploadedPhotos) / Double(set.totalPhotos)) * 100) : 0
                                Text("\(pct)%").fontWeight(.bold)
                                    .foregroundColor(set.status == .paused
                                        ? VaultTheme.Colors.textSecondary : VaultTheme.Colors.warning)
                            }
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        .padding(.top, 10)
                    }

                    // Active toggle strip — always visible at the bottom of the card
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.top, 10)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isActive {
                                activeSetSettings.setActive(nil, for: set.type)
                            } else {
                                activeSetSettings.setActive(set.id, for: set.type)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isActive ? typeAccent : VaultTheme.Colors.textTertiary)
                            Text(isActive ? "Active set" : "Set as active")
                                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? typeAccent : VaultTheme.Colors.textSecondary)
                            Spacer()
                            if isActive {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(typeAccent.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, isActive ? 8 : 0)
        }
        .glowEffect(color: isActive ? typeAccent.opacity(0.35) : .clear, radius: 6)
        .glowEffect(color: isLoggedIn && set.status == .uploading ? VaultTheme.Colors.warning : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.2), value: isActive)
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
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @State private var settingsProfilePic: UIImage? = nil
    @State private var showingLogoutAlert = false
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

    // Top-level auto-input mode per target (off/clipboard/api/ocr)
    @AppStorage("noteTopInputMode") private var noteTopInputMode: String = "off"
    @AppStorage("bioTopInputMode")  private var bioTopInputMode:  String = "off"

    // OCR configuration (shared between note and bio)
    @AppStorage("ocr_language") private var ocrLanguage: String = "es-ES"
    @AppStorage("ocr_camera")   private var ocrCamera:   Int    = 0  // 0=back, 1=front

    // Biography
    @State private var bioText: String = ""
    @State private var isSendingBio = false
    @State private var bioMessage: String?
    @State private var showingBioAlert = false
    @FocusState private var bioFieldFocused: Bool
    
    // Hidden Login (easter egg)
    @State private var showingLogin = false
    @State private var developerMode = false

    // Other Settings — Fake Home Screen
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @State private var showingHomeScreenPicker = false

    // Collapsible cards — Instagram Profile section
    @State private var profilePicExpanded = false
    @State private var noteExpanded = false
    @State private var bioExpanded = false
    // TEST: Archive access
    
    var body: some View {
        mainScrollView
            .background(Color(hex: "#0F0F0F"))
            .navigationTitle("Settings")
            .toolbarBackground(Color(hex: "#1C1C1E"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .alert("Logout", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) { instagram.logout() }
            } message: { Text("Are you sure you want to logout?") }
            .alert(uploadMessage ?? "Upload Complete", isPresented: $showingUploadAlert) {
                Button("OK") { uploadMessage = nil }
            } message: { Text(uploadMessage ?? "") }
            .alert(noteMessage ?? "", isPresented: $showingNoteAlert) {
                Button("OK") { noteMessage = nil }
            } message: { Text(noteMessage ?? "") }
            .alert(bioMessage ?? "", isPresented: $showingBioAlert) {
                Button("OK") { bioMessage = nil }
            } message: { Text(bioMessage ?? "") }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImageData: $selectedImageData)
            }
            .sheet(isPresented: $showingHomeScreenPicker) {
                HomeScreenImagePicker { image in
                    illusionService.save(image)
                }
            }
            .sheet(isPresented: $showingFollowerData) {
                FollowerDataSheet(follower: latestFollower, fullInfo: followerFullInfo)
            }
            .sheet(isPresented: $showingLogin) {
                InstagramWebLoginView(isPresented: $showingLogin)
            }
    }

    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !instagram.isLoggedIn {
                    notLoggedInSection
                } else {
                    loggedInSections
                }
            }
            .padding(.horizontal, VaultTheme.Spacing.lg)
            .padding(.vertical, VaultTheme.Spacing.lg)
        }
    }

    @ViewBuilder private var loggedInSections: some View {
        accountSection
        instagramProfileSection
        tricksSection
        integrationsSection
        otherSection
        dataSection
    }

    // MARK: - Section: Not Logged In

    @ViewBuilder private var notLoggedInSection: some View {
        settingsSectionLabel("ACCOUNT", icon: "person.circle", color: Self.colorAccount)
        modernCard {
            VStack(spacing: VaultTheme.Spacing.md) {
                Text("Version 1.0.0")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .onLongPressGesture(minimumDuration: 2.0) {
                        withAnimation { developerMode = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                if developerMode {
                    OutlineButton(title: "Connect Account", icon: "link.badge.plus",
                                  action: { showingLogin = true })
                }
            }
        }
    }

    // MARK: - Section: Account

    @ViewBuilder private var accountSection: some View {
        settingsSectionLabel("ACCOUNT", icon: "person.circle.fill", color: Self.colorAccount)
        accentedSection(color: Self.colorAccount) {
            modernCard {
                VStack(spacing: 0) {
                    // Avatar row
                    HStack(spacing: VaultTheme.Spacing.md) {
                        Group {
                            if let pic = settingsProfilePic ?? profileCache.pendingProfilePic {
                                Image(uiImage: pic)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle().fill(Self.colorAccount.opacity(0.2)).frame(width: 48, height: 48)
                                    Text(String(instagram.session.username.prefix(1)).uppercased())
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Self.colorAccount)
                                }
                            }
                        }
                        .task { await loadSettingsProfilePic() }
                        VStack(alignment: .leading, spacing: 2) {
                            let fullName = profileCache.cachedProfile?.fullName ?? ""
                            if !fullName.isEmpty {
                                Text(fullName)
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("@\(instagram.session.username)")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            } else {
                                Text("@\(instagram.session.username)")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                            }
                            Text("Instagram account connected")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                    }
                    modernDivider()
                    NavigationLink(destination: LogsView()) {
                        modernRow(icon: "doc.text.fill", iconColor: Self.colorAccount,
                                  title: "View App Logs",
                                  trailing: Text("\(LogManager.shared.logs.count)").font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary))
                    }
                    .buttonStyle(.plain)
                    modernDivider()
                    Button(action: { showingLogoutAlert = true }) {
                        modernRow(icon: "rectangle.portrait.and.arrow.right", iconColor: VaultTheme.Colors.error,
                                  title: "Logout",
                                  trailing: EmptyView())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Spacer().frame(height: 28)
    }

    private func loadSettingsProfilePic() async {
        guard let url = profileCache.cachedProfile?.profilePicURL, !url.isEmpty else { return }
        if let cached = ProfileCacheService.shared.loadImage(forURL: url) {
            await MainActor.run { settingsProfilePic = cached }
            return
        }
        guard let imageUrl = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: imageUrl),
              let image = UIImage(data: data) else { return }
        ProfileCacheService.shared.saveImage(image, forURL: url)
        await MainActor.run { settingsProfilePic = image }
    }

    // MARK: - Section: Instagram Profile

    @ViewBuilder private var instagramProfileSection: some View {
        settingsSectionLabel("INSTAGRAM PROFILE", icon: "camera.fill", color: Self.colorProfile)
        accentedSection(color: Self.colorProfile) {
            profilePictureCard
            noteCard
            biographyCard
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Tricks

    @ViewBuilder private var tricksSection: some View {
        settingsSectionLabel("TRICKS", icon: "wand.and.stars", color: Self.colorTricks)
        accentedSection(color: Self.colorTricks) {
            ForceReelSettingsCard()
            ForcePostSettingsCard()
            ForceNumberRevealSettingsCard()
            FollowingMagicSettingsCard()
            DateForceSettingsCard()
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Integrations

    @ViewBuilder private var integrationsSection: some View {
        settingsSectionLabel("INTEGRATIONS", icon: "bolt.horizontal.fill", color: Self.colorIntegration)
        accentedSection(color: Self.colorIntegration) {
            modernCard {
                VStack(spacing: 0) {
                    NavigationLink(destination: IntegrationsSettingsView()) {
                        modernRow(icon: "bolt.horizontal.fill", iconColor: Self.colorIntegration,
                                  title: "Magic API",
                                  trailing: Text("Inject & Custom APIs")
                                      .font(VaultTheme.Typography.caption())
                                      .foregroundColor(VaultTheme.Colors.textSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Other

    @ViewBuilder private var otherSection: some View {
        settingsSectionLabel("OTHER", icon: "gearshape.2.fill", color: Self.colorData)
        accentedSection(color: Self.colorData) {
            FakeHomeScreenCard(showingPicker: $showingHomeScreenPicker)
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Section: Data

    @ViewBuilder private var dataSection: some View {
        settingsSectionLabel("DATA & INFO", icon: "externaldrive.fill", color: Self.colorData)
        accentedSection(color: Self.colorData) {
            BackupCard(backup: backup)
            modernCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Version")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                        Text("1.0.0 (1)")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .onLongPressGesture(minimumDuration: 2.0) {
                                withAnimation { developerMode = true }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                    }
                }
            }
        }
        Spacer().frame(height: 28)
    }

    // MARK: - Profile Picture Card

    @ViewBuilder private var profilePictureCard: some View {
        collapsibleCard(icon: "person.crop.circle.fill", iconColor: Self.colorProfile,
                        title: "Profile Picture", subtitle: "Change your Instagram profile photo",
                        isExpanded: $profilePicExpanded) {
            modernToggleRow(icon: "wand.and.stars", iconColor: Self.colorProfile,
                            title: "Auto on Performance open",
                            detail: "Uploads the latest gallery photo each time Performance opens",
                            isOn: $autoProfilePicOnPerformance)
            modernDivider()
            if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                HStack { Spacer()
                    VStack(spacing: 6) {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(width: 80, height: 80).clipShape(Circle())
                            .overlay(Circle().stroke(VaultTheme.Colors.primary, lineWidth: 2))
                        Text("Ready to upload").font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    Spacer()
                }
            }
            if selectedImageData != nil {
                modernActionButton(title: isUploadingProfilePic ? "Uploading…" : "Upload Profile Picture",
                                   icon: "arrow.up.circle.fill",
                                   loading: isUploadingProfilePic,
                                   enabled: canUpload()) { uploadProfilePicture() }
            }
            if let msg = getCooldownMessage() { modernStatusRow(msg, color: VaultTheme.Colors.warning, icon: "clock.fill") }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            profilePicURLSchemesContent
        }
    }

    // MARK: - Note Card

    @ViewBuilder private var noteCard: some View {
        collapsibleCard(icon: "bubble.left.fill", iconColor: Self.colorProfile,
                        title: "Note", subtitle: "Visible above your profile picture for 24h",
                        isExpanded: $noteExpanded) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField("Write a note…", text: $noteText)
                    .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                    .padding(VaultTheme.Spacing.md)
                    .background(Color(hex: "#2C2C2E")).cornerRadius(VaultTheme.CornerRadius.sm)
                    .disabled(isSendingNote)
                    .onChange(of: noteText) { if $0.count > 60 { noteText = String($0.prefix(60)) } }
                Text("\(noteText.count)/60").font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(noteText.count > 50 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
            }
            modernActionButton(title: isSendingNote ? "Sending…" : "Send Note",
                               icon: "paperplane.fill", loading: isSendingNote,
                               enabled: !noteText.isEmpty && !isSendingNote && !instagram.isLocked && getNoteCooldownSeconds() == 0,
                               action: sendNote)
            if let msg = getNoteCooldownMessage() { modernStatusRow(msg, color: VaultTheme.Colors.warning, icon: "clock.fill") }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            autoInputPicker(
                clipboardKey: "note",
                topMode: $noteTopInputMode,
                apiSource: $integrations.noteApiSource)
            modernDivider()
            urlSchemeRow(icon: "link", title: "URL Scheme",
                         detail: "Open this URL to send a note when Performance opens",
                         url: noteText.isEmpty ? "vault://note?text=<your text>" : URLActionManager.buildURL(mode: "note", text: noteText))
        }
    }

    // MARK: - Biography Card

    @ViewBuilder private var biographyCard: some View {
        collapsibleCard(icon: "text.alignleft", iconColor: Self.colorProfile,
                        title: "Biography", subtitle: "Appears on your Instagram profile page",
                        isExpanded: $bioExpanded) {
            let currentBio = ProfileCacheService.shared.cachedProfile?.biography ?? ""
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if bioText.isEmpty {
                        Text(currentBio.isEmpty ? "Write your biography…" : currentBio)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textSecondary.opacity(0.5))
                            .padding(.horizontal, VaultTheme.Spacing.md).padding(.vertical, VaultTheme.Spacing.md)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $bioText)
                        .font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(.horizontal, VaultTheme.Spacing.sm).padding(.vertical, 4)
                        .scrollContentBackground(.hidden).background(Color.clear)
                        .focused($bioFieldFocused).disabled(isSendingBio)
                        .onChange(of: bioText) { if $0.count > 150 { bioText = String($0.prefix(150)) } }
                }
                .background(Color(hex: "#2C2C2E")).cornerRadius(VaultTheme.CornerRadius.sm)
                Text("\(bioText.count)/150").font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(bioText.count > 130 ? VaultTheme.Colors.warning : VaultTheme.Colors.textSecondary)
            }
            modernActionButton(title: isSendingBio ? "Updating…" : "Update Biography",
                               icon: "checkmark.circle.fill", loading: isSendingBio,
                               enabled: !bioText.isEmpty && !isSendingBio && !instagram.isLocked) {
                bioFieldFocused = false; sendBiography()
            }
            if instagram.isLocked { modernStatusRow("Lockdown active", color: VaultTheme.Colors.error, icon: "exclamationmark.triangle.fill") }
            modernDivider()
            autoInputPicker(
                clipboardKey: "bio",
                topMode: $bioTopInputMode,
                apiSource: $integrations.bioApiSource)
            modernDivider()
            urlSchemeRow(icon: "link", title: "URL Scheme",
                         detail: "Open this URL to update biography when Performance opens",
                         url: bioText.isEmpty ? "vault://bio?text=<your text>" : URLActionManager.buildURL(mode: "bio", text: bioText))
        }
    }

    // MARK: - Section accent colors (internal so CollapsibleCard structs can reference them)
    static let colorAccount     = Color(hex: "#0A84FF")
    static let colorProfile     = Color(hex: "#FF9F0A")
    static let colorTricks      = Color(hex: "#BF5AF2")
    static let colorIntegration = Color(hex: "#FFD60A")
    static let colorData        = Color(hex: "#30D158")

    // MARK: - Modern UI Helpers

    @ViewBuilder
    private func settingsSectionLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .tracking(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wraps section cards with a left-side colored accent line
    @ViewBuilder
    private func accentedSection<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(color)
                .frame(width: 3)
            VStack(spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func modernCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            content()
        }
        .padding(VaultTheme.Spacing.md)
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }

    /// Card con cabecera pulsable que expande/colapsa el contenido
    @ViewBuilder
    private func collapsibleCard<Content: View>(
        icon: String, iconColor: Color, title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible, tap to toggle
            HStack(spacing: VaultTheme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(VaultTheme.Colors.textPrimary)
                    if let sub = subtitle {
                        Text(sub).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded.wrappedValue)
            }
            .padding(VaultTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.wrappedValue.toggle()
                }
            }

            // Expandable content
            if isExpanded.wrappedValue {
                Divider().background(Color(hex: "#2C2C2E"))
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                    content()
                }
                .padding(VaultTheme.Spacing.md)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }

    @ViewBuilder
    private func modernCardHeader(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
            }
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(VaultTheme.Colors.textPrimary)
        }
    }

    private func modernDivider() -> some View {
        Divider().background(Color(hex: "#2C2C2E"))
    }

    @ViewBuilder
    private func modernToggleRow(icon: String, iconColor: Color, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
                Text(detail).font(VaultTheme.Typography.caption()).foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    @ViewBuilder
    private func modernRow<T: View>(icon: String, iconColor: Color, title: String, trailing: T) -> some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor)
            }
            Text(title).font(VaultTheme.Typography.body()).foregroundColor(VaultTheme.Colors.textPrimary)
            Spacer()
            trailing
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(VaultTheme.Colors.textTertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modernActionButton(title: String, icon: String, loading: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                if loading {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: icon)
                }
                Text(title).font(VaultTheme.Typography.bodyBold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VaultTheme.Spacing.md)
            .background(enabled ? VaultTheme.Colors.primary : VaultTheme.Colors.textDisabled)
            .cornerRadius(VaultTheme.CornerRadius.md)
        }
        .disabled(!enabled || loading)
    }

    @ViewBuilder
    private func modernStatusRow(_ message: String, color: Color, icon: String) -> some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            Image(systemName: icon).foregroundColor(color)
            Text(message).font(VaultTheme.Typography.caption()).foregroundColor(color)
        }
    }

    // MARK: - Auto Input Picker (Off / Clipboard / API / OCR)

    @ViewBuilder
    private func autoInputPicker(
        clipboardKey: String,
        topMode: Binding<String>,
        apiSource: Binding<ApiSource>
    ) -> some View {
        let currentMode = AutoInputMode(rawValue: topMode.wrappedValue) ?? .off

        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            Text("Auto Input")
                .font(VaultTheme.Typography.bodyBold())
                .foregroundColor(VaultTheme.Colors.textPrimary)
            Text("Text fetched automatically when Performance opens")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            // ── Pill row ────────────────────────────────────────────
            HStack(spacing: 8) {
                ForEach(AutoInputMode.allCases.filter { $0 != .clipboard }, id: \.rawValue) { mode in
                    let isSelected = currentMode == mode
                    let isOcr = mode == .ocr

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            topMode.wrappedValue = mode.rawValue
                            if clipboardAutoMode == clipboardKey { clipboardAutoMode = "" }
                            if mode != .api { apiSource.wrappedValue = .none }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(isSelected ? .white : VaultTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Self.colorProfile : Color(hex: "#2C2C2E"))
                        .cornerRadius(8)
                    }
                    .contentShape(Rectangle())
                }
            }

            // ── API sub-picker (visible only when API mode is active) ─
            if currentMode == .api {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().background(Color(hex: "#3A3A3C"))
                    Text("API Source")
                        .font(VaultTheme.Typography.captionSmall())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                    HStack(spacing: 6) {
                        ForEach(ApiSource.allCases.filter { $0 != .none }, id: \.rawValue) { src in
                            let isActive = apiSource.wrappedValue == src
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    apiSource.wrappedValue = isActive ? .none : src
                                }
                            } label: {
                                Text(src.displayName.replacingOccurrences(of: "Custom API ", with: "API "))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isActive ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isActive ? Self.colorIntegration : Color(hex: "#2C2C2E"))
                                    .cornerRadius(6)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

            // ── OCR sub-panel (visible only when OCR mode is active) ─
            if currentMode == .ocr {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(Color(hex: "#3A3A3C"))

                    // Language picker
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 13))
                            .foregroundColor(Self.colorProfile)
                            .frame(width: 20)
                        Text("Language")
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                                Button {
                                    ocrLanguage = lang.code
                                } label: {
                                    HStack {
                                        Text(lang.display)
                                        if ocrLanguage == lang.code {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(OCRConfiguration.displayName(for: ocrLanguage))
                                    .font(VaultTheme.Typography.body())
                                    .foregroundColor(Self.colorProfile)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Self.colorProfile)
                            }
                        }
                    }

                    Divider().background(Color(hex: "#3A3A3C"))

                    // Camera picker
                    HStack {
                        Image(systemName: ocrCamera == 0 ? "camera.fill" : "camera.rotate.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Self.colorProfile)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Camera")
                                .font(VaultTheme.Typography.body())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text(ocrCamera == 0 ? "Rear camera" : "Front camera")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach([(0, "Rear"), (1, "Front")], id: \.0) { val, label in
                                let sel = ocrCamera == val
                                Button { ocrCamera = val } label: {
                                    Text(label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(sel ? .white : VaultTheme.Colors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(sel ? Self.colorProfile : Color(hex: "#2C2C2E"))
                                        .cornerRadius(6)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    // Info note
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        Text("Camera activates silently in background when Performance opens. Vibrates once on recognition.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .padding(8)
                    .background(Color(hex: "#2C2C2E"))
                    .cornerRadius(8)
                }
                .padding(.top, 2)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
    }

    private func apiSourceRow(target: String, source: Binding<ApiSource>, onSelect: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Magic API source")
                        .font(VaultTheme.Typography.body())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Fetch text from Inject or Custom API when Performance opens")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(ApiSource.allCases, id: \.rawValue) { apiSource in
                    Button {
                        source.wrappedValue = apiSource
                        if apiSource != .none { onSelect() }
                    } label: {
                        Text(apiSource == .none ? "Off" : apiSource.displayName.replacingOccurrences(of: "Custom API ", with: "API "))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(source.wrappedValue == apiSource ? .white : VaultTheme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(source.wrappedValue == apiSource ? VaultTheme.Colors.primary : Color(hex: "#2C2C2E"))
                            .cornerRadius(6)
                    }
                }
            }
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
    
    // MARK: - URL Scheme Helper Views

    @ViewBuilder
    private var profilePicURLSchemesContent: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(VaultTheme.Colors.primary)
                Text("URL Schemes")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
            }
            Text("Use these URLs in iOS Shortcuts to update your profile picture automatically when Performance opens.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            urlSchemeRow(
                icon:   "photo.on.rectangle",
                title:  "Last gallery photo",
                detail: "Uploads the most recent photo from your camera roll",
                url:    URLActionManager.profilePicLastURL
            )
            Divider()
            profilePicBase64Row
        }
    }

    @ViewBuilder
    private var profilePicBase64Row: some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(VaultTheme.Colors.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base64 from external app")
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Another app sends the image as base64. Vault handles resize and compression automatically.")
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = "vault://profilepic?data=<base64>"
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Copy")
                    }
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            Text("vault://profilepic?data=<base64>")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .padding(.horizontal, VaultTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(VaultTheme.Colors.backgroundSecondary)
                .cornerRadius(VaultTheme.CornerRadius.sm)
        }
    }

    @ViewBuilder
    private func urlSchemeRow(icon: String, title: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: VaultTheme.Spacing.xs) {
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(VaultTheme.Colors.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text(detail)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Copy")
                    }
                    .font(VaultTheme.Typography.captionSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, VaultTheme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(VaultTheme.Colors.primary)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            Text(url)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(VaultTheme.Colors.textSecondary)
                .lineLimit(2)
                .padding(.horizontal, VaultTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(VaultTheme.Colors.backgroundSecondary)
                .cornerRadius(VaultTheme.CornerRadius.sm)
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

// MARK: - Reusable Collapsible Card Shell

struct CollapsibleCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(iconColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(VaultTheme.Typography.caption())
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
            }
            .padding(VaultTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider().background(Color(hex: "#2C2C2E"))
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.md) {
                    content()
                }
                .padding(VaultTheme.Spacing.md)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(Color(hex: "#1C1C1E"))
        .cornerRadius(VaultTheme.CornerRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.lg)
            .stroke(Color(hex: "#2C2C2E"), lineWidth: 0.5))
    }
}

// MARK: - Force Reel Settings Card

// MARK: - Force Post Settings Card

struct ForcePostSettingsCard: View {
    @ObservedObject private var settings = ForcePostSettings.shared
    @State private var showingPicker = false
    @State private var isExpanded = false

    var body: some View {
        Group {
        CollapsibleCard(icon: "square.grid.2x2", iconColor: SettingsView.colorTricks,
                        title: "Force Post",
                        subtitle: "Force a scroll to stop on a specific post",
                        isExpanded: $isExpanded) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
            }

            Text("Pre-select a post from any profile. During performance, the spectator scrolls through their posts and the scroll always stops on the forced image.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            if settings.isEnabled {
                Divider()

                if settings.hasPost {
                        HStack(spacing: VaultTheme.Spacing.md) {
                            if let img = settings.localThumbnailImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(width: 64, height: 64)
                                    .overlay(ProgressView().scaleEffect(0.7))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Post selected")
                                    .font(VaultTheme.Typography.bodyBold())
                                    .foregroundColor(VaultTheme.Colors.textPrimary)
                                Text("from @\(settings.targetUsername)")
                                    .font(VaultTheme.Typography.caption())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                                Text("ID: \(String(settings.forcedMediaId.prefix(16)))…")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundColor(VaultTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: VaultTheme.Spacing.sm) {
                            Button(action: { showingPicker = true }) {
                                Label("Change Post", systemImage: "arrow.triangle.2.circlepath")
                                    .font(VaultTheme.Typography.body())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive, action: { settings.clearPost() }) {
                                Label("Remove", systemImage: "trash")
                                    .font(VaultTheme.Typography.body())
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    } else {
                        Button(action: { showingPicker = true }) {
                            Label("Select Post", systemImage: "photo.on.rectangle.angled")
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
            ForcePostPickerView()
        }
    }
}

struct ForceReelSettingsCard: View {
    @ObservedObject private var settings = ForceReelSettings.shared
    @State private var showingPicker = false
    @State private var previewImage: UIImage?
    @State private var isExpanded = false

    var body: some View {
        Group {
        CollapsibleCard(icon: "hand.point.up.left.fill", iconColor: SettingsView.colorTricks,
                        title: "Force Reel",
                        subtitle: "Place a reel at an exact slot in Explore",
                        isExpanded: $isExpanded) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
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
        .sheet(isPresented: $showingPicker) {
            ForceReelPickerView()
        }
        .onChange(of: settings.thumbnailURL) { _ in loadPreview() }
    }

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
    @ObservedObject private var secretSettings  = SecretInputSettings.shared
    @State private var isExpanded = false

    @AppStorage("ocr_language")      private var ocrLanguage:      String = "es-ES"
    @AppStorage("ocr_camera")        private var ocrCamera:        Int    = 0
    @AppStorage("noteTopInputMode")  private var noteTopInputMode: String = "off"
    @AppStorage("bioTopInputMode")   private var bioTopInputMode:  String = "off"

    private var ocrEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.ocrEnabled },
            set: { newValue in settings.ocrEnabled = newValue }
        )
    }

    private var activeNumberSet: PhotoSet? {
        guard let id = activeSetSettings.activeNumberSetId else { return nil }
        return dataManager.sets.first { $0.id == id && $0.type == .number }
    }

    private var activeWordSet: PhotoSet? {
        guard let id = activeSetSettings.activeWordSetId else { return nil }
        return dataManager.sets.first { $0.id == id && $0.type == .word }
    }

    private var coverTypingPreview: String {
        let word = "coche"
        let maskText = secretSettings.mode == .customUsername
            ? secretSettings.customUsername.lowercased()
            : "user"
        guard !maskText.isEmpty else { return "user" }
        var result = ""
        for i in 0..<word.count {
            let idx = maskText.index(maskText.startIndex, offsetBy: i % maskText.count)
            result.append(maskText[idx])
        }
        return result
    }

    var body: some View {
        CollapsibleCard(icon: "number.circle.fill", iconColor: SettingsView.colorTricks,
                        title: "Post Prediction",
                        subtitle: "Reveal a post with a word by unarchiving photos",
                        isExpanded: $isExpanded) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
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

                        // Time picker slider
                        VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                            HStack {
                                Text("Re-archive after")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("\(settings.autoReArchiveMinutes) min")
                                    .font(VaultTheme.Typography.captionSmall())
                                    .foregroundColor(VaultTheme.Colors.primary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(settings.autoReArchiveMinutes) },
                                    set: { settings.autoReArchiveMinutes = Int($0.rounded()) }
                                ),
                                in: 5...60,
                                step: 5
                            )
                            .tint(VaultTheme.Colors.primary)
                            HStack {
                                Text("5 min").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
                                Spacer()
                                Text("60 min").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
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

            // ── Cover Typing Input ─────────────────────────────────
            Divider()
            HStack {
                Text("Cover Typing Input")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $secretSettings.isEnabled).labelsHidden()
            }
            Text("Masks what you type in Explore so spectators see a different word. Pressing SPACE triggers the word reveal.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)
            if secretSettings.isEnabled {
                VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                    Text("Mask Mode")
                        .font(VaultTheme.Typography.bodyBold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    ForEach(MaskInputMode.allCases, id: \.self) { mode in
                        let selected = secretSettings.mode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { secretSettings.mode = mode }
                        } label: {
                            HStack(spacing: VaultTheme.Spacing.md) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected ? VaultTheme.Colors.primary : VaultTheme.Colors.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(VaultTheme.Typography.body())
                                        .foregroundColor(VaultTheme.Colors.textPrimary)
                                    Text(mode.rawValue)
                                        .font(VaultTheme.Typography.caption())
                                        .foregroundColor(VaultTheme.Colors.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if secretSettings.mode == .customUsername {
                        TextField("Custom username", text: $secretSettings.customUsername)
                            .font(VaultTheme.Typography.body())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(VaultTheme.Spacing.md)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    HStack(spacing: 4) {
                        Text("Preview:")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                        Text("\"coche\" → \"\(coverTypingPreview)\"")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.primary)
                    }
                }
            }

            // ── OCR Recognition ───────────────────────────────────
            Divider()
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(SettingsView.colorTricks)
                    .frame(width: 20)
                Text("OCR Recognition")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: ocrEnabledBinding).labelsHidden()
            }
            Text("Camera starts silently when Performance opens. Recognized text auto-reveals: letters → word set, digits → number set.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            if settings.ocrEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Active sets summary
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "text.cursor")
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Word set: \(activeWordSet?.name ?? "None selected")")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(activeWordSet != nil ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.warning)
                            Text("Number set: \(activeNumberSet?.name ?? "None selected")")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(activeNumberSet != nil ? VaultTheme.Colors.textPrimary : VaultTheme.Colors.warning)
                        }
                    }

                    // Camera selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Camera")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .textCase(.uppercase)
                        HStack(spacing: 6) {
                            ForEach([0, 1], id: \.self) { val in
                                let sel = ocrCamera == val
                                Button { ocrCamera = val } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: val == 0 ? "camera.fill" : "camera.rotate.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(val == 0 ? "Rear" : "Front")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(sel ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(sel ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                                    .cornerRadius(8)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    // Language selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Language")
                            .font(VaultTheme.Typography.captionSmall())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                            .textCase(.uppercase)
                        Menu {
                            ForEach(OCRConfiguration.supportedLanguages, id: \.code) { lang in
                                Button { ocrLanguage = lang.code } label: {
                                    if ocrLanguage == lang.code {
                                        Label(lang.display, systemImage: "checkmark")
                                    } else {
                                        Text(lang.display)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                Text(OCRConfiguration.displayName(for: ocrLanguage))
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color(hex: "#2C2C2E"))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Counter Glitch Effect Settings Card

struct FollowingMagicSettingsCard: View {
    @ObservedObject private var settings = FollowingMagicSettings.shared
    @State private var isExpanded = false

    var body: some View {
        CollapsibleCard(icon: "person.2.fill", iconColor: SettingsView.colorTricks,
                        title: "Counter Glitch Effect",
                        subtitle: "Inflate a follower or following count with a countdown",
                        isExpanded: $isExpanded) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $settings.isEnabled).labelsHidden()
            }
            Text("Swipe the grid to secretly build a number (1–100), then open Explore. When you visit an audience member's profile the selected counter appears inflated. Press a volume button to start the countdown back to the real number.")
                .font(VaultTheme.Typography.caption())
                .foregroundColor(VaultTheme.Colors.textSecondary)

            if settings.isEnabled {
                    Divider()

                    // ── Target stat ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: VaultTheme.Spacing.sm) {
                        Text("Target counter")
                            .font(VaultTheme.Typography.bodyBold())
                            .foregroundColor(VaultTheme.Colors.textPrimary)
                        HStack(spacing: 8) {
                            ForEach([(false, "Following", "person.2"), (true, "Followers", "person.2.fill")], id: \.0) { isFollowers, label, icon in
                                let selected = settings.targetFollowers == isFollowers
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settings.targetFollowers = isFollowers
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(label)
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(selected ? .white : VaultTheme.Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? SettingsView.colorTricks : Color(hex: "#2C2C2E"))
                                    .cornerRadius(8)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    Divider()

                    // ── Transfer illusion ─────────────────────────────────
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .foregroundColor(SettingsView.colorTricks)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer effect")
                                .font(VaultTheme.Typography.bodyBold())
                                .foregroundColor(VaultTheme.Colors.textPrimary)
                            Text("Deflates the searched profile, then inflates yours when you press the volume button.")
                                .font(VaultTheme.Typography.caption())
                                .foregroundColor(VaultTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.transferEnabled)
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
                                .monospacedDigit()
                        }
                        Text("Time between pressing the volume button and the numbers starting to decrease.")
                            .font(VaultTheme.Typography.caption())
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                        Slider(
                            value: Binding(
                                get: { Double(settings.triggerDelay) },
                                set: { settings.triggerDelay = Int($0.rounded()) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                        .tint(VaultTheme.Colors.primary)
                        HStack {
                            Text("0s").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
                            Spacer()
                            Text("10s").font(VaultTheme.Typography.captionSmall()).foregroundColor(VaultTheme.Colors.textTertiary)
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
    @State private var isExpanded = false

    var body: some View {
        Group {
        CollapsibleCard(icon: "calendar.badge.clock", iconColor: SettingsView.colorTricks,
                        title: "Date Force",
                        subtitle: "Force followers/following to reveal today's date",
                        isExpanded: $isExpanded) {
            HStack {
                Text("Enabled")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Spacer()
                HStack(spacing: 10) {
                    Button(action: { showingHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(VaultTheme.Colors.textTertiary)
                    }
                    Toggle("", isOn: $settings.isEnabled).labelsHidden()
                }
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

// MARK: - Fake Home Screen Card

struct FakeHomeScreenCard: View {
    @Binding var showingPicker: Bool
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @AppStorage("fakeHomeScreenEnabled") private var fakeHomeScreenEnabled = false
    @State private var isExpanded = false

    private static let accent = SettingsView.colorData

    var body: some View {
        CollapsibleCard(
            icon: "iphone",
            iconColor: Self.accent,
            title: "Fake Home Screen",
            subtitle: "Show a home screen screenshot when Performance opens",
            isExpanded: $isExpanded
        ) {
            toggleRow
            modernDivider()
            imagePickerRow
        }
    }

    @ViewBuilder private var toggleRow: some View {
        HStack(spacing: VaultTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Self.accent)
                    .frame(width: 28, height: 28)
                Image(systemName: "iphone.homebutton")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable fake home screen")
                    .font(VaultTheme.Typography.body())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text("Tap anywhere to reveal your Instagram profile")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $fakeHomeScreenEnabled).labelsHidden()
        }
    }

    @ViewBuilder private var imagePickerRow: some View {
        HStack(alignment: .top, spacing: VaultTheme.Spacing.sm) {
            thumbnailView
            VStack(alignment: .leading, spacing: 6) {
                Text(illusionService.hasImage ? "Screenshot loaded" : "No screenshot")
                    .font(VaultTheme.Typography.bodyBold())
                    .foregroundColor(VaultTheme.Colors.textPrimary)
                Text("Upload a screenshot of your iPhone home screen showing the Instagram icon.")
                    .font(VaultTheme.Typography.caption())
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var thumbnailView: some View {
        if let img = illusionService.screenshot {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#3A3A3C"), lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#2C2C2E"))
                .frame(width: 52, height: 92)
                .overlay(Image(systemName: "iphone")
                    .font(.system(size: 22))
                    .foregroundColor(VaultTheme.Colors.textTertiary))
        }
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { showingPicker = true } label: {
                Label(illusionService.hasImage ? "Replace" : "Select screenshot",
                      systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Self.accent)
                    .cornerRadius(7)
            }
            if illusionService.hasImage {
                Button { illusionService.delete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VaultTheme.Colors.error)
                        .padding(6)
                        .background(VaultTheme.Colors.error.opacity(0.12))
                        .cornerRadius(7)
                }
            }
        }
    }

    @ViewBuilder private func modernDivider() -> some View {
        Divider().background(Color(hex: "#3A3A3C"))
    }
}

// MARK: - Home Screen Image Picker

import PhotosUI

struct HomeScreenImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { self?.onPick(image) }
            }
        }
    }
}
