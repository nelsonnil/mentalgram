import SwiftUI
import Photos
import AVFoundation
import AudioToolbox

// MARK: - Performance View (Instagram Profile Replica)

struct PerformanceView: View {
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject private var dateForce = DateForceSettings.shared
    @ObservedObject private var profileCache = ProfileCacheService.shared
    @AppStorage("autoProfilePicOnPerformance") private var autoProfilePicOnPerformance = false
    @AppStorage("clipboardAutoMode") private var clipboardAutoMode: String = ""
    // Last clipboard text sent — avoids re-sending the same text on repeated opens.
    @AppStorage("clipboardAutoLastSent") private var clipboardAutoLastSent: String = ""
    @ObservedObject private var integrations = IntegrationsSettings.shared
    @ObservedObject private var urlAction = URLActionManager.shared

    // OCR
    @AppStorage("noteTopInputMode") private var noteTopInputMode: String = "off"
    @AppStorage("bioTopInputMode")  private var bioTopInputMode:  String = "off"
    // Text templates — user-defined wrappers with {word} token
    @AppStorage("note_template") private var noteTemplate: String = ""
    @AppStorage("bio_template")  private var bioTemplate:  String = ""
    // Optimistic note state — @AppStorage triggers instant re-render on write
    @AppStorage("last_note_text")           private var lastNoteText: String = ""
    @AppStorage("last_note_sent_timestamp") private var lastNoteSentTimestamp: Double = 0
    @ObservedObject private var forceRevealSettings = ForceNumberRevealSettings.shared
    @ObservedObject private var followingMagic = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor  = VolumeButtonMonitor.shared
    @StateObject private var ocrCoordinator = OCRCoordinator()
    /// Set by OCR result handler; observed by InstagramProfileView to trigger post-prediction reveal.
    @State private var pendingOCRWord: String? = nil
    /// True once OCR has recognised and routed a word in this session.
    /// Prevents a second OCR trigger in the same Performance session (one reveal per trick).
    @State private var ocrUsedInSession: Bool = false
    @State private var profile: InstagramProfile?
    @State private var isLoading = false
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    @State private var showingMagicianDebug = false  // For long-press debug info
    @State private var showDigitGridAlert = false
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    
    // MARK: - Infinite Scroll State
    @State private var allMediaURLs: [String] = []
    @State private var mediaItemsByURL: [String: InstagramMediaItem] = [:]
    @State private var revealDates: [String: Date] = [:]
    @State private var nextMaxId: String? = nil
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    private let maxPhotosOwnProfile = 100

    // MARK: - Fake Home Screen illusion
    @AppStorage("fakeHomeScreenEnabled") private var fakeHomeScreenEnabled = false
    @ObservedObject private var illusionService = HomeScreenIllusionService.shared
    @State private var showingHomeScreenIllusion = false

    // MARK: - Spectator profile overlay
    @State private var selectedSpectator: InstagramFollower? = nil
    @State private var spectatorProfile: InstagramProfile?  = nil
    @State private var isLoadingSpectator: Bool             = false

    // MARK: - Upload conflict alert (reveal blocked while upload is active)
    @State private var showUploadConflictAlert = false
    @State private var spectatorLoadError: String? = nil

    // MARK: - Anti-bot: auto-pause upload while Performance is visible
    // True when PerformanceView itself requested the pause (not the user, not an error).
    // Used in onDisappear to signal SetDetailView to auto-resume.
    @State private var didAutoPauseUpload = false
    @ObservedObject private var uploadManager = UploadManager.shared

    // MARK: - Refresh throttle (prevent rapid consecutive API calls)
    @State private var lastRefreshDate: Date? = nil
    private let minRefreshInterval: TimeInterval = 10
    
    // MARK: - Sub-views (split to help Swift type-checker)

    private var performanceRoot: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
            profileContent
                .padding(.bottom, 54)
            bottomBar
        }
    }

    @ViewBuilder private var profileContent: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let profile = profile {
                instagramProfileView(profile: profile)
            } else {
                InstagramProfileSkeleton(onPlusPress: { selectedTab = 1 })
            }
            if instagram.isLocked { performanceLockdownOverlay }
        }
    }

    @ViewBuilder private var spectatorOverlay: some View {
        if isLoadingSpectator {
            Color.white.ignoresSafeArea()
                .overlay(
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.2)
                        Text("Loading profile…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                )
                .zIndex(899)
        }
        if showingHomeScreenIllusion, let screenshot = illusionService.screenshot {
            Image(uiImage: screenshot)
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width,
                       height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.12)) { showingHomeScreenIllusion = false }
                }
                .zIndex(999)
        }
    }

    private var bottomBar: some View {
        InstagramBottomBar(
            profileImageURL: profile?.profilePicURL,
            cachedImage: profile?.profilePicURL != nil ? cachedImages[profile!.profilePicURL] : nil,
            isHome: true, isSearch: false,
            onHomePress: {},
            onSearchPress: {
                // Capture buffer ONCE before any consumer resets it.
                // FollowingMagic's captureFromBuffer() calls reset() internally,
                // which would empty the buffer before ForceReel can read it.
                let capturedDigits = SecretNumberManager.shared.digitBuffer
                let capturedNumber = capturedDigits.reduce(0) { $0 * 10 + $1 }

                if FollowingMagicSettings.shared.isEnabled && !capturedDigits.isEmpty {
                    FollowingMagicSettings.shared.captureFromBuffer()
                }
                if ForceReelSettings.shared.isEnabled && ForceReelSettings.shared.hasReel && capturedNumber > 0 {
                    ForceReelSettings.shared.pendingPosition = capturedNumber
                    print("🎭 [FORCE] Position captured: \(capturedNumber)")
                    // Buffer may already be reset by FollowingMagic above; only reset if still populated.
                    if SecretNumberManager.shared.hasDigits {
                        SecretNumberManager.shared.reset()
                    }
                }
                showingExplore = true
            },
            onReelsPress: {},
            onMessagesPress: {},
            onProfilePress: {}
        )
    }

    private func instagramProfileView(profile: InstagramProfile) -> some View {
        InstagramProfileView(
            profile: profile,
            cachedImages: $cachedImages,
            onRefresh: loadProfileSync,
            onAsyncRefresh: loadProfile,
            onPlusPress: { selectedTab = 1 },
            mediaURLs: allMediaURLs,
            onMediaAppear: loadMoreIfNeeded,
            onAutoFollowedByTap: { handleAutoFollowedByTap() },
            onAddLocalImages: { photos in
                for item in photos {
                    if let image = item.image { cachedImages[item.pseudoURL] = image }
                    insertRevealURL(item.pseudoURL)
                }
                print("⚡️ [PERF] \(photos.count) photo(s) pre-inserted instantly — API unarchive in progress")
            },
            onRevealComplete: { revealedPhotos in
                for item in revealedPhotos {
                    if let image = item.image { cachedImages[item.pseudoURL] = image }
                    insertRevealURL(item.pseudoURL)
                }
                if !revealedPhotos.isEmpty {
                    print("⚡️ [PERF] \(revealedPhotos.count) photo(s) inserted from local storage")
                    LogManager.shared.info("Grid updated from local images: \(revealedPhotos.count) photo(s)", category: .general)
                }
                // Double full-power vibration (notification-level) — magician confirms photos live on Instagram
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s gap
                    await MainActor.run {
                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    }
                }
                Task { await refreshMediaGridSilently() }
            },
            mediaItemsByURL: mediaItemsByURL,
            isLoading: isLoading,
            lastRefreshDate: lastRefreshDate,
            minRefreshInterval: minRefreshInterval,
            onUploadConflict: { showUploadConflictAlert = true },
            onFollowerTap: { follower in
                withAnimation(.easeInOut(duration: 0.25)) { selectedSpectator = follower }
            },
            pendingOCRWord: $pendingOCRWord
        )
    }

    // MARK: - OCR modifiers (split out to reduce body complexity for the Swift type-checker)

    private var ocrModifiers: some View {
        ZStack {
            performanceRoot
            spectatorOverlay
        }
            .onChange(of: volumeMonitor.upCount) { _ in
                guard spectatorProfile == nil else {
                    print("📷 [OCR] Blocked — spectator profile is visible")
                    return
                }
                guard !showingExplore else {
                    print("📷 [OCR] Blocked — Explore is open")
                    return
                }
                guard !followingMagic.transferEnabled || followingMagic.transferOffset == 0 else {
                    print("📷 [OCR] Blocked — Transfer offset saved, volume UP reserved for inflation")
                    return
                }
                guard !ocrUsedInSession else {
                    print("📷 [OCR] Blocked — already used once in this Performance session")
                    return
                }
                let noteOcr     = noteTopInputMode == "ocr"
                let bioOcr      = bioTopInputMode  == "ocr"
                let postPredOcr = forceRevealSettings.ocrEnabled
                guard noteOcr || bioOcr || postPredOcr else { return }
                if ocrCoordinator.isRunning {
                    ocrCoordinator.stop()
                    print("📷 [OCR] Stopped by volume UP (toggle off)")
                } else {
                    let config = OCRConfiguration.fromUserDefaults()
                    ocrCoordinator.start(config: config)
                    print("📷 [OCR] Started by volume UP — note=\(noteOcr) bio=\(bioOcr) postPrediction=\(postPredOcr)")
                }
            }
            .onChange(of: ocrCoordinator.recognizedText) { text in
                guard let text = text, !text.isEmpty else { return }
                print("📷 [OCR] Recognized: \"\(text)\"")
                // Full-power vibration: confirms recognition to the magician
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                // Lock OCR for the rest of this Performance session — one reveal per trick.
                ocrUsedInSession = true
                // Execute all active OCR targets sequentially (bio → note → post prediction)
                // to avoid concurrent API calls that could trigger bot detection.
                Task {
                    let hasBio  = bioTopInputMode  == "ocr"
                    let hasNote = noteTopInputMode == "ocr"
                    let hasPost = forceRevealSettings.ocrEnabled

                    if hasBio {
                        print("📷 [OCR] Step 1/3 — applying to biography")
                        await applyOCRResult(text: text, target: "bio")
                    }
                    if hasNote {
                        if hasBio {
                            // Brief gap between consecutive API write operations
                            print("📷 [OCR] Waiting 3s before note (anti-bot gap)")
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                        }
                        print("📷 [OCR] Step \(hasBio ? "2" : "1")/\([hasBio, hasNote, hasPost].filter { $0 }.count) — applying to note")
                        await applyOCRResult(text: text, target: "note")
                    }
                    if hasPost {
                        let priorSteps = (hasBio ? 1 : 0) + (hasNote ? 1 : 0)
                        if priorSteps > 0 {
                            print("📷 [OCR] Waiting 3s before post prediction (anti-bot gap)")
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                        }
                        print("📷 [OCR] Step \(priorSteps + 1)/\([hasBio, hasNote, hasPost].filter { $0 }.count) — applying to post prediction")
                        await applyOCRToPostPrediction(text: text)
                    }
                }
            }
    }

    var body: some View {
        ocrModifiers
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarHidden(true)
            .preferredColorScheme(.light)
            .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
            .alert("Error", isPresented: Binding(
                get: { spectatorLoadError != nil },
                set: { if !$0 { spectatorLoadError = nil } }
            )) {
                Button("OK") { spectatorLoadError = nil }
            } message: {
                Text(spectatorLoadError ?? "")
            }
            .alert("Digit Grid Disabled", isPresented: $showDigitGridAlert) {
                Button("Enable") { ForceNumberRevealSettings.shared.gridSwipeEnabled = true }
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text("You have an active number set but Digit Grid input is off. Enable it to unarchive photos by swiping the grid.")
            }
            // Spectator profile: bound to selectedSpectator to avoid the nil→item race
            // condition that caused stale profiles when tapping a second follower.
            .fullScreenCover(item: $selectedSpectator) { follower in
                SpectatorProfileCover(follower: follower, onClose: {
                    selectedSpectator = nil
                })
                .preferredColorScheme(.light)
            }
        // selectedSpectator drives fullScreenCover directly — no extra onChange needed.
        // When Explore closes, reset digit buffer (InstagramProfileView's onChange clears followingOverride)
        .onChange(of: showingExplore) { isOpen in
            if !isOpen {
                SecretNumberManager.shared.reset()
            }
        }
        // Instantly show a newly uploaded profile picture without waiting for a CDN URL.
        // HomeView sets this override right after a successful upload; we mirror it into
        // cachedImages under the current profilePicURL key so the header and bottom bar
        // update immediately. The override is cleared on the next full profile refresh.
        .onChange(of: profileCache.pendingProfilePic) { newPic in
            guard let pic = newPic, let url = profile?.profilePicURL, !url.isEmpty else { return }
            cachedImages[url] = pic
            print("⚡️ [PERF] Profile pic updated instantly from local image (no CDN GET needed)")
            LogManager.shared.info("Profile pic shown instantly from local storage", category: .general)
        }
        // Instantly reflect a biography update in the fake Instagram profile view.
        // changeBiography() saves to ProfileCacheService on success; we pick it up here.
        .onChange(of: profileCache.cachedProfile?.biography) { newBio in
            guard let newBio, !isLoading else { return }
            guard let current = profile, current.biography != newBio else { return }
            profile = InstagramProfile(
                userId: current.userId, username: current.username,
                fullName: current.fullName, biography: newBio,
                externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                isVerified: current.isVerified, isPrivate: current.isPrivate,
                followerCount: current.followerCount, followingCount: current.followingCount,
                mediaCount: current.mediaCount, followedBy: current.followedBy,
                isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                cachedHighlights: current.cachedHighlights
            )
            print("⚡️ [PERF] Biography updated instantly in fake profile (no GET needed)")
            LogManager.shared.info("Biography updated instantly in profile view", category: .general)
        }
        // React to local profile cache changes (archive/unarchive, etc.)
        // without making any extra API call.
        .onChange(of: profileCache.cachedProfile?.cachedMediaURLs) { newURLs in
            guard let newURLs else { return }
            // Only sync if the change came from somewhere else (not from our own full reload)
            guard !isLoading else {
                print("🔄 [PERF] onChange cachedMediaURLs fired but isLoading=true — skipped")
                return
            }
            let currentSet = Set(allMediaURLs)
            let newSet = Set(newURLs)
            guard currentSet != newSet else {
                print("🔄 [PERF] onChange cachedMediaURLs fired — no diff (both \(newURLs.count) items), skipped")
                return
            }
            let removed = currentSet.subtracting(newSet).count
            let added   = newSet.subtracting(currentSet).count
            print("🔄 [PERF] onChange cachedMediaURLs: \(allMediaURLs.count)→\(newURLs.count) (-\(removed) +\(added))")
            allMediaURLs = newURLs
            // Download thumbnails for any new URLs not yet cached
            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty { downloadImagesForURLs(missing) }
            print("🔄 [PERF] Grid updated locally — \(newURLs.count) items (no API call)")
        }
        .onAppear {
            // Screen always on — managed globally by MentalGram1App
            // Show fake home screen if enabled and image is available
            if fakeHomeScreenEnabled && illusionService.hasImage {
                showingHomeScreenIllusion = true
                print("🏠 [ILLUSION] Fake home screen active — tap to reveal profile")
            }

            // Anti-bot: if a set upload is actively running, pause it while we're here.
            // Parallel API calls (upload POSTs + profile GETs / auto-pic POSTs) from the
            // same session are a strong bot signal.
            if uploadManager.isUploading {
                uploadManager.requestPause = true
                didAutoPauseUpload = true
                print("⏸️ [PERF] Upload paused — entering Performance view (anti-bot)")
                LogManager.shared.warning("Upload auto-paused: Performance view opened", category: .general)
            }

            // Activate volume button detection for FollowingMagic and/or OCR.
            // prepareVolume() warms up the audio session and slider (must run first).
            // startMonitoring() registers the KVO observer that increments upCount/downCount.
            let needsVolume = FollowingMagicSettings.shared.isEnabled
                || noteTopInputMode == "ocr"
                || bioTopInputMode  == "ocr"
                || forceRevealSettings.ocrEnabled
            if needsVolume {
                VolumeButtonMonitor.shared.prepareVolume()
                VolumeButtonMonitor.shared.startMonitoring()
            }
            checkAndLoadProfile()

            // Serialize all auto-actions in a single sequential Task.
            // Running them in parallel creates concurrent API calls from the
            // same session → strong bot signal (especially POST+GET combos).
            Task { @MainActor in
                // 1. Auto profile pic (POST) — wait for loadProfile to finish first
                if autoProfilePicOnPerformance {
                    // Brief pause so loadProfile's GET finishes or at least starts
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !instagram.isLocked, !instagram.isSessionChallenged else {
                        print("📷 [AUTO PIC] Skipped in serial queue — locked or challenged")
                        return
                    }
                    await autoUploadLatestGalleryPhoto()
                }

                // 2. URL scheme action OR clipboard OR API auto-mode (never more than one)
                if let action = urlAction.consume() {
                    if action.mode.hasPrefix("profilepic") {
                        await applyURLProfilePicAction(mode: action.mode, data: action.text)
                    } else {
                        await applyURLAction(mode: action.mode, text: action.text)
                    }
                } else if clipboardAutoMode != "" {
                    await applyClipboardAutoMode()
                } else {
                    if integrations.noteApiSource != .none && noteTopInputMode == "api" {
                        await applyApiAutoMode(target: "note")
                    }
                    if integrations.bioApiSource != .none && bioTopInputMode == "api" {
                        await applyApiAutoMode(target: "bio")
                    }
                }
            }
            ocrUsedInSession = false

            // Show a nudge if Post Prediction is enabled with an active number set
            // but Digit Grid input is off — and this is NOT a URL scheme reveal
            // (URL reveals supply the word directly so no grid is needed).
            let hasNumberSet = ActiveSetSettings.shared.activeNumberSetId != nil
            let isURLReveal  = urlAction.pendingMode == "reveal"
            if forceRevealSettings.isEnabled,
               !forceRevealSettings.gridSwipeEnabled,
               hasNumberSet,
               !isURLReveal {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showDigitGridAlert = true
                }
            }
        }
        .onDisappear {
            // Stop volume monitoring and OCR when leaving Performance
            VolumeButtonMonitor.shared.stopMonitoring()
            ocrCoordinator.stop()

            // Anti-bot: if we auto-paused an upload on appear, signal SetDetailView to resume it.
            // Only resume if the upload is still in .paused state (user didn't cancel/error).
            if didAutoPauseUpload && uploadManager.isPaused {
                uploadManager.autoResumePending = true
                print("▶️ [PERF] Leaving Performance — signalling upload to auto-resume")
                LogManager.shared.info("Upload auto-resume pending: leaving Performance view", category: .general)
            }
            didAutoPauseUpload = false
        }
    }
    
    // MARK: - URL Scheme Profile Pic Action

    /// Handles vault://profilepic in its three variants.
    private func applyURLProfilePicAction(mode: String, data: String) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [URL PIC] Not logged in or lockdown active — skipping")
            return
        }

        print("📲 [URL PIC] Handling mode=\(mode)")
        LogManager.shared.info("URL scheme profile pic action: \(mode)", category: .general)

        var imageData: Data?

        switch mode {
        case "profilepic_last":
            // Reuse existing logic but force upload (ignore asset-ID duplicate check)
            let authorized = await requestPhotosPermissionIfNeeded()
            guard authorized else {
                print("📷 [URL PIC] No Photos permission")
                return
            }
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: .image, options: fetchOptions).firstObject else {
                print("📷 [URL PIC] Gallery empty")
                return
            }
            imageData = await loadImageData(from: asset)

        case "profilepic_clipboard":
            guard let clipImage = UIPasteboard.general.image else {
                print("📋 [URL PIC] No image in clipboard")
                return
            }
            imageData = resizeAndCompress(clipImage, maxDimension: 512, quality: 0.75)

        case "profilepic_base64":
            guard !data.isEmpty,
                  let decoded = Data(base64Encoded: data, options: .ignoreUnknownCharacters),
                  let img = UIImage(data: decoded) else {
                print("❌ [URL PIC] Invalid base64 image data")
                return
            }
            // Vault handles resize + compress — the sender doesn't need to do anything
            imageData = resizeAndCompress(img, maxDimension: 512, quality: 0.75)
            print("📲 [URL PIC] Base64 decoded: \(decoded.count / 1024) KB → \((imageData?.count ?? 0) / 1024) KB after resize")

        default:
            print("⚠️ [URL PIC] Unknown mode: \(mode)")
            return
        }

        guard let finalData = imageData else {
            print("❌ [URL PIC] Could not prepare image data")
            return
        }

        do {
            let success = try await instagram.changeProfilePicture(imageData: finalData)
            if success, let uiImage = UIImage(data: finalData) {
                let picURL = profile?.profilePicURL ?? "urlpic_pending"
                await MainActor.run {
                    cachedImages[picURL] = uiImage
                    ProfileCacheService.shared.pendingProfilePic = uiImage
                }
                print("✅ [URL PIC] Profile picture updated via URL scheme (\(mode))")
                LogManager.shared.success("Profile pic updated via URL scheme (\(mode))", category: .general)
            }
        } catch {
            print("⚠️ [URL PIC] Upload failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme profile pic failed: \(error.localizedDescription)", category: .general)
        }
    }

    /// Resizes a UIImage to fit within maxDimension×maxDimension and compresses to JPEG.
    private func resizeAndCompress(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Template Helper

    /// Replaces `{word}` in `template` with the detected/fetched word.
    /// Returns `word` unchanged when the template is empty or contains no token,
    /// so existing behaviour is fully preserved for users without a template set.
    private func applyTemplate(_ word: String, template: String) -> String {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.contains("{word}") else { return word }
        return t.replacingOccurrences(of: "{word}", with: word)
    }

    // MARK: - URL Scheme Action

    private func applyURLAction(mode: String, text: String) async {
        guard !instagram.isLocked else {
            print("🚫 [URL] Lockdown active — skipping URL action")
            return
        }
        print("📲 [URL] Executing action=\(mode), text=\"\(text.prefix(40))\"")
        LogManager.shared.info("URL scheme action: \(mode) — \"\(text.prefix(40))\"", category: .general)

        // ── Word reveal via vault://reveal?word= ─────────────────────────────
        if mode == "reveal" {
            guard ForceNumberRevealSettings.shared.isEnabled else {
                print("🚫 [URL] Reveal blocked: Post Prediction not enabled")
                return
            }
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return }
            print("📲 [URL] Reveal word: \"\(word)\"")
            LogManager.shared.info("URL reveal → word: \"\(word)\"", category: .general)
            // Mark as URL-triggered so the OCR handler skips the ocrEnabled guard
            await MainActor.run {
                ForceNumberRevealSettings.shared.urlRevealActive = true
                pendingOCRWord = word
            }
            return
        }

        do {
            if mode == "note" {
                let final = truncateAtWordBoundary(text, limit: 60)
                if final.count < text.count {
                    print("✂️ [URL] Note truncated: \(text.count)→\(final.count) chars")
                }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    print("✅ [URL] Note sent via URL scheme")
                    LogManager.shared.success("Note sent via URL scheme (\(final.count) chars)", category: .general)
                }
            } else if mode == "bio" {
                let final = truncateAtWordBoundary(text, limit: 150)
                if final.count < text.count {
                    print("✂️ [URL] Bio truncated: \(text.count)→\(final.count) chars")
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    print("✅ [URL] Biography updated via URL scheme")
                    LogManager.shared.success("Biography updated via URL scheme (\(final.count) chars)", category: .general)
                }
            }
        } catch {
            print("⚠️ [URL] Action failed: \(error.localizedDescription)")
            LogManager.shared.warning("URL scheme action failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Clipboard Auto-Mode

    private func applyClipboardAutoMode() async {
        guard clipboardAutoMode == "note" || clipboardAutoMode == "bio" else { return }
        guard !instagram.isLocked else {
            print("🚫 [CLIPBOARD] Lockdown active — skipping clipboard auto-mode")
            return
        }

        // Read clipboard text
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            print("📋 [CLIPBOARD] Clipboard is empty — nothing to send")
            return
        }

        // Avoid re-sending the same text on repeated Performance opens
        guard text != clipboardAutoLastSent else {
            print("📋 [CLIPBOARD] Same text as last send — skipping (\"\(text.prefix(30))…\")")
            return
        }

        print("📋 [CLIPBOARD] Auto-mode=\(clipboardAutoMode), text=\"\(text.prefix(40))\"")
        LogManager.shared.info("Clipboard auto-mode triggered (\(clipboardAutoMode)): \"\(text.prefix(40))\"", category: .general)

        do {
            if clipboardAutoMode == "note" {
                let composed = applyTemplate(text, template: noteTemplate)
                let final = truncateAtWordBoundary(composed, limit: 60)
                if final.count < composed.count {
                    print("✂️ [CLIPBOARD] Note truncated at word boundary: \(composed.count)→\(final.count) chars")
                }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    clipboardAutoLastSent = text  // track original clipboard text to avoid re-sends
                    print("✅ [CLIPBOARD] Note sent from clipboard")
                    LogManager.shared.success("Auto-note sent from clipboard (\(final.count) chars)", category: .general)
                }
            } else {
                let composed = applyTemplate(text, template: bioTemplate)
                let final = truncateAtWordBoundary(composed, limit: 150)
                if final.count < composed.count {
                    print("✂️ [CLIPBOARD] Biography truncated at word boundary: \(composed.count)→\(final.count) chars")
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    clipboardAutoLastSent = text  // track original clipboard text to avoid re-sends
                    print("✅ [CLIPBOARD] Biography updated from clipboard")
                    LogManager.shared.success("Auto-bio updated from clipboard (\(final.count) chars)", category: .general)
                }
            }
        } catch {
            print("⚠️ [CLIPBOARD] Auto-mode error: \(error.localizedDescription)")
            LogManager.shared.warning("Clipboard auto-mode failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Magic API Auto-Mode

    /// Fetches a value from the configured API source and applies it as note or biography.
    private func applyApiAutoMode(target: String) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [API AUTO] Lockdown active or not logged in — skipping")
            return
        }

        let source = target == "note" ? integrations.noteApiSource : integrations.bioApiSource
        guard source != .none else { return }

        print("⚡ [API AUTO] Fetching from \(source.displayName) for target=\(target)…")
        guard let text = await integrations.fetchValue(for: source), !text.isEmpty else {
            print("⚠️ [API AUTO] No value received from \(source.displayName)")
            LogManager.shared.warning("Magic API returned no value (\(source.displayName))", category: .general)
            return
        }

        // Skip if same value was already sent — avoids Instagram duplicate spam rejection
        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_text" : "last_biography_text"
        if let lastSent = ud.string(forKey: lastKey), lastSent == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            print("⏭️ [API AUTO] Same value as last sent — skipping (\"\(text.prefix(30))\")")
            return
        }

        print("⚡ [API AUTO] Got value: \"\(text.prefix(40))\" — applying to \(target)")
        LogManager.shared.info("Magic API (\(source.displayName)) → \(target): \"\(text.prefix(40))\"", category: .general)

        // Apply text template ({word} → fetched word)
        let tpl = target == "note" ? noteTemplate : bioTemplate
        let composed = applyTemplate(text, template: tpl)
        if tpl.contains("{word}") {
            print("⚡ [API AUTO] Template applied (\(target)): \"\(composed.prefix(60))\"")
        }

        do {
            if target == "note" {
                let final = truncateAtWordBoundary(composed, limit: 60)
                // Optimistic: show note bubble instantly, before API confirms
                await MainActor.run {
                    lastNoteText = final
                    lastNoteSentTimestamp = Date().timeIntervalSince1970
                }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    print("✅ [API AUTO] Note sent: \"\(final)\"")
                    ud.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: lastKey)  // store raw for dedup
                    fireDoubleConfirmationVibration()
                }
            } else {
                let final = truncateAtWordBoundary(composed, limit: 150)
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    print("✅ [API AUTO] Biography updated: \"\(final)\"")
                    ud.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: lastKey)  // store raw for dedup
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [API AUTO] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("Magic API auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
            // If Instagram says "already sent", mark as sent so we stop retrying it
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already sent") || msg.contains("duplicate") {
                ud.set(text.trimmingCharacters(in: .whitespacesAndNewlines), forKey: lastKey)
                print("⏭️ [API AUTO] Marked as already sent to prevent future retries")
            }
        }
    }

    // MARK: - OCR → Post Prediction

    /// Routes the OCR result to InstagramProfileView via pendingOCRWord binding.
    private func applyOCRToPostPrediction(text: String) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        await MainActor.run { pendingOCRWord = cleaned }
    }

    private func applyOCRResult(text: String, target: String) async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("🚫 [OCR] Not logged in or lockdown active — skipping")
            return
        }

        let ud = UserDefaults.standard
        let lastKey = target == "note" ? "last_note_text" : "last_biography_text"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Dedup on the raw detected word (template-agnostic)
        if let lastSent = ud.string(forKey: lastKey), lastSent == trimmed {
            print("⏭️ [OCR] Same value as last sent — skipping")
            return
        }

        // Apply text template ({word} → detected word)
        let tpl = target == "note" ? noteTemplate : bioTemplate
        let composed = applyTemplate(trimmed, template: tpl)
        if tpl.contains("{word}") {
            print("📷 [OCR] Template applied (\(target)): \"\(composed.prefix(60))\"")
        }

        print("📷 [OCR] Applying to \(target): \"\(trimmed.prefix(40))\"")
        LogManager.shared.info("OCR → \(target): \"\(composed.prefix(40))\"", category: .general)

        do {
            if target == "note" {
                let final = truncateAtWordBoundary(composed, limit: 60)
                // Optimistic: show note bubble instantly, before API confirms
                await MainActor.run {
                    lastNoteText = final
                    lastNoteSentTimestamp = Date().timeIntervalSince1970
                }
                let ok = try await instagram.createNote(text: final)
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // store raw word for dedup
                    print("✅ [OCR] Note sent: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            } else {
                let final = truncateAtWordBoundary(composed, limit: 150)
                // Optimistic: update bio in fake profile instantly, before API confirms
                await MainActor.run {
                    if let current = profile {
                        profile = InstagramProfile(
                            userId: current.userId, username: current.username,
                            fullName: current.fullName, biography: final,
                            externalUrl: current.externalUrl, profilePicURL: current.profilePicURL,
                            isVerified: current.isVerified, isPrivate: current.isPrivate,
                            followerCount: current.followerCount, followingCount: current.followingCount,
                            mediaCount: current.mediaCount, followedBy: current.followedBy,
                            isFollowing: current.isFollowing, isFollowRequested: current.isFollowRequested,
                            cachedAt: current.cachedAt, cachedMediaURLs: current.cachedMediaURLs,
                            cachedReelURLs: current.cachedReelURLs, cachedTaggedURLs: current.cachedTaggedURLs,
                            cachedHighlights: current.cachedHighlights
                        )
                    }
                }
                let ok = try await instagram.changeBiography(text: final)
                if ok {
                    ud.set(trimmed, forKey: lastKey)  // store raw word for dedup
                    print("✅ [OCR] Biography updated: \"\(final)\"")
                    fireDoubleConfirmationVibration()
                }
            }
        } catch {
            print("⚠️ [OCR] Error applying \(target): \(error.localizedDescription)")
            LogManager.shared.warning("OCR auto-mode failed (\(target)): \(error.localizedDescription)", category: .general)
        }
    }

    /// Two full-power vibrations with a 2-second gap — mirrors the post-unarchive confirmation.
    private func fireDoubleConfirmationVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    /// Truncates `text` to `limit` characters, cutting at the last whitespace
    /// within the limit so no word is split. Returns the original string unchanged
    /// if it is already within the limit.
    private func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let truncated = String(text.prefix(limit))
        // Find the last whitespace to avoid splitting a word
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[truncated.startIndex..<lastSpace])
        }
        // No space found — the whole text is one long word; hard-truncate
        return truncated
    }

    private func checkAndLoadProfile() {
        // ALWAYS try to load from cache first (anti-bot: no automatic requests)
        if let cached = ProfileCacheService.shared.loadProfile() {
            print("📦 [CACHE] Loading profile from cache (no auto-request)")
            print("📦 [CACHE]   cachedMediaURLs: \(cached.cachedMediaURLs.count), cachedMediaItems: \(cached.cachedMediaItems.count)")
            // Show full grid state on entry so we can diagnose order/duplicate issues
            print("📦 [CACHE] Grid on entry (newest→oldest):")
            for (i, url) in cached.cachedMediaURLs.enumerated() {
                if let item = cached.cachedMediaItems.first(where: { $0.imageURL == url }) {
                    let date = item.takenAt.map { "\($0)" } ?? "noDate"
                    print("  [\(i)] id=\(item.mediaId) date=\(date)")
                } else {
                    print("  [\(i)] url=\(url.suffix(50)) — no matching item")
                }
            }
            self.profile = cached
            self.allMediaURLs = cached.cachedMediaURLs
            self.hasMorePages = cached.cachedMediaURLs.count >= 18
            for item in cached.cachedMediaItems { mediaItemsByURL[item.imageURL] = item }
            loadCachedImages()
        } else {
            print("📦 [CACHE] No cached profile found, loading fresh")
            loadProfileSync()
        }
    }
    
    /// Fetches reels, tagged and highlights in background, updates the cached profile
    @MainActor
    private func fetchAndUpdateReelsTagged(for cached: InstagramProfile) async {
        guard instagram.isLoggedIn else { return }

        // Anti-bot: delay 5s so this doesn't compete with Explore background refresh at startup
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // Re-check after delay: bail if locked, uploading profile pic, or session challenged
        guard !instagram.isLocked else {
            print("🚫 [CACHE] Supplementary fetch skipped — lockdown active after startup delay")
            return
        }
        guard !instagram.isUploadingProfilePic else {
            print("🚫 [CACHE] Supplementary fetch skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("Supplementary fetch skipped: profile pic upload active", category: .general)
            return
        }
        guard !instagram.isSessionChallenged else {
            print("🚫 [CACHE] Supplementary fetch skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Supplementary fetch skipped: session recently challenged", category: .general)
            return
        }

        do {
            // Sequential instead of parallel — avoids 3 simultaneous API calls
            let reels      = try await instagram.getUserReels(userId: cached.userId, amount: 18)
            guard !instagram.isLocked else { return }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))

            let tagged     = try await instagram.getUserTagged(userId: cached.userId, amount: 18)
            guard !instagram.isLocked else { return }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))

            let highlights = (try? await instagram.getUserHighlights(userId: cached.userId)) ?? cached.cachedHighlights

            let reelURLs     = reels.map { $0.imageURL }
            let taggedURLs   = tagged.map { $0.imageURL }

            print("📦 [CACHE] Background fetch: \(reelURLs.count) reels, \(taggedURLs.count) tagged, \(highlights.count) highlights")

            // Build updated profile preserving all existing data
            let updated = InstagramProfile(
                userId: cached.userId, username: cached.username, fullName: cached.fullName,
                biography: cached.biography, externalUrl: cached.externalUrl,
                profilePicURL: cached.profilePicURL, isVerified: cached.isVerified,
                isPrivate: cached.isPrivate, followerCount: cached.followerCount,
                followingCount: cached.followingCount, mediaCount: cached.mediaCount,
                followedBy: cached.followedBy, isFollowing: cached.isFollowing,
                isFollowRequested: cached.isFollowRequested, cachedAt: cached.cachedAt,
                cachedMediaURLs: cached.cachedMediaURLs,
                cachedReelURLs: reelURLs,
                cachedTaggedURLs: taggedURLs,
                cachedHighlights: highlights
            )

            self.profile = updated
            ProfileCacheService.shared.saveProfile(updated)

            // Download thumbnails for reels + tagged + highlight covers
            let allNew = reelURLs + taggedURLs + highlights.map { $0.coverImageURL }
            for url in allNew {
                if let img = await downloadImage(from: url) {
                    cachedImages[url] = img
                    ProfileCacheService.shared.saveImage(img, forURL: url)
                }
            }
            print("✅ [CACHE] Background supplementary fetch complete")
        } catch {
            print("⚠️ [CACHE] Background supplementary fetch failed (non-critical): \(error)")
        }
    }
    
    @MainActor
    private func loadProfile() async {
        guard instagram.isLoggedIn else { return }

        // Prevent concurrent loads (double swipe-to-refresh)
        guard !isLoading else {
            print("🚫 [PERF] loadProfile skipped — already loading")
            LogManager.shared.warning("loadProfile skipped: already loading", category: .general)
            return
        }

        // Throttle: block refreshes faster than minRefreshInterval
        if let last = lastRefreshDate, Date().timeIntervalSince(last) < minRefreshInterval {
            let waited = Int(Date().timeIntervalSince(last))
            print("🚫 [PERF] loadProfile throttled — \(waited)s since last refresh (min \(Int(minRefreshInterval))s)")
            LogManager.shared.warning("loadProfile throttled: \(waited)s since last refresh", category: .general)
            return
        }

        // Anti-bot: skip if profile-pic POST is running, OR if the session is in a challenged
        // state (challenge_required detected recently). Making more calls while challenged
        // escalates bot signals and can cause action_blocked lockdowns.
        if instagram.isUploadingProfilePic {
            print("🚫 [PERF] loadProfile skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("loadProfile skipped: profile pic upload active", category: .general)
            return
        }
        lastRefreshDate = Date()

        print("🔄 [PERF] loadProfile starting — full profile refresh")
        LogManager.shared.info("Profile refresh started", category: .general)

        isLoading = true
        
        // Clear old cache first
        print("🗑️ [CACHE] Clearing old cache before fresh load")
        ProfileCacheService.shared.clearAll()
        cachedImages.removeAll()
        mediaItemsByURL.removeAll()
        revealDates.removeAll()
        
        do {
            // ANTI-BOT: Wait if network changed recently
            try await instagram.waitForNetworkStability()
            
            let fetchedProfile = try await instagram.getProfileInfo()
            
            if let fetchedProfile = fetchedProfile {
                self.profile = fetchedProfile
                self.allMediaURLs = fetchedProfile.cachedMediaURLs
                self.hasMorePages = fetchedProfile.cachedMediaURLs.count >= 18
                // Populate post viewer data (likes/comments already in items, 0 extra API calls)
                for item in fetchedProfile.cachedMediaItems {
                    mediaItemsByURL[item.imageURL] = item
                }
                ProfileCacheService.shared.saveProfile(fetchedProfile)
                // New CDN URL is now in fetchedProfile.profilePicURL → pending override no longer needed.
                ProfileCacheService.shared.pendingProfilePic = nil
                downloadAndCacheImages(profile: fetchedProfile)
            }
            isLoading = false
        } catch let error as InstagramError {
            print("⚠️ Instagram error detected: \(error)")
            isLoading = false
            switch error {
            case .challengeRequired:
                // Transient GET challenge — the session will recover on its own.
                // Do NOT show the connection error alert; it would confuse the user
                // since no actual bot detection appears in the Instagram app.
                print("⚠️ [PERF] loadProfile: transient challenge_required — suppressing connection error alert")
                LogManager.shared.warning("loadProfile: transient challenge_required — alert suppressed", category: .general)
            default:
                lastError = error
                showingConnectionError = true
            }
        } catch {
            print("❌ Error loading profile: \(error)")
            isLoading = false
            lastError = .apiError(error.localizedDescription)
            showingConnectionError = true
        }
    }
    
    // Sync wrapper for non-async call sites (onRefresh button, header "@" button)
    private func loadProfileSync() {
        Task { await loadProfile() }
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
        var missingMediaURLs: [String] = []
        for url in profile.cachedMediaURLs {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
                loadedCount += 1
            } else {
                missingMediaURLs.append(url)
            }
        }
        print("📦 [CACHE] Loaded \(loadedCount)/\(profile.cachedMediaURLs.count) media thumbnails from cache")
        
        // If some media thumbnails are missing, download them
        if !missingMediaURLs.isEmpty {
            print("🖼️ [CACHE] Downloading \(missingMediaURLs.count) missing media thumbnails...")
            Task {
                for url in missingMediaURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
                print("✅ [CACHE] Finished downloading missing media thumbnails")
            }
        }
        
        // Load followed by profile pics
        var followerPicsLoaded = 0
        var missingFollowerURLs: [String] = []
        for follower in profile.followedBy {
            if let picURL = follower.profilePicURL {
                if let image = ProfileCacheService.shared.loadImage(forURL: picURL) {
                    cachedImages[picURL] = image
                    followerPicsLoaded += 1
                } else {
                    missingFollowerURLs.append(picURL)
                }
            }
        }
        print("📦 [CACHE] Loaded \(followerPicsLoaded)/\(profile.followedBy.count) follower pics from cache")
        
        // If some follower pics are missing, download them
        if !missingFollowerURLs.isEmpty {
            print("🖼️ [CACHE] Downloading \(missingFollowerURLs.count) missing follower pics...")
            Task {
                for url in missingFollowerURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
                print("✅ [CACHE] Finished downloading missing follower pics")
            }
        }
        
        // Load reel + tagged + highlight cover thumbnails from disk cache
        let highlightCoverURLs = profile.cachedHighlights.map { $0.coverImageURL }
        let allExtraURLs = profile.cachedReelURLs + profile.cachedTaggedURLs + highlightCoverURLs
        var missingExtraURLs: [String] = []
        for url in allExtraURLs {
            if let image = ProfileCacheService.shared.loadImage(forURL: url) {
                cachedImages[url] = image
            } else {
                missingExtraURLs.append(url)
            }
        }
        if !missingExtraURLs.isEmpty {
            Task {
                for url in missingExtraURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }
        }

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
                    if let image = await downloadImage(from: picURL) {
                        await MainActor.run {
                            cachedImages[picURL] = image
                            ProfileCacheService.shared.saveImage(image, forURL: picURL)
                        }
                    }
                }
            }
            
            // Download reel thumbnails
            if !profile.cachedReelURLs.isEmpty {
                print("🎬 [CACHE] Downloading \(profile.cachedReelURLs.count) reel thumbnails...")
                for url in profile.cachedReelURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }
            
            // Download tagged thumbnails
            if !profile.cachedTaggedURLs.isEmpty {
                print("🏷️ [CACHE] Downloading \(profile.cachedTaggedURLs.count) tagged thumbnails...")
                for url in profile.cachedTaggedURLs {
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }

            // Download highlight cover images
            if !profile.cachedHighlights.isEmpty {
                print("🌟 [CACHE] Downloading \(profile.cachedHighlights.count) highlight covers...")
                for highlight in profile.cachedHighlights {
                    let url = highlight.coverImageURL
                    if let image = await downloadImage(from: url) {
                        await MainActor.run {
                            cachedImages[url] = image
                            ProfileCacheService.shared.saveImage(image, forURL: url)
                        }
                    }
                }
            }

            print("✅ [CACHE] All images download process completed")
        }
    }
    
    // MARK: - Infinite Scroll
    
    private func loadMoreMedia() {
        guard !isLoadingMore, hasMorePages, allMediaURLs.count < maxPhotosOwnProfile else {
            print("📜 [PROFILE] Cannot load more - loading: \(isLoadingMore), hasMore: \(hasMorePages), count: \(allMediaURLs.count)")
            return
        }
        
        isLoadingMore = true
        print("📜 [PROFILE] Loading more media (current count: \(allMediaURLs.count))...")
        
        Task {
            do {
                // Fetch next batch
                let (mediaItems, newMaxId) = try await instagram.getUserMediaItems(userId: profile?.userId, amount: 21, maxId: nextMaxId)
                
                await MainActor.run {
                    // Calculate how many we can add without exceeding limit
                    let remainingSlots = maxPhotosOwnProfile - allMediaURLs.count
                    let itemsToAdd = min(mediaItems.count, remainingSlots)
                    
                    let newItems = Array(mediaItems.prefix(itemsToAdd))
                    let newURLs = newItems.map { $0.imageURL }

                    // Store items for post viewer (likes/comments already included)
                    for item in newItems { mediaItemsByURL[item.imageURL] = item }

                    // Filter to multiples of 3 to avoid UI gaps
                    let totalAfterAdd = allMediaURLs.count + newURLs.count
                    let remainder = totalAfterAdd % 3
                    let urlsToDisplay = remainder == 0 ? newURLs : Array(newURLs.dropLast(remainder))
                    
                    allMediaURLs.append(contentsOf: urlsToDisplay)
                    nextMaxId = newMaxId
                    hasMorePages = (newMaxId != nil) && (allMediaURLs.count < maxPhotosOwnProfile)
                    isLoadingMore = false
                    
                    print("📜 [PROFILE] Loaded \(urlsToDisplay.count) more, total now: \(allMediaURLs.count), hasMore: \(hasMorePages)")
                    
                    // Download images for new URLs
                    downloadImagesForURLs(urlsToDisplay)
                }
            } catch {
                print("❌ [PROFILE] Error loading more: \(error)")
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }
    
    private func loadMoreIfNeeded(currentURL: String) {
        // Trigger load when user reaches 80% of loaded items
        guard let index = allMediaURLs.firstIndex(of: currentURL) else { return }
        let threshold = max(1, Int(Double(allMediaURLs.count) * 0.8))
        
        if index >= threshold {
            print("📜 [PROFILE] User reached 80% (\(index)/\(allMediaURLs.count)) - loading more...")
            loadMoreMedia()
        }
    }
    
    private func downloadImagesForURLs(_ urls: [String]) {
        Task {
            for url in urls {
                if cachedImages[url] == nil, let image = await downloadImage(from: url) {
                    await MainActor.run {
                        cachedImages[url] = image
                        ProfileCacheService.shared.saveImage(image, forURL: url)
                    }
                }
            }
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
    
    // MARK: - Performance Lockdown Overlay (Hide errors from spectators)
    
    private var performanceLockdownOverlay: some View {
        ZStack {
            // Full-screen semi-transparent backdrop
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Generic "No Internet" icon (hide technical details)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
                
                VStack(spacing: 8) {
                    Text("ig.no_internet")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("ig.check_connection")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Hidden "Info" button for magician (long-press to reveal)
                Text("⚠️")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.3))
                    .onLongPressGesture(minimumDuration: 2.0) {
                        showMagicianDebugInfo()
                    }
            }
            .padding(40)
        }
        .alert("Upload in progress", isPresented: $showUploadConflictAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A photo upload is currently running. Wait for it to finish before revealing numbers — both actions share the same hourly Instagram limit and triggering both together can cause bot detection.")
        }
        .alert("🔓 Debug Info (Magician Only)", isPresented: $showingMagicianDebug) {
            Button("Close", role: .cancel) { }
        } message: {
            if let lockUntil = instagram.lockUntil {
                let remaining = max(0, Int(lockUntil.timeIntervalSinceNow))
                let mins = remaining / 60
                let secs = remaining % 60
                
                Text("""
                Real Cause: \(instagram.lockReason)
                
                ⚠️ STOP THE TRICK - DO NOT CONTINUE
                
                Countdown: \(mins):\(String(format: "%02d", secs)) remaining
                
                Instructions:
                • Do NOT reveal/hide more photos
                • Do NOT open Instagram
                • End the trick naturally
                • Wait for countdown to finish
                • Check logs in Settings > Developer > Logs
                
                The app has stopped all requests to prevent account suspension.
                """)
            } else {
                Text("""
                Real Cause: \(instagram.lockReason)
                
                ⚠️ STOP THE TRICK - DO NOT CONTINUE
                
                Check logs in Settings > Developer > Logs for details.
                """)
            }
        }
    }
    
    private func showMagicianDebugInfo() {
        print("🔓 [MAGICIAN] Debug info requested")
        LogManager.shared.info("Magician accessed debug info during performance lockdown", category: .general)
        showingMagicianDebug = true
    }

    // MARK: - Silent Media Grid Refresh (after Force Number Reveal unarchive)

    /// Inserts a reveal:// pseudo-URL at the correct chronological position (newest-first).
    ///
    /// Strategy:
    ///  1. Find the photo's `uploadDate` from DataManager (set at upload time, very close to Instagram's
    ///     `taken_at` since Instagram uses its own server timestamp upon receiving the photo).
    ///  2. Store that date in `revealDates` so sibling reveal:// items can be compared against it.
    ///  3. Scan `allMediaURLs` newest-first; insert just before the first item that is OLDER.
    ///     - CDN items:    compare via `mediaItemsByURL[url]?.takenAt`
    ///     - reveal:// items: compare via `revealDates[url]`
    ///  4. Fallback: insert at position 0 if no date is available (safe default, old behavior).
    ///
    /// Example — word "julia", grid has two new real posts (Mar 28) and old posts (Jan 10):
    ///   Each magic photo has uploadDate in Feb 2026 → they land AFTER the Mar 28 posts, BEFORE Jan 10.
    ///   Final: [new1(Mar28), new2(Mar28), J, U, L, I, A, old(Jan10)] ✓
    @MainActor
    private func insertRevealURL(_ pseudoURL: String) {
        guard !allMediaURLs.contains(pseudoURL) else { return }

        let mediaId = String(pseudoURL.dropFirst("reveal://".count))

        // Look up the upload date from DataManager — this is the closest approximation
        // to Instagram's `taken_at` that we have without an extra API call.
        let uploadDate: Date? = DataManager.shared.sets
            .flatMap { $0.photos }
            .first(where: { $0.mediaId == mediaId })
            .flatMap { $0.uploadDate }

        guard let revealDate = uploadDate else {
            // No date available — fall back to prepend (old behavior).
            allMediaURLs.insert(pseudoURL, at: 0)
            print("⚡️ [REVEAL] No uploadDate for \(mediaId) — inserted at position 0 (fallback)")
            return
        }

        // Cache the date so future siblings can compare against this reveal.
        revealDates[pseudoURL] = revealDate

        // Scan grid newest-first: insert before the first item that is strictly OLDER.
        for (i, url) in allMediaURLs.enumerated() {
            let itemDate: Date?
            if url.hasPrefix("reveal://") {
                itemDate = revealDates[url]
            } else {
                itemDate = mediaItemsByURL[url]?.takenAt
            }
            guard let d = itemDate else { continue }
            if d < revealDate {
                allMediaURLs.insert(pseudoURL, at: i)
                print("⚡️ [REVEAL] \(mediaId) (uploadDate=\(revealDate)) → inserted at pos \(i)")
                return
            }
        }

        // All existing items are newer — this is the oldest; append at the end.
        allMediaURLs.append(pseudoURL)
        print("⚡️ [REVEAL] \(mediaId) (uploadDate=\(revealDate)) → appended at end (all existing are newer)")
    }

    /// Does NOT touch profile stats, bio, follower count, etc. — zero visible disruption.
    @MainActor
    private func refreshMediaGridSilently() async {
        guard !instagram.isLocked, let userId = profile?.userId else {
            print("⚠️ [PERF] Silent refresh skipped — locked or no profile")
            return
        }
        // Anti-bot: skip silent GET if a profile-pic POST is still running, or if the
        // session is in a challenged state — avoid cascading bot signals.
        guard !instagram.isUploadingProfilePic else {
            print("⚠️ [PERF] Silent refresh skipped — profile pic upload in progress (anti-bot)")
            LogManager.shared.warning("Silent refresh skipped: profile pic upload active", category: .general)
            return
        }
        guard !instagram.isSessionChallenged else {
            print("⚠️ [PERF] Silent refresh skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Silent refresh skipped: session recently challenged", category: .general)
            return
        }

        // No delay needed: the grid already shows local images via pseudo-URLs.
        // This GET only replaces pseudo-URLs with real CDN URLs in the background.
        print("🔄 [PERF] Silent refresh: fetching updated media grid (no delay — local images shown already)…")
        LogManager.shared.info("Silent media refresh triggered after reveal", category: .general)

        do {
            let (items, _) = try await instagram.getUserMediaItems(userId: userId, amount: 21, maxId: nil)
            let newURLs = items.map { $0.imageURL }
            guard !newURLs.isEmpty else {
                print("⚠️ [PERF] Silent refresh: empty response from Instagram")
                return
            }

            // Pre-download all new images BEFORE swapping allMediaURLs.
            // This prevents blank cells: cells keep showing local reveal:// images
            // until the real CDN images are fully cached and ready.
            let missing = newURLs.filter { cachedImages[$0] == nil }
            if !missing.isEmpty {
                print("🔄 [PERF] Silent refresh: pre-downloading \(missing.count) CDN image(s) before swap…")
                await withTaskGroup(of: Void.self) { group in
                    for url in missing {
                        group.addTask {
                            if let image = await self.downloadImage(from: url) {
                                await MainActor.run {
                                    self.cachedImages[url] = image
                                    ProfileCacheService.shared.saveImage(image, forURL: url)
                                }
                            }
                        }
                    }
                }
                print("🔄 [PERF] Silent refresh: all CDN images cached — swapping grid now")
            }

            // Atomic swap: reveal:// placeholders replaced with real CDN URLs.
            // All images are already in cache so no blank frames appear.
            let revealURLsBefore = allMediaURLs.filter { $0.hasPrefix("reveal://") }
            let cleanedExisting  = allMediaURLs.filter { !$0.hasPrefix("reveal://") }

            // Build existingTail by mediaId — NOT by URL string.
            // CDN URLs rotate per session, so the same post has different URL strings
            // between fetches. Comparing URL strings causes every previously-seen
            // post to land in existingTail, creating duplicates in the grid.
            let newMediaIds = Set(items.map { $0.mediaId })
            let existingTail = cleanedExisting.filter { url -> Bool in
                // Only keep URLs whose mediaId is known AND not covered by the new fetch.
                // Stale/orphan URLs (no matching item) are always discarded.
                guard let item = mediaItemsByURL[url] else { return false }
                return !newMediaIds.contains(item.mediaId)
            }
            let merged = newURLs + existingTail
            
            // ── Diagnostic logs ──────────────────────────────────────────────
            print("🔄 [SWAP] allMediaURLs BEFORE (\(allMediaURLs.count) total, \(revealURLsBefore.count) reveal://):")
            for (i, url) in allMediaURLs.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                print("  [\(i)] \(url.hasPrefix("reveal://") ? url : "cdn…\(url.suffix(40))") id=\(itemId)")
            }
            print("🔄 [SWAP] Instagram returned \(newURLs.count) URLs (newest→oldest):")
            for (i, url) in newURLs.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                let date   = items.first(where: { $0.imageURL == url })?.takenAt.map { "\($0)" } ?? "noDate"
                print("  [\(i)] id=\(itemId) date=\(date)")
            }
            print("🔄 [SWAP] existingTail (\(existingTail.count) old paged URLs not in new fetch)")
            print("🔄 [SWAP] merged AFTER (\(merged.count) total):")
            for (i, url) in merged.enumerated() {
                let itemId = items.first(where: { $0.imageURL == url })?.mediaId ?? "?"
                print("  [\(i)] \(url.hasPrefix("reveal://") ? url : "cdn…\(url.suffix(40))") id=\(itemId)")
            }
            // ─────────────────────────────────────────────────────────────────

            allMediaURLs = merged

            // reveal:// placeholders have been replaced by real CDN URLs — clear cached dates.
            revealDates.removeAll()

            // Keep mediaItemsByURL in sync so removeMediaItem(byMediaId:) can resolve fresh URLs.
            for item in items { mediaItemsByURL[item.imageURL] = item }

            // Persist both URLs and items — this keeps cachedMediaItems fresh so that
            // removeMediaItem(byMediaId:) can find the correct CDN URL to remove.
            ProfileCacheService.shared.updateMediaURLsAndItems(merged, items: items)

            let newCount = newURLs.filter { !cleanedExisting.contains($0) }.count
            print("🔄 [PERF] Silent refresh done — \(merged.count) total, \(newCount) newly visible")
            LogManager.shared.info("Silent refresh done: \(merged.count) items, \(newCount) new", category: .general)
        } catch {
            print("⚠️ [PERF] Silent media refresh failed: \(error.localizedDescription)")
            LogManager.shared.warning("Silent refresh failed: \(error.localizedDescription)", category: .general)
        }
    }

    // MARK: - Auto Profile Picture

    private static let lastUploadedAssetKey = "autoPic_lastUploadedAssetId"
    private static let lastUploadedHashKey  = "autoPic_lastUploadedHash"

    /// Silently uploads the most recent gallery photo as profile picture.
    /// Safe to call on every onAppear — does nothing if same photo as last upload.
    @MainActor
    private func autoUploadLatestGalleryPhoto() async {
        guard instagram.isLoggedIn, !instagram.isLocked else {
            print("📷 [AUTO PIC] Skipped — not logged in or locked")
            return
        }

        // ── Ensure permission ──
        let authorized = await requestPhotosPermissionIfNeeded()
        guard authorized else {
            print("📷 [AUTO PIC] No Photos permission — skipping")
            return
        }

        // ── Fast check: compare asset identifier before loading any image data ──
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = result.firstObject else {
            print("📷 [AUTO PIC] Gallery is empty — skipping")
            return
        }

        let assetId      = asset.localIdentifier
        let lastId       = UserDefaults.standard.string(forKey: Self.lastUploadedAssetKey)
        let lastHash     = UserDefaults.standard.string(forKey: Self.lastUploadedHashKey)
        let instagramHash = UserDefaults.standard.string(forKey: "last_profile_pic_hash")

        // Same asset AND instagram already has this hash → absolutely nothing to do
        if assetId == lastId, let lh = lastHash, lh == instagramHash {
            print("📷 [AUTO PIC] Same photo already on Instagram — skipping (0 API calls)")
            return
        }

        print("📷 [AUTO PIC] New photo detected (assetId changed or hash mismatch) — loading image…")

        // ── Load image only when necessary ──
        guard let imageData = await loadImageData(from: asset) else {
            print("📷 [AUTO PIC] Failed to load image data from asset")
            return
        }

        // Pre-check hash to avoid waitForNetworkStability() for duplicates
        let hash = instagram.hashImageData(imageData)
        if hash == instagramHash {
            UserDefaults.standard.set(assetId, forKey: Self.lastUploadedAssetKey)
            UserDefaults.standard.set(hash,    forKey: Self.lastUploadedHashKey)
            print("📷 [AUTO PIC] Hash matches Instagram — recording asset and skipping upload")
            return
        }

        // Anti-bot: block if any sensitive operation is already in progress.
        // Two concurrent POST operations from the same session is a strong bot signal.
        guard !instagram.isRevealOperationActive else {
            print("📷 [AUTO PIC] Skipped — OCR reveal is active (anti-bot)")
            LogManager.shared.warning("Auto profile pic skipped: OCR reveal active", category: .general)
            return
        }
        // If the session was recently challenged (challenge_required returned for any call),
        // skip the profile-pic POST — it is the most likely cause of escalating to action_blocked.
        guard !instagram.isSessionChallenged else {
            print("📷 [AUTO PIC] Skipped — session in challenged state (anti-bot cooldown)")
            LogManager.shared.warning("Auto profile pic skipped: session recently challenged", category: .general)
            return
        }
        guard !isLoading else {
            print("📷 [AUTO PIC] Skipped — profile refresh is in progress (anti-bot)")
            LogManager.shared.warning("Auto profile pic skipped: profile refresh active", category: .general)
            return
        }

        print("📷 [AUTO PIC] Uploading new profile picture (\(imageData.count / 1024) KB)…")
        // NOTE: isUploadingProfilePic flag is now managed inside changeProfilePicture() itself,
        // so all callers (auto-pic, HomeView manual upload) are covered automatically.

        do {
            let success = try await instagram.changeProfilePicture(imageData: imageData)
            if success, let uiImage = UIImage(data: imageData) {
                UserDefaults.standard.set(assetId, forKey: Self.lastUploadedAssetKey)
                UserDefaults.standard.set(hash,    forKey: Self.lastUploadedHashKey)

                // Show new image in the fake profile immediately
                // Use current profilePicURL as cache key — visually correct until next full refresh
                let picURL = profile?.profilePicURL ?? "autoPic_pending"
                cachedImages[picURL] = uiImage
                ProfileCacheService.shared.saveImage(uiImage, forURL: picURL)

                print("📷 [AUTO PIC] ✅ Profile picture updated successfully")
            }
        } catch {
            print("📷 [AUTO PIC] Upload skipped: \(error.localizedDescription)")
        }

        // Reset exponential backoff so a failed background upload cannot delay
        // user-facing requests (e.g. Explore feed) that run shortly after.
        await instagram.resetBackoff()
    }

    /// Requests Photos read access if not yet determined. Returns true if granted.
    private func requestPhotosPermissionIfNeeded() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    /// Loads full-quality JPEG data from a PHAsset.
    private func loadImageData(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let reqOptions = PHImageRequestOptions()
            reqOptions.deliveryMode = .highQualityFormat
            reqOptions.isNetworkAccessAllowed = true
            reqOptions.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: reqOptions) { data, _, _, _ in
                if let data, let image = UIImage(data: data) {
                    continuation.resume(returning: image.jpegData(compressionQuality: 0.9))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Date Force Auto Mode

    private func handleAutoFollowedByTap() {
        guard dateForce.isEnabled && dateForce.mode == .auto else { return }
        guard !dateForce.isAutoLoading else { return }

        if dateForce.hasSpectators {
            dateForce.toggleAutoDisplayGroup()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            loadAutoFollowers()
        }
    }

    @MainActor
    private func loadAutoFollowers() {
        guard !dateForce.isAutoLoading else { return }
        dateForce.isAutoLoading = true

        Task {
            do {
                let count = dateForce.autoSpectatorCount
                print("🤖 [AUTO] Fetching \(count) recent followers...")
                let followers = try await instagram.getRecentFollowers(count: count)
                print("🤖 [AUTO] Got \(followers.count) followers, fetching profiles one by one...")

                await MainActor.run {
                    dateForce.beginAutoLoad(totalExpected: followers.count)
                }

                for (i, follower) in followers.enumerated() {
                    if i > 0 {
                        try? await Task.sleep(nanoseconds: UInt64.random(in: 700_000_000...1_500_000_000))
                    }

                    if let p = try? await instagram.getProfileInfo(userId: follower.userId) {
                        await MainActor.run {
                            dateForce.appendAutoSpectator(
                                username: follower.username,
                                followingCount: p.followingCount,
                                followerCount: p.followerCount
                            )
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } else {
                        print("⚠️ [AUTO] Could not fetch profile for @\(follower.username)")
                    }
                }

                await MainActor.run {
                    dateForce.isAutoLoading = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    print("🤖 [AUTO] Done — \(dateForce.spectators.count) spectators loaded")
                }
            } catch {
                print("❌ [AUTO] Error: \(error)")
                await MainActor.run { dateForce.isAutoLoading = false }
            }
        }
    }

}

// MARK: - Instagram Profile View

struct InstagramProfileView: View {
    let profile: InstagramProfile
    @Binding var cachedImages: [String: UIImage]
    let onRefresh: () -> Void          // sync — used by header button
    let onAsyncRefresh: () async -> Void  // async — used by pull-to-refresh
    let onPlusPress: () -> Void
    @State private var selectedTab = 0

    // Infinite scroll support
    var mediaURLs: [String]? = nil // If provided, use instead of profile.cachedMediaURLs
    var onMediaAppear: ((String) -> Void)? = nil // Called when a media cell appears

    // Date Force Auto mode
    @ObservedObject private var dateForce = DateForceSettings.shared
    var onAutoFollowedByTap: (() -> Void)? = nil

    // Optimistic note state — @AppStorage triggers instant re-render on write
    @AppStorage("last_note_text")           private var lastNoteText: String = ""
    @AppStorage("last_note_sent_timestamp") private var lastNoteSentTimestamp: Double = 0

    // Called after a successful Force Number Reveal with local images already loaded.
    // Each element: pseudo-URL key + optional UIImage from local storage.
    // PerformanceView inserts them into the grid immediately (no GET needed).
    /// Inserts local images into the grid immediately — does NOT trigger CDN refresh.
    /// Use before API unarchive calls so images appear before Instagram processes them.
    var onAddLocalImages: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil
    /// Called after all API unarchives complete — inserts any remaining images AND triggers CDN refresh.
    var onRevealComplete: (([(pseudoURL: String, image: UIImage?)]) -> Void)? = nil

    // Media items dictionary for post viewer (keyed by imageURL)
    var mediaItemsByURL: [String: InstagramMediaItem] = [:]

    // Passed from PerformanceView so the pull-to-refresh guard can check them.
    var isLoading: Bool = false
    var lastRefreshDate: Date? = nil
    var minRefreshInterval: TimeInterval = 30
    // Called when reveal is blocked because an upload is active.
    var onUploadConflict: (() -> Void)? = nil
    // Called when user taps a follower — PerformanceView handles the overlay.
    var onFollowerTap: ((InstagramFollower) -> Void)? = nil

    /// Set by PerformanceView when OCR recognizes text for Post Prediction.
    /// InstagramProfileView consumes it, routes to word or digit reveal, then clears it.
    @Binding var pendingOCRWord: String?

    // Post viewer state
    @State private var showingPostViewer = false
    @State private var selectedPostIndex = 0

    // Secret number input
    @ObservedObject private var secretManager      = SecretNumberManager.shared
    @ObservedObject private var instagram          = InstagramService.shared
    @ObservedObject private var followingMagic     = FollowingMagicSettings.shared
    @ObservedObject private var volumeMonitor      = VolumeButtonMonitor.shared
    @State private var followingOverride: String?   = nil
    @State private var followerOverride: String?    = nil
    // Transfer effect: inflate own profile after deflating a searched one
    @State private var transferCountdownTimer: Timer? = nil
    @State private var showTransferGlitch = false
    // isTransferCounting lives in FollowingMagicSettings.shared so PerformanceView
    // can read it and block OCR while the animation runs.

    // OCR peek: temporarily shows the recognized text in the Posts stat for 3 seconds
    @State private var postsOCRNumberOverride: String? = nil   // for numeric results
    @State private var postsOCRLabelOverride:  String? = nil   // for word results

    // Effective override for follower/following stats.
    // During the waiting phase (transferOffset > 0, animation not yet started),
    // returns the pre-deflated value directly so it shows from the very first frame
    // without any flash. During animation, falls through to the timer-driven @State.
    private var effectiveFollowerOverride: String? {
        if let o = followerOverride { return o }
        guard followingMagic.transferEnabled,
              followingMagic.transferOffset > 0,
              !followingMagic.isTransferCounting,
              followingMagic.targetFollowers else { return nil }
        return "\(max(0, profile.followerCount - followingMagic.transferOffset))"
    }
    private var effectiveFollowingOverride: String? {
        if let o = followingOverride { return o }
        guard followingMagic.transferEnabled,
              followingMagic.transferOffset > 0,
              !followingMagic.isTransferCounting,
              !followingMagic.targetFollowers else { return nil }
        return "\(max(0, profile.followingCount - followingMagic.transferOffset))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                InstagramHeaderView(
                    username: profile.username,
                    isVerified: profile.isVerified,
                    onRefresh: onRefresh,
                    onPlusPress: onPlusPress
                )
                profileInfoSection
                    .padding(.top, 12)
                tabBarSection
                Divider()
                tabContentSection
            }
        }
        // Pull-to-refresh: runs load in an unstructured Task so SwiftUI
            // cancellation doesn't abort the URLSession requests inside loadProfile.
            // The spinner stays visible until the task finishes.
            .refreshable {
                await Task { await onAsyncRefresh() }.value
            }
            .background(Color.white)
        // Keep following count display in sync with digit buffer
        .onChange(of: secretManager.digitBuffer) { _ in
            updateFollowingOverride()
        }
        // Transfer effect: volume UP on own profile inflates count by saved offset
        .onChange(of: volumeMonitor.upCount) { _ in
            guard followingMagic.transferEnabled,
                  followingMagic.transferOffset > 0,
                  !followingMagic.isTransferCounting,
                  !showTransferGlitch else { return }
            let delay = followingMagic.triggerDelay
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    guard followingMagic.transferOffset > 0,
                          !followingMagic.isTransferCounting,
                          !showTransferGlitch else { return }
                    GlitchSoundPlayer.shared.play(style: .electricBuzz)
                    showTransferGlitch = true
                }
            } else {
                GlitchSoundPlayer.shared.play(style: .electricBuzz)
                showTransferGlitch = true
            }
        }
        .overlay {
            if showTransferGlitch {
                GlitchOverlayView {
                    showTransferGlitch = false
                    startTransferInflation()
                }
            }
        }
        .onChange(of: pendingOCRWord) { word in
            guard let word = word, !word.isEmpty else { return }
            pendingOCRWord = nil  // consume immediately
            let fromURL = ForceNumberRevealSettings.shared.urlRevealActive
            ForceNumberRevealSettings.shared.urlRevealActive = false  // reset immediately
            // URL reveals bypass the ocrEnabled guard — they only need the master switch
            guard ForceNumberRevealSettings.shared.ocrEnabled || fromURL else { return }
            guard !UploadManager.shared.isActive else {
                print("⚠️ [OCR-PP] Reveal blocked: upload is active")
                return
            }
            // Anti-bot: if a profile pic upload is running, delay reveal until it finishes.
            // Two simultaneous POST operations from the same session is a bot signal.
            guard !InstagramService.shared.isUploadingProfilePic else {
                print("⚠️ [OCR-PP] Reveal blocked: profile pic upload in progress (anti-bot)")
                LogManager.shared.warning("OCR reveal blocked: profile pic upload active", category: .general)
                // Retry once after a short delay to avoid losing the reveal
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3s
                    guard !InstagramService.shared.isUploadingProfilePic else {
                        print("⚠️ [OCR-PP] Reveal still blocked after 3s wait — aborting")
                        return
                    }
                    // Re-trigger reveal after pic upload finishes
                    await MainActor.run { pendingOCRWord = word }
                }
                return
            }
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cleaned.allSatisfy({ $0.isNumber }) {
                let digits = cleaned.compactMap { Int(String($0)) }
                guard !digits.isEmpty,
                      let activeId = ActiveSetSettings.shared.activeNumberSetId,
                      let set = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) else {
                    print("⚠️ [OCR-PP] No active number set for '\(cleaned)'")
                    return
                }
                print("📷 [OCR-PP] Numeric '\(cleaned)' → revealByDigits \(digits)")
                LogManager.shared.info("OCR Post Prediction (numeric): \(cleaned)", category: .general)
                // Peek: show recognized number in Posts stat for 3 s
                showOCRPeek(number: cleaned)
                Task { await revealByDigits(digits, fromSet: set) }
            } else {
                guard let set = {
                    let dm = DataManager.shared
                    if let id = ActiveSetSettings.shared.activeWordSetId,
                       let s = dm.sets.first(where: { $0.id == id && $0.type == .word }) { return s }
                    return dm.sets.first { $0.type == .word && !$0.banks.isEmpty &&
                        $0.photos.contains(where: { $0.mediaId != nil && $0.isArchived }) }
                }() else {
                    print("⚠️ [OCR-PP] No active word set for '\(cleaned)'")
                    return
                }
                print("📷 [OCR-PP] Word '\(cleaned)' → revealByLetters")
                LogManager.shared.info("OCR Post Prediction (word): \(cleaned)", category: .general)
                // Peek: show recognized word as Posts label for 3 s
                showOCRPeek(label: cleaned)
                Task { await revealByLetters(cleaned, fromSet: set) }
            }
        }
    }

    // MARK: - OCR Peek

    /// Briefly shows the OCR-recognized value in the Posts stat for 3 seconds, then reverts.
    /// - number: passes the text as the count override (e.g. "425")
    /// - label:  passes the text as the label override (e.g. "coche")
    /// Shows the recognized text in the "seguidos" stat immediately.
    /// The override stays until clearOCRPeek() is called (when all unarchives finish).
    private func showOCRPeek(number: String? = nil, label: String? = nil) {
        withAnimation(.easeInOut(duration: 0.25)) {
            postsOCRNumberOverride = number
            postsOCRLabelOverride  = label
        }
    }

    /// Clears the "seguidos" override with a fade animation.
    private func clearOCRPeek() {
        withAnimation(.easeInOut(duration: 0.35)) {
            postsOCRNumberOverride = nil
            postsOCRLabelOverride  = nil
        }
    }

    // MARK: - Body sub-sections

    @ViewBuilder private var profileInfoSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 0) {
                // Profile pic + note bubble stacked vertically
                VStack(spacing: 0) {
                    // Note bubble: shown if note exists AND was sent within last 24h.
                    // Uses @AppStorage so it re-renders instantly on optimistic write.
                    let noteIsActive = !lastNoteText.isEmpty
                        && lastNoteSentTimestamp > 0
                        && Date().timeIntervalSince1970 - lastNoteSentTimestamp < 86400
                    if noteIsActive {
                        NotesBubbleView(text: lastNoteText)
                            .padding(.bottom, 4)
                    }

                    ZStack(alignment: .bottomTrailing) {
                        if let image = cachedImages[profile.profilePicURL] {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 86, height: 86)
                                .clipShape(Circle())
                                .onAppear { print("✅ [UI] Profile pic image displayed") }
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 86, height: 86)
                                .overlay(ProgressView().scaleEffect(0.8))
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
                }
                .padding(.leading, UIScreen.main.bounds.width * 0.04)

                Spacer(minLength: 8)

                // Columna derecha: nombre encima de los stats
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.fullName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        StatView(number: profile.mediaCount, label: String(localized: "ig.stat.posts"))
                            .frame(maxWidth: .infinity)
                        StatView(number: profile.followerCount, label: String(localized: "ig.stat.followers"),
                                 overrideText: effectiveFollowerOverride)
                            .frame(maxWidth: .infinity)
                        StatView(number: profile.followingCount, label: String(localized: "ig.stat.following"),
                                 overrideText: postsOCRNumberOverride ?? effectiveFollowingOverride,
                                 overrideLabel: postsOCRLabelOverride)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, UIScreen.main.bounds.width * 0.04)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !profile.biography.isEmpty {
                    Text(profile.biography)
                        .font(.system(size: 14))
                        .foregroundColor(.black)
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

            if dateForce.isEnabled && dateForce.mode == .auto {
                AutoFollowedByView(dateForce: dateForce, onTap: onAutoFollowedByTap)
                    .responsiveHorizontalPadding()
            } else if !profile.followedBy.isEmpty {
                FollowedByView(
                    followers: profile.followedBy,
                    cachedImages: cachedImages,
                    onFollowerTap: { follower in onFollowerTap?(follower) }
                )
                .responsiveHorizontalPadding()
            }

            HStack(spacing: 8) {
                Button(action: {}) {
                    Text("ig.edit_profile")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .foregroundColor(.black).cornerRadius(8)
                }
                Button(action: {}) {
                    Text("ig.share_profile")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .foregroundColor(.black).cornerRadius(8)
                }
                Button(action: {}) {
                    IGIcon(asset: "instagram_follow", fallback: "person.badge.plus", size: 16)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.898, green: 0.898, blue: 0.918))
                        .cornerRadius(8)
                }
            }
            .responsiveHorizontalPadding()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "plus").foregroundColor(.black))
                        Text("ig.new")
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                    }
                    if profile.cachedHighlights.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Circle().fill(Color.gray.opacity(0.2)).frame(width: 64, height: 64)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 44, height: 10)
                            }
                        }
                    } else {
                        ForEach(profile.cachedHighlights) { highlight in
                            StoryHighlightCell(highlight: highlight,
                                               image: cachedImages[highlight.coverImageURL])
                        }
                    }
                }
                .responsiveHorizontalPadding()
            }
            .padding(.vertical, 8)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var tabBarSection: some View {
        HStack(spacing: 0) {
            TabButton(icon: "square.grid.3x3", activeAsset: "instagram_grid_active", inactiveAsset: "instagram_grid_inactive", isSelected: selectedTab == 0) {
                if ForceNumberRevealSettings.shared.isEnabled,
                   ForceNumberRevealSettings.shared.gridSwipeEnabled,
                   secretManager.hasDigits,
                   let activeId = ActiveSetSettings.shared.activeNumberSetId,
                   let activeSet = DataManager.shared.sets.first(where: { $0.id == activeId && $0.type == .number }) {
                    let digits = secretManager.digitBuffer
                    let digitLabel = digits.map(String.init).joined()
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil

                    // Block reveal if an upload is active — they share the same hourly rate limit
                    if UploadManager.shared.isActive {
                        print("⚠️ [FORCE#] Reveal blocked: upload is active (shared rate limit)")
                        LogManager.shared.warning("Force reveal blocked: upload in progress — try after upload completes", category: .general)
                        onUploadConflict?()
                    } else {
                        // Show recognized number in "seguidos" immediately while unarchiving
                        showOCRPeek(number: digitLabel)
                        Task { await revealByDigits(digits, fromSet: activeSet) }
                    }
                } else {
                    secretManager.reset()
                    followingOverride = nil; followerOverride = nil
                }
                selectedTab = 0
            }
            TabButton(icon: "play.rectangle", activeAsset: "instagram_reels_active", inactiveAsset: "instagram_reels_inactive", isSelected: selectedTab == 1) {
                selectedTab = 1
                secretManager.reset()
                followingOverride = nil; followerOverride = nil
            }
            TabButton(icon: "person.crop.square", activeAsset: "instagram_tagged_active", inactiveAsset: "instagram_tagged_inactive", isSelected: selectedTab == 2) {
                selectedTab = 2
                secretManager.reset()
                followingOverride = nil; followerOverride = nil
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder private var tabContentSection: some View {
        Group {
            switch selectedTab {
            case 0:
                let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
                PhotosGridView(
                    mediaURLs: urlsToShow,
                    cachedImages: cachedImages,
                    onMediaAppear: onMediaAppear,
                    onTapIndex: { index in
                        selectedPostIndex = index
                        showingPostViewer = true
                    }
                )
            case 1:
                ReelsGridView(reelURLs: profile.cachedReelURLs, cachedImages: cachedImages)
            case 2:
                PhotosGridView(mediaURLs: profile.cachedTaggedURLs, cachedImages: cachedImages)
            default:
                EmptyView()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in handleGridSwipe(value) }
        )
        .fullScreenCover(isPresented: $showingPostViewer) {
            let urlsToShow = mediaURLs ?? profile.cachedMediaURLs
            PostScrollView(
                mediaURLs: urlsToShow,
                mediaItemsByURL: mediaItemsByURL,
                cachedImages: cachedImages,
                initialIndex: selectedPostIndex,
                username: profile.username,
                profileImage: cachedImages[profile.profilePicURL],
                userId: profile.userId
            )
        }
    }

    // MARK: - Secret number gesture handling

    private func handleGridSwipe(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let absDx = abs(dx)
        let absDy = abs(dy)

        let isHorizontal = absDx > absDy && absDx > 30
        let isVertical   = absDy > absDx && absDy > 40

        guard isHorizontal else { return }

        // Register digit from the row where the swipe started
        let gridWidth = UIScreen.main.bounds.width
        let digit = SecretNumberManager.digit(
            x: value.startLocation.x,
            y: value.startLocation.y,
            gridWidth: gridWidth
        )
        secretManager.addDigit(digit)
        updateFollowingOverride()

        // Natural tab navigation: swipe left = next tab, right = previous tab
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = dx < 0
                ? min(2, selectedTab + 1)
                : max(0, selectedTab - 1)
        }
    }

    private func updateFollowingOverride() {
        if secretManager.digitBuffer.isEmpty {
            followingOverride = nil
            followerOverride  = nil
        } else if followingMagic.targetFollowers {
            followingOverride = nil
            followerOverride  = secretManager.followingDisplayString(originalCount: profile.followerCount)
        } else {
            followerOverride  = nil
            followingOverride = secretManager.followingDisplayString(originalCount: profile.followingCount)
        }
    }

    /// Inflates own following/followers from (realCount - transferOffset) up to realCount.
    /// The pre-deflated value was already set in onAppear; this just animates back to real.
    private func startTransferInflation() {
        let steps      = followingMagic.transferOffset
        let totalMs    = followingMagic.countdownDuration * 1000
        let intervalMs = max(16, totalMs / steps)

        followingMagic.isTransferCounting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let realCount = followingMagic.targetFollowers
            ? profile.followerCount
            : profile.followingCount
        var current = max(0, realCount - steps)  // start from the pre-deflated value

        transferCountdownTimer = Timer.scheduledTimer(
            withTimeInterval: Double(intervalMs) / 1000.0,
            repeats: true
        ) { timer in
            current += 1
            let text = "\(current)"
            if followingMagic.targetFollowers {
                followerOverride  = text
                followingOverride = nil
            } else {
                followingOverride = text
                followerOverride  = nil
            }
            if current >= realCount {
                timer.invalidate()
                transferCountdownTimer = nil
                // Clear override so the real count shows through
                followerOverride  = nil
                followingOverride = nil
                followingMagic.isTransferCounting = false
                followingMagic.transferOffset = 0
                VolumeButtonMonitor.shared.stopMonitoring()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                print("🎩 [TRANSFER] Inflation complete — back to real count: \(realCount)")
            }
        }
    }

    // MARK: - Force Number Reveal

    /// Unarchives the photo matching each digit in the corresponding bank, sequentially.
    /// Digit at position i (0-based) → bank i+1 → find photo with symbol == String(digit).
    private func revealByDigits(_ digits: [Int], fromSet set: PhotoSet) async {
        let sortedBanks = set.banks.sorted { $0.position < $1.position }
        let instagram = InstagramService.shared
        let dataManager = DataManager.shared

        // Signal operation start — blocks pull-to-refresh while running
        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        // Secondary guard: block if upload became active between button tap and Task execution
        if UploadManager.shared.isActive {
            print("⚠️ [FORCE#] Reveal aborted inside task: upload became active (shared rate limit)")
            LogManager.shared.warning("Force reveal aborted: upload became active after tap", category: .general)
            return
        }

        // Digits are read right-to-left: last digit → bank 1, second-to-last → bank 2, etc.
        // e.g. 568 → bank1=8, bank2=6, bank3=5
        let reversedDigits = digits.reversed()

        print("🔢 [FORCE#] ═══════════════════════════════════════")
        print("🔢 [FORCE#] Revealing digits: \(digits.map { String($0) }.joined()) (reversed: \(reversedDigits.map { String($0) }.joined())) from set '\(set.name)'")
        LogManager.shared.info("Force number reveal: \(digits.map { String($0) }.joined()) from set '\(set.name)'", category: .general)

        var successCount  = 0
        var skipCount     = 0
        var failCount     = 0
        var revealedIds: [String] = []           // only IDs actually unarchived via API in this session
        var revealedPhotos: [(pseudoURL: String, image: UIImage?)] = [] // for instant grid update

        // Cancel any previous pending re-archive before starting a new reveal
        ForceNumberRevealSettings.shared.cancelPendingReArchive()

        for (i, digit) in reversedDigits.enumerated() {
            // Stop if lockdown activates mid-reveal
            guard !instagram.isLocked else {
                print("🚨 [FORCE#] Lockdown active — stopping reveal")
                break
            }

            guard i < sortedBanks.count else {
                print("⚠️ [FORCE#] No bank at position \(i + 1) — skipping digit \(digit)")
                failCount += 1
                continue
            }

            let bank         = sortedBanks[i]
            let symbol       = String(digit)
            let photosInBank = set.photos.filter { $0.bankId == bank.id }

            // Already unarchived locally → skip API call.
            // IMPORTANT: do NOT add to revealedIds — we didn't unarchive it in this session,
            // so scheduling a re-archive would risk archiving something already archived on
            // Instagram (state-desync) which triggers bot detection.
            if photosInBank.contains(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
                print("ℹ️ [FORCE#] Digit \(digit) bank \(i + 1): already unarchived locally — skipping (not added to re-archive)")
                skipCount += 1
                continue
            }

            // Find archived photo → need API call
            guard let photo = photosInBank.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
                  let mediaId = photo.mediaId else {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1): no archived photo found with symbol '\(symbol)'")
                failCount += 1
                continue
            }

            // Anti-bot: random human-like delay before each unarchive
            let delay = UInt64.random(in: 800_000_000...2_200_000_000)
            try? await Task.sleep(nanoseconds: delay)

            do {
                let unarchived = try await instagram.unarchivePhoto(mediaId: mediaId)
                if unarchived {
                    dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId,
                                            isArchived: false, uploadStatus: .completed, errorMessage: nil)
                    print("✅ [FORCE#] Digit \(digit) bank \(i + 1): unarchived (ID: \(mediaId))")
                    LogManager.shared.success("Force reveal digit \(digit) bank \(i + 1) (ID: \(mediaId))", category: .general)
                    revealedIds.append(mediaId)
                    successCount += 1

                    // Load local image so PerformanceView can insert it instantly (no GET needed)
                    let localImage: UIImage? = photo.imageData.flatMap { UIImage(data: $0) }
                    revealedPhotos.append((pseudoURL: "reveal://\(mediaId)", image: localImage))
                    print("🖼️ [FORCE#] Local image \(localImage != nil ? "loaded" : "not found") for \(mediaId)")
                } else {
                    print("⚠️ [FORCE#] Digit \(digit) bank \(i + 1): unarchive returned false")
                    failCount += 1
                }
            } catch {
                print("❌ [FORCE#] Digit \(digit) bank \(i + 1) error: \(error)")
                LogManager.shared.error("Force reveal error digit \(digit) bank \(i + 1): \(error.localizedDescription)", category: .general)
                failCount += 1
                let msg = error.localizedDescription.lowercased()
                if msg.contains("session expired") || msg.contains("login_required") || msg.contains("please login again") {
                    UploadManager.shared.sendSessionExpiredNotification()
                }
            }
        }

        print("🔢 [FORCE#] Done — \(successCount) ok, \(skipCount) skipped, \(failCount) failed")

        // Schedule auto re-archive if enabled and we have IDs to re-archive
        if !revealedIds.isEmpty {
            ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: revealedIds)
        }

        // If at least one photo was actually unarchived via API, pass local images
        // to PerformanceView for an immediate grid update — no GET call needed.
        if successCount > 0 {
            onRevealComplete?(revealedPhotos)
        }

        // All unarchives done — clear the "seguidos" override
        await MainActor.run { clearOCRPeek() }
    }

    // MARK: - OCR Post Prediction: reveal by letters (word set)

    /// Reveals a word by unarchiving one photo per letter from the active word set.
    /// Letters are reversed so the spectator reads top→bottom = left→right word order.
    /// e.g. "hola" → reversed ["a","l","o","h"] → a→bank1, l→bank2, o→bank3, h→bank4
    ///
    /// Flow:
    ///  Phase 1 — Preparation (sync): find all photos, insert local images instantly into grid.
    ///  Phase 2 — API (async): unarchive each photo on Instagram sequentially.
    ///  Phase 3 — Finish: trigger CDN refresh once, clear override.
    private func revealByLetters(_ word: String, fromSet set: PhotoSet) async {
        let dm          = DataManager.shared
        let instagram   = InstagramService.shared
        let letters     = word.lowercased().reversed().map { String($0) }
        let alphabet    = set.selectedAlphabet ?? .latin
        let sortedBanks = set.banks.sorted { $0.position < $1.position }

        await MainActor.run { instagram.isRevealOperationActive = true }
        defer { Task { await MainActor.run { instagram.isRevealOperationActive = false } } }

        print("📷 [OCR-PP] ═══ Revealing '\(word)' (\(letters.count) letters) from '\(set.name)'")
        print("📷 [OCR-PP] Banks: \(sortedBanks.map { "pos\($0.position)=\($0.name)" })")

        // ── PHASE 1: Collect photos & insert local images instantly ──────────────
        struct LetterJob {
            let letter: String
            let photo: SetPhoto
            let mediaId: String
            let pseudoURL: String
            let localImage: UIImage?
        }

        var jobs: [LetterJob] = []

        for (idx, letter) in letters.enumerated() {
            let bankPosition = idx + 1
            guard let bank = sortedBanks.first(where: { $0.position == bankPosition })
                          ?? (idx < sortedBanks.count ? sortedBanks[idx] : nil) else {
                print("❌ [OCR-PP] No bank at position \(bankPosition) for letter '\(letter)'"); break
            }
            guard let charIndex = alphabet.indexFor(String(letter)) else {
                print("❌ [OCR-PP] '\(letter)' not found in alphabet"); continue
            }
            let symbol = alphabet.characters[charIndex]
            let photos = set.photos.filter { $0.bankId == bank.id }

            print("📷 [OCR-PP] [\(idx+1)/\(letters.count)] '\(letter)' → '\(symbol)' bank '\(bank.name)' pos\(bank.position)")

            // Already unarchived locally — skip
            if photos.contains(where: { $0.symbol == symbol && $0.mediaId != nil && !$0.isArchived }) {
                print("ℹ️ [OCR-PP] '\(letter)' already unarchived — skip")
                continue
            }
            guard let photo = photos.first(where: { $0.symbol == symbol && $0.mediaId != nil && $0.isArchived }),
                  let mediaId = photo.mediaId else {
                print("❌ [OCR-PP] No archived photo for '\(symbol)' in '\(bank.name)'")
                print("❌ [OCR-PP] Bank photos: \(photos.prefix(5).map { "sym=\($0.symbol) arch=\($0.isArchived)" })")
                continue
            }
            let localImage = photo.imageData.flatMap { UIImage(data: $0) }
            jobs.append(LetterJob(letter: letter, photo: photo, mediaId: mediaId,
                                  pseudoURL: "reveal://\(mediaId)", localImage: localImage))
        }

        // Insert ALL local images into grid immediately (before any API call)
        if !jobs.isEmpty {
            let instantPhotos = jobs.map { (pseudoURL: $0.pseudoURL, image: $0.localImage) }
            await MainActor.run { onAddLocalImages?(instantPhotos) }
            print("⚡️ [OCR-PP] \(instantPhotos.count) local image(s) pre-inserted into grid")
        }

        // ── PHASE 2: API unarchive calls ──────────────────────────────────────────
        var revealedIds: [String] = []

        for (jobIdx, job) in jobs.enumerated() {
            guard !instagram.isLocked else { break }

            do {
                let result = try await instagram.reveal(mediaId: job.mediaId)
                if result.success {
                    await MainActor.run {
                        dm.updatePhoto(photoId: job.photo.id, isArchived: false, commentId: result.commentId)
                    }
                    revealedIds.append(job.mediaId)
                    print("✅ [OCR-PP] '\(job.letter)' unarchived on Instagram (ID: \(job.mediaId))")
                    LogManager.shared.success("OCR revealed '\(job.letter)' (mediaId: \(job.mediaId))", category: .general)
                } else {
                    print("❌ [OCR-PP] reveal returned false for '\(job.letter)'")
                }
            } catch {
                print("❌ [OCR-PP] Error '\(job.letter)': \(error.localizedDescription)")
                LogManager.shared.error("OCR reveal error '\(job.letter)': \(error.localizedDescription)", category: .general)
            }

            // Anti-bot delay between letters (skip after last one)
            if jobIdx < jobs.count - 1 {
                let delay = UInt64.random(in: 800_000_000...2_200_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        // ── PHASE 3: Finish ───────────────────────────────────────────────────────
        ForceNumberRevealSettings.shared.scheduleReArchive(mediaIds: revealedIds)
        print("📷 [OCR-PP] ═══ Done — \(revealedIds.count)/\(jobs.count) unarchived on Instagram")

        // Trigger ONE CDN refresh now that all photos are unarchived on Instagram
        await MainActor.run { onRevealComplete?([]) }

        // Clear the "seguidos" override
        await MainActor.run { clearOCRPeek() }
    }

}

// MARK: - Reels Grid View (4:5 aspect with play icon overlay)

struct ReelsGridView: View {
    let reelURLs: [String]
    let cachedImages: [String: UIImage]
    /// 12 cells = 4 rows, so digit 0 (row 4+) is reachable
    var minCells: Int = 12

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        let placeholderCount = max(0, minCells - reelURLs.count)
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(reelURLs, id: \.self) { url in
                Color.clear
                    .aspectRatio(4/5, contentMode: .fit)
                    .overlay(
                        ZStack(alignment: .bottomLeading) {
                            if let image = cachedImages[url] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                            IGIcon(asset: "instagram_play", fallback: "play.fill", size: 12, color: .white)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    )
                    .clipped()
            }
            // Placeholder cells
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(4/5, contentMode: .fit)
                        .overlay(
                            ZStack(alignment: .bottomLeading) {
                                Rectangle().fill(Color.gray.opacity(0.15))
                                IGIcon(asset: "instagram_play", fallback: "play.fill", size: 12, color: .white.opacity(0.4))
                                    .padding(6)
                            }
                        )
                        .clipped()
                }
            }
        }
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
                IGIcon(asset: "Instagram_plus", fallback: "plus.app", size: 24)
            }

            Spacer()

            // Username with dropdown
            HStack(spacing: 4) {
                if isVerified {
                    IGIcon(asset: "instagram_verified", fallback: "checkmark.seal.fill", size: 16, color: .blue)
                }
                Text(username)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.black)
                IGIcon(asset: "instagram_chevron_down", fallback: "chevron.down", size: 12)
            }

            Spacer()

            HStack(spacing: 20) {
                Button(action: {}) {
                    IGIcon(asset: "instagram_threads", fallback: "at", size: 22)
                }

                Button(action: {}) {
                    IGIcon(asset: "Instagram_menu", fallback: "line.3.horizontal", size: 24)
                }
            }
        }
        .responsiveHorizontalPadding()
        .frame(height: 44)
        .background(Color.white)
    }
}

// MARK: - Stat View

struct StatView: View {
    let number: Int
    let label: String
    var overrideText: String? = nil
    var overrideLabel: String? = nil

    var body: some View {
        // alignment: .leading → número y label alineados al mismo borde izquierdo.
        // El primer dígito y la primera letra quedan exactamente en la misma columna.
        VStack(alignment: .leading, spacing: 1) {
            Text(overrideText ?? formatCount(number))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
                .monospacedDigit()
            Text(overrideLabel ?? label)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 10_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }
}

// MARK: - Followed By View

// MARK: - Story Highlight Cell

struct StoryHighlightCell: View {
    let highlight: InstagramHighlight
    let image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.99, green: 0.42, blue: 0.05),
                                     Color(red: 0.85, green: 0.08, blue: 0.40),
                                     Color(red: 0.57, green: 0.12, blue: 0.76)],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 68, height: 68)

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 62, height: 62)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }

            Text(highlight.title)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 68)
        }
    }
}

// MARK: - Auto Followed By View (Date Force Auto Mode)
// Looks identical to FollowedByView: 3 overlapping circles + "Seguido/a por" text.
// Tapping alternates between the date group and the time group spectators.

struct AutoFollowedByView: View {
    @ObservedObject var dateForce: DateForceSettings
    let onTap: (() -> Void)?

    private var isLoading: Bool { dateForce.isAutoLoading }
    private var loaded: Int { dateForce.spectators.count }

    /// Up to 3 spectators from the currently active display group.
    private var visible: [DateForceSpectator] {
        Array(dateForce.spectators
            .filter { $0.group == dateForce.autoDisplayGroup }
            .prefix(3))
    }

    var body: some View {
        HStack(spacing: 4) {
            // ── Circles ───────────────────────────────────────────────────
            circlesArea

            // ── Text ──────────────────────────────────────────────────────
            textArea
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLoading else { return }
            withAnimation(.easeInOut(duration: 0.2)) { onTap?() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Circles section extracted so the body stays simple
    @ViewBuilder private var circlesArea: some View {
        if isLoading && loaded == 0 {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 20, height: 20)
        } else {
            HStack(spacing: -8) {
                ForEach(0..<min(max(visible.count, 0), 3), id: \.self) { _ in
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                if isLoading {
                    ForEach(0..<max(0, 3 - min(loaded, 3)), id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: loaded)
        }
    }

    // Text section: each HStack gets its own .frame(maxWidth:.infinity) so
    // fixedSize() texts never overflow the available width.
    @ViewBuilder private var textArea: some View {
        if isLoading && loaded == 0 {
            Text("Capturing followers…")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.isEmpty {
            Text("ig.followed_by")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count >= 3 {
            HStack(spacing: 0) {
                Text("ig.followed_by")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                Text(", ")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[1].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                Text("ig.and")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[2].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if visible.count == 2 {
            HStack(spacing: 0) {
                Text("ig.followed_by")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).fixedSize()
                Text("ig.and")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[1].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                Text("ig.followed_by")
                    .font(.system(size: 12)).foregroundColor(Color(white: 0.56)).fixedSize()
                Text(visible[0].username)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Followed By View

struct FollowedByView: View {
    let followers: [InstagramFollower]
    let cachedImages: [String: UIImage]
    var onFollowerTap: ((InstagramFollower) -> Void)? = nil

    /// Toggles between first page (0–2) and second page (3–5) when tapping the avatar area.
    @State private var showingAltPage = false

    /// Followers for the currently visible page (up to 3).
    private var visibleFollowers: [InstagramFollower] {
        let start = showingAltPage ? 3 : 0
        let end   = min(start + 3, followers.count)
        guard start < end else { return Array(followers.prefix(3)) }
        return Array(followers[start..<end])
    }

    /// True if there's a second page to toggle to.
    private var hasAltPage: Bool { followers.count > 3 }

    var body: some View {
        HStack(spacing: 4) {
            // Avatar circles — tap always toggles page, never opens a profile directly.
            // Profile opening is only via tapping a name in the text section.
            HStack(spacing: -8) {
                ForEach(visibleFollowers, id: \.username) { follower in
                    if let picURL = follower.profilePicURL,
                       let image = cachedImages[picURL] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasAltPage else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showingAltPage.toggle() }
            }

            // Names — each individually tappable, matches the current page.
            // All text stays on a single line; the last name truncates with "…"
            // if the total content is wider than the available space.
            if visibleFollowers.count >= 3 {
                HStack(spacing: 0) {
                    Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).fixedSize()
                        .onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                    Text(", ").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).fixedSize()
                        .onTapGesture { onFollowerTap?(visibleFollowers[1]) }
                    Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[2].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).truncationMode(.tail)
                        .onTapGesture { onFollowerTap?(visibleFollowers[2]) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if visibleFollowers.count == 2 {
                HStack(spacing: 0) {
                    Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).fixedSize()
                        .onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                    Text("ig.and").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[1].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).truncationMode(.tail)
                        .onTapGesture { onFollowerTap?(visibleFollowers[1]) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if visibleFollowers.count == 1 {
                HStack(spacing: 0) {
                    Text("ig.followed_by").font(.system(size: 12)).foregroundColor(Color(white: 0.56))
                        .fixedSize()
                    Text(visibleFollowers[0].username).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                        .lineLimit(1).truncationMode(.tail)
                        .onTapGesture { onFollowerTap?(visibleFollowers[0]) }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: showingAltPage)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let icon: String
    let activeAsset: String?
    let inactiveAsset: String?
    let isSelected: Bool
    let action: () -> Void

    init(icon: String, activeAsset: String? = nil, inactiveAsset: String? = nil,
         isSelected: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.activeAsset = activeAsset
        self.inactiveAsset = inactiveAsset
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                let assetName = isSelected ? activeAsset : inactiveAsset
                if let asset = assetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                }
            }
            .foregroundColor(isSelected ? .black : Color(white: 0.56))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.black : Color.clear)
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
    var onMediaAppear: ((String) -> Void)? = nil
    var onTapIndex: ((Int) -> Void)? = nil
    /// Always render at least this many cells so swipe digit-detection works
    /// even on tabs with few or no photos. 12 = 4 rows (row 4 maps to digit 0).
    var minCells: Int = 12

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        let placeholderCount = max(0, minCells - mediaURLs.count)
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                Color.clear
                    .aspectRatio(4/5, contentMode: .fit)
                    .overlay(
                        Group {
                            if let image = cachedImages[url] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                        }
                    )
                    .clipped()
                    .onAppear { onMediaAppear?(url) }
                    .onTapGesture { onTapIndex?(index) }
            }
            // Placeholder cells
            if placeholderCount > 0 {
                ForEach(0..<placeholderCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(4/5, contentMode: .fit)
                        .overlay(Rectangle().fill(Color.gray.opacity(0.15)))
                        .clipped()
                }
            }
        }
    }
}

// MARK: - Post Scroll Viewer (Instagram "Posts" style)

struct PostScrollView: View {
    let mediaURLs: [String]
    let mediaItemsByURL: [String: InstagramMediaItem]
    let cachedImages: [String: UIImage]
    let initialIndex: Int
    let username: String
    let profileImage: UIImage?
    let userId: String
    var forcePostURL: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedItems: [String: InstagramMediaItem] = [:]
    @State private var hasForceActivated: Bool = false

    private var isForceActive: Bool { forcePostURL != nil }
    private var forcedPostIndex: Int {
        guard let url = forcePostURL else { return 0 }
        return mediaURLs.firstIndex(of: url) ?? 0
    }

    private func postID(_ index: Int) -> String { "post_\(index)" }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        // VStack (not Lazy) ensures all cards are in the view hierarchy
                        // so the forced card's exact frame is always measurable.
                        VStack(spacing: 0) {
                            ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                                PostCardView(
                                    url: url,
                                    item: resolvedItems[url],
                                    cachedImage: cachedImages[url],
                                    username: username,
                                    profileImage: profileImage
                                )
                                .id(postID(index))
                                .accessibilityIdentifier(url == forcePostURL ? "forced_post_card" : "")
                                Divider().background(Color(white: 0.9))
                            }
                        }
                    }

                    if isForceActive {
                        ScrollViewInterceptor(
                            forcedIndex: forcedPostIndex,
                            totalPostCount: mediaURLs.count,
                            hasActivated: $hasForceActivated,
                            isActive: isForceActive
                        )
                        .frame(width: 0, height: 0)
                    }
                }
                .onAppear {
                    resolvedItems = mediaItemsByURL
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(postID(initialIndex), anchor: .top)
                    }
                    let missingCount = mediaURLs.filter { mediaItemsByURL[$0] == nil }.count
                    if missingCount > 0 {
                        Task { await fetchMissingItems() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.black)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("ig.tab_posts")
                            .font(.system(size: 15, weight: .semibold))
                        Text(username)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(Color.white)
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func fetchMissingItems() async {
        guard !InstagramService.shared.isLocked else {
            print("🚫 [POSTS] Item fetch skipped — lockdown active")
            return
        }
        do {
            let (items, _) = try await InstagramService.shared.getUserMediaItems(
                userId: userId, amount: 18, maxId: nil
            )
            for item in items { resolvedItems[item.imageURL] = item }
        } catch {
            print("⚠️ [POSTS] Background item fetch failed: \(error)")
        }
    }
}

// MARK: - Individual Post Card

private struct PostCardView: View {
    let url: String
    let item: InstagramMediaItem?
    let cachedImage: UIImage?
    let username: String
    let profileImage: UIImage?

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private func formatted(_ n: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: avatar + username + "..." menu
            HStack(spacing: 10) {
                if let pic = profileImage {
                    Image(uiImage: pic)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                Text(username)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                IGIcon(asset: "instagram_more_horizontal", fallback: "ellipsis", size: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Media
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(ProgressView().tint(.gray))
            }

            // Action bar with counts (like real Instagram)
            HStack(spacing: 4) {
                actionIcon("instagram_like", fallback: "heart", count: item?.likeCount)
                actionIcon("instagram_comment", fallback: "bubble.left", count: item?.commentCount)
                    .padding(.leading, 8)
                actionIcon("instagram_share", fallback: "paperplane", count: nil)
                    .padding(.leading, 8)
                Spacer()
                IGIcon(asset: "instagram_save", fallback: "bookmark", size: 22)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Caption: username bold + text inline (like real Instagram)
            if let caption = item?.caption, !caption.isEmpty {
                captionView(caption)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Date
            if let date = item?.takenAt {
                Text(date, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 12)
            }
        }
    }

    @ViewBuilder
    private func actionIcon(_ assetName: String, fallback: String = "square", count: Int?) -> some View {
        HStack(spacing: 4) {
            IGIcon(asset: assetName, fallback: fallback, size: 24)
            if let c = count, c > 0 {
                Text(formatted(c))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
    }

    @ViewBuilder
    private func captionView(_ caption: String) -> some View {
        // Username bold + caption inline using attributed text — flows naturally like Instagram
        let attributed = attributedCaption(caption)
        Text(attributed)
            .font(.system(size: 13))
            .lineLimit(3)
            .foregroundColor(.black)
    }

    private func attributedCaption(_ caption: String) -> AttributedString {
        var user = AttributedString(username + " ")
        user.font = .system(size: 13, weight: .semibold)
        var text = AttributedString(caption)
        text.font = .system(size: 13)
        return user + text
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
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 0, x: 0, y: -0.33)
            
            HStack(spacing: 0) {
                Button(action: onHomePress) {
                    IGIcon(asset: "instagram_home", fallback: "house", size: 24)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
                .padding(.bottom, 44)
                
                Button(action: onReelsPress) {
                    IGIcon(asset: "instagram_reels_tab", fallback: "play.rectangle", size: 24)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
                .padding(.bottom, 44)
                
                Button(action: onMessagesPress) {
                    ZStack(alignment: .topTrailing) {
                        IGIcon(asset: "instagram_share", fallback: "paperplane", size: 24)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 6, y: -3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
                .padding(.bottom, 44)
                
                Button(action: onSearchPress) {
                    IGIcon(asset: "instagram_search", fallback: "magnifyingglass", size: 24)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
                .padding(.bottom, 44)
                
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
                .padding(.top, 10)
                .padding(.bottom, 44)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Notes Bubble View (Instagram-style note above profile pic)

struct NotesBubbleView: View {
    let text: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Bubble body
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(UIColor.systemGray5), lineWidth: 0.8)
                        )
                )
                // Small tail pointing downward-left (Instagram style)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "bubble.left.fill")
                        .resizable()
                        .frame(width: 10, height: 8)
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                        .offset(x: 10, y: 6)
                        .rotationEffect(.degrees(180))
                }
        }
        .frame(maxWidth: 120)
        .padding(.bottom, 2)
    }
}

// MARK: - Spectator Profile Cover

/// Loads a follower's full profile then presents it as a UserProfileView.
/// Owned by fullScreenCover(item: $selectedSpectator) so each new follower
/// gets a fresh presentation context with no stale-item race condition.
private struct SpectatorProfileCover: View {
    let follower: InstagramFollower
    let onClose: () -> Void

    @State private var profile: InstagramProfile? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let profile {
                UserProfileView(profile: profile, onClose: onClose)
            } else if isLoading {
                Color.white.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text("Loading profile…")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    )
            } else {
                Color.white.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(errorMessage ?? "Could not load profile")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button("Close", action: onClose)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    )
            }
        }
        .task {
            print("👤 [SPECTATOR] Loading profile for @\(follower.username)")
            do {
                if let p = try await InstagramService.shared.getProfileInfo(userId: follower.userId) {
                    await MainActor.run {
                        profile = p
                        isLoading = false
                    }
                    print("✅ [SPECTATOR] Profile loaded: @\(p.username)")
                } else {
                    await MainActor.run {
                        errorMessage = "Could not load profile for @\(follower.username)"
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                print("❌ [SPECTATOR] Error: \(error)")
            }
        }
    }
}

