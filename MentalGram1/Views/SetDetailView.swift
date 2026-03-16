import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Upload Phase Enum

enum UploadPhase: Equatable {
    case idle
    case uploading(photoNumber: Int)
    case archiving(photoNumber: Int)
    case waiting(nextPhoto: Int, remainingSeconds: Int)
    case cooldown(remainingSeconds: Int)
    case autoRetrying(remainingSeconds: Int, attempt: Int)
    case waitingNetwork(attempt: Int)
    case escalatedPause(remainingSeconds: Int)
    case botLockdown(remainingSeconds: Int)
    case sessionExpired
    case paused
    case completed
    
    var borderColor: Color {
        switch self {
        case .idle: return .green
        case .uploading: return .purple
        case .archiving: return .blue
        case .waiting: return .orange
        case .cooldown: return Color.orange.opacity(0.8)
        case .autoRetrying: return .orange
        case .waitingNetwork: return .yellow
        case .escalatedPause: return .red
        case .botLockdown: return .red
        case .sessionExpired: return .red
        case .paused: return .gray
        case .completed: return .green
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .botLockdown, .sessionExpired: return Color.red.opacity(0.05)
        case .cooldown, .autoRetrying: return Color.orange.opacity(0.05)
        case .escalatedPause: return Color.red.opacity(0.05)
        default: return Color.gray.opacity(0.1)
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "checkmark.circle.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .archiving: return "archivebox.fill"
        case .waiting: return "clock.fill"
        case .cooldown: return "clock.badge.exclamationmark"
        case .autoRetrying: return "arrow.clockwise.circle.fill"
        case .waitingNetwork: return "wifi.exclamationmark"
        case .escalatedPause: return "exclamationmark.triangle.fill"
        case .botLockdown: return "exclamationmark.triangle.fill"
        case .sessionExpired: return "lock.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Set Detail View

struct SetDetailView: View {
    let set: PhotoSet
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var instagram = InstagramService.shared
    
    @ObservedObject var uploadManager = UploadManager.shared
    
    @State private var selectedBankIndex = 0
    @State private var isReorderMode = false
    @State private var consecutiveDuplicates: Set<Int> = []
    @State private var selectedReorderIndex: Int? = nil  // Tap-to-swap: first selected photo
    
    // SLOT-BASED PHOTO MANAGEMENT (Word/Number Reveal)
    @State private var slotPickerItem: PhotosPickerItem? = nil
    @State private var targetSlotSymbol: String? = nil
    @State private var showDeleteConfirm = false
    @State private var deleteTargetSymbol: String? = nil
    @State private var isProcessingSlotPhoto = false
    
    // ARCHIVED PHOTO MAPPING
    @State private var showArchivedPicker = false
    @State private var archivedPickerTargetSymbol: String? = nil
    @State private var showSlotSourcePicker = false
    @State private var slotSourcePickerSymbol: String? = nil
    @State private var showGalleryPickerSheet = false

    // VERIFY & SYNC state
    @State private var isSyncing = false
    @State private var syncProgress = 0
    @State private var syncTotal = 0
    @State private var syncFixedCount = 0
    @State private var syncUnknownCount = 0          // couldn't check (nil response)
    @State private var syncTrulyVisibleIds: [String] = []  // confirmed public by Instagram
    @State private var syncCompleted = false

    // ARCHIVE ALL state (post-sync)
    @State private var isArchivingAll = false
    @State private var archiveAllProgress = 0
    @State private var archiveAllTotal = 0
    @State private var archiveAllCompleted = false
    /// True during the human-gap pause between Phase 1 (verify) and Phase 2 (archive).
    @State private var isPausingBeforeArchive = false
    /// Seconds remaining in the current pause or inter-archive cooldown (shown as countdown).
    @State private var saCountdownSeconds: Int = 0

    var currentSet: PhotoSet {
        dataManager.sets.first(where: { $0.id == set.id }) ?? set
    }

    /// Photos that are locally marked as visible (isArchived=false) AND fully uploaded.
    /// These are candidates for a state desync with Instagram's real archive status.
    private var visibleUploadedPhotos: [SetPhoto] {
        currentSet.photos.filter {
            $0.mediaId != nil &&
            $0.uploadStatus == .completed &&
            !$0.isArchived
        }
    }

    /// All uploaded photos (including locally-archived) that have a mediaId.
    /// Used by "Re-verify All" to detect desync where local state says archived
    /// but Instagram still has the photo as public.
    private var allUploadedPhotos: [SetPhoto] {
        currentSet.photos.filter {
            $0.mediaId != nil &&
            $0.uploadStatus == .completed
        }
    }

    /// isReverifying is now driven by uploadManager.isReverifying (persists across view lifecycle).
    
    var body: some View {
        ZStack {
            VaultTheme.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: VaultTheme.Spacing.lg) {
                // Header Stats
                statsSection

                // Session expired banner
                if instagram.isSessionExpired {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.lock.fill")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session expired")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Log out and log in again to continue uploading.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                }

                // Verify & Sync banner (shown when visible uploaded photos exist)
                verifySyncSection

                // Re-verify button — always available when all photos appear archived locally
                // but might be out of sync with Instagram's real state.
                if instagram.isLoggedIn && visibleUploadedPhotos.isEmpty && !allUploadedPhotos.isEmpty && !isSyncing && !isArchivingAll {
                    if uploadManager.isReverifying {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text("Re-verifying \(uploadManager.reverifyProgress)/\(uploadManager.reverifyTotal)…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if uploadManager.reverifyDesynced > 0 {
                                Text("(\(uploadManager.reverifyDesynced) desync)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    } else {
                        Button(action: {
                            startReverify()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Text("Re-verify all (\(allUploadedPhotos.count) photos)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Status & Actions (only when logged in)
                if instagram.isLoggedIn {
                    statusSection
                        .id("\(uploadManager.uploadPhase)-\(uploadManager.nextPhotoCountdown)-\(uploadManager.botCountdownSeconds)-\(uploadManager.autoRetryCountdown)-\(uploadManager.escalatedPauseCountdown)")
                    
                    // ERROR RECOVERY SECTION (only for photo rejected - others are auto-handled)
                    if uploadManager.isPhotoRejected {
                        photoRejectedRecoverySection
                    }
                }
                
                // Banks Tabs (for word/number)
                if !currentSet.banks.isEmpty {
                    banksTabsSection
                }
                
                // Reorder / Done button (below banks)
                reorderToggleButton
                
                // Photos Grid
                photosGridSection
            }
            .padding(VaultTheme.Spacing.lg)
        }
        }
        .navigationTitle(currentSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { }
        .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Error", isPresented: .constant(uploadManager.showingError != nil), presenting: uploadManager.showingError) { _ in
            if uploadManager.isPhotoRejected {
                // Photo rejected: Offer skip or replace (only non-auto-retryable alert)
                Button("Skip This Photo") {
                    resetErrorState()
                    Task { await skipFailedPhotoAndContinue() }
                }
                Button("Cancel Upload", role: .cancel) { resetErrorState() }
            } else {
                // Generic dismissible alert (startup errors, etc.)
                Button("OK") { resetErrorState() }
            }
        } message: { error in
            Text(error)
        }
        .onChange(of: instagram.networkChangedDuringUpload) { changed in
            // Network changed during active upload → request pause
            if changed && uploadManager.isUploading && isThisSetActive {
                print("⚠️ [UPLOAD] Network changed during upload - requesting PAUSE")
                LogManager.shared.warning("Network changed during active upload - pausing for safety", category: .network)
                uploadManager.requestPause = true
                uploadManager.showingError = "Network Changed\n\nYour connection changed (e.g., WiFi to Cellular).\n\nCheck your connection and tap 'Resume' to continue."
                // Reset flag
                instagram.networkChangedDuringUpload = false
            }
        }
        .onAppear {
            // Reconstruir timers si es necesario cuando la vista aparece
            restoreTimersIfNeeded()
        }
        .onDisappear {
            // NO invalidar timers aquí - deben seguir corriendo en background
            // Solo los invalidamos cuando el upload termina/pausa/cancela
        }
        .onChange(of: slotPickerItem) { newItem in
            guard let item = newItem, let symbol = targetSlotSymbol else { return }
            loadPhotoForSlot(item: item, symbol: symbol)
        }
        .alert("Delete Photo", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let symbol = deleteTargetSymbol {
                    dataManager.deletePhotosBySymbol(setId: currentSet.id, symbol: symbol)
                    deleteTargetSymbol = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTargetSymbol = nil
            }
        } message: {
            Text("Remove this photo from all banks? This cannot be undone.")
        }
        .confirmationDialog("Add photo for slot", isPresented: $showSlotSourcePicker, titleVisibility: .visible) {
            Button("From Gallery") {
                if let symbol = slotSourcePickerSymbol {
                    targetSlotSymbol = symbol
                    showGalleryPickerSheet = true
                }
                showSlotSourcePicker = false
            }
            if instagram.isLoggedIn {
                Button("From Archived") {
                    if let symbol = slotSourcePickerSymbol {
                        archivedPickerTargetSymbol = symbol
                        showArchivedPicker = true
                    }
                    showSlotSourcePicker = false
                }
            }
            Button("Cancel", role: .cancel) {
                slotSourcePickerSymbol = nil
                showSlotSourcePicker = false
            }
        } message: {
            if let symbol = slotSourcePickerSymbol {
                Text("Choose where to get the photo for \"\(symbol)\"")
            }
        }
        .sheet(isPresented: $showArchivedPicker) {
            if let symbol = archivedPickerTargetSymbol {
                ArchivedPhotosPickerView(
                    targetSlotSymbol: symbol,
                    onPhotoSelected: { archivedPhoto in
                        mapArchivedPhotoToSlot(archivedPhoto: archivedPhoto, symbol: symbol)
                    }
                )
            }
        }
        .sheet(isPresented: $showGalleryPickerSheet) {
            if let symbol = targetSlotSymbol ?? slotSourcePickerSymbol {
                galleryPickerSheetView(symbol: symbol)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Restore State
    
    private func restoreTimersIfNeeded() {
        uploadManager.restoreTimersIfNeeded()
    }
    
    // MARK: - Stats Section
    
    // MARK: - Verify & Sync Section

    /// Banner visible only when logged in and there are locally-visible uploaded photos
    /// that could be desynced from Instagram's real archive state.
    @ViewBuilder
    private var verifySyncSection: some View {
        if instagram.isLoggedIn && !visibleUploadedPhotos.isEmpty {
            VStack(spacing: 8) {

                // ── Phase 1 running: verifying ─────────────────────────
                if isSyncing {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uploadManager.isSyncArchiveActive
                                 ? "Sync & Archive — verifying (\(syncProgress)/\(syncTotal))…"
                                 : "Verifying (\(syncProgress)/\(syncTotal))…")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Checking real state on Instagram")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.09))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2), lineWidth: 1))

                // ── Pause between Phase 1 and Phase 2 ─────────────────
                } else if isPausingBeforeArchive {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preparing to archive… \(saCountdownSeconds)s")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Short pause before sending archive requests")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.09))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))

                // ── Phase 2 running: archiving ─────────────────────────
                } else if isArchivingAll {
                    HStack(spacing: 10) {
                        if saCountdownSeconds > 0 {
                            // During inter-archive cooldown: show countdown
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.purple)
                                .font(.system(size: 16))
                        } else {
                            ProgressView().scaleEffect(0.85)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Archiving (\(archiveAllProgress)/\(archiveAllTotal))")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            if saCountdownSeconds > 0 {
                                let m = saCountdownSeconds / 60
                                let s = saCountdownSeconds % 60
                                Text(m > 0
                                     ? "Next archive in \(m)m \(s)s — do not close the app"
                                     : "Next archive in \(s)s — do not close the app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("Archiving… do not close the app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.09))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2), lineWidth: 1))

                // ── All done ───────────────────────────────────────────
                } else if archiveAllCompleted {
                    HStack(spacing: 10) {
                        if archiveAllProgress == archiveAllTotal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16))
                            Text("All \(archiveAllTotal) photos archived")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Archived \(archiveAllProgress)/\(archiveAllTotal) photos")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                Text("\(archiveAllTotal - archiveAllProgress) failed — tap Sync & Archive to retry")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background((archiveAllProgress == archiveAllTotal ? Color.green : Color.orange).opacity(0.09))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke((archiveAllProgress == archiveAllTotal ? Color.green : Color.orange).opacity(0.2), lineWidth: 1))

                // ── Sync-only result (verify ran, no archive started yet) ──
                } else if syncCompleted && !syncTrulyVisibleIds.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncResultTitle)
                                .font(.subheadline.bold())
                            if syncUnknownCount > 0 {
                                Text("\(syncUnknownCount) photo\(syncUnknownCount > 1 ? "s" : "") couldn't be checked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.07))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2), lineWidth: 1))

                // ── Idle: main action button ───────────────────────────
                } else {
                    // PRIMARY: Sync & Archive (single safe action)
                    Button(action: {
                        guard !isSyncing, !isArchivingAll else { return }
                        Task { await syncThenArchiveAll() }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sync & Archive (\(visibleUploadedPhotos.count) visible)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Verifies state · then archives with safe delays · no duplicate API calls")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing || isArchivingAll || uploadManager.isSyncArchiveActive)

                    // SECONDARY: Verify only (read-only, no archive)
                    Button(action: {
                        guard !isSyncing else { return }
                        Task { await verifySyncAll() }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("Verify only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing || isArchivingAll)
                }
            }
        }
    }

    private var syncResultTitle: String {
        var parts: [String] = []
        if syncFixedCount > 0 {
            parts.append("Fixed \(syncFixedCount) desync\(syncFixedCount > 1 ? "s" : "")")
        }
        if !syncTrulyVisibleIds.isEmpty {
            parts.append("\(syncTrulyVisibleIds.count) confirmed public")
        }
        if parts.isEmpty {
            if syncUnknownCount == syncTotal {
                return "API returned no data — check logs"
            }
            return "All photos in sync ✓"
        }
        return parts.joined(separator: " · ")
    }

    /// Checks each locally-visible uploaded photo against Instagram's real archive status.
    /// Outcome per photo:
    ///  - Instagram says archived  → fix local state (no write API call) [fixed]
    ///  - Instagram says visible   → truly public, candidate for Archive All [trulyVisible]
    ///  - Instagram returns nil    → couldn't determine, skip [unknown]
    /// Uses 1.5s delay between GETs to avoid rapid-request patterns.
    private func verifySyncAll() async {
        let photos = visibleUploadedPhotos
        guard !photos.isEmpty, !isSyncing else {
            print("⚠️ [SYNC] verifySyncAll called but already running or no photos")
            return
        }

        print("🔄 [SYNC] Starting verify for \(photos.count) photo(s)")
        LogManager.shared.info("State sync started: \(photos.count) visible photos to check", category: .general)

        await MainActor.run {
            isSyncing = true
            syncProgress = 0
            syncTotal = photos.count
            syncFixedCount = 0
            syncUnknownCount = 0
            syncTrulyVisibleIds = []
            syncCompleted = false
            archiveAllCompleted = false
        }

        var fixed = 0
        var unknown = 0
        var trulyVisible: [String] = []

        for (index, photo) in photos.enumerated() {
            guard let mediaId = photo.mediaId else {
                print("⚠️ [SYNC] Photo index \(index) has no mediaId — skipping")
                unknown += 1
                continue
            }

            // Anti-bot gap: 1.5s between GET requests (skip before first)
            if index > 0 {
                print("⏳ [SYNC] Waiting 1.5s before next check...")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            await MainActor.run { syncProgress = index + 1 }
            print("🔍 [SYNC] Checking photo \(index + 1)/\(photos.count) — mediaId: \(mediaId)")

            do {
                let result = try await instagram.getMediaIsArchived(mediaId: mediaId)

                switch result {
                case .some(true):
                    // Desync: Instagram says archived, local says visible → fix local silently
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: mediaId,
                            isArchived: true,
                            uploadStatus: .completed,
                            errorMessage: nil
                        )
                        fixed += 1
                    }
                    print("🔄 [SYNC] ✅ FIXED desync: \(mediaId) → set local to archived")
                    LogManager.shared.info(
                        "State sync: fixed desync for \(mediaId) (local visible → Instagram archived)",
                        category: .general
                    )

                case .some(false):
                    // Truly public on Instagram
                    trulyVisible.append(mediaId)
                    print("🔍 [SYNC] ℹ️ Truly visible: \(mediaId) — Instagram confirms it's public")
                    LogManager.shared.info("State sync: \(mediaId) confirmed public on Instagram", category: .general)

                case .none:
                    // Couldn't determine — API returned nil (no 'is_archived' field or error)
                    unknown += 1
                    print("⚠️ [SYNC] ❓ Unknown state for: \(mediaId) — API returned nil, skipping")
                    LogManager.shared.warning("State sync: could not determine state for \(mediaId)", category: .general)
                }
            } catch {
                // Session expired (403/401) → abort entire sync, show re-login prompt
                let msg = error.localizedDescription
                print("🚫 [SYNC] Session error — aborting sync: \(msg)")
                LogManager.shared.warning("State sync aborted: session error — \(msg)", category: .api)
                UploadManager.shared.sendSessionExpiredNotification()
                await MainActor.run {
                    isSyncing = false
                    syncCompleted = false
                    syncUnknownCount = photos.count
                }
                return
            }
        }

        print("🔄 [SYNC] Done — fixed: \(fixed), trulyVisible: \(trulyVisible.count), unknown: \(unknown)")
        LogManager.shared.info(
            "State sync complete: fixed=\(fixed), trulyVisible=\(trulyVisible.count), unknown=\(unknown)",
            category: .general
        )

        await MainActor.run {
            syncFixedCount = fixed
            syncUnknownCount = unknown
            syncTrulyVisibleIds = trulyVisible
            isSyncing = false
            syncCompleted = true
        }

        // Auto-hide result banner only when there's nothing actionable
        if trulyVisible.isEmpty {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { syncCompleted = false }
        }
    }

    /// Archives all confirmed-visible photos sequentially with anti-bot delays.
    private func archiveAllVisible() async {
        let ids = syncTrulyVisibleIds
        guard !ids.isEmpty, !isArchivingAll else { return }

        print("📦 [ARCHIVE-ALL] Starting archive for \(ids.count) confirmed-visible photo(s)")
        LogManager.shared.info("Archive All started: \(ids.count) photo(s)", category: .general)

        await MainActor.run {
            isArchivingAll = true
            archiveAllProgress = 0
            archiveAllTotal = ids.count
            archiveAllCompleted = false
        }

        for (index, mediaId) in ids.enumerated() {
            // Human-like delay before each archive: 3–6s
            let delaySeconds = Double.random(in: 3.0...6.0)
            print("⏳ [ARCHIVE-ALL] Waiting \(String(format: "%.1f", delaySeconds))s before archiving \(index + 1)/\(ids.count)...")
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))

            // Check rate limit before each call (synchronous — no await needed)
            let rateLimit = instagram.checkRateLimit()
            print("🔒 [ARCHIVE-ALL] Rate limit: used=\(rateLimit.actionsUsed), remaining=\(rateLimit.remaining)")
            if rateLimit.limited || rateLimit.remaining < 2 {
                print("⛔️ [ARCHIVE-ALL] Rate limit reached — stopping at \(index)/\(ids.count)")
                LogManager.shared.warning("Archive All stopped: rate limit reached (used: \(rateLimit.actionsUsed))", category: .api)
                break
            }

            print("📦 [ARCHIVE-ALL] Archiving \(index + 1)/\(ids.count): \(mediaId)")
            let success = (try? await instagram.archivePhoto(mediaId: mediaId)) ?? false
            print("📦 [ARCHIVE-ALL] Result for \(mediaId): \(success ? "✅ archived" : "❌ failed")")

            if success {
                await MainActor.run {
                    archiveAllProgress = index + 1
                    syncTrulyVisibleIds.removeAll { $0 == mediaId }
                    // Update local state so the photo disappears from the visible grid
                    if let photo = currentSet.photos.first(where: { $0.mediaId == mediaId }) {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: mediaId,
                            isArchived: true,
                            uploadStatus: .completed,
                            errorMessage: nil
                        )
                    }
                }
            } else {
                LogManager.shared.warning("Archive All: failed to archive \(mediaId)", category: .api)
            }
        }

        print("📦 [ARCHIVE-ALL] Finished — archived \(archiveAllProgress)/\(archiveAllTotal)")
        LogManager.shared.info("Archive All complete: \(archiveAllProgress)/\(archiveAllTotal)", category: .general)

        await MainActor.run {
            isArchivingAll = false
            archiveAllCompleted = true
        }
    }

    // MARK: - Re-verify All (detect local↔Instagram desync for archived photos)

    /// Fetches all VISIBLE media from Instagram in 1-2 API calls, then compares
    /// against local state. Much faster than checking 100+ photos one by one.
    private func startReverify() {
        let photos = allUploadedPhotos
        guard !photos.isEmpty, !uploadManager.isReverifying else { return }

        let photoSnapshots: [(id: UUID, mediaId: String, isArchived: Bool)] = photos.compactMap { p in
            guard let mid = p.mediaId else { return nil }
            return (p.id, mid, p.isArchived)
        }

        let manager = uploadManager
        let ig = instagram
        let dm = dataManager

        manager.reverifyTask?.cancel()
        manager.isReverifying = true
        manager.reverifyProgress = 0
        manager.reverifyTotal = photoSnapshots.count
        manager.reverifyDesynced = 0

        manager.reverifyTask = Task.detached(priority: .utility) {
            print("🔍 [RE-VERIFY] Fast mode: fetching all visible media from Instagram…")

            // Fetch all visible (non-archived) media IDs from Instagram feed.
            // Paginate to get the full list (each page ~18 items).
            var visibleOnIG: Set<String> = []
            var nextMaxId: String? = nil
            var page = 0

            do {
                repeat {
                    page += 1
                    let (items, cursor) = try await ig.getUserMedia(maxId: nextMaxId)
                    for item in items {
                        visibleOnIG.insert(item.id)
                    }
                    nextMaxId = cursor
                    print("🔍 [RE-VERIFY] Page \(page): got \(items.count) visible items (total: \(visibleOnIG.count))")
                    // Stop if page returned no items (avoid infinite pagination)
                    if items.isEmpty { break }
                    if nextMaxId != nil {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                } while nextMaxId != nil
            } catch {
                print("❌ [RE-VERIFY] Failed to fetch feed: \(error.localizedDescription)")
                await MainActor.run {
                    manager.isReverifying = false
                    manager.reverifyTask = nil
                }
                return
            }

            print("🔍 [RE-VERIFY] Instagram reports \(visibleOnIG.count) visible post(s) — comparing with \(photoSnapshots.count) local photo(s)")

            // Compare: if a photo is locally archived but appears in the visible feed → desync
            var desynced = 0
            for (index, snap) in photoSnapshots.enumerated() {
                let isVisibleOnIG = visibleOnIG.contains(snap.mediaId)

                if isVisibleOnIG && snap.isArchived {
                    await MainActor.run {
                        dm.updatePhoto(
                            photoId: snap.id,
                            mediaId: snap.mediaId,
                            isArchived: false,
                            uploadStatus: .completed,
                            errorMessage: nil
                        )
                    }
                    desynced += 1
                    print("⚠️ [RE-VERIFY] Desync: \(snap.mediaId) visible on IG but locally archived")
                    LogManager.shared.warning("Re-verify desync: \(snap.mediaId) is public on IG, fixed local state", category: .general)
                }

                await MainActor.run {
                    manager.reverifyProgress = index + 1
                    manager.reverifyDesynced = desynced
                }
            }

            await MainActor.run {
                manager.isReverifying = false
                manager.reverifyTask = nil
            }
            print("🔍 [RE-VERIFY] Done — \(desynced) desync(s) found out of \(photoSnapshots.count) photos (used \(page) API call(s))")
            if desynced > 0 {
                LogManager.shared.info("Re-verify: fixed \(desynced) desync(s) — S&A button should now appear", category: .general)
            } else {
                LogManager.shared.info("Re-verify: all \(photoSnapshots.count) photos confirmed archived (\(page) API calls)", category: .general)
            }
        }
    }

    // MARK: - Sync & Archive (unified, bot-safe)

    /// Single action that verifies visible photos then archives them without duplicate GETs.
    ///
    /// Phase 1 – VERIFY (GET only, 1.5s between each)
    ///   Determines which photos are truly public. Fixes desync locally.
    ///
    /// Pause – 8–15s randomised gap (simulates human reading results before acting)
    ///
    /// Phase 2 – ARCHIVE (POST only, skipPreCheck=true, cooldown 160–215s between)
    ///   Archives each confirmed-public photo without repeating the GET.
    private func syncThenArchiveAll() async {
        let photos = visibleUploadedPhotos
        guard !photos.isEmpty, !isSyncing, !isArchivingAll else {
            print("⚠️ [S&A] Already running or no photos")
            return
        }

        // Lock out auto re-archive for the duration
        await MainActor.run {
            uploadManager.isSyncArchiveActive = true
            isSyncing = true
            syncProgress = 0
            syncTotal = photos.count
            syncFixedCount = 0
            syncUnknownCount = 0
            syncTrulyVisibleIds = []
            syncCompleted = false
            archiveAllCompleted = false
            isPausingBeforeArchive = false
            saCountdownSeconds = 0
        }

        // ── PHASE 1: VERIFY ──────────────────────────────────────────────
        print("🔄 [S&A] Phase 1: verifying \(photos.count) photo(s)")
        LogManager.shared.info("State sync started: \(photos.count) visible photos to check", category: .general)

        var confirmedToArchive: [String] = []
        var fixed = 0
        var unknown = 0

        for (index, photo) in photos.enumerated() {
            guard let mediaId = photo.mediaId else {
                unknown += 1
                continue
            }

            if index > 0 {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s anti-bot gap
            }

            await MainActor.run { syncProgress = index + 1 }

            do {
                let result = try await instagram.getMediaIsArchived(mediaId: mediaId)
                switch result {
                case .some(true):
                    // Already archived on Instagram — fix local desync
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: mediaId,
                            isArchived: true,
                            uploadStatus: .completed,
                            errorMessage: nil
                        )
                        fixed += 1
                    }
                    LogManager.shared.info("State sync: fixed desync for \(mediaId)", category: .general)

                case .some(false):
                    // Truly public — queue for archive
                    confirmedToArchive.append(mediaId)
                    LogManager.shared.info("State sync: \(mediaId) confirmed public on Instagram", category: .general)

                case .none:
                    unknown += 1
                    LogManager.shared.warning("State sync: could not determine state for \(mediaId)", category: .general)
                }
            } catch {
                // Session error — abort entirely
                LogManager.shared.warning("S&A sync aborted: session error — \(error.localizedDescription)", category: .api)
                UploadManager.shared.sendSessionExpiredNotification()
                await MainActor.run {
                    isSyncing = false
                    uploadManager.isSyncArchiveActive = false
                }
                return
            }
        }

        let syncSummary = "fixed=\(fixed), toArchive=\(confirmedToArchive.count), unknown=\(unknown)"
        print("🔄 [S&A] Phase 1 done — \(syncSummary)")
        LogManager.shared.info("State sync complete: \(syncSummary)", category: .general)

        await MainActor.run {
            syncFixedCount = fixed
            syncUnknownCount = unknown
            syncTrulyVisibleIds = confirmedToArchive
            isSyncing = false
            syncCompleted = true
        }

        // If nothing to archive, finish here
        guard !confirmedToArchive.isEmpty else {
            await MainActor.run { uploadManager.isSyncArchiveActive = false }
            if fixed > 0 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { syncCompleted = false }
            }
            return
        }

        // ── PHASE 2: ARCHIVE ──────────────────────────────────────────────
        print("📦 [S&A] Phase 2: archiving \(confirmedToArchive.count) photo(s) (no pre-check GET)")
        LogManager.shared.info("Archive All started: \(confirmedToArchive.count) photo(s)", category: .general)

        await MainActor.run {
            isArchivingAll = true
            archiveAllProgress = 0
            archiveAllTotal = confirmedToArchive.count
        }

        var archived = 0
        for (index, mediaId) in confirmedToArchive.enumerated() {
            // Rate limit guard
            let rateLimit = instagram.checkRateLimit()
            if rateLimit.limited || rateLimit.remaining < 2 {
                LogManager.shared.warning("S&A archive stopped: rate limit (used: \(rateLimit.actionsUsed))", category: .api)
                break
            }

            print("📦 [S&A] Archiving \(index + 1)/\(confirmedToArchive.count): \(mediaId)")

            // skipPreCheck=true — we already verified in Phase 1, no duplicate GET.
            // Retry once on failure (network hiccups are common).
            var success = (try? await instagram.archivePhoto(mediaId: mediaId, skipPreCheck: true)) ?? false
            if !success {
                print("⚠️ [S&A] First attempt failed for \(mediaId) — retrying in 5s…")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                success = (try? await instagram.archivePhoto(mediaId: mediaId, skipPreCheck: true)) ?? false
            }

            if success {
                archived += 1
                await MainActor.run {
                    archiveAllProgress = archived
                    syncTrulyVisibleIds.removeAll { $0 == mediaId }
                    if let photo = currentSet.photos.first(where: { $0.mediaId == mediaId }) {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: mediaId,
                            isArchived: true,
                            uploadStatus: .completed,
                            errorMessage: nil
                        )
                    }
                }
            } else {
                LogManager.shared.warning("S&A: failed to archive \(mediaId) after retry", category: .api)
            }

            // Cooldown between archives (skip after last one)
            if index < confirmedToArchive.count - 1 {
                let cooldownMs = Int.random(in: 1500...3000)
                let cooldownSec = max(1, cooldownMs / 1000)
                print("⏳ [S&A] Cooldown \(cooldownMs)ms before next archive...")
                LogManager.shared.info("Cooldown: \(cooldownMs)ms until next archive", category: .upload)
                await MainActor.run { saCountdownSeconds = cooldownSec }
                try? await Task.sleep(nanoseconds: UInt64(cooldownMs) * 1_000_000)
                await MainActor.run { saCountdownSeconds = 0 }
            }
        }

        print("📦 [S&A] Done — \(archived)/\(confirmedToArchive.count) archived")
        LogManager.shared.info("Archive All complete: \(archived)/\(confirmedToArchive.count)", category: .general)

        await MainActor.run {
            isArchivingAll = false
            archiveAllCompleted = true
            uploadManager.isSyncArchiveActive = false
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: VaultTheme.Spacing.xl) {
            StatCard(title: "Total", value: "\(currentSet.totalPhotos)", icon: "photo.stack")
            
            // Only show "Uploaded" when logged in
            if instagram.isLoggedIn {
                StatCard(title: "Uploaded", value: "\(currentSet.uploadedPhotos)", icon: "arrow.up.circle")
            }
            
            if !currentSet.banks.isEmpty {
                StatCard(title: "Banks", value: "\(currentSet.banks.count)", icon: "square.stack.3d.up")
            }
        }
    }
    
    // MARK: - Status Section (Enhanced - Single Source of Truth)
    
    private var isThisSetActive: Bool {
        uploadManager.activeSetId == currentSet.id
    }
    
    private var statusSection: some View {
        VStack(spacing: 16) {
            if instagram.isLoggedIn {
                if isThisSetActive {
                    // === THIS SET is the active upload set ===
                    
                    // Status icon + text
                    HStack(spacing: 8) {
                        Image(systemName: uploadManager.uploadPhase.icon)
                            .font(.title3)
                        Text(uploadManager.currentPhaseDescription.isEmpty ? phaseDefaultText : uploadManager.currentPhaseDescription)
                            .font(.headline)
                    }
                    .foregroundColor(uploadManager.uploadPhase.borderColor)
                    
                    // COUNTDOWN DISPLAY (per phase)
                    phaseCountdownView
                    
                    // Progress bar (visible for ALL active phases + paused)
                    if uploadManager.uploadProgress.total > 0 && uploadManager.isActive {
                        VStack(spacing: VaultTheme.Spacing.sm) {
                            ProgressView(value: Double(uploadManager.uploadProgress.current), total: Double(max(uploadManager.uploadProgress.total, 1)))
                                .tint(uploadManager.hasError ? VaultTheme.Colors.error : VaultTheme.Colors.warning)
                            
                            progressText
                        }
                    }
                    
                    // Action buttons
                    actionButtons
                    
                } else if uploadManager.activeSetId != nil {
                    // === ANOTHER set is uploading ===
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                        Text("Another set is currently uploading")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                    
                } else {
                    // === No upload active — show Start button if there are pending photos ===
                    if currentSet.photos.contains(where: { $0.mediaId == nil }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Ready to upload")
                                .font(.headline)
                        }
                        .foregroundColor(.green)
                        
                        actionButtons
                    } else if currentSet.status == .completed {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Upload Completed")
                                .font(.headline)
                        }
                        .foregroundColor(.green)
                        
                        quickActionsSection
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.title3)
                            Text("Photo Collection")
                                .font(.headline)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            } else {
                // When not logged in, show generic info
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text("Photo Collection")
                        .font(.headline)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .strokeBorder(isThisSetActive ? uploadManager.uploadPhase.borderColor : Color.clear, lineWidth: 2)
        )
    }
    
    // MARK: - Phase Default Text
    private var phaseDefaultText: String {
        switch uploadManager.uploadPhase {
        case .idle: return "Ready to upload"
        case .uploading(let n): return "Uploading photo #\(n) of \(uploadManager.uploadProgress.total)"
        case .archiving(let n): return "Archiving photo #\(n)..."
        case .waiting(let next, let secs): return "Next photo in \(secs / 60):\(String(format: "%02d", secs % 60))"
        case .cooldown(let secs): return "Cooldown \(secs / 60):\(String(format: "%02d", secs % 60))"
        case .autoRetrying(let secs, let att): return "Retrying in \(secs / 60):\(String(format: "%02d", secs % 60)) (attempt \(att)/3)"
        case .waitingNetwork(let att): return "Waiting for connection... (attempt \(att)/3)"
        case .paused: return "Upload Paused"
        case .escalatedPause(let secs): return "Cooling down \(secs / 60):\(String(format: "%02d", secs % 60))"
        case .botLockdown(let secs): return "Locked \(secs / 60):\(String(format: "%02d", secs % 60))"
        case .sessionExpired: return "Session Expired"
        case .completed: return "Upload Completed"
        }
    }
    
    // MARK: - Phase Countdown View
    @ViewBuilder
    private var phaseCountdownView: some View {
        switch uploadManager.uploadPhase {
        case .waiting(_, let seconds) where seconds > 0:
            countdownDisplay(seconds: seconds, color: .orange, label: "Next photo in")
        case .cooldown(let seconds) where seconds > 0:
            countdownDisplay(seconds: seconds, color: .orange, label: "Cooldown remaining")
        case .autoRetrying(let seconds, let attempt) where seconds > 0:
            VStack(spacing: 8) {
                countdownDisplay(seconds: seconds, color: .orange, label: "Auto-retrying in")
                Text("Attempt \(attempt) of 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .waitingNetwork(let attempt):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.yellow)
                    Text("Waiting for connection...")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                }
                Text("Attempt \(attempt) of 3 - Will retry automatically")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
        case .escalatedPause(let seconds) where seconds > 0:
            VStack(spacing: 8) {
                countdownDisplay(seconds: seconds, color: .red, label: "Multiple errors - Cooling down")
                Text("Upload will resume automatically after this wait")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .botLockdown(let seconds) where seconds > 0:
            countdownDisplay(seconds: seconds, color: .red, label: "Lockdown - Wait")
        case .sessionExpired:
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text("Session Expired")
                    .font(.headline)
                    .foregroundColor(.red)
                Text("Go to Settings and re-login to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
        default:
            EmptyView()
        }
    }
    
    // MARK: - Status Section Helpers
    
    private func countdownDisplay(seconds: Int, color: Color, label: String) -> some View {
        VStack(spacing: 8) {
            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var progressText: some View {
        Group {
            if case .waiting(let nextPhoto, let seconds) = uploadManager.uploadPhase {
                Text("\(uploadManager.uploadProgress.current)/\(uploadManager.uploadProgress.total) completed - Waiting \(seconds / 60):\(String(format: "%02d", seconds % 60)) for photo #\(nextPhoto)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(uploadManager.uploadProgress.current) / \(uploadManager.uploadProgress.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if isThisSetActive {
            // This set is the active upload set — show phase-based buttons
            switch uploadManager.uploadPhase {
            case .uploading, .archiving, .waiting:
                // Pausable phases
                Button(action: togglePause) {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(VaultTheme.Colors.warning)
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            case .cooldown, .autoRetrying, .waitingNetwork:
                // Auto-managed phases — no button (system handles it)
                EmptyView()
            case .paused:
                // Paused — show Resume
                Button(action: resumeUpload) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(VaultTheme.Colors.success)
                        .cornerRadius(VaultTheme.CornerRadius.md)
                }
            case .escalatedPause(let seconds):
                // Escalated pause — disabled with countdown
                if seconds > 0 {
                    Label("Resume in \(seconds / 60):\(String(format: "%02d", seconds % 60))", systemImage: "clock.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(VaultTheme.CornerRadius.md)
                } else {
                    Button(action: resumeUpload) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(VaultTheme.Colors.success)
                            .cornerRadius(VaultTheme.CornerRadius.md)
                    }
                }
            case .botLockdown(let seconds):
                // Bot lockdown — disabled with countdown
                if seconds > 0 {
                    Label("Locked \(seconds / 60):\(String(format: "%02d", seconds % 60))", systemImage: "lock.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(VaultTheme.CornerRadius.md)
                } else {
                    Button(action: resumeUpload) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(VaultTheme.Colors.success)
                            .cornerRadius(VaultTheme.CornerRadius.md)
                    }
                }
            case .sessionExpired:
                // Session expired — cannot resume
                Label("Re-login Required", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(VaultTheme.CornerRadius.md)
            case .completed:
                quickActionsSection
            case .idle:
                // Shouldn't happen for an active set, but handle gracefully
                EmptyView()
            }
        } else {
            // No active upload or this set isn't active — show Start if pending photos exist
            if currentSet.photos.contains(where: { $0.mediaId == nil }) && uploadManager.activeSetId == nil {
                Button(action: startUpload) {
                    Label("Start Upload", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(VaultTheme.Colors.success)
                        .cornerRadius(VaultTheme.CornerRadius.md)
                }
                .disabled(uploadManager.isActive || uploadManager.activeTask != nil)
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Reveal All Archived
                Button(action: revealAllArchived) {
                    VStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .font(.title2)
                        Text("Reveal All")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VaultTheme.Colors.success.opacity(0.15))
                    .foregroundColor(VaultTheme.Colors.success)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
                
                // Hide All Visible
                Button(action: hideAllVisible) {
                    VStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .font(.title2)
                        Text("Hide All")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VaultTheme.Colors.warning.opacity(0.15))
                    .foregroundColor(VaultTheme.Colors.warning)
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
            
            Text("\(archivedCount) archived • \(visibleCount) visible")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var archivedCount: Int {
        currentSet.photos.filter { $0.isArchived && $0.mediaId != nil }.count
    }
    
    private var visibleCount: Int {
        currentSet.photos.filter { !$0.isArchived && $0.mediaId != nil }.count
    }
    
    // MARK: - Banks Tabs
    
    private var banksTabsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VaultTheme.Spacing.md) {
                ForEach(currentSet.banks.indices, id: \.self) { index in
                    Button(action: { selectedBankIndex = index }) {
                        Text(currentSet.banks[index].name)
                            .font(.subheadline.weight(selectedBankIndex == index ? .bold : .regular))
                            .foregroundColor(selectedBankIndex == index ? .white : VaultTheme.Colors.primary)
                            .padding(.horizontal, VaultTheme.Spacing.lg)
                            .padding(.vertical, VaultTheme.Spacing.sm)
                            .background(selectedBankIndex == index ? VaultTheme.Colors.primary : VaultTheme.Colors.primary.opacity(0.1))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                    }
                }
            }
        }
    }
    
    // MARK: - Error Recovery Sections
    
    private var photoRejectedRecoverySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundColor(.orange)
                Text("Photo Rejected")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            if let failedIndex = uploadManager.failedPhotoIndex {
                Text("Photo #\(failedIndex + 1) was rejected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    Task { await skipFailedPhotoAndContinue() }
                }) {
                    Label("Skip Photo", systemImage: "forward.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(VaultTheme.Colors.warning)
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                }
                
                Button(action: {
                    // TODO: Implement photo replacement
                    resetErrorState()
                }) {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(VaultTheme.Colors.primary)
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
        }
        .padding(VaultTheme.Spacing.lg)
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(VaultTheme.CornerRadius.md)
    }
    
    // MARK: - Reorder Toggle Button
    
    @ViewBuilder
    private var reorderToggleButton: some View {
        if isReorderMode {
            Button(action: {
                withAnimation {
                    isReorderMode = false
                    selectedReorderIndex = nil
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done Reordering")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, VaultTheme.Spacing.lg)
                .padding(.vertical, 10)
                .background(VaultTheme.Colors.success)
                .cornerRadius(VaultTheme.CornerRadius.sm)
            }
            .disabled(!consecutiveDuplicates.isEmpty)
            .opacity(consecutiveDuplicates.isEmpty ? 1.0 : 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let hasPending = currentSet.photos.contains(where: { $0.uploadStatus == .pending || $0.uploadStatus == .error })
            if hasPending {
                Button(action: {
                    withAnimation { isReorderMode = true }
                    checkConsecutiveDuplicates()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("Reorder Photos")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(VaultTheme.Colors.primary)
                    .padding(.horizontal, VaultTheme.Spacing.lg)
                    .padding(.vertical, VaultTheme.Spacing.sm)
                    .background(VaultTheme.Colors.primary.opacity(0.1))
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Photos Grid
    
    private var photosGridSection: some View {
        let photosToShow = currentSet.banks.isEmpty 
            ? currentSet.photos 
            : dataManager.getPhotosForBank(setId: currentSet.id, bankId: currentSet.banks[selectedBankIndex].id)
        
        if isReorderMode {
            return AnyView(reorderableGrid(photos: photosToShow))
        } else if (currentSet.type == .word || currentSet.type == .number) && currentSet.expectedPhotosPerBank > 0 {
            return AnyView(slotBasedGrid(photos: photosToShow))
        } else {
            return AnyView(normalGrid(photos: photosToShow))
        }
    }
    
    // MARK: - Slot-Based Grid (Word/Number Reveal)
    
    private func slotBasedGrid(photos: [SetPhoto]) -> some View {
        let labels = currentSet.slotLabels
        let photosBySymbol = Dictionary(grouping: photos, by: { $0.symbol })
        
        return VStack(spacing: 12) {
            // Summary
            let filled = labels.filter { photosBySymbol[$0] != nil }.count
            let total = labels.count
            
            HStack(spacing: 8) {
                Image(systemName: filled == total ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundColor(filled == total ? .green : .orange)
                Text("\(filled)/\(total) slots filled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if filled < total {
                    Text("(\(total - filled) missing)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            if isProcessingSlotPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing photo...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if let photos = photosBySymbol[label], let photo = photos.first {
                        // FILLED SLOT: show photo with symbol label
                        filledSlotView(photo: photo, label: label, position: index + 1)
                    } else {
                        // EMPTY SLOT: tappable placeholder to add photo
                        emptySlotView(label: label, position: index + 1)
                    }
                }
            }
        }
    }
    
    private func filledSlotView(photo: SetPhoto, label: String, position: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(10)
                        .opacity(photo.isArchived ? 0.4 : 1.0)
                        .overlay(
                            // Overlay oscuro cuando está archivado
                            photo.isArchived ? 
                                Color.black.opacity(0.3)
                                    .cornerRadius(10)
                                : nil
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                // Symbol label badge (top-left)
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(VaultTheme.Colors.primary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -3, y: -3)
                
                // Upload status badge (top-right) - only when logged in
                if instagram.isLoggedIn {
                    uploadStatusBadge(for: photo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: 100, height: 100)
            .contextMenu {
                Button(role: .destructive) {
                    deleteTargetSymbol = label
                    showDeleteConfirm = true
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
                
                // Replace from gallery
                Button {
                    targetSlotSymbol = label
                    // PhotosPicker will trigger automatically
                } label: {
                    Label("Replace from Gallery", systemImage: "photo.on.rectangle")
                }
                
                // Replace from archived (only when logged in)
                if instagram.isLoggedIn {
                    Button {
                        archivedPickerTargetSymbol = label
                        showArchivedPicker = true
                    } label: {
                        Label("Replace from Archived", systemImage: "archivebox")
                    }
                }
            }
            
            // Status text below photo (only when logged in)
            if instagram.isLoggedIn {
                statusTextView(for: photo)
            }
        }
    }
    
    private func emptySlotView(label: String, position: Int) -> some View {
        Button(action: {
            slotSourcePickerSymbol = label
            showSlotSourcePicker = true
        }) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundColor(VaultTheme.Colors.primary.opacity(0.4))
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(VaultTheme.Colors.primary.opacity(0.05))
                        )
                    
                    VStack(spacing: 6) {
                        // Symbol label
                        Text(label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(VaultTheme.Colors.primary.opacity(0.6))
                        
                        // Plus icon
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(VaultTheme.Colors.primary.opacity(0.5))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func uploadStatusBadge(for photo: SetPhoto) -> some View {
        switch photo.uploadStatus {
        case .completed:
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        case .error:
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        case .uploading, .archiving, .uploaded:
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(.white)
            }
        case .pending:
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 20, height: 20)
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private func statusTextView(for photo: SetPhoto) -> some View {
        switch photo.uploadStatus {
        case .pending:
            Text("Pending")
                .font(.caption2)
                .foregroundColor(.orange)
        case .uploading:
            Text("Uploading...")
                .font(.caption2)
                .foregroundColor(.blue)
        case .uploaded:
            Text("Archiving...")
                .font(.caption2)
                .foregroundColor(VaultTheme.Colors.primary)
        case .archiving:
            Text("Archiving...")
                .font(.caption2)
                .foregroundColor(VaultTheme.Colors.primary)
        case .completed:
            if photo.isArchived {
                Text("Archived")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Text("Visible")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        case .error:
            Text("Error")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private func uploadStatusDot(for photo: SetPhoto) -> some View {
        switch photo.uploadStatus {
        case .completed:
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                )
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                )
        case .uploading, .archiving, .uploaded:
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
                .overlay(
                    ProgressView()
                        .scaleEffect(0.4)
                )
        case .pending:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 12, height: 12)
        }
    }
    
    // MARK: - Load Photo for Specific Slot
    
    private func loadPhotoForSlot(item: PhotosPickerItem, symbol: String) {
        isProcessingSlotPhoto = true
        
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { isProcessingSlotPhoto = false }
                return
            }
            
            // Apply same compression pipeline as CreateSetView
            let validImageData = InstagramService.adjustImageAspectRatio(imageData: data)
            let optimizedImageData = InstagramService.compressImageForUpload(imageData: validImageData, photoIndex: 0)
            
            let filename = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
            
            // Check if slot already has a photo (replace) or is empty (insert)
            let existingPhotos = currentSet.photos.filter { $0.symbol == symbol }
            
            await MainActor.run {
                if !existingPhotos.isEmpty {
                    // Replace existing
                    dataManager.replacePhotoAtSymbol(
                        setId: currentSet.id,
                        symbol: symbol,
                        newFilename: filename,
                        newImageData: optimizedImageData
                    )
                } else {
                    // Insert new
                    let labels = currentSet.slotLabels
                    let position = labels.firstIndex(of: symbol) ?? labels.count
                    dataManager.insertPhotoAtPosition(
                        setId: currentSet.id,
                        symbol: symbol,
                        filename: filename,
                        imageData: optimizedImageData,
                        position: position
                    )
                }
                
                slotPickerItem = nil
                targetSlotSymbol = nil
                isProcessingSlotPhoto = false
                showGalleryPickerSheet = false
            }
        }
    }
    
    // MARK: - Gallery Picker Sheet (for slot tap flow)
    
    private func galleryPickerSheetView(symbol: String) -> some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Select a photo for \"\(symbol)\"")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                
                PhotosPicker(
                    selection: $slotPickerItem,
                    matching: .images
                ) {
                    Label("Choose from Gallery", systemImage: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(VaultTheme.Colors.primary)
                        .cornerRadius(VaultTheme.CornerRadius.md)
                }
                
                Spacer()
            }
            .padding()
            .background(VaultTheme.Colors.background)
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        slotPickerItem = nil
                        targetSlotSymbol = nil
                        showGalleryPickerSheet = false
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    // MARK: - Map Archived Photo to Slot
    
    private func mapArchivedPhotoToSlot(archivedPhoto: ArchivedPhoto, symbol: String) {
        isProcessingSlotPhoto = true
        
        Task {
            do {
                // Download the full image from Instagram
                guard let url = URL(string: archivedPhoto.imageURL) else {
                    throw InstagramError.invalidURL
                }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                
                // Apply same compression pipeline
                let validImageData = InstagramService.adjustImageAspectRatio(imageData: data)
                let optimizedImageData = InstagramService.compressImageForUpload(imageData: validImageData, photoIndex: 0)
                
                let filename = "archived_\(archivedPhoto.mediaId)"
                
                // Check if slot already has a photo (replace) or is empty (insert)
                let existingPhotos = currentSet.photos.filter { $0.symbol == symbol }
                
                await MainActor.run {
                    if !existingPhotos.isEmpty {
                        // Replace existing photo
                        dataManager.replacePhotoAtSymbol(
                            setId: currentSet.id,
                            symbol: symbol,
                            newFilename: filename,
                            newImageData: optimizedImageData
                        )
                        
                        // Update with archived metadata
                        if let updatedPhoto = currentSet.photos.first(where: { $0.symbol == symbol }) {
                            dataManager.updatePhoto(
                                photoId: updatedPhoto.id,
                                mediaId: archivedPhoto.mediaId,
                                isArchived: true,
                                uploadStatus: .completed,
                                errorMessage: nil,
                                uploadDate: archivedPhoto.timestamp
                            )
                        }
                    } else {
                        // Insert new photo
                        let labels = currentSet.slotLabels
                        let position = labels.firstIndex(of: symbol) ?? labels.count
                        dataManager.insertPhotoAtPosition(
                            setId: currentSet.id,
                            symbol: symbol,
                            filename: filename,
                            imageData: optimizedImageData,
                            position: position
                        )
                        
                        // Update with archived metadata
                        if let newPhoto = currentSet.photos.first(where: { $0.symbol == symbol }) {
                            dataManager.updatePhoto(
                                photoId: newPhoto.id,
                                mediaId: archivedPhoto.mediaId,
                                isArchived: true,
                                uploadStatus: .completed,
                                errorMessage: nil,
                                uploadDate: archivedPhoto.timestamp
                            )
                        }
                    }
                    
                    isProcessingSlotPhoto = false
                    LogManager.shared.success("Mapped archived photo (ID: \(archivedPhoto.mediaId)) to slot '\(symbol)'", category: .general)
                    
                    // Auto-complete set if all photos have mediaId and are archived
                    let allPhotosReady = currentSet.photos.allSatisfy { $0.mediaId != nil && $0.uploadStatus == .completed }
                    if allPhotosReady && currentSet.status != .completed {
                        dataManager.updateSetStatus(id: currentSet.id, status: .completed)
                        LogManager.shared.success("Set '\(currentSet.name)' auto-completed (all photos mapped from archived)", category: .general)
                    }
                }
                
            } catch {
                await MainActor.run {
                    isProcessingSlotPhoto = false
                    LogManager.shared.error("Failed to map archived photo: \(error.localizedDescription)", category: .general)
                }
            }
        }
    }
    
    private func normalGrid(photos: [SetPhoto]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                PhotoItemView(
                    photo: photo,
                    setId: currentSet.id,
                    position: index + 1
                )
            }
        }
    }
    
    private func reorderableGrid(photos: [SetPhoto]) -> some View {
        VStack(spacing: 12) {
            // Instructions
            HStack(spacing: VaultTheme.Spacing.sm) {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(VaultTheme.Colors.primary)
                if selectedReorderIndex != nil {
                    Text("Now tap the photo to swap with")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.primary)
                        .fontWeight(.semibold)
                } else {
                    Text("Tap a photo, then tap another to swap them")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Warning for consecutive duplicates
            if !consecutiveDuplicates.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Identical photos next to each other will trigger bot detection. Reorder to fix.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    let isUploaded = photo.uploadStatus == .completed || photo.uploadStatus == .uploaded || photo.uploadStatus == .archiving
                    let isDup = consecutiveDuplicates.contains(index)
                    let isSelected = selectedReorderIndex == index
                    
                    TapToSwapPhotoCell(
                        photo: photo,
                        position: index + 1,
                        isDuplicate: isDup,
                        isLocked: isUploaded,
                        isSelected: isSelected
                    )
                    .onTapGesture {
                        handleReorderTap(index: index, isLocked: isUploaded)
                    }
                }
            }
        }
    }
    
    private func handleReorderTap(index: Int, isLocked: Bool) {
        guard !isLocked else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            return
        }
        
        if let fromIndex = selectedReorderIndex {
            if fromIndex == index {
                // Tapped same photo: deselect
                withAnimation(.spring(response: 0.3)) {
                    selectedReorderIndex = nil
                }
                return
            }
            
            // SWAP: Exchange positions directly (A goes to B, B goes to A)
            let bankId = currentSet.banks.isEmpty ? nil : currentSet.banks[selectedBankIndex].id
            
            withAnimation(.spring(response: 0.3)) {
                dataManager.swapPhotos(setId: currentSet.id, bankId: bankId, indexA: fromIndex, indexB: index)
                selectedReorderIndex = nil
            }
            
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                checkConsecutiveDuplicates()
            }
        } else {
            // First tap: select photo
            withAnimation(.spring(response: 0.3)) {
                selectedReorderIndex = index
            }
            
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    // MARK: - Duplicate Detection
    
    private func checkConsecutiveDuplicates() {
        let photosToCheck = currentSet.banks.isEmpty
            ? currentSet.photos
            : dataManager.getPhotosForBank(setId: currentSet.id, bankId: currentSet.banks[selectedBankIndex].id)
        
        consecutiveDuplicates.removeAll()
        guard photosToCheck.count >= 2 else { return }
        
        for i in 0..<(photosToCheck.count - 1) {
            guard let data1 = photosToCheck[i].imageData,
                  let data2 = photosToCheck[i + 1].imageData else { continue }
            
            let hash1 = SHA256.hash(data: data1).compactMap { String(format: "%02x", $0) }.joined()
            let hash2 = SHA256.hash(data: data2).compactMap { String(format: "%02x", $0) }.joined()
            
            if hash1 == hash2 {
                consecutiveDuplicates.insert(i)
                consecutiveDuplicates.insert(i + 1)
            }
        }
    }
    
    // MARK: - Upload Controls
    
    private func startUpload() {
        // Guard against double-launch: rapid double-tap or duplicate SwiftUI renders
        guard uploadManager.activeTask == nil, !uploadManager.isActive else {
            print("⚠️ [UPLOAD] Ignored duplicate startUpload() call — already active (phase: \(uploadManager.uploadPhase))")
            return
        }

        // Safe to reset: no active task exists at this point
        uploadManager.resetAllState()

        uploadManager.activeSetId = currentSet.id
        uploadManager.requestPause = false
        uploadManager.uploadPhase = .uploading(photoNumber: 1)
        uploadManager.currentPhaseDescription = "Starting upload..."

        let task = Task {
            await uploadAllPhotos()
        }
        uploadManager.activeTask = task
    }
    
    private func togglePause() {
        // Signal the upload loop to pause at the next safe point
        uploadManager.requestPause = true
        print("⏸️ [UPLOAD] User requested pause")
    }
    
    private func resumeUpload() {
        resetErrorState()
        uploadManager.requestPause = false
        uploadManager.invalidateAllTimers()
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        
        // Update phase immediately
        uploadManager.uploadPhase = .uploading(photoNumber: (uploadManager.failedPhotoIndex ?? 0) + 1)
        uploadManager.currentPhaseDescription = "Resuming upload..."
        
        // If we have a failed photo index, resume from there
        let startIndex = uploadManager.failedPhotoIndex ?? 0
        uploadManager.failedPhotoIndex = nil
        
        let task = Task {
            await uploadAllPhotos(startFrom: startIndex)
        }
        uploadManager.activeTask = task
    }
    
    private func retryFromFailedPhoto() async {
        guard let startIndex = uploadManager.failedPhotoIndex else {
            print("⚠️ [RETRY] No failed photo index found")
            return
        }
        
        print("🔄 [RETRY] Retrying from photo #\(startIndex + 1)")
        resetErrorState()
        await uploadAllPhotos(startFrom: startIndex)
    }
    
    private func skipFailedPhotoAndContinue() async {
        guard let skipIndex = uploadManager.failedPhotoIndex else {
            print("⚠️ [SKIP] No failed photo index found")
            return
        }
        
        print("⏭️ [SKIP] Skipping photo #\(skipIndex + 1), continuing with next")
        
        // Mark skipped photo as permanently skipped
        let skippedPhoto = currentSet.photos[skipIndex]
        dataManager.updatePhoto(photoId: skippedPhoto.id, mediaId: nil, uploadStatus: .error, errorMessage: "Skipped by user")
        
        resetErrorState()
        uploadManager.requestPause = false
        uploadManager.uploadPhase = .uploading(photoNumber: skipIndex + 2)
        uploadManager.currentPhaseDescription = "Resuming after skip..."
        
        // Continue from next photo
        await uploadAllPhotos(startFrom: skipIndex + 1)
    }
    
    private func resetErrorState() {
        uploadManager.resetErrorState()
    }
    
    // Helper: Check if error is network-related (retryable)
    private func isNetworkRelatedError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        let nsError = error as NSError
        
        // Check NSURLError codes
        if nsError.domain == NSURLErrorDomain {
            let networkErrorCodes: [Int] = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorCallIsActive,
                NSURLErrorDataNotAllowed
            ]
            if networkErrorCodes.contains(nsError.code) {
                return true
            }
        }
        
        // Check description keywords
        return description.contains("timeout") ||
               description.contains("network") ||
               description.contains("connection") ||
               description.contains("offline") ||
               description.contains("no internet") ||
               description.contains("unreachable")
    }
    
    // Helper: Check if pause was requested and handle it
    private func checkPauseRequested(atPhotoIndex index: Int) async -> Bool {
        if uploadManager.requestPause {
            print("⏸️ [UPLOAD] Pause requested by user")
            await MainActor.run {
                uploadManager.requestPause = false
                UIApplication.shared.isIdleTimerDisabled = false
                uploadManager.invalidateAllTimers()
                uploadManager.failedPhotoIndex = index
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = "Upload Paused"
                dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                uploadManager.activeTask = nil
            }
            return true
        }
        return false
    }
    
    private func uploadAllPhotos(startFrom: Int = 0) async {
        print("🚀 [UPLOAD ALL] Starting upload process...")
        print("   Total photos to upload: \(currentSet.photos.count)")
        LogManager.shared.upload("Starting upload process for set '\(currentSet.name)' - \(currentSet.photos.count) photos")
        
        // CRITICAL: Keep screen awake during upload (prevent interruptions)
        await MainActor.run {
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔆 [SCREEN] Screen sleep DISABLED (Upload mode)")
            LogManager.shared.info("Screen sleep disabled for upload", category: .device)
        }
        
        // CRITICAL: Check if lockdown is active before starting
        if instagram.isLocked {
            print("🚨 [UPLOAD] Cannot start - lockdown is active")
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                uploadManager.showingError = "Instagram lockdown active. Cannot upload. Wait for lockdown to clear."
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = "Upload Paused - Lockdown Active"
                uploadManager.activeTask = nil
            }
            return
        }
        
        // CRITICAL: Check GLOBAL cooldown before starting (prevent switching sets to bypass cooldown)
        let (onCooldown, remainingCooldown) = instagram.isPhotoUploadOnCooldown()
        if onCooldown && startFrom == 0 {
            let minutes = remainingCooldown / 60
            let seconds = remainingCooldown % 60
            print("⏰ [UPLOAD] Global cooldown active: \(minutes)m \(seconds)s remaining")
            await waitWithCountdown(seconds: remainingCooldown, label: "Cooldown Active")
        }
        
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        
        // ANTI-BOT: Wait if network changed recently (before first upload)
        do {
            try await instagram.waitForNetworkStability()
        } catch {
            print("⚠️ [UPLOAD] Network stability check failed: \(error)")
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                dataManager.updateSetStatus(id: currentSet.id, status: .error)
                uploadManager.showingError = "Network error starting upload: \(error.localizedDescription)"
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = "Upload Paused - Network Error"
                uploadManager.activeTask = nil
            }
            return
        }
        
        // ── RESCUE PASS ──────────────────────────────────────────────────────────
        // Detect photos stuck in .archiving or .uploaded state (mediaId assigned but
        // isArchived == false). This happens when the app is interrupted during the
        // archive step (network change, crash, background kill). Without this pass
        // those photos are permanently skipped by the `mediaId == nil` filter below
        // and stay visually stuck as "archiving" with no recovery path.
        let stuckPhotos = currentSet.photos.filter {
            $0.mediaId != nil && !$0.isArchived &&
            ($0.uploadStatus == .archiving || $0.uploadStatus == .uploaded)
        }
        if !stuckPhotos.isEmpty {
            print("🔧 [RESCUE] Found \(stuckPhotos.count) photo(s) stuck mid-archive — retrying archive...")
            LogManager.shared.warning("Rescue pass: \(stuckPhotos.count) photo(s) stuck in archiving state", category: .upload)

            await MainActor.run {
                uploadManager.uploadPhase = .archiving(photoNumber: 0)
                uploadManager.currentPhaseDescription = "Recovering interrupted archives…"
            }

            for stuckPhoto in stuckPhotos {
                guard let mediaId = stuckPhoto.mediaId else { continue }

                // Check lockdown / pause before each rescue archive
                if instagram.isLocked { break }
                if await checkPauseRequested(atPhotoIndex: 0) { return }

                print("🔧 [RESCUE] Retrying archive for photo \(stuckPhoto.symbol) (ID: \(mediaId))")

                // Human-like delay before archive call (same range as normal flow)
                let waitSeconds = Double.random(in: 5...10)
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))

                do {
                    let archived = try await instagram.archivePhoto(mediaId: mediaId)
                    if archived {
                        dataManager.updatePhoto(photoId: stuckPhoto.id, mediaId: mediaId,
                                                isArchived: true, uploadStatus: .completed, errorMessage: nil)
                        print("✅ [RESCUE] Archived \(stuckPhoto.symbol) (ID: \(mediaId))")
                        LogManager.shared.success("Rescue archive OK (ID: \(mediaId))", category: .upload)
                    } else {
                        // Archive returned false — mark as error so the UI shows it as retryable
                        dataManager.updatePhoto(photoId: stuckPhoto.id, mediaId: mediaId,
                                                isArchived: false, uploadStatus: .error,
                                                errorMessage: "Archive failed (rescue pass)")
                        print("⚠️ [RESCUE] Archive returned false for \(stuckPhoto.symbol) — marked as error")
                    }
                } catch {
                    // Network or API error during rescue — mark as error rather than leaving stuck
                    dataManager.updatePhoto(photoId: stuckPhoto.id, mediaId: mediaId,
                                            isArchived: false, uploadStatus: .error,
                                            errorMessage: "Rescue archive error: \(error.localizedDescription)")
                    print("⚠️ [RESCUE] Archive error for \(stuckPhoto.symbol): \(error)")
                }
            }
            print("🔧 [RESCUE] Rescue pass complete")
        }
        // ─────────────────────────────────────────────────────────────────────────

        let allPhotosToUpload = currentSet.photos.filter { $0.mediaId == nil }

        // If retrying, start from failed photo index
        let photosToUpload = startFrom > 0 ? Array(allPhotosToUpload.dropFirst(startFrom)) : allPhotosToUpload
        
        let totalPhotos = allPhotosToUpload.count
        let alreadyUploaded = totalPhotos - photosToUpload.count
        await MainActor.run {
            uploadManager.uploadProgress = UploadManager.UploadProgressInfo(current: alreadyUploaded, total: totalPhotos)
        }
        
        print("   Photos needing upload: \(photosToUpload.count)")
        if startFrom > 0 {
            print("   🔄 [RETRY] Starting from photo #\(startFrom + 1) (skipping \(startFrom) already processed)")
        }
        
        // Reset consecutive retries at start
        await MainActor.run { uploadManager.consecutiveAutoRetries = 0 }
        
        for (relativeIndex, photo) in photosToUpload.enumerated() {
            let index = relativeIndex + startFrom
            
            // Check if pause requested
            if await checkPauseRequested(atPhotoIndex: index) { return }
            
            // CRITICAL: Check if lockdown is active (bot detection)
            if instagram.isLocked {
                print("🚨 [UPLOAD] Lockdown is active - STOPPING upload")
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = false
                    dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                    uploadManager.uploadPhase = .paused
                    uploadManager.currentPhaseDescription = "Upload Paused - Lockdown Active"
                    uploadManager.activeTask = nil
                }
                return
            }
            
            print("\n--- Photo \(index + 1)/\(totalPhotos) ---")
            print("   Symbol: \(photo.symbol)")
            print("   Filename: \(photo.filename)")
            
            guard let imageData = photo.imageData else {
                print("❌ [UPLOAD ALL] No imageData for photo \(photo.id)")
                continue
            }
            
            // ===== AUTO-RETRY LOOP FOR EACH PHOTO =====
            let maxRetries = 3
            var retryAttempt = 0
            var photoUploadSuccess = false
            
            while retryAttempt <= maxRetries && !photoUploadSuccess {
                // Check if pause requested between retries
                if await checkPauseRequested(atPhotoIndex: index) { return }
                
                // Update photo status: uploading
                dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .uploading, errorMessage: nil)
                
                // UPDATE PHASE: Uploading
                await MainActor.run {
                    uploadManager.uploadPhase = .uploading(photoNumber: index + 1)
                    uploadManager.currentPhaseDescription = retryAttempt > 0 
                        ? "Retrying photo #\(index + 1) (attempt \(retryAttempt + 1))"
                        : "Uploading photo #\(index + 1) of \(totalPhotos)"
                }
                
                do {
                    // ANTI-BOT: Allow duplicates for Word/Number Reveal sets
                    let allowDuplicates = (currentSet.type == .word || currentSet.type == .number)
                    let mediaId = try await instagram.uploadPhoto(
                        imageData: imageData,
                        caption: "",
                        allowDuplicates: allowDuplicates,
                        photoIndex: index
                    )
                    
                    if let mediaId = mediaId {
                        print("✅ [UPLOAD] Photo #\(index + 1) uploaded. Media ID: \(mediaId)")
                        
                        // Update status: uploaded (waiting for archive)
                        dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, uploadStatus: .uploaded, errorMessage: nil)
                        
                        // Wait before archiving (human-like delay)
                        let waitSeconds = Double.random(in: 5...10)
                        print("   Waiting \(String(format: "%.1f", waitSeconds))s before archive...")
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                        
                        // Check if pause requested during wait
                        if await checkPauseRequested(atPhotoIndex: index) { return }
                        
                        // Update status: archiving
                        dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, uploadStatus: .archiving, errorMessage: nil)
                        
                        // UPDATE PHASE: Archiving
                        await MainActor.run {
                            uploadManager.uploadPhase = .archiving(photoNumber: index + 1)
                            uploadManager.currentPhaseDescription = "Archiving photo #\(index + 1)..."
                        }
                        
                        // Archive
                        let archived = try await instagram.archivePhoto(mediaId: mediaId)
                        
                        if archived {
                            print("✅ [UPLOAD] Photo #\(index + 1) archived successfully")
                            dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, isArchived: true, uploadStatus: .completed, errorMessage: nil)
                            photoUploadSuccess = true
                            
                            // Reset consecutive retries on success
                            await MainActor.run { uploadManager.consecutiveAutoRetries = 0 }
                        } else {
                            print("❌ [UPLOAD] Archive failed for photo #\(index + 1)")
                            dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, isArchived: false, uploadStatus: .error, errorMessage: "Archive failed")
                            LogManager.shared.error("Archive failed for Photo #\(index + 1) (ID: \(mediaId))", category: .upload)
                            
                            // Treat archive failure as retryable
                            retryAttempt += 1
                            await MainActor.run { uploadManager.consecutiveAutoRetries += 1 }
                            
                            if retryAttempt > maxRetries || uploadManager.consecutiveAutoRetries >= maxRetries {
                                await handleEscalation(photoIndex: index)
                                return
                            }
                            
                            await autoRetryWait(seconds: 60, attempt: retryAttempt, photoInfo: "Photo #\(index + 1)")
                            continue
                        }
                    } else {
                        print("❌ [UPLOAD] Upload returned nil media ID for photo #\(index + 1)")
                        retryAttempt += 1
                        await MainActor.run { uploadManager.consecutiveAutoRetries += 1 }
                        
                        if retryAttempt > maxRetries || uploadManager.consecutiveAutoRetries >= maxRetries {
                            await handleEscalation(photoIndex: index)
                            return
                        }
                        
                        await autoRetryWait(seconds: 60, attempt: retryAttempt, photoInfo: "Photo #\(index + 1)")
                        continue
                    }
                    
                } catch {
                    print("❌ [UPLOAD] Error at Photo #\(index + 1): \(error)")
                    let photoInfo = "Photo #\(index + 1) (\(photo.symbol))"
                    let errorDescription = error.localizedDescription.lowercased()
                    
                    // ===== CLASSIFY ERROR =====
                    
                    // SESSION EXPIRED - STOP, prompt re-login (NOT bot lockdown)
                    let isSessionExpired = errorDescription.contains("session expired") ||
                                           errorDescription.contains("session invalid") ||
                                           errorDescription.contains("please login again") ||
                                           errorDescription.contains("login_required")

                    // BOT DETECTION - STOP, lockdown
                    // Note: login_required is intentionally excluded — it means session expired, not bot
                    let isBotError = errorDescription.contains("challenge") ||
                                     errorDescription.contains("spam") ||
                                     errorDescription.contains("checkpoint") ||
                                     errorDescription.contains("bot")
                    
                    // PHOTO REJECTED - STOP, offer skip
                    let isPhotoError = errorDescription.contains("aspect ratio") ||
                                       errorDescription.contains("invalid image") ||
                                       errorDescription.contains("file format")
                    
                    // COOLDOWN - auto-retry after wait
                    let isCooldownError = errorDescription.contains("please wait") && 
                                         (errorDescription.contains("before uploading") || errorDescription.contains("before upload") || errorDescription.contains("uploading another"))
                    
                    // NETWORK - auto-retry when connected
                    let isNetworkErr = isNetworkRelatedError(error) && !isBotError && !isSessionExpired
                    
                    // ===== HANDLE BY TYPE =====
                    
                    if isSessionExpired {
                        LogManager.shared.error("Session expired at \(photoInfo) - re-login required", category: .auth)
                        dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: "Session expired")
                        
                        await MainActor.run {
                            UIApplication.shared.isIdleTimerDisabled = false
                            uploadManager.failedPhotoIndex = index
                            uploadManager.uploadPhase = .sessionExpired
                            uploadManager.currentPhaseDescription = "Session Expired - Re-login Required"
                            dataManager.updateSetStatus(id: currentSet.id, status: .error)
                            uploadManager.activeTask = nil
                            uploadManager.sendSessionExpiredNotification()
                        }
                        return
                        
                    } else if isBotError {
                        LogManager.shared.bot("Bot detection triggered at \(photoInfo): \(error.localizedDescription)")
                        dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: "Bot detected")
                        
                        await MainActor.run {
                            UIApplication.shared.isIdleTimerDisabled = false
                            uploadManager.failedPhotoIndex = index
                            uploadManager.botDetectionTime = Date()
                            uploadManager.botCountdownSeconds = 900
                            
                            uploadManager.uploadPhase = .botLockdown(remainingSeconds: 900)
                            uploadManager.currentPhaseDescription = "Bot Detection - Account Locked"
                            
                            uploadManager.botCountdownTimer?.invalidate()
                            uploadManager.botCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                                guard let um = uploadManager else { return }
                                if um.botCountdownSeconds > 0 {
                                    um.botCountdownSeconds -= 1
                                    um.uploadPhase = .botLockdown(remainingSeconds: um.botCountdownSeconds)
                                    um.currentPhaseDescription = "Bot Detection - Account Locked"
                                } else {
                                    um.botCountdownTimer?.invalidate()
                                    um.botCountdownTimer = nil
                                    um.uploadPhase = .paused
                                    um.currentPhaseDescription = "Upload Paused - Ready to Resume"
                                }
                            }
                            
                            dataManager.updateSetStatus(id: currentSet.id, status: .error)
                            uploadManager.activeTask = nil
                        }
                        return
                        
                    } else if isPhotoError {
                        LogManager.shared.error("Photo rejected at \(photoInfo): \(error.localizedDescription)", category: .upload)
                        dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: "Photo rejected")
                        
                        await MainActor.run {
                            UIApplication.shared.isIdleTimerDisabled = false
                            uploadManager.failedPhotoIndex = index
                            uploadManager.isPhotoRejected = true
                            uploadManager.showingError = "Photo #\(index + 1) was rejected\n\nReason: \(error.localizedDescription)\n\nYou can skip this photo or replace it."
                            uploadManager.uploadPhase = .paused
                            uploadManager.currentPhaseDescription = "Upload Paused - Photo Rejected"
                            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                            uploadManager.activeTask = nil
                        }
                        return
                        
                    } else {
                        // ===== AUTO-RETRYABLE ERRORS (cooldown, network, generic) =====
                        retryAttempt += 1
                        await MainActor.run { uploadManager.consecutiveAutoRetries += 1 }
                        
                        LogManager.shared.warning("Auto-retryable error at \(photoInfo) (attempt \(retryAttempt)/\(maxRetries)): \(error.localizedDescription)", category: .upload)
                        dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .pending, errorMessage: "Retrying...")
                        
                        // Check if we've exceeded max retries → ESCALATE
                        if retryAttempt > maxRetries || uploadManager.consecutiveAutoRetries >= maxRetries {
                            LogManager.shared.error("Max auto-retries reached at \(photoInfo) - escalating to pause", category: .upload)
                            await handleEscalation(photoIndex: index)
                            return
                        }
                        
                        // AUTO-RETRY based on error type
                        if isCooldownError {
                            var waitSeconds = extractCooldownSeconds(from: errorDescription)
                            waitSeconds += 30
                            print("⏰ [AUTO-RETRY] Cooldown detected. Waiting \(waitSeconds)s then auto-retrying...")
                            LogManager.shared.info("Auto-retry: waiting \(waitSeconds)s for cooldown (attempt \(retryAttempt))", category: .upload)
                            
                            await autoRetryWait(seconds: waitSeconds, attempt: retryAttempt, photoInfo: photoInfo)
                            
                        } else if isNetworkErr {
                            print("🌐 [AUTO-RETRY] Network error. Waiting for connection...")
                            LogManager.shared.info("Auto-retry: waiting for network (attempt \(retryAttempt))", category: .upload)
                            
                            await MainActor.run {
                                uploadManager.uploadPhase = .waitingNetwork(attempt: retryAttempt)
                                uploadManager.currentPhaseDescription = "Waiting for connection..."
                            }
                            
                            // Wait up to 120s for network
                            var networkWait = 0
                            while networkWait < 120 {
                                if uploadManager.requestPause {
                                    if await checkPauseRequested(atPhotoIndex: index) { return }
                                }
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                networkWait += 2
                                
                                do {
                                    try await instagram.waitForNetworkStability()
                                    break
                                } catch {
                                    continue
                                }
                            }
                            
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s buffer
                            
                        } else {
                            let waitSeconds = 60 + Int.random(in: 0...30)
                            print("⚠️ [AUTO-RETRY] Generic error. Waiting \(waitSeconds)s then auto-retrying...")
                            LogManager.shared.info("Auto-retry: waiting \(waitSeconds)s for generic error (attempt \(retryAttempt))", category: .upload)
                            
                            await autoRetryWait(seconds: waitSeconds, attempt: retryAttempt, photoInfo: photoInfo)
                        }
                        
                        continue
                    }
                }
            } // end while (retry loop)
            
            if !photoUploadSuccess {
                print("❌ [UPLOAD] Photo #\(index + 1) failed after all retries")
                await handleEscalation(photoIndex: index)
                return
            }
            
            await MainActor.run {
                uploadManager.uploadProgress.current = index + 1
            }
            
            // ANTI-BOT: Delay before next photo (wait for cooldown from archive)
            if relativeIndex < photosToUpload.count - 1 {
                let (hasCooldown, cooldownRemaining) = instagram.isPhotoUploadOnCooldown()
                let delaySeconds: Int
                
                if hasCooldown && cooldownRemaining > 0 {
                    delaySeconds = cooldownRemaining + Int.random(in: 5...15)
                    print("   Using archive cooldown: \(cooldownRemaining)s + buffer = \(delaySeconds)s")
                } else {
                    delaySeconds = Int(Double.random(in: 160...220))
                    print("   Using fallback delay: \(delaySeconds)s")
                }
                
                // Persist the absolute end-time so background/kill doesn't lose it
                let endTime = Date().addingTimeInterval(Double(delaySeconds))
                await MainActor.run {
                    uploadManager.persistWait(endTime: endTime, nextPhotoIndex: index + 2)
                    uploadManager.uploadPhase = .waiting(nextPhoto: index + 2, remainingSeconds: delaySeconds)
                    uploadManager.currentPhaseDescription = "Next photo in \(delaySeconds / 60):\(String(format: "%02d", delaySeconds % 60))"
                    uploadManager.nextPhotoCountdown = delaySeconds
                    
                    uploadManager.nextPhotoTimer?.invalidate()
                    uploadManager.nextPhotoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                        guard let um = uploadManager else { return }
                        let r = um.remainingWaitSeconds()
                        um.nextPhotoCountdown = r
                        um.uploadPhase = .waiting(nextPhoto: index + 2, remainingSeconds: r)
                        um.currentPhaseDescription = "Next photo in \(r / 60):\(String(format: "%02d", r % 60))"
                        if r <= 0 {
                            um.nextPhotoTimer?.invalidate()
                            um.nextPhotoTimer = nil
                        }
                    }
                }
                
                // Allow screen to sleep during the wait (user can lock phone)
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                
                // Wait using persisted timestamp — survives background
                while true {
                    let remaining = uploadManager.remainingWaitSeconds()
                    if remaining <= 0 { break }
                    if uploadManager.requestPause {
                        print("⏸️ [UPLOAD] Paused by user during delay")
                        await MainActor.run {
                            uploadManager.requestPause = false
                            uploadManager.nextPhotoTimer?.invalidate()
                            uploadManager.nextPhotoTimer = nil
                            uploadManager.clearWaitPersistence()
                            UIApplication.shared.isIdleTimerDisabled = false
                            uploadManager.uploadPhase = .paused
                            uploadManager.currentPhaseDescription = "Upload Paused"
                            uploadManager.failedPhotoIndex = index + 1
                            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                            uploadManager.activeTask = nil
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                
                // Wait finished — re-enable screen lock prevention for the upload
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = true
                    uploadManager.nextPhotoTimer?.invalidate()
                    uploadManager.nextPhotoTimer = nil
                    uploadManager.clearWaitPersistence()
                }
            }
        } // end for (photos loop)
        
        print("\n✅ [UPLOAD ALL] All photos uploaded and archived!")
        LogManager.shared.success("Upload completed for set '\(currentSet.name)' - All \(currentSet.photos.count) photos uploaded", category: .upload)
        await MainActor.run {
            UIApplication.shared.isIdleTimerDisabled = false
            LogManager.shared.info("Screen sleep re-enabled after upload completion", category: .device)
            uploadManager.uploadPhase = .completed
            uploadManager.currentPhaseDescription = "Upload Completed"
            uploadManager.activeTask = nil
        }
        dataManager.updateSetStatus(id: currentSet.id, status: .completed)
    }
    
    // MARK: - Auto-Retry Helpers
    
    /// Wait with countdown display for auto-retry
    private func autoRetryWait(seconds: Int, attempt: Int, photoInfo: String) async {
        await MainActor.run {
            uploadManager.autoRetryCountdown = seconds
            uploadManager.uploadPhase = .autoRetrying(remainingSeconds: seconds, attempt: attempt)
            uploadManager.currentPhaseDescription = "Auto-retrying \(photoInfo) in \(seconds)s"
            
            uploadManager.autoRetryTimer?.invalidate()
            uploadManager.autoRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                guard let um = uploadManager else { return }
                if um.autoRetryCountdown > 0 {
                    um.autoRetryCountdown -= 1
                    um.uploadPhase = .autoRetrying(remainingSeconds: um.autoRetryCountdown, attempt: attempt)
                } else {
                    um.autoRetryTimer?.invalidate()
                    um.autoRetryTimer = nil
                }
            }
        }
        
        // Wait in 1-second chunks (respects pause)
        for _ in 0..<seconds {
            if uploadManager.requestPause {
                await MainActor.run {
                    uploadManager.autoRetryTimer?.invalidate()
                    uploadManager.autoRetryTimer = nil
                }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        await MainActor.run {
            uploadManager.autoRetryTimer?.invalidate()
            uploadManager.autoRetryTimer = nil
        }
    }
    
    /// Wait with countdown for cooldown (used before first upload)
    private func waitWithCountdown(seconds: Int, label: String) async {
        await MainActor.run {
            uploadManager.uploadPhase = .cooldown(remainingSeconds: seconds)
            uploadManager.currentPhaseDescription = label
        }
        
        for remaining in stride(from: seconds, to: 0, by: -1) {
            if uploadManager.requestPause { return }
            await MainActor.run {
                uploadManager.uploadPhase = .cooldown(remainingSeconds: remaining)
                uploadManager.currentPhaseDescription = "Cooldown \(remaining / 60):\(String(format: "%02d", remaining % 60))"
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    /// Extract cooldown seconds from error message like "Please wait 1m 30s"
    private func extractCooldownSeconds(from errorDescription: String) -> Int {
        let components = errorDescription.components(separatedBy: " ")
        var totalSeconds = 0
        for component in components {
            if component.hasSuffix("m") {
                if let mins = Int(component.dropLast()) {
                    totalSeconds += mins * 60
                }
            } else if component.hasSuffix("s") {
                if let secs = Int(component.dropLast()) {
                    totalSeconds += secs
                }
            }
        }
        return max(totalSeconds, 30) // minimum 30s
    }
    
    /// Handle escalation after 3 consecutive failures
    private func handleEscalation(photoIndex: Int) async {
        let escalationWaitSeconds = 300 // 5 minutes
        
        print("🚨 [ESCALATION] Multiple failures - pausing for \(escalationWaitSeconds)s")
        LogManager.shared.warning("Upload escalated at Photo #\(photoIndex + 1) - pausing for 5 minutes after multiple failures", category: .upload)
        
        await MainActor.run {
            UIApplication.shared.isIdleTimerDisabled = false
            uploadManager.failedPhotoIndex = photoIndex
            uploadManager.activeTask = nil
            
            let pauseEndDate = Date().addingTimeInterval(Double(escalationWaitSeconds))
            uploadManager.escalatedPauseEndTime = pauseEndDate
            uploadManager.escalatedPauseCountdown = escalationWaitSeconds
            uploadManager.uploadPhase = .escalatedPause(remainingSeconds: escalationWaitSeconds)
            uploadManager.currentPhaseDescription = "Multiple errors - Cooling down"
            
            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
            
            uploadManager.escalatedPauseTimer?.invalidate()
            uploadManager.escalatedPauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                guard let um = uploadManager else { return }
                let left = Int((um.escalatedPauseEndTime ?? Date()).timeIntervalSinceNow)
                if left > 0 {
                    um.escalatedPauseCountdown = left
                    um.uploadPhase = .escalatedPause(remainingSeconds: left)
                    um.currentPhaseDescription = "Multiple errors - Cooling down"
                } else {
                    um.escalatedPauseTimer?.invalidate()
                    um.escalatedPauseTimer = nil
                    um.escalatedPauseEndTime = nil
                    um.escalatedPauseCountdown = 0
                    um.uploadPhase = .paused
                    um.currentPhaseDescription = "Upload Paused - Ready to Resume"
                }
            }
        }
    }
    
    // MARK: - Reveal All Archived
    
    private func revealAllArchived() {
        Task {
            let archivedPhotos = currentSet.photos.filter { $0.isArchived && $0.mediaId != nil }
            
            guard !archivedPhotos.isEmpty else { return }
            
            for photo in archivedPhotos {
                guard let mediaId = photo.mediaId else { continue }
                
                do {
                    let result = try await instagram.reveal(mediaId: mediaId)
                    
                    if result.success {
                        await MainActor.run {
                            dataManager.updatePhoto(
                                photoId: photo.id,
                                mediaId: nil,
                                isArchived: false,
                                commentId: result.commentId
                            )
                        }
                    }
                    
                    // Delay between reveals
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    print("❌ Error revealing photo: \(error)")
                }
            }
        }
    }
    
    // MARK: - Hide All Visible
    
    private func hideAllVisible() {
        Task {
            let visiblePhotos = currentSet.photos.filter { !$0.isArchived && $0.mediaId != nil }
            
            guard !visiblePhotos.isEmpty else { return }
            
            for photo in visiblePhotos {
                guard let mediaId = photo.mediaId else { continue }
                
                do {
                    let success = try await instagram.hide(mediaId: mediaId, commentId: photo.lastCommentId)
                    
                    if success {
                        await MainActor.run {
                            dataManager.updatePhoto(
                                photoId: photo.id,
                                mediaId: nil,
                                isArchived: true,
                                clearComment: true
                            )
                        }
                    }
                    
                    // Delay between hides
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    print("❌ Error hiding photo: \(error)")
                }
            }
        }
    }
}

// MARK: - Photo Item View

struct PhotoItemView: View {
    let photo: SetPhoto
    let setId: UUID
    let position: Int
    
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @State private var isProcessing = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Photo con badges
            ZStack {
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipped()
                        .cornerRadius(12)
                        .opacity(photo.isArchived ? 0.5 : 1.0) // Más opaco si está archivado
                        .overlay(
                            // Overlay oscuro cuando está archivado
                            photo.isArchived ? 
                                Color.black.opacity(0.3)
                                    .cornerRadius(12)
                                : nil
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 110, height: 110)
                        .cornerRadius(12)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
                
                // Position badge (top-left)
                ZStack {
                    Circle()
                        .fill(VaultTheme.Colors.primary)
                        .frame(width: 32, height: 32)
                    
                    Text("\(position)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -4, y: -4)
                
                // Symbol badge debajo de la foto (primeras 3 letras) - MOVIDO
                Text(String(photo.symbol.prefix(3)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)
            }
            
            // Info
            VStack(spacing: 4) {
                
                // ONLY show upload-related info when logged in
                if instagram.isLoggedIn {
                    if let uploadDate = photo.uploadDate {
                        Text(uploadDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Status - Detailed based on uploadStatus
                    statusBadge(for: photo)
                }
                
                // Action Buttons - ONLY VISIBLE WHEN LOGGED IN
                if instagram.isLoggedIn {
                    if let mediaId = photo.mediaId {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.top, 6)
                        } else {
                            if photo.isArchived {
                                Button(action: { revealPhoto() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                        Text("Reveal")
                                            .font(.caption.bold())
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [VaultTheme.Colors.success, VaultTheme.Colors.success.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(VaultTheme.CornerRadius.sm)
                                    .shadow(color: VaultTheme.Colors.success.opacity(0.3), radius: 3, x: 0, y: 2)
                                }
                                .padding(.top, 6)
                            } else {
                                Button(action: { hidePhoto() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "archivebox.fill")
                                        Text("Hide")
                                            .font(.caption.bold())
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, VaultTheme.Spacing.sm)
                                    .background(VaultTheme.Colors.warning.opacity(0.2))
                                    .foregroundColor(VaultTheme.Colors.warning)
                                    .cornerRadius(VaultTheme.CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                            .stroke(VaultTheme.Colors.warning.opacity(0.5), lineWidth: 1)
                                        )
                                }
                                .padding(.top, 6)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(VaultTheme.Colors.cardBackground)
        .cornerRadius(VaultTheme.CornerRadius.md)
        .opacity(photo.isArchived ? 0.6 : 1.0)
        .alert("Result", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Reveal (Unarchive + Comment)
    
    private func revealPhoto() {
        guard let mediaId = photo.mediaId else { return }
        
        isProcessing = true
        
        Task {
            do {
                let result = try await instagram.reveal(mediaId: mediaId)
                
                if result.success {
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: nil,
                            isArchived: false,
                            commentId: result.commentId
                        )
                        alertMessage = "✅ Revealed!\n\nComment posted for: \(result.follower ?? "latest follower")"
                        showingAlert = true
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "❌ Error: \(error.localizedDescription)"
                    showingAlert = true
                    isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Hide (Delete Comment + Archive)
    
    private func hidePhoto() {
        guard let mediaId = photo.mediaId else { return }
        
        isProcessing = true
        
        Task {
            do {
                let success = try await instagram.hide(mediaId: mediaId, commentId: photo.lastCommentId)
                
                if success {
                    await MainActor.run {
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: nil,
                            isArchived: true,
                            clearComment: true
                        )
                        alertMessage = "✅ Hidden!\n\nComment deleted, photo archived."
                        showingAlert = true
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "❌ Error: \(error.localizedDescription)"
                    showingAlert = true
                    isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Status Badge
    
    @ViewBuilder
    private func statusBadge(for photo: SetPhoto) -> some View {
        switch photo.uploadStatus {
        case .pending:
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("Waiting to upload")
            }
            .font(.caption2)
            .foregroundColor(.orange)
            
        case .uploading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Uploading...")
            }
            .font(.caption2)
            .foregroundColor(.blue)
            
        case .uploaded:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Waiting to archive...")
            }
            .font(.caption2)
            .foregroundColor(VaultTheme.Colors.primary)
            
        case .archiving:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Archiving...")
            }
            .font(.caption2)
            .foregroundColor(VaultTheme.Colors.primary)
            
        case .completed:
            if photo.isArchived {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Archived")
                }
                .font(.caption2)
                .foregroundColor(.green)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                    Text("Visible")
                }
                .font(.caption2)
                .foregroundColor(.green)
            }
            
        case .error:
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Failed")
                }
                .font(.caption2)
                .foregroundColor(.red)
                
                if let errorMessage = photo.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Tap-to-Swap Photo Cell (for reorder mode)

struct TapToSwapPhotoCell: View {
    let photo: SetPhoto
    let position: Int
    let isDuplicate: Bool
    let isLocked: Bool
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isSelected ? VaultTheme.Colors.success :
                                    isDuplicate ? VaultTheme.Colors.error :
                                    isLocked ? VaultTheme.Colors.textDisabled.opacity(0.5) :
                                    VaultTheme.Colors.primary.opacity(0.3),
                                    lineWidth: isSelected ? 4 : (isDuplicate ? 3 : 2)
                                )
                        )
                        .opacity(isLocked ? 0.4 : 1.0)
                        .overlay(
                            isLocked ?
                                Color.black.opacity(0.3).cornerRadius(12)
                                : nil
                        )
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                        .shadow(color: isSelected ? VaultTheme.Colors.success.opacity(0.5) : Color.clear, radius: 8)
                }
                
                // Lock icon for uploaded photos
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                
                // Selected checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(VaultTheme.Colors.success)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
                
                // Position badge
                ZStack {
                    Circle()
                        .fill(
                            isSelected ? VaultTheme.Colors.success :
                            isDuplicate ? VaultTheme.Colors.error :
                            isLocked ? VaultTheme.Colors.textDisabled :
                            VaultTheme.Colors.primary
                        )
                        .frame(width: 34, height: 34)
                    
                    Text("\(position)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -5, y: -5)
                
                // Warning icon for duplicates
                if isDuplicate {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .shadow(color: .red, radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: -5, y: 32)
                }
            }
            .frame(width: 110, height: 110)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3), value: isSelected)
            
            // Symbol label below photo
            Text(String(photo.symbol.prefix(3)))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Stat Card is now in VaultComponents.swift
