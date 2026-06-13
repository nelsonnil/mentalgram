import SwiftUI
import Combine
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
    @ObservedObject private var activeSetSettings = ActiveSetSettings.shared
    
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

    private func clampedBankIndex(for bankCount: Int) -> Int {
        guard bankCount > 0 else { return 0 }
        return min(max(selectedBankIndex, 0), bankCount - 1)
    }

    private var selectedBankIfAvailable: Bank? {
        let banks = currentSet.banks
        guard !banks.isEmpty else { return nil }
        let safeIndex = clampedBankIndex(for: banks.count)
        guard banks.indices.contains(safeIndex) else { return nil }
        return banks[safeIndex]
    }

    // BULK "SELECT ALL" for current bank empty slots
    @State private var bulkSelectedItems: [PhotosPickerItem] = []
    @State private var isBulkLoading = false
    @State private var bulkLoadProgress: (current: Int, total: Int) = (0, 0)

    // ARCHIVED PHOTO MAPPING
    @State private var showArchivedPicker = false
    @State private var archivedPickerTargetSymbol: String? = nil
    @State private var showSlotSourcePicker = false
    @State private var slotSourcePickerSymbol: String? = nil
    @State private var showDirectGalleryPicker = false

    // FILLED SLOT ACTIONS (tap → action sheet)
    @State private var showFilledSlotActions = false
    @State private var filledSlotActionSymbol: String? = nil
    @State private var filledSlotActionIsUploaded = false

    // LIST SET
    @State private var showListImport = false
    @State private var listRenameSymbol: String? = nil
    @State private var listRenameText = ""
    @State private var showListRenameAlert = false
    @State private var listImportError: String? = nil
    @State private var listSeparatorSlot: Int = 10

    // VERIFY & SYNC state
    @State private var syncArchivePulse = false
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
    /// Re-evaluation tick driving countdowns on the S&A button (post-reveal hold,
    /// per-set cooldown). Bumped every second by a timer while the section is
    /// visible. Keeps the SwiftUI body in sync without forcing the whole view
    /// to re-render on every model change.
    @State private var safetyCountdownTick: Int = 0
    /// Set when the archive loop stops early for a benign reason (budget cap,
    /// rate limit, post-reveal). Surfaced in the result banner so the magician
    /// knows pending photos are deferred, not failed.
    @State private var archiveStopReason: String? = nil
    /// Presents the LockdownDetailsSheet from the "Start Uploading" button when locked.
    @State private var showingLockdownSheet: Bool = false

    // GRID ANCHOR — taken_at override computed automatically at upload time.
    // Set to (oldest post in the current first-page fetch) - 1 second so the prediction
    // slots in just below all existing posts. Any posts pinned or uploaded afterwards
    // naturally appear above it without any manual configuration.
    @State private var uploadTakenAt: Date? = nil

    var currentSet: PhotoSet {
        dataManager.sets.first(where: { $0.id == set.id }) ?? set
    }

    /// Effective slot labels used for grid display.
    /// For custom sets, derives labels numerically from existing photos (or defaults to 1 slot).
    /// For word/number sets, returns the model's fixed labels.
    private var effectiveSlotLabels: [String] {
        if currentSet.type == .list {
            return currentSet.slotLabels
        }
        if currentSet.type == .custom {
            let numericSymbols = currentSet.photos.compactMap { Int($0.symbol) }
            let maxSlot = numericSymbols.max() ?? 0
            let count = max(maxSlot, 1)
            return (1...count).map { "\($0)" }
        }
        return currentSet.slotLabels
    }

    private var listDisplayLabelsBySymbol: [String: String] {
        guard currentSet.type == .list else { return [:] }
        let symbols = currentSet.slotLabels
        let labels = currentSet.listDisplayLabels
        return Dictionary(uniqueKeysWithValues: symbols.enumerated().map { index, symbol in
            (symbol, index < labels.count ? labels[index] : "Item \(symbol)")
        })
    }

    private var listPreviewColumns: [GridItem] {
        switch currentSet.resolvedListColumns {
        case .automatic:
            return [GridItem(.adaptive(minimum: 150), spacing: 10)]
        case .two:
            return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        case .three:
            return Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        }
    }

    private func listPreviewButtonColor(at index: Int) -> Color {
        let blue = Color(hex: "0A84FF")
        let green = Color(hex: "30D158")
        let orange = Color(hex: "FF9500")

        switch currentSet.resolvedListColumns {
        case .two:
            return index % 2 == 0 ? blue : green
        case .three:
            switch index % 3 {
            case 0:  return blue
            case 1:  return green
            default: return orange
            }
        case .automatic:
            return Color(hex: "64D2FF")
        }
    }

    private var listPreviewItems: [(symbol: String, label: String)] {
        let symbols = currentSet.slotLabels
        let labels = currentSet.listDisplayLabels
        return symbols.enumerated().map { index, symbol in
            (symbol, index < labels.count ? labels[index] : "Item \(symbol)")
        }
    }

    private var listPreviewGroups: [[(offset: Int, symbol: String, label: String)]] {
        var groups: [[(offset: Int, symbol: String, label: String)]] = []
        var current: [(offset: Int, symbol: String, label: String)] = []
        let separators = Set(currentSet.resolvedListSeparators)

        for (index, item) in listPreviewItems.enumerated() {
            current.append((offset: index, symbol: item.symbol, label: item.label))
            if let slot = Int(item.symbol), separators.contains(slot) {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
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

    /// All photos that have a mediaId (were at least uploaded to Instagram),
    /// regardless of whether the archive step completed or failed.
    /// Used by "Re-verify All" to detect:
    ///   (a) local says archived but IG shows it public (desync)
    ///   (b) local says error/incomplete but IG has the photo — needs archive
    private var allUploadedPhotos: [SetPhoto] {
        currentSet.photos.filter {
            $0.mediaId != nil &&
            $0.uploadStatus != .pending &&
            $0.uploadStatus != .uploading
        }
    }

    /// isReverifying is now driven by uploadManager.isReverifying (persists across view lifecycle).
    
    private var mainScrollContent: some View {
        ScrollView {
            VStack(spacing: VaultTheme.Spacing.lg) {
                statsSection
                sessionExpiredBanner
                verifySyncSection
                reverifySection
                if instagram.isLoggedIn {
                    statusSection
                        .id("\(uploadManager.uploadPhase)-\(uploadManager.nextPhotoCountdown)-\(uploadManager.botCountdownSeconds)-\(uploadManager.autoRetryCountdown)-\(uploadManager.escalatedPauseCountdown)")
                    if uploadManager.isPhotoRejected {
                        photoRejectedRecoverySection
                    }
                }
                if currentSet.type == .list {
                    listSetControlsSection
                }
                banksTabsWithActions
                // reorderToggleButton — hidden until needed
                photosGridSection
            }
            .padding(VaultTheme.Spacing.lg)
        }
    }

    @ViewBuilder private var sessionExpiredBanner: some View {
        if instagram.isSessionExpired {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Session expired")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Instagram rejected the session. Re-login to refresh, or read why before retrying.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button(action: { showSessionRelogin = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Re-login")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                    Button(action: { showSessionInfo = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Why?")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.red)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .sheet(isPresented: $showSessionInfo) {
                MagicianSessionPanel(
                    showRelogin: $showSessionRelogin,
                    dismissPanel: { showSessionInfo = false }
                )
            }
            .sheet(isPresented: $showSessionRelogin) {
                ReloginSheet(isPresented: $showSessionRelogin)
            }
            .sheet(isPresented: $showingLockdownSheet) {
                LockdownDetailsSheet()
            }
        }
    }

    @ViewBuilder private var reverifySection: some View {
        // ANTI-CRASH: Do NOT show while S&A is running or just completed — at the
        // moment `isArchivingAll` flips to false all photos may be locally still
        // in transition (isArchived update pending). Evaluating `allUploadedPhotos`
        // before that settles can produce an inconsistent state and a SwiftUI
        // body crash. `archiveAllCompleted` stays true until the next navigation
        // away and back, so this guard also suppresses the accidental launch of
        // a background archive scan (which caused the /feed/only_me_feed/ scan
        // visible in logs while S&A was still running its second archive).
        if instagram.isLoggedIn
            && visibleUploadedPhotos.isEmpty
            && !allUploadedPhotos.isEmpty
            && !isSyncing
            && !isArchivingAll
            && !archiveAllCompleted
            && !uploadManager.isSyncArchiveActive {
            VStack(spacing: 6) {
                if uploadManager.isReverifying {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Re-verifying \(uploadManager.reverifyProgress)/\(uploadManager.reverifyTotal)…")
                            .font(.caption).foregroundColor(.secondary)
                        if uploadManager.reverifyDesynced > 0 {
                            Text("(\(uploadManager.reverifyDesynced) desync)")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.gray.opacity(0.08)).cornerRadius(8)
                } else {
                    // Error banner — shown when the previous re-verify attempt failed
                    if let err = uploadManager.reverifyError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12)).foregroundColor(.orange)
                            Text(err)
                                .font(.caption).foregroundColor(.orange)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                uploadManager.reverifyError = nil
                                startReverify()
                            } label: {
                                Text("Retry")
                                    .font(.caption.bold()).foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08)).cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                    }

                    Button {
                        uploadManager.reverifyError = nil
                        startReverify()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Re-verify All (\(allUploadedPhotos.count) photos)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("Check if any photo is currently unarchived on Instagram")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.55))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.7), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("Use Re-verify All before Performance to detect public photos and avoid accidental reveal.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var bankManagementSection: some View {
        let isThisSetMidUpload = uploadManager.activeSetId == currentSet.id && uploadManager.isUploading
        if (currentSet.type == .word || currentSet.type == .number) && !isThisSetMidUpload {
            HStack(spacing: 10) {
                Button { _ = dataManager.addBank(setId: currentSet.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 13))
                        Text("Add Bank").font(.caption.bold())
                    }
                    .foregroundColor(VaultTheme.Colors.primary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(VaultTheme.Colors.primary.opacity(0.1)).cornerRadius(8)
                }
                .buttonStyle(.plain)
                deleteLastBankButton
                Spacer()
            }
        }
    }

    @State private var showForceDeleteBankConfirm = false
    /// Task running the smart auto-resume countdown after a network change (A).
    @State private var networkAutoResumeTask: Task<Void, Never>? = nil

    @ViewBuilder private var deleteLastBankButton: some View {
        let hasManyBanks = currentSet.banks.count > 1
        let isExtraBank: Bool = {
            guard let target = currentSet.targetBankCount else { return false }
            return currentSet.banks.count > target
        }()
        let canDeleteSafely: Bool = {
            guard hasManyBanks else { return false }
            guard let last = currentSet.banks.max(by: { $0.position < $1.position }) else { return false }
            let bankPhotos = currentSet.photos.filter { $0.bankId == last.id }
            // Allow deleting banks whose photos are still pending (not yet archived on Instagram),
            // even if imageData is present ("ready for archive" state).
            return !bankPhotos.contains(where: { $0.uploadStatus != .pending })
        }()

        if canDeleteSafely {
            Button {
                dataManager.removeLastBank(setId: currentSet.id)
                let newCount = currentSet.banks.count
                selectedBankIndex = min(max(selectedBankIndex, 0), max(0, newCount - 1))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 13))
                    Text("Delete last bank").font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.red.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
        } else if isExtraBank && hasManyBanks {
            Button { showForceDeleteBankConfirm = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 13))
                    Text("Remove extra bank").font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.red.opacity(0.08)).cornerRadius(8)
            }
            .buttonStyle(.plain)
            .alert("Remove Extra Bank?", isPresented: $showForceDeleteBankConfirm) {
                Button("Remove", role: .destructive) {
                    dataManager.removeLastBank(setId: currentSet.id, force: true)
                    let newCount = currentSet.banks.count
                    selectedBankIndex = min(max(selectedBankIndex, 0), max(0, newCount - 1))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This bank was created beyond your target of \(currentSet.targetBankCount ?? 0). Its photos will be removed from the app but will remain archived on Instagram.")
            }
        }
    }

    var body: some View {
        bodyWithPresentation
    }

    private var bodyBase: some View {
        ZStack {
            VaultTheme.Colors.background.ignoresSafeArea()
            mainScrollContent
        }
        .navigationTitle(currentSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { }
        .toolbarBackground(VaultTheme.Colors.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var bodyWithAlerts: some View {
        bodyBase
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
        .alert("Safety Pause", isPresented: .constant(uploadManager.safetyBlockMessage != nil), presenting: uploadManager.safetyBlockMessage) { _ in
            Button("OK") {
                uploadManager.safetyBlockMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }

    private var bodyWithLifecycle: some View {
        bodyWithAlerts
        // Safety clamp: whenever the bank count changes (add or delete), make sure
        // selectedBankIndex still points to a valid bank. This prevents the
        // "Index out of range" crash in photosGridSection that happens when SwiftUI
        // re-renders the view with the updated bank list before the button action
        // has a chance to update selectedBankIndex manually.
        .onChange(of: currentSet.banks.count) { newCount in
            guard newCount > 0 else { selectedBankIndex = 0; return }
            if selectedBankIndex >= newCount {
                selectedBankIndex = newCount - 1
            }
        }
        .onChange(of: instagram.networkChangedDuringUpload) { changed in
            guard changed else { return }
            instagram.networkChangedDuringUpload = false
            guard uploadManager.isUploading && isThisSetActive else { return }

            let newType = instagram.connectionType
            print("⚠️ [UPLOAD] Network changed → \(newType) — starting smart auto-resume")
            LogManager.shared.warning("Network changed → \(newType) during upload — smart auto-resume started", category: .network)

            // C: Reset retry counter — pause was caused by a network transition,
            //    not an upload failure. The user deserves a fresh retry budget.
            uploadManager.consecutiveAutoRetries = 0
            uploadManager.requestPause = true
            // D: Store the new connection type so the UI can display it.
            uploadManager.networkReconnectingTo = newType

            // A: Enter reconnecting state (attempt: 0 means "auto-resume in progress",
            //    distinct from attempt: 1+ which is "upload failed, manual retry needed").
            let stabilizationSeconds = 15
            uploadManager.networkAutoResumeCountdown = stabilizationSeconds
            uploadManager.uploadPhase = .waitingNetwork(attempt: 0)
            uploadManager.currentPhaseDescription = "Connection changed — reconnecting..."

            // A: Launch the smart auto-resume task.
            networkAutoResumeTask?.cancel()
            networkAutoResumeTask = Task { @MainActor in
                // Count down the stabilization window.
                for i in stride(from: stabilizationSeconds, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    // If phase changed externally (e.g. user tapped Resume Now), stop.
                    guard case .waitingNetwork(let att) = uploadManager.uploadPhase, att == 0 else { return }
                    uploadManager.networkAutoResumeCountdown = i
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard !Task.isCancelled else { return }
                guard case .waitingNetwork(let att) = uploadManager.uploadPhase, att == 0 else { return }
                uploadManager.networkAutoResumeCountdown = 0

                // Verify the new connection is actually up before resuming.
                guard instagram.isConnected else {
                    LogManager.shared.warning("Smart auto-resume: no connection after wait — showing manual resume", category: .network)
                    uploadManager.networkReconnectingTo = ""
                    uploadManager.uploadPhase = .paused
                    uploadManager.showingError = "No connection found.\n\nCheck your network (\(newType)) and tap Resume when ready."
                    return
                }

                LogManager.shared.info("Smart auto-resume: \(newType) stable — resuming upload automatically", category: .upload)
                uploadManager.networkReconnectingTo = ""
                resumeUpload()
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
        // Anti-bot: PerformanceView sets autoResumePending when it leaves after having
        // auto-paused the upload. We react here (onChange fires even after onAppear order issues).
        .onChange(of: uploadManager.autoResumePending) { pending in
            guard pending else { return }
            // Never auto-resume while Sync & Archive is in progress — concurrent POST
            // calls (upload + archive) from the same session trigger bot detection.
            guard isThisSetActive && uploadManager.isPaused && !uploadManager.isSyncArchiveActive else {
                uploadManager.autoResumePending = false
                return
            }
            // After a POST challenge_required the user must tap Resume manually to
            // confirm they've verified in Instagram. Auto-resuming would repeat the
            // exact failure pattern (04:39 scenario in the logs).
            guard !uploadManager.requiresManualResumeAfterChallenge else {
                uploadManager.autoResumePending = false
                print("⏸️ [UPLOAD] Auto-resume blocked — challenge requires manual confirmation")
                LogManager.shared.warning("Auto-resume blocked: challenge requires manual resume", category: .upload)
                return
            }
            uploadManager.autoResumePending = false
            // Brief delay to let Performance view fully dismiss and its API calls settle.
            // If the session is in a challenged state, wait until it clears before resuming
            // to avoid firing requests into a temporarily restricted session.
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s safety gap

                // Wait up to 2 min for challenge window to clear (checks every 10s)
                var challengeWaitLoops = 0
                while instagram.isSessionChallenged && challengeWaitLoops < 12 {
                    challengeWaitLoops += 1
                    print("⏸️ [UPLOAD] Auto-resume waiting — session challenged (\(challengeWaitLoops * 10)s)")
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }

                // Re-check: S&A might have started during the wait, or lockdown activated
                guard uploadManager.isPaused && isThisSetActive && !uploadManager.isSyncArchiveActive else {
                    print("⏸️ [UPLOAD] Auto-resume skipped — S&A active or state changed")
                    return
                }
                guard !instagram.isLocked, !instagram.isSessionChallenged else {
                    print("⏸️ [UPLOAD] Auto-resume skipped — locked or still challenged")
                    return
                }
                print("▶️ [UPLOAD] Auto-resuming after Performance view — anti-bot gap cleared")
                LogManager.shared.info("Upload auto-resumed: returned from Performance view", category: .general)
                await MainActor.run { resumeUpload() }
            }
        }
        .onChange(of: slotPickerItem) { newItem in
            guard let item = newItem, let symbol = targetSlotSymbol else { return }
            loadPhotoForSlot(item: item, symbol: symbol)
        }
        .onChange(of: bulkSelectedItems) { newItems in
            guard !newItems.isEmpty else { return }
            loadBulkPhotosIntoEmptySlots(items: newItems)
        }
    }

    private var bodyWithPresentation: some View {
        bodyWithLifecycle
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
        .confirmationDialog("Photo options", isPresented: $showFilledSlotActions, titleVisibility: .visible) {
            Button(filledSlotActionIsUploaded ? "Replace from Gallery" : "Change photo from Gallery") {
                if let symbol = filledSlotActionSymbol {
                    targetSlotSymbol = symbol
                    showDirectGalleryPicker = true
                }
                showFilledSlotActions = false
            }
            if instagram.isLoggedIn {
                Button(filledSlotActionIsUploaded ? "Replace from Archived" : "Change photo from Archived") {
                    if let symbol = filledSlotActionSymbol {
                        archivedPickerTargetSymbol = symbol
                        showArchivedPicker = true
                    }
                    showFilledSlotActions = false
                }
            }
            if currentSet.type == .list {
                Button("Rename Item") {
                    if let symbol = filledSlotActionSymbol {
                        startRenamingListItem(symbol)
                    }
                    showFilledSlotActions = false
                }
            }
            Button("Remove Photo", role: .destructive) {
                if let symbol = filledSlotActionSymbol {
                    deleteTargetSymbol = symbol
                    showDeleteConfirm = true
                }
                showFilledSlotActions = false
            }
            Button("Cancel", role: .cancel) {
                filledSlotActionSymbol = nil
                showFilledSlotActions = false
            }
        } message: {
            if let symbol = filledSlotActionSymbol {
                Text("Slot \"\(displayLabel(for: symbol))\"")
            }
        }
        .confirmationDialog("Add photo for slot", isPresented: $showSlotSourcePicker, titleVisibility: .visible) {
            Button("From Gallery") {
                if let symbol = slotSourcePickerSymbol {
                    targetSlotSymbol = symbol
                    showDirectGalleryPicker = true
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
                Text("Choose where to get the photo for \"\(displayLabel(for: symbol))\"")
            }
        }
        .alert("Rename List Item", isPresented: $showListRenameAlert) {
            TextField("Item name", text: $listRenameText)
            Button("Save") {
                if let symbol = listRenameSymbol {
                    dataManager.renameListItem(setId: currentSet.id, symbol: symbol, label: listRenameText)
                }
                listRenameSymbol = nil
            }
            Button("Cancel", role: .cancel) { listRenameSymbol = nil }
        } message: {
            Text("This changes the private list button text. The linked media stays attached to the same slot.")
        }
        .alert("Import Failed", isPresented: Binding(
            get: { listImportError != nil },
            set: { if !$0 { listImportError = nil } }
        )) {
            Button("OK", role: .cancel) { listImportError = nil }
        } message: {
            Text(listImportError ?? "")
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
        .fileImporter(
            isPresented: $showListImport,
            allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "csv") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            importListItems(from: result)
        }
        .photosPicker(isPresented: $showDirectGalleryPicker, selection: $slotPickerItem, matching: .images)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Restore State
    
    private func restoreTimersIfNeeded() {
        uploadManager.restoreTimersIfNeeded()
    }
    
    // MARK: - Stats Section
    
    // MARK: - Verify & Sync Section

    /// Drives the post-reveal / set-cooldown countdown on the S&A button.
    /// Declared as a stored property so the publisher isn't recreated on each
    /// SwiftUI body evaluation.
    private let safetySectionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Re-login sheet bound to the session-expired banner (so the magician
    /// doesn't have to navigate to Settings to fix a dead session).
    @State private var showSessionRelogin = false
    /// Info sheet (same content as the WiFi-style overlay's "i" button) bound
    /// to the session-expired banner.
    @State private var showSessionInfo = false

    /// Banner visible only when logged in and there are locally-visible uploaded photos
    /// that could be desynced from Instagram's real archive state.
    @ViewBuilder
    private var verifySyncSection: some View {
        // Keep the section visible while any S&A operation is active, even if
        // visibleUploadedPhotos becomes empty mid-archive (all photos archived).
        let saIsActive = isSyncing || isArchivingAll || uploadManager.isSyncArchiveActive || archiveAllCompleted
        // ANTI-FLASH: when the session is expired we surface the action buttons
        // through `sessionExpiredBanner` (Re-login + Why). Showing the disabled
        // red S&A here on top of that produces the visual "red flash" the user
        // reported when returning to the app from the WiFi overlay.
        if instagram.isLoggedIn
            && (!visibleUploadedPhotos.isEmpty || saIsActive)
            && !instagram.isSessionExpired {
            VStack(spacing: 8) {

                // ── Phase 1 running: verifying ─────────────────────────
                if isSyncing {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uploadManager.isSyncArchiveActive
                                 ? String(format: String(localized: "Sync & Archive — verifying (%d/%d)…"), syncProgress, syncTotal)
                                 : String(format: String(localized: "Verifying (%d/%d)…"), syncProgress, syncTotal))
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
                            Text(String(format: String(localized: "Preparing to archive… %ds"), saCountdownSeconds))
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
                            Text(String(format: String(localized: "Archiving (%d/%d)"), archiveAllProgress, archiveAllTotal))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            if saCountdownSeconds > 0 {
                                let m = saCountdownSeconds / 60
                                let s = saCountdownSeconds % 60
                                Text(m > 0
                                     ? String(format: String(localized: "Next archive in %dm %ds — do not close the app"), m, s)
                                     : String(format: String(localized: "Next archive in %ds — do not close the app"), s))
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
                            Text(String(format: String(localized: "All %d photos archived"), archiveAllTotal))
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        } else {
                            // Partial finish — most likely a safe pause (budget
                            // cap) rather than a genuine failure. Phrase the
                            // subtitle accordingly and prefer the explicit
                            // stoppedReason captured during the archive loop.
                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: String(localized: "Archived %d/%d photos"), archiveAllProgress, archiveAllTotal))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                let remaining = archiveAllTotal - archiveAllProgress
                                Text(archiveStopReason
                                     ?? String(format: String(localized: "%d remaining — tap Sync & Archive in a few minutes to finish"), remaining))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
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
                    // Tick the countdown view every second while idle so the
                    // post-reveal hold / set-cooldown labels stay accurate.
                    let _ = safetyCountdownTick
                    let rateCheck = instagram.checkRateLimit()
                    let saRateLimited = rateCheck.limited || rateCheck.remaining < 3

                    // ANTI-BOT: surface post-reveal hold and per-set cooldown
                    // so the magician sees *why* the button is gated and waits
                    // instead of looking for a workaround.
                    let postRevealLeft = InstagramSafetyGate.shared.postRevealSecondsRemaining
                    let setCooldown = InstagramSafetyGate.shared.canSyncSet(setId: currentSet.id.uuidString)
                    let setCooldownLeft = setCooldown.allowed ? 0 : setCooldown.waitSeconds
                    let saBlockedBySafety = postRevealLeft > 0 || setCooldownLeft > 0

                    // Rate limit warning banner
                    if saRateLimited {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rate limit reached (\(rateCheck.actionsUsed)/55 actions)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                Text("Wait a few minutes before syncing. Instagram limits API calls per hour.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }

                    // Recent-reveal warning banner — shown when the same set was
                    // revealed less than 30 minutes ago. Rapid reveal→archive→reveal
                    // cycles with the same photos are the main trigger for Instagram
                    // bot detection (same mediaIds archived/unarchived repeatedly).
                    let lastRevealedSetId = UserDefaults.standard.string(forKey: "perf_lastRevealedSetId") ?? ""
                    let lastRevealedTs    = UserDefaults.standard.double(forKey: "perf_lastRevealedSetTimestamp")
                    let minutesSinceReveal = lastRevealedTs > 0
                        ? Int((Date().timeIntervalSince1970 - lastRevealedTs) / 60)
                        : -1
                    let recentRevealWarning = lastRevealedSetId == currentSet.id.uuidString
                        && minutesSinceReveal >= 0
                        && minutesSinceReveal < 30

                    if recentRevealWarning {
                        let waitLeft = 30 - minutesSinceReveal
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "FF9F0A"))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Set revelado hace \(minutesSinceReveal) min")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color(hex: "FF9F0A"))
                                Text("Archivar el mismo set demasiado pronto después de un reveal (ciclo reveal→archive→reveal) es la causa más frecuente de detección de bot en Instagram. Se recomienda esperar al menos \(waitLeft) min más.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color(hex: "FF9F0A").opacity(0.07))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "FF9F0A").opacity(0.3), lineWidth: 1))
                    }

                    // PRIMARY: Sync & Archive (single safe action — Re-verify
                    // was removed in May 2026; it bypassed the post-reveal
                    // protection that S&A respects and turned into a bot-
                    // detection vector on the second sync).
                    let sessionDead = instagram.isSessionExpired
                    let saDisabled = isSyncing
                        || isArchivingAll
                        || uploadManager.isSyncArchiveActive
                        || saRateLimited
                        || saBlockedBySafety
                        || sessionDead
                    let saIconName: String = {
                        if sessionDead { return "person.crop.circle.badge.exclamationmark" }
                        if saBlockedBySafety { return "shield.lefthalf.filled" }
                        if saRateLimited { return "clock.badge.exclamationmark" }
                        return "archivebox.circle.fill"
                    }()
                    let saIconColor: Color = {
                        if sessionDead { return .red }
                        if saBlockedBySafety { return Color(hex: "FF9F0A") }
                        if saRateLimited { return .orange }
                        return .purple
                    }()
                    let saTitleColor: Color = saDisabled ? .secondary : .primary
                    let saSubtitle: String = {
                        if sessionDead {
                            return String(localized: "Session expired — open Settings and log in again")
                        }
                        if postRevealLeft > 0 {
                            return String(
                                format: String(localized: "Recent reveals are protected — wait %@"),
                                formatCountdown(postRevealLeft)
                            )
                        }
                        if setCooldownLeft > 0 {
                            return String(
                                format: String(localized: "Same set just synced — wait %@ before syncing again"),
                                formatCountdown(setCooldownLeft)
                            )
                        }
                        if saRateLimited {
                            return String(localized: "Rate limit active — wait a few minutes")
                        }
                        return String(localized: "Verifies state · then archives with safe delays · no duplicate API calls")
                    }()
                    let saPulse = syncArchivePulse && !saDisabled

                    Button(action: {
                        guard !isSyncing, !isArchivingAll else { return }
                        Task { await syncThenArchiveAll() }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: saIconName)
                                .font(.system(size: 22))
                                .foregroundColor(saIconColor)
                                .opacity(saDisabled ? 0.6 : 1.0)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sync & Archive (\(visibleUploadedPhotos.count) visible)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(saTitleColor)
                                Text(saSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(
                            saIconColor.opacity(saPulse ? 0.16 : 0.08)
                        )
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                            saIconColor.opacity(saPulse ? 0.5 : 0.25),
                            lineWidth: saPulse ? 1.5 : 1))
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: syncArchivePulse)
                        .onAppear { syncArchivePulse = true }
                    }
                    .buttonStyle(.plain)
                    .disabled(saDisabled)
                }
            }
            .onReceive(safetySectionTimer) { _ in
                // Only tick when there's an active safety countdown to display,
                // otherwise idle redraws are wasted work.
                let needsTick = InstagramSafetyGate.shared.postRevealSecondsRemaining > 0
                    || !InstagramSafetyGate.shared.canSyncSet(setId: currentSet.id.uuidString).allowed
                if needsTick {
                    safetyCountdownTick &+= 1
                }
            }
        }
    }

    /// Renders a "Xm Ys" / "Ys" countdown for the safety labels on the S&A
    /// button. Re-evaluated whenever `safetyCountdownTick` changes.
    private func formatCountdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        if m > 0 {
            return String(format: "%dm %02ds", m, r)
        }
        return String(format: "%ds", r)
    }

    private var syncResultTitle: String {
        var parts: [String] = []
        if syncFixedCount > 0 {
            parts.append(String(format: String(localized: "Fixed %d desync(s)"), syncFixedCount))
        }
        if !syncTrulyVisibleIds.isEmpty {
            parts.append(String(format: String(localized: "%d confirmed public"), syncTrulyVisibleIds.count))
        }
        if parts.isEmpty {
            if syncUnknownCount == syncTotal {
                return String(localized: "API returned no data — check logs")
            }
            return String(localized: "All photos in sync ✓")
        }
        return parts.joined(separator: " · ")
    }

    /// ANTI-BOT: If a cold-start or warm-resume window is currently active, wait
    /// for it to close before starting a batch operation. We surface a countdown
    /// in the UI via `isPausingBeforeArchive` + `saCountdownSeconds` so the user
    /// knows the sync is queued, not stuck. No-op if no window is active.
    private func waitForColdStartIfNeeded(label: String) async {
        guard InstagramSafetyGate.shared.isInColdStartWindow else { return }
        let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
        guard remaining > 0 else { return }

        print("⏳ [\(label.uppercased())] Cold-start active — waiting \(remaining)s before starting batch")
        LogManager.shared.info("[\(label)] Deferred — cold-start active, waiting \(remaining)s", category: .general)

        await MainActor.run {
            isPausingBeforeArchive = true
            saCountdownSeconds = remaining
        }

        var left = remaining
        while left > 0 && InstagramSafetyGate.shared.isInColdStartWindow {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            left -= 1
            let snapshot = max(left, 0)
            await MainActor.run { saCountdownSeconds = snapshot }
        }

        await MainActor.run {
            isPausingBeforeArchive = false
            saCountdownSeconds = 0
        }
    }

    /// Archives all confirmed-visible photos sequentially with anti-bot delays.
    /// LEGACY: the active path is `syncThenArchiveAll`. This function is kept
    /// for any future direct-archive entry points but is not currently wired to
    /// any UI control. If you bring it back, note that `archivePhoto()` already
    /// performs a 3–6.5s human-like delay internally, so we no longer add an
    /// additional pre-call delay here (it would double-wait to 6–12s per item).
    private func archiveAllVisible() async {
        let ids = syncTrulyVisibleIds
        guard !ids.isEmpty, !isArchivingAll else { return }
        let archiveSafety = InstagramSafetyGate.shared.decision(for: .archive)
        guard archiveSafety.allowed else {
            print("🛡️ [ARCHIVE-ALL] Skipped — \(archiveSafety.reason) (\(archiveSafety.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — Archive All blocked: \(archiveSafety.reason)", category: .api)
            return
        }

        print("📦 [ARCHIVE-ALL] Starting archive for \(ids.count) confirmed-visible photo(s)")
        LogManager.shared.info("Archive All started: \(ids.count) photo(s)", category: .general)

        await MainActor.run {
            isArchivingAll = true
            archiveAllProgress = 0
            archiveAllTotal = ids.count
            archiveAllCompleted = false
        }

        for (index, mediaId) in ids.enumerated() {
            // NOTE: previously added a 3–6s pre-archive sleep here, but
            // archivePhoto() already does the same delay internally — keeping
            // both caused 6–12s per item which is not what the inter-archive
            // safety design calls for.

            // Check rate limit before each call (synchronous — no await needed)
            let rateLimit = instagram.checkRateLimit()
            print("🔒 [ARCHIVE-ALL] Rate limit: used=\(rateLimit.actionsUsed), remaining=\(rateLimit.remaining)")
            if rateLimit.limited || rateLimit.remaining < 2 {
                print("⛔️ [ARCHIVE-ALL] Rate limit reached — stopping at \(index)/\(ids.count)")
                LogManager.shared.warning("Archive All stopped: rate limit reached (used: \(rateLimit.actionsUsed))", category: .api)
                break
            }

            let perItemSafety = InstagramSafetyGate.shared.canArchive(mediaId: mediaId)
            if !perItemSafety.allowed {
                LogManager.shared.warning("SAFETY BLOCK — Archive All paused for \(perItemSafety.waitSeconds)s: \(perItemSafety.reason)", category: .api)
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
                    // Remove from ProfileCache so PerformanceView grid updates instantly
                    ProfileCacheService.shared.removeMediaItem(byMediaId: mediaId)
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
        // ── DIAGNOSTIC DUMP ─────────────────────────────────────────────
        print("🔍 [RE-VERIFY] startReverify() called")
        print("🔍 [RE-VERIFY] allUploadedPhotos=\(allUploadedPhotos.count)  isReverifying=\(uploadManager.isReverifying)  isLocked=\(instagram.isLocked)")
        print("🔍 [RE-VERIFY] All photos in set (\(currentSet.photos.count) total):")
        for p in currentSet.photos {
            print("🔍 [RE-VERIFY]   symbol=\(p.symbol)  mediaId=\(p.mediaId ?? "nil")  status=\(p.uploadStatus)  isArchived=\(p.isArchived)")
        }
        // ────────────────────────────────────────────────────────────────

        let photos = allUploadedPhotos
        guard !photos.isEmpty else {
            print("🔍 [RE-VERIFY] Guard exit: allUploadedPhotos is EMPTY — no photos to verify")
            return
        }
        guard !uploadManager.isReverifying else {
            print("🔍 [RE-VERIFY] Guard exit: already reverifying")
            return
        }
        guard !instagram.isLocked else {
            uploadManager.reverifyError = "App is in safety lockdown — wait for it to clear."
            print("⚠️ [RE-VERIFY] Skipped — lockdown active")
            return
        }
        // ANTI-BOT: Cooldown 5 min between re-verify runs. The log showed the
        // re-verify firing twice within 36 seconds (13:25:50 and 13:26:11),
        // generating 12 GET /feed/user/ calls in 53s. Same per-set gate used
        // by S&A, keyed by set ID so different sets don't share the cooldown.
        let reverifyKey = "reverify_\(currentSet.id.uuidString)"
        let reverifyCooldown = InstagramSafetyGate.shared.canSyncSet(setId: reverifyKey)
        guard reverifyCooldown.allowed else {
            let m = reverifyCooldown.waitSeconds / 60
            let s = reverifyCooldown.waitSeconds % 60
            let label = m > 0 ? "\(m)m \(s)s" : "\(s)s"
            print("🛡️ [RE-VERIFY] Skipped — cooldown active (\(label))")
            LogManager.shared.info("Re-verify cooldown: \(reverifyCooldown.waitSeconds)s remaining", category: .general)
            return
        }
        InstagramSafetyGate.shared.markSetSyncStarted(setId: reverifyKey)

        let photoSnapshots: [(id: UUID, mediaId: String, isArchived: Bool, status: PhotoUploadStatus)] = photos.compactMap { p in
            guard let mid = p.mediaId else { return nil }
            return (p.id, mid, p.isArchived, p.uploadStatus)
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
            print("🔍 [RE-VERIFY] ─────────────────────────────────────")
            print("🔍 [RE-VERIFY] Starting — \(photoSnapshots.count) photo(s) to check")
            for snap in photoSnapshots {
                print("🔍 [RE-VERIFY]   local mediaId=\(snap.mediaId) isArchived=\(snap.isArchived) status=\(snap.status)")
            }

            // Fetch all visible (non-archived) media IDs from Instagram feed.
            // Store BOTH the raw id and the pk-only prefix (strips _userId suffix)
            // so comparison works regardless of which format was stored locally.
            var visibleOnIG: Set<String> = []
            var nextMaxId: String? = nil
            var page = 0

            do {
                await MainActor.run { manager.reverifyError = nil }
                repeat {
                    page += 1
                    print("🔍 [RE-VERIFY] Fetching page \(page) from /feed/user/…")
                    let (items, cursor) = try await ig.getUserMedia(maxId: nextMaxId)
                    for item in items {
                        visibleOnIG.insert(item.id)
                        // Also insert the pk-only form (before first '_') so we match
                        // both "123456" and "123456_999" regardless of which side has the suffix
                        let pkOnly = item.id.split(separator: "_").first.map(String.init) ?? item.id
                        visibleOnIG.insert(pkOnly)
                    }
                    nextMaxId = cursor
                    print("🔍 [RE-VERIFY] Page \(page): got \(items.count) visible items (total unique: \(visibleOnIG.count / 2))")
                    if !items.isEmpty {
                        let sample = items.prefix(3).map { $0.id }.joined(separator: ", ")
                        print("🔍 [RE-VERIFY]   Sample IDs from feed: \(sample)")
                    }
                    // Stop if page returned no items (avoid infinite pagination)
                    if items.isEmpty { break }
                    if nextMaxId != nil {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                } while nextMaxId != nil
            } catch let igErr as InstagramError {
                let isChallengeOrBot: Bool
                switch igErr {
                case .challengeRequired: isChallengeOrBot = true
                case .botDetected: isChallengeOrBot = true
                default: isChallengeOrBot = false
                }
                if isChallengeOrBot {
                    let streak = await MainActor.run { InstagramService.shared.challengeRequiredStreak }
                    let reloginHint = streak >= 2
                        ? "\n\nThis has happened multiple times. Try logging out and back in (Settings) to refresh the session."
                        : ""
                    print("⚠️ [RE-VERIFY] challenge_required on feed fetch — Instagram soft-check (streak: \(streak))")
                    LogManager.shared.warning("Re-verify: feed returned challenge_required (streak: \(streak))", category: .api)
                    await MainActor.run {
                        manager.reverifyError = "Instagram requires a temporary check. Wait a few minutes and try again." + reloginHint
                        manager.isReverifying = false
                        manager.reverifyTask = nil
                    }
                } else {
                    print("❌ [RE-VERIFY] Failed to fetch feed: \(igErr.localizedDescription)")
                    LogManager.shared.warning("Re-verify failed: \(igErr.localizedDescription)", category: .api)
                    await MainActor.run {
                        manager.reverifyError = igErr.localizedDescription
                        manager.isReverifying = false
                        manager.reverifyTask = nil
                    }
                }
                return
            } catch {
                print("❌ [RE-VERIFY] Network error: \(error.localizedDescription)")
                LogManager.shared.warning("Re-verify network error: \(error.localizedDescription)", category: .api)
                await MainActor.run {
                    manager.reverifyError = "Network error — check your connection and try again."
                    manager.isReverifying = false
                    manager.reverifyTask = nil
                }
                return
            }

            print("🔍 [RE-VERIFY] Instagram reports \(visibleOnIG.count / 2) visible post(s) — comparing with \(photoSnapshots.count) local photo(s)")

            // Compare each local photo against the visible feed:
            //   Case A: locally archived=true  but visible on IG → desync, fix to isArchived=false
            //   Case B: locally error/incomplete but visible on IG → upload arrived, needs archive → fix to completed+isArchived=false
            var desynced = 0
            for (index, snap) in photoSnapshots.enumerated() {
                // Normalize local mediaId: try both raw form and pk-only (strips _userId suffix)
                let localPkOnly = snap.mediaId.split(separator: "_").first.map(String.init) ?? snap.mediaId
                let isVisibleOnIG = visibleOnIG.contains(snap.mediaId) || visibleOnIG.contains(localPkOnly)
                print("🔍 [RE-VERIFY]   [\(index)] mediaId=\(snap.mediaId) pkOnly=\(localPkOnly) visibleOnIG=\(isVisibleOnIG) isArchived=\(snap.isArchived) status=\(snap.status)")

                if isVisibleOnIG && snap.isArchived {
                    // Case A: app thinks archived but IG shows it public
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
                    print("⚠️ [RE-VERIFY] Case A desync: \(snap.mediaId) visible on IG but locally archived → fixed")
                    LogManager.shared.warning("Re-verify desync: \(snap.mediaId) is public on IG, fixed local state", category: .general)

                } else if isVisibleOnIG && snap.status != .completed {
                    // Case B: upload succeeded on IG (photo is visible) but local state is error/incomplete
                    // Mark as completed+not-archived so Sync & Archive can pick it up
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
                    print("⚠️ [RE-VERIFY] Case B orphan: \(snap.mediaId) visible on IG but local status=\(snap.status) → marked completed+visible")
                    LogManager.shared.warning("Re-verify orphan: \(snap.mediaId) is public on IG, local was \(snap.status) → fixed", category: .general)
                }

                await MainActor.run {
                    manager.reverifyProgress = index + 1
                    manager.reverifyDesynced = desynced
                }
            }

            // ── ORPHAN CLEANUP ───────────────────────────────────────────────
            // Remove from the profile cache any media item whose ID is NOT in the
            // current visible feed. This catches "ghost" uploads: photos that reached
            // Instagram but were never tracked by the set (e.g. a failed-retry upload
            // where the first attempt's pk was never saved), which kept showing in
            // the Performance grid even though the set believed everything was archived.
            // NOTE: reads from disk directly (loadProfile) so it works even when
            //       the in-memory cachedProfile is nil (e.g. cleared by another path).
            await MainActor.run {
                let cache = ProfileCacheService.shared
                // Prefer in-memory; fall back to disk so we never miss orphans
                guard let cached = cache.cachedProfile ?? cache.loadProfile() else {
                    print("🔍 [RE-VERIFY] Orphan cleanup: no profile on disk — skipping")
                    return
                }
                guard !cached.cachedMediaItems.isEmpty else {
                    print("🔍 [RE-VERIFY] Orphan cleanup: cachedMediaItems empty — skipping")
                    return
                }

                print("🔍 [RE-VERIFY] Orphan cleanup: checking \(cached.cachedMediaItems.count) cached items against \(visibleOnIG.count / 2) visible IDs")

                // Find items in the profile cache that are NOT in the visible feed
                let orphanItems = cached.cachedMediaItems.filter { item in
                    let pkOnly = item.mediaId.split(separator: "_").first.map(String.init) ?? item.mediaId
                    let found = visibleOnIG.contains(item.mediaId) || visibleOnIG.contains(pkOnly)
                    if !found {
                        print("🔍 [RE-VERIFY]   orphan candidate: mediaId=\(item.mediaId)")
                    }
                    return !found
                }

                guard !orphanItems.isEmpty else {
                    print("🔍 [RE-VERIFY] Orphan cleanup: no orphans found")
                    return
                }

                let orphanURLs  = Set(orphanItems.map { $0.imageURL })
                let cleanedURLs  = cached.cachedMediaURLs.filter  { !orphanURLs.contains($0) }
                let cleanedItems = cached.cachedMediaItems.filter  { !orphanURLs.contains($0.imageURL) }

                // Write directly to disk via saveProfile so both disk + memory are updated.
                // Use struct copy so all other fields stay intact.
                var cleaned = cached
                cleaned.cachedMediaURLs  = cleanedURLs
                cleaned.cachedMediaItems = cleanedItems
                cache.saveProfile(cleaned)

                print("🔍 [RE-VERIFY] Orphan cleanup: removed \(orphanItems.count) ghost post(s) from profile cache ✅")
                for item in orphanItems {
                    print("🔍 [RE-VERIFY]   removed ghost mediaId=\(item.mediaId)")
                }
                LogManager.shared.info("Re-verify: removed \(orphanItems.count) ghost post(s) from profile cache", category: .general)
            }
            // ────────────────────────────────────────────────────────────────────

            // ── GHOST ARCHIVER ────────────────────────────────────────────────────
            // Detect and archive visible posts that are NOT tracked in this set but
            // whose media ID falls within the upload range of this set's tracked
            // photos. These are "ghost" uploads: posts the app sent to Instagram but
            // failed to persist in the set data (e.g. a crashed retry). Legitimate
            // old user posts have much lower IDs and are never matched.
            let allTrackedMediaIds = Set(photoSnapshots.map { $0.mediaId })
            let trackedInt64s = allTrackedMediaIds.compactMap { Int64($0) }
            if let minTracked = trackedInt64s.min() {
                // Collect unique numeric IDs from the live feed
                let uniqueVisibleNumericIds = visibleOnIG.filter { Int64($0) != nil }
                let ghostIds = uniqueVisibleNumericIds.filter { id in
                    guard let idInt = Int64(id) else { return false }
                    return idInt >= minTracked && !allTrackedMediaIds.contains(id)
                }
                if !ghostIds.isEmpty {
                    print("🔍 [RE-VERIFY] Ghost archiver: found \(ghostIds.count) untracked visible post(s) in upload range — archiving")
                    for ghostId in ghostIds {
                        print("🔍 [RE-VERIFY]   archiving ghost: \(ghostId)")
                        do {
                            let ok = try await InstagramService.shared.archivePhoto(mediaId: ghostId, skipPreCheck: true)
                            print("🔍 [RE-VERIFY]   \(ok ? "✅" : "⚠️") archive result for ghost \(ghostId): \(ok)")
                        } catch {
                            print("🔍 [RE-VERIFY]   ❌ failed to archive ghost \(ghostId): \(error)")
                        }
                    }
                    // Remove archived ghosts from profile cache
                    await MainActor.run {
                        let cache = ProfileCacheService.shared
                        guard let cached = cache.cachedProfile ?? cache.loadProfile() else { return }
                        let ghostURLs = Set(cached.cachedMediaItems.filter { ghostIds.contains($0.mediaId) }.map { $0.imageURL })
                        guard !ghostURLs.isEmpty else { return }
                        var cleaned = cached
                        cleaned.cachedMediaURLs  = cached.cachedMediaURLs.filter  { !ghostURLs.contains($0) }
                        cleaned.cachedMediaItems = cached.cachedMediaItems.filter { !ghostURLs.contains($0.imageURL) }
                        cache.saveProfile(cleaned)
                        print("🔍 [RE-VERIFY] Ghost archiver: removed \(ghostURLs.count) ghost URL(s) from profile cache ✅")
                        LogManager.shared.info("Re-verify: archived and removed \(ghostIds.count) ghost post(s)", category: .general)
                    }
                } else {
                    print("🔍 [RE-VERIFY] Ghost archiver: no untracked posts in upload range")
                }
            }
            // ────────────────────────────────────────────────────────────────────

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
        guard !instagram.isLocked else {
            print("⚠️ [S&A] Skipped — lockdown active")
            return
        }
        // ANTI-BOT: If the session is already expired (commonly carried over
        // from a previous bot-detection that persisted to UserDefaults), do
        // not even start the batch — every GET would just rebuild the same
        // 403 wall against an invalidated token. Bounce the user to re-login.
        if instagram.isSessionExpired {
            print("⚠️ [S&A] Skipped — session already expired (re-login required)")
            LogManager.shared.warning("S&A blocked: session already expired — user must re-login", category: .auth)
            UploadManager.shared.sendSessionExpiredNotification()
            return
        }
        let archiveSafety = InstagramSafetyGate.shared.decision(for: .archive)
        guard archiveSafety.allowed else {
            print("🛡️ [S&A] Skipped — \(archiveSafety.reason) (\(archiveSafety.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — Sync & Archive blocked: \(archiveSafety.reason)", category: .api)
            return
        }
        // ANTI-BOT: Refuse to re-sync the same set within 5 min. Repeating the
        // exact same /media/{pk}/info/ sequence on the same 10 photos is the
        // pattern that triggered the May 15 HTTP 403.
        let setKey = currentSet.id.uuidString
        let setCooldown = InstagramSafetyGate.shared.canSyncSet(setId: setKey)
        guard setCooldown.allowed else {
            print("🛡️ [S&A] Skipped — \(setCooldown.reason) (\(setCooldown.waitSeconds)s)")
            LogManager.shared.warning("SAFETY BLOCK — Sync & Archive blocked: \(setCooldown.reason)", category: .api)
            return
        }

        // ANTI-BOT: If there has been a burst of recent API activity (e.g. the user
        // Two-tier burst detection before S&A:
        //   Heavy (12 actions / 10 min): covers a full performance with reveals, profile
        //   visits and bio changes spread over several minutes → 120 s buffer.
        //   Light  (8 actions / 90 s):  rapid-fire activity moments before → 20 s buffer.
        let heavyBurst = instagram.hasRecentApiBurst(threshold: 12, seconds: 600)
        let lightBurst = !heavyBurst && instagram.hasRecentApiBurst(threshold: 8, seconds: 90)
        let burstBufferSec = heavyBurst ? 120 : (lightBurst ? 20 : 0)

        if burstBufferSec > 0 {
            let burstLabel = heavyBurst ? "heavy (12/600s)" : "light (8/90s)"
            LogManager.shared.info("S&A: \(burstLabel) burst — adding \(burstBufferSec)s safety buffer", category: .api)
            print("⏸️ [S&A] Burst detected (\(burstLabel)) — \(burstBufferSec)s buffer before first state check")
            await MainActor.run {
                isPausingBeforeArchive = true
                saCountdownSeconds = burstBufferSec
            }
            for _ in 0..<burstBufferSec {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { saCountdownSeconds = max(0, saCountdownSeconds - 1) }
            }
            await MainActor.run {
                isPausingBeforeArchive = false
                saCountdownSeconds = 0
            }
        }

        // ANTI-BOT: Wait out cold-start / warm-resume window before starting the
        // full batch. Shows a countdown via isPausingBeforeArchive in the UI.
        await waitForColdStartIfNeeded(label: "sync & archive")

        // Mark set-sync start AFTER the cold-start wait so the 5-min cooldown
        // is measured from when work actually began.
        InstagramSafetyGate.shared.markSetSyncStarted(setId: setKey)

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
            archiveStopReason = nil
        }

        // ── PHASE 1: VERIFY ──────────────────────────────────────────────
        print("🔄 [S&A] Phase 1: verifying \(photos.count) photo(s)")
        LogManager.shared.info("State sync started: \(photos.count) visible photos to check", category: .general)

        var confirmedToArchive: [String] = []
        var fixed = 0
        var unknown = 0
        var skippedProtected = 0
        // Track whether at least one /media/{pk}/info/ actually hit the network
        // in this run. Used to randomize gaps only between real requests — back
        // to back cache hits or protected-skips don't need to space apart.
        var didNetworkRequestLast = false
        // ANTI-BOT: If the session gets challenge_required during state checks,
        // abort the whole S&A rather than continuing with the archive phase.
        // In the May 16 incident, 3 challenge_required errors occurred during
        // state checks but S&A continued, leading to archives going through and
        // then a GET /feed/user/ triggering a second challenge_required.
        var consecutiveChallengeErrors = 0

        for (index, photo) in photos.enumerated() {
            guard let mediaId = photo.mediaId else {
                unknown += 1
                continue
            }

            // ANTI-BOT: Don't even ask Instagram about media we just revealed.
            // The reveal → check → archive ping-pong is the pattern they flag.
            if InstagramSafetyGate.shared.isMediaPostRevealProtected(mediaId: mediaId) {
                skippedProtected += 1
                await MainActor.run { syncProgress = index + 1 }
                LogManager.shared.info("S&A: skipped state-check for \(mediaId) — post-reveal protected", category: .general)
                continue
            }

            // ANTI-BOT: Randomized gap between real /media/info/ requests
            // (2.5–4.5s) replaces the previous mechanical 1.5s. Mechanical
            // intervals are trivially fingerprinted; jitter breaks the
            // clockwork pattern. Cache hits / protected skips don't add a gap.
            if didNetworkRequestLast {
                let nanos = UInt64.random(in: 2_500_000_000...4_500_000_000)
                let secs = Double(nanos) / 1_000_000_000
                print(String(format: "⏳ [S&A] Waiting %.1fs before next check…", secs))
                try? await Task.sleep(nanoseconds: nanos)
            }

            await MainActor.run { syncProgress = index + 1 }

            do {
                // Distinguish cache-hit vs network-hit so the gap policy works.
                // Pre-check: if the SafetyGate cache or InstagramService cache
                // would serve this, the next iteration shouldn't add a long gap.
                let beforeActions = instagram.actionsThisHour
                let result = try await instagram.getMediaIsArchived(mediaId: mediaId)
                didNetworkRequestLast = instagram.actionsThisHour > beforeActions

                switch result {
                case .some(true):
                    // Already archived on Instagram — fix local desync
                    consecutiveChallengeErrors = 0
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
                    consecutiveChallengeErrors = 0
                    confirmedToArchive.append(mediaId)
                    LogManager.shared.info("State sync: \(mediaId) confirmed public on Instagram", category: .general)

                case .none:
                    unknown += 1
                    consecutiveChallengeErrors += 1
                    LogManager.shared.warning("State sync: could not determine state for \(mediaId)", category: .general)
                }
                // If 2+ consecutive state-checks fail (challenge_required), abort now.
                // Continuing into the archive phase after a challenge streak risks
                // compounding the bot signal with more API calls.
                if consecutiveChallengeErrors >= 2 {
                    LogManager.shared.warning("S&A aborted: \(consecutiveChallengeErrors) consecutive challenge errors during state checks — waiting for cooldown", category: .api)
                    await MainActor.run {
                        isSyncing = false
                        uploadManager.isSyncArchiveActive = false
                        archiveStopReason = String(localized: "Instagram verification required — wait a few minutes and try again")
                    }
                    return
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
        if skippedProtected > 0 {
            LogManager.shared.info("S&A: \(skippedProtected) photo(s) skipped (post-reveal protected)", category: .general)
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
        // Anti-bot: if a photo upload is running in parallel, pause it first.
        // Concurrent POST requests (archive + upload) from the same session
        // increase bot-detection risk and can cause silent archive failures.
        if uploadManager.isUploading {
            print("⏸️ [S&A] Pausing active upload before archiving (anti-bot)")
            LogManager.shared.info("S&A: pausing upload to avoid concurrent API calls", category: .general)
            await MainActor.run { uploadManager.requestPause = true }
            // Give the upload loop up to 6 s to react and actually stop
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
                if uploadManager.isPaused || !uploadManager.isUploading { break }
            }
            print("⏸️ [S&A] Upload stopped — starting archive phase")
        }

        print("📦 [S&A] Phase 2: archiving \(confirmedToArchive.count) photo(s) (no pre-check GET)")
        LogManager.shared.info("Archive All started: \(confirmedToArchive.count) photo(s)", category: .general)

        await MainActor.run {
            isArchivingAll = true
            archiveAllProgress = 0
            archiveAllTotal = confirmedToArchive.count
        }

        var archived = 0
        var stoppedReason: String? = nil
        for (index, mediaId) in confirmedToArchive.enumerated() {
            // Rate limit guard
            let rateLimit = instagram.checkRateLimit()
            if rateLimit.limited || rateLimit.remaining < 2 {
                LogManager.shared.warning("S&A archive stopped: rate limit (used: \(rateLimit.actionsUsed))", category: .api)
                stoppedReason = String(localized: "Hourly rate limit reached — try again later")
                break
            }

            let perItemSafety = InstagramSafetyGate.shared.canArchive(mediaId: mediaId)
            if !perItemSafety.allowed {
                LogManager.shared.warning("SAFETY BLOCK — S&A archive paused for \(perItemSafety.waitSeconds)s: \(perItemSafety.reason)", category: .api)
                stoppedReason = String(localized: "Some photos are post-reveal protected — try again later")
                break
            }

            // ANTI-BOT: Archive budget is 8 per 10-min rolling window. If we're
            // at the cap, don't fail — pause in-place with a visible countdown
            // and resume when a slot frees up. This converts what used to be a
            // "failed to archive after retry" into a transparent safe pause.
            // Wait can be up to ~10 min, but the loop polls the gate each
            // second so as soon as the oldest archive falls out of the window
            // we get a green light.
            var budgetPauseInitialSeconds: Int?
            var lastBudgetLogBucket: Int?
            while true {
                let budget = InstagramSafetyGate.shared.decision(for: .archive)
                if budget.allowed { break }
                // Bail out only when the wait is unreasonable (>12 min, which
                // can only happen if the user just ran another big batch).
                if budget.waitSeconds > 720 {
                    LogManager.shared.warning("S&A archive deferred: budget cooldown \(budget.waitSeconds)s — \(budget.reason)", category: .api)
                    stoppedReason = String(
                        format: String(localized: "Safety pause — %d photo(s) will be archived later"),
                        confirmedToArchive.count - archived
                    )
                    break
                }
                let snapshot = budget.waitSeconds
                await MainActor.run { saCountdownSeconds = snapshot }
                print("⏸️ [S&A] Budget pause — waiting \(snapshot)s before continuing (\(budget.reason))")
                let bucket = snapshot / 30
                if budgetPauseInitialSeconds == nil {
                    budgetPauseInitialSeconds = snapshot
                    lastBudgetLogBucket = bucket
                    LogManager.shared.info("S&A: archive budget exceeded — pausing for \(snapshot)s (\(budget.reason))", category: .upload)
                } else if bucket != lastBudgetLogBucket && snapshot % 30 == 0 {
                    lastBudgetLogBucket = bucket
                    LogManager.shared.info("S&A: still waiting — \(snapshot)s remaining", category: .upload)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if let initial = budgetPauseInitialSeconds {
                LogManager.shared.info("S&A: pause completed after \(initial)s", category: .upload)
            }
            // If the inner while bailed out (long cooldown), stop the loop too.
            if stoppedReason != nil { break }
            await MainActor.run { saCountdownSeconds = 0 }

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
                    // Remove from ProfileCache so PerformanceView grid updates instantly
                    ProfileCacheService.shared.removeMediaItem(byMediaId: mediaId)
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
        InstagramSafetyGate.shared.markHeavyArchiveCompleted(photoCount: archived)

        let finalStopReason = stoppedReason
        await MainActor.run {
            isArchivingAll = false
            archiveAllCompleted = true
            uploadManager.isSyncArchiveActive = false
            archiveStopReason = finalStopReason
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

                    // E: Network status pill — visible whenever the upload is active.
                    HStack {
                        Spacer()
                        networkStatusPill
                    }

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
                    uploadInfoBanner
                    
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
                        
                        completedActionsSection
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
        func fmt(_ secs: Int) -> String { "\(secs / 60):\(String(format: "%02d", secs % 60))" }
        switch uploadManager.uploadPhase {
        case .idle:
            return String(localized: "Ready to upload")
        case .uploading(let n):
            return String(format: String(localized: "Uploading photo #%d of %d"), n, uploadManager.uploadProgress.total)
        case .archiving(let n):
            return String(format: String(localized: "Archiving photo #%d..."), n)
        case .waiting(_, let secs):
            return String(format: String(localized: "Next photo in %@"), fmt(secs))
        case .cooldown(let secs):
            return String(format: String(localized: "Cooldown %@"), fmt(secs))
        case .autoRetrying(let secs, let att):
            return String(format: String(localized: "Retrying in %@ (attempt %d/3)"), fmt(secs), att)
        case .waitingNetwork(let att):
            if att == 0 {
                return uploadManager.networkAutoResumeCountdown > 0
                    ? String(format: String(localized: "Auto-resuming in %ds..."), uploadManager.networkAutoResumeCountdown)
                    : String(localized: "Verifying connection...")
            }
            return String(format: String(localized: "Waiting for connection... (attempt %d/3)"), att)
        case .paused:
            return String(localized: "Upload Paused")
        case .escalatedPause(let secs):
            return String(format: String(localized: "Cooling down %@"), fmt(secs))
        case .botLockdown(let secs):
            return String(format: String(localized: "Locked %@"), fmt(secs))
        case .sessionExpired:
            return String(localized: "Session Expired")
        case .completed:
            return String(localized: "Upload Completed")
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
                Text(String(format: String(localized: "Attempt %d of 3"), attempt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .waitingNetwork(let attempt):
            if attempt == 0 {
                // Smart auto-resume UI (D) — shown after WiFi → Cellular or similar change.
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: networkConnectionIcon(uploadManager.networkReconnectingTo.isEmpty
                            ? instagram.connectionType : uploadManager.networkReconnectingTo))
                            .font(.title3)
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connection changed")
                                .font(.subheadline.bold())
                                .foregroundColor(.yellow)
                            let connName = uploadManager.networkReconnectingTo.isEmpty
                                ? instagram.connectionType : uploadManager.networkReconnectingTo
                            if !connName.isEmpty && connName != "unknown" {
                                Text("Now on: \(connName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if uploadManager.networkAutoResumeCountdown > 0 {
                            Text("\(uploadManager.networkAutoResumeCountdown)s")
                                .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                                .foregroundColor(.yellow)
                                .monospacedDigit()
                        }
                    }
                    HStack(spacing: 6) {
                        ProgressView().tint(.yellow).scaleEffect(0.85)
                        Text(uploadManager.networkAutoResumeCountdown > 0
                             ? "Upload will resume automatically — no action needed"
                             : "Verifying connection before resuming...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.yellow)
                        Text("Waiting for connection...")
                            .font(.subheadline)
                            .foregroundColor(.yellow)
                    }
                    Text(String(format: String(localized: "Attempt %d of 3 - Will retry automatically"), attempt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
            }
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
    
    private func countdownDisplay(seconds: Int, color: Color, label: LocalizedStringKey) -> some View {
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
                Text(String(format: String(localized: "%d/%d completed - Waiting %@ for photo #%d"),
                            uploadManager.uploadProgress.current, uploadManager.uploadProgress.total,
                            "\(seconds / 60):\(String(format: "%02d", seconds % 60))", nextPhoto))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(String(format: String(localized: "%d / %d"),
                            uploadManager.uploadProgress.current, uploadManager.uploadProgress.total))
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
            case .cooldown, .autoRetrying:
                // Auto-managed phases — no button (system handles it)
                EmptyView()
            case .waitingNetwork(let att):
                if att == 0 {
                    // Smart auto-resume: offer a "Resume Now" shortcut to skip the wait.
                    Button(action: {
                        networkAutoResumeTask?.cancel()
                        networkAutoResumeTask = nil
                        uploadManager.networkAutoResumeCountdown = 0
                        uploadManager.networkReconnectingTo = ""
                        resumeUpload()
                    }) {
                        Label("Resume Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.yellow.opacity(0.85))
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                    }
                } else {
                    EmptyView()
                }
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
                    Label(String(format: String(localized: "Resume in %@"), "\(seconds / 60):\(String(format: "%02d", seconds % 60))"), systemImage: "clock.fill")
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
                    Label(String(format: String(localized: "Locked %@"), "\(seconds / 60):\(String(format: "%02d", seconds % 60))"), systemImage: "lock.fill")
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

                uploadInfoBanner
            }
        }
    }
    
    // MARK: - Network Status Pill (E)

    /// Small pill showing the current connection type and stability during an active upload.
    private var networkStatusPill: some View {
        let type = instagram.connectionType
        let connected = instagram.isConnected
        let stabilising = instagram.isNetworkStabilizing
        let label = connected ? (stabilising ? "Stabilising…" : type) : "No connection"
        let color: Color = connected ? (stabilising ? .yellow : .green) : .red
        let icon = networkConnectionIcon(type)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(20)
        .animation(.easeInOut(duration: 0.3), value: connected)
        .animation(.easeInOut(duration: 0.3), value: stabilising)
        .animation(.easeInOut(duration: 0.3), value: type)
    }

    /// SF Symbol name for a given connection type string.
    private func networkConnectionIcon(_ type: String) -> String {
        switch type {
        case "WiFi":     return "wifi"
        case "Cellular": return "antenna.radiowaves.left.and.right"
        case "Ethernet": return "cable.connector"
        default:         return "network"
        }
    }

    // MARK: - Upload Info Banner

    private var uploadInfoBanner: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "FFD60A"))
                Text(String(localized: "upload.tip.title"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "FFD60A"))
                Spacer()
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 17, alignment: .top)
                    .padding(.top, 1)
                Text(String(localized: "upload.tip.overnight"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 17, alignment: .top)
                    .padding(.top, 1)
                Text(String(localized: "upload.tip.background"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFD60A").opacity(0.07))
        .cornerRadius(VaultTheme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.md)
                .strokeBorder(Color(hex: "FFD60A").opacity(0.22), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    // MARK: - Completed Actions Section

    private var completedActionsSection: some View {
        VStack(spacing: 12) {
            let hasUnuploadedPhotos = currentSet.photos.contains { $0.mediaId == nil }

            if hasUnuploadedPhotos {
                // Show lockdown countdown inline so the user never sees the wifi overlay
                // just because they tapped "Start Uploading" while a safety lockdown is active.
                let isLocked = instagram.isLocked
                let lockSeconds: Int = {
                    guard let until = instagram.lockUntil else { return 0 }
                    return max(0, Int(until.timeIntervalSinceNow))
                }()

                Button {
                    guard !uploadManager.isActive else { return }
                    if instagram.isLocked {
                        // Tapping while locked: show the lockdown details sheet instead
                        // of letting the upload attempt fail visually with a wifi overlay.
                        showingLockdownSheet = true
                        return
                    }
                    dataManager.updateSetStatus(id: currentSet.id, status: .ready)
                    Task { await uploadAllPhotos() }
                } label: {
                    if isLocked && lockSeconds > 0 {
                        let m = lockSeconds / 60
                        let s = lockSeconds % 60
                        let cd = m > 0 ? "\(m)m \(s)s" : "\(s)s"
                        Label("Locked — \(cd)", systemImage: "lock.shield.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                    } else {
                        Label("Start Uploading", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(VaultTheme.Colors.primary)
                            .cornerRadius(VaultTheme.CornerRadius.sm)
                    }
                }
                .disabled(uploadManager.isActive)
                .onReceive(safetySectionTimer) { _ in
                    // safetySectionTimer already ticks every second — reuse it to
                    // refresh the lockdown countdown without adding a second timer.
                    safetyCountdownTick += 1
                }
                uploadInfoBanner
            }

            if currentSet.type == .word || currentSet.type == .number {
                Button {
                    _ = dataManager.addBank(setId: currentSet.id)
                    dataManager.updateSetStatus(id: currentSet.id, status: .ready)
                } label: {
                    Label("Add Another Bank", systemImage: "plus.rectangle.on.rectangle")
                        .font(.subheadline.bold())
                        .foregroundColor(VaultTheme.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VaultTheme.Colors.primary.opacity(0.12))
                        .cornerRadius(VaultTheme.CornerRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: VaultTheme.CornerRadius.sm)
                                .stroke(VaultTheme.Colors.primary.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            Text(String(format: String(localized: "%lld archived • %lld visible"), archivedCount, visibleCount))
                .font(.caption2)
                .foregroundColor(.secondary)
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
            
            Text(String(format: String(localized: "%lld archived • %lld visible"), archivedCount, visibleCount))
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
    
    @ViewBuilder private var banksTabsWithActions: some View {
        // Show + / trash whenever type supports banks AND this set is not mid-upload.
        // ".paused", ".idle", ".completed", botLockdown, etc. all allow bank management.
        // Only hide when THIS specific set is actively uploading (counting/archiving/cooldown…).
        let isThisSetMidUpload = uploadManager.activeSetId == currentSet.id && uploadManager.isUploading
        let showActions = (currentSet.type == .word || currentSet.type == .number) && !isThisSetMidUpload
        // A bank is safe to delete when it has more than 1 bank AND the last
        // bank contains no photos that were already archived on Instagram
        // (uploadStatus != .pending). Photos that are "ready for archive"
        // (pending + imageData != nil) have NOT yet been sent to Instagram, so
        // deleting them is safe and must be allowed.
        let canDelete: Bool = {
            guard currentSet.banks.count > 1 else { return false }
            guard let last = currentSet.banks.max(by: { $0.position < $1.position }) else { return false }
            let bankPhotos = currentSet.photos.filter { $0.bankId == last.id }
            return !bankPhotos.contains(where: { $0.uploadStatus != .pending })
        }()

        if !currentSet.banks.isEmpty || showActions {
            HStack(spacing: 8) {
                // Tabs — scrollable
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaultTheme.Spacing.sm) {
                        ForEach(Array(currentSet.banks.enumerated()), id: \.element.id) { index, bank in
                            Button(action: { selectedBankIndex = index }) {
                                Text(bank.name)
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

                if showActions {
                    // Thin separator between tabs and action buttons
                    Divider()
                        .frame(height: 24)
                        .opacity(0.4)

                    // Add bank
                    Button {
                        _ = dataManager.addBank(setId: currentSet.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(VaultTheme.Colors.primary)
                            .frame(width: 34, height: 34)
                            .background(VaultTheme.Colors.primary.opacity(0.15))
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    // Delete last bank — clamp selectedBankIndex to prevent an
                    // out-of-bounds crash when the tab that was selected is removed.
                    Button {
                        dataManager.removeLastBank(setId: currentSet.id)
                        let newCount = currentSet.banks.count  // already decremented by removeLastBank
                        selectedBankIndex = min(max(selectedBankIndex, 0), max(0, newCount - 1))
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(canDelete ? .red : Color(white: 0.5))
                            .frame(width: 34, height: 34)
                            .background(canDelete ? Color.red.opacity(0.12) : Color(white: 0.5).opacity(0.12))
                            .cornerRadius(9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(canDelete ? Color.red.opacity(0.25) : Color(white: 0.5).opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete)
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
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(VaultTheme.Colors.success)
                .cornerRadius(VaultTheme.CornerRadius.sm)
            }
            .disabled(!consecutiveDuplicates.isEmpty)
            .opacity(consecutiveDuplicates.isEmpty ? 1.0 : 0.5)
        } else {
            let hasPending = currentSet.photos.contains(where: { $0.uploadStatus == .pending || $0.uploadStatus == .error })
            if hasPending {
                Button(action: {
                    withAnimation { isReorderMode = true }
                    checkConsecutiveDuplicates()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("Reorder")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(VaultTheme.Colors.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(VaultTheme.Colors.primary.opacity(0.1))
                    .cornerRadius(VaultTheme.CornerRadius.sm)
                }
            }
        }
    }
    
    // MARK: - Photos Grid

    private var listSetControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .foregroundColor(Color(hex: "64D2FF"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("List Set")
                        .font(.headline)
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Text("Import TXT/CSV labels, then link one photo or video to each item.")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                }
                Spacer()
                Button {
                    showListImport = true
                } label: {
                    Label("Import TXT/CSV", systemImage: "square.and.arrow.down")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: "0A84FF"))
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Picker("Columns", selection: Binding(
                    get: { currentSet.resolvedListColumns },
                    set: { dataManager.setListLayout(setId: currentSet.id, columns: $0) }
                )) {
                    ForEach(ListSetColumns.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color(hex: "64D2FF"))

                Picker("Button Size", selection: Binding(
                    get: { currentSet.resolvedListButtonSize },
                    set: { dataManager.setListLayout(setId: currentSet.id, buttonSize: $0) }
                )) {
                    ForEach(ListSetButtonSize.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color(hex: "64D2FF"))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Group separators")
                        .font(.caption.bold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    if !currentSet.resolvedListSeparators.isEmpty {
                        Text(currentSet.resolvedListSeparators.map { "after \($0)" }.joined(separator: ", "))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color(hex: "64D2FF"))
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    Stepper(value: $listSeparatorSlot, in: 1...max(1, currentSet.listDisplayLabels.count - 1)) {
                        Text("After slot \(listSeparatorSlot)")
                            .font(.caption)
                            .foregroundColor(VaultTheme.Colors.textSecondary)
                    }
                    .tint(Color(hex: "64D2FF"))

                    Button {
                        dataManager.addListSeparator(setId: currentSet.id, afterSlot: listSeparatorSlot)
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(hex: "64D2FF"))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentSet.listDisplayLabels.count < 2)
                    .opacity(currentSet.listDisplayLabels.count < 2 ? 0.5 : 1)
                }

                if !currentSet.resolvedListSeparators.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(currentSet.resolvedListSeparators, id: \.self) { separator in
                                Button {
                                    dataManager.removeListSeparator(setId: currentSet.id, afterSlot: separator)
                                } label: {
                                    HStack(spacing: 5) {
                                        Text("After \(separator)")
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Color(hex: "64D2FF"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "64D2FF").opacity(0.12))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)

            if !activeSetSettings.isActive(currentSet.id, type: currentSet.type) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                    Text("Set this list as active before entering Performance, otherwise the private list will not appear.")
                        .font(.caption)
                        .foregroundColor(VaultTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(9)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Performance Preview")
                        .font(.caption.bold())
                        .foregroundColor(VaultTheme.Colors.textPrimary)
                    Spacer()
                    Text("\(currentSet.listDisplayLabels.count) items")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color(hex: "64D2FF"))
                }

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(listPreviewGroups.enumerated()), id: \.offset) { groupIndex, group in
                            if groupIndex > 0 {
                                HStack {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(height: 1)
                                    Text("GROUP \(groupIndex + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.48))
                                    Rectangle()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(height: 1)
                                }
                            }

                            LazyVGrid(columns: listPreviewColumns, spacing: 10) {
                                ForEach(group, id: \.symbol) { item in
                                    let buttonColor = listPreviewButtonColor(at: item.offset)
                                    Text(item.label)
                                        .font(.system(size: currentSet.resolvedListButtonSize == .large ? 16 : 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: currentSet.resolvedListButtonSize.minHeight)
                                        .padding(.horizontal, 8)
                                        .background(buttonColor.opacity(0.28))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(buttonColor.opacity(0.72), lineWidth: 1)
                                        )
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: min(280, max(120, CGFloat(currentSet.listDisplayLabels.count) * 10)))
                .background(Color.black)
                .cornerRadius(12)
            }

            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(Color(hex: "64D2FF"))
                Text("Long-press any slot below to rename its list item.")
                    .font(.caption)
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(VaultTheme.Colors.backgroundSecondary)
        .cornerRadius(12)
    }
    
    private var photosGridSection: some View {
        let photosToShow = currentSet.banks.isEmpty
            ? currentSet.photos
            : selectedBankIfAvailable.map { dataManager.getPhotosForBank(setId: currentSet.id, bankId: $0.id) } ?? []
        
        if isReorderMode {
            return AnyView(reorderableGrid(photos: photosToShow))
        } else if currentSet.type == .list {
            return AnyView(slotBasedGrid(
                photos: photosToShow,
                overrideLabels: effectiveSlotLabels,
                displayLabels: listDisplayLabelsBySymbol
            ))
        } else if currentSet.type == .custom {
            return AnyView(slotBasedGrid(photos: photosToShow, overrideLabels: effectiveSlotLabels))
        } else if currentSet.type == .card {
            return AnyView(slotBasedGrid(photos: photosToShow))
        } else if (currentSet.type == .word || currentSet.type == .number) && currentSet.expectedPhotosPerBank > 0 {
            return AnyView(slotBasedGrid(photos: photosToShow))
        } else {
            return AnyView(normalGrid(photos: photosToShow))
        }
    }
    
    // MARK: - Slot-Based Grid (Word/Number Reveal)
    
    private func slotBasedGrid(
        photos: [SetPhoto],
        overrideLabels: [String]? = nil,
        displayLabels: [String: String] = [:]
    ) -> some View {
        let labels = overrideLabels ?? currentSet.slotLabels
        let photosBySymbol = Dictionary(grouping: photos, by: { $0.symbol })

        // Empty slots = slots without a photo or with a photo but no imageData
        let emptyLabels = labels.filter { label in
            guard let p = photosBySymbol[label]?.first else { return true }
            return p.imageData == nil
        }

        return VStack(spacing: 12) {
            // Summary + Select All
            let filled = labels.count - emptyLabels.count
            let total = labels.count

            HStack(spacing: 8) {
                Image(systemName: filled == total ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundColor(filled == total ? .green : .orange)
                Text("\(filled)/\(total) slots filled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if filled < total {
                    Text("(\(emptyLabels.count) missing)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                // Import Photos (bulk load) — hidden until needed
                // if !emptyLabels.isEmpty && !isBulkLoading {
                //     PhotosPicker(
                //         selection: $bulkSelectedItems,
                //         maxSelectionCount: emptyLabels.count,
                //         matching: .images
                //     ) {
                //         HStack(spacing: 5) {
                //             Image(systemName: "photo.stack")
                //                 .font(.system(size: 13))
                //             Text("Import Photos")
                //                 .font(.caption.bold())
                //         }
                //         .foregroundColor(.white)
                //         .padding(.horizontal, 12)
                //         .padding(.vertical, 7)
                //         .background(VaultTheme.Colors.primary)
                //         .cornerRadius(8)
                //     }
                // }
            }
            .padding(.horizontal)

            // Bulk loading progress — hidden until Import Photos is re-enabled
            // if isBulkLoading {
            //     HStack(spacing: 8) {
            //         ProgressView().scaleEffect(0.8).tint(VaultTheme.Colors.primary)
            //         Text("Loading \(bulkLoadProgress.current)/\(bulkLoadProgress.total)…")
            //             .font(.caption)
            //             .foregroundColor(.secondary)
            //     }
            // }

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
                    let visibleLabel = displayLabels[label] ?? label
                    if let photo = photosBySymbol[label]?.first, photo.imageData != nil {
                        // FILLED SLOT: has real image data
                        filledSlotView(photo: photo, label: label, displayLabel: visibleLabel, position: index + 1)
                    } else {
                        // EMPTY SLOT: no image yet (new set or photo removed)
                        emptySlotView(label: label, displayLabel: visibleLabel, position: index + 1)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func filledSlotView(photo: SetPhoto, label: String, displayLabel: String? = nil, position: Int) -> some View {
        let title = displayLabel ?? label
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
                            photo.isArchived
                                ? Color.black.opacity(0.3).cornerRadius(10)
                                : nil
                        )
                }
                
                // Symbol label badge (top-left)
                Text(currentSet.type == .list ? "\(position)" : label)
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
            .onTapGesture {
                filledSlotActionSymbol = label
                filledSlotActionIsUploaded = photo.mediaId != nil
                showFilledSlotActions = true
            }
            .contextMenu {
                if currentSet.type == .list {
                    Button("Rename Item") { startRenamingListItem(label) }
                }
            }

            if currentSet.type == .list {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(VaultTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
            }
            
            // Status text below photo (only when logged in)
            if instagram.isLoggedIn {
                statusTextView(for: photo)
            }
        }
    }
    
    @ViewBuilder
    private func emptySlotView(label: String, displayLabel: String? = nil, position: Int) -> some View {
        let title = displayLabel ?? label
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
                        Text(currentSet.type == .list ? title : label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(VaultTheme.Colors.primary.opacity(0.6))
                            .lineLimit(currentSet.type == .list ? 3 : 1)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                        
                        // Plus icon
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(VaultTheme.Colors.primary.opacity(0.5))
                    }
                }
            }
        }
        .contextMenu {
            if currentSet.type == .list {
                Button("Rename Item") { startRenamingListItem(label) }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func displayLabel(for symbol: String) -> String {
        listDisplayLabelsBySymbol[symbol] ?? symbol
    }

    private func startRenamingListItem(_ symbol: String) {
        listRenameSymbol = symbol
        listRenameText = displayLabel(for: symbol)
        showListRenameAlert = true
    }

    private func importListItems(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let needsSecurity = url.startAccessingSecurityScopedResource()
            defer {
                if needsSecurity { url.stopAccessingSecurityScopedResource() }
            }

            let rawText = try String(contentsOf: url, encoding: .utf8)
            let labels = parseListImport(rawText, isCSV: url.pathExtension.lowercased() == "csv")
            guard !labels.isEmpty else {
                listImportError = "The selected file did not contain any list items."
                return
            }
            dataManager.updateListItems(setId: currentSet.id, labels: labels)
            LogManager.shared.success("Imported \(labels.count) List Set item(s)", category: .general)
        } catch {
            listImportError = error.localizedDescription
        }
    }

    private func parseListImport(_ text: String, isCSV: Bool) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { isCSV ? firstCSVColumn($0) : $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func firstCSVColumn(_ line: String) -> String {
        var result = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        result.append("\"")
                    } else if next == "," {
                        return result
                    } else {
                        isQuoted = false
                        result.append(next)
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if char == "," && !isQuoted {
                return result
            } else {
                result.append(char)
            }
        }

        return result
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
                    let labels = effectiveSlotLabels
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
            }
        }
    }
    
    // MARK: - Bulk Load (Select All empty slots)

    private func loadBulkPhotosIntoEmptySlots(items: [PhotosPickerItem]) {
        let photos = currentSet.photos
        let labels = effectiveSlotLabels
        let photosBySymbol = Dictionary(grouping: photos, by: { $0.symbol })
        let emptyLabels = labels.filter { label in
            guard let p = photosBySymbol[label]?.first else { return true }
            return p.imageData == nil
        }
        guard !emptyLabels.isEmpty else {
            bulkSelectedItems = []
            return
        }
        let itemsToLoad = Array(zip(items, emptyLabels))
        isBulkLoading = true
        bulkLoadProgress = (0, itemsToLoad.count)

        Task {
            for (idx, (item, symbol)) in itemsToLoad.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let validData    = InstagramService.adjustImageAspectRatio(imageData: data)
                let optimized    = InstagramService.compressImageForUpload(imageData: validData, photoIndex: idx)
                let filename     = item.itemIdentifier ?? "photo_\(UUID().uuidString)"
                let existingPhotos = currentSet.photos.filter { $0.symbol == symbol }
                await MainActor.run {
                    if !existingPhotos.isEmpty {
                        dataManager.replacePhotoAtSymbol(
                            setId: currentSet.id, symbol: symbol,
                            newFilename: filename, newImageData: optimized)
                    } else {
                        let position = labels.firstIndex(of: symbol) ?? labels.count
                        dataManager.insertPhotoAtPosition(
                            setId: currentSet.id, symbol: symbol,
                            filename: filename, imageData: optimized, position: position)
                    }
                    bulkLoadProgress = (idx + 1, itemsToLoad.count)
                }
            }
            await MainActor.run {
                isBulkLoading = false
                bulkLoadProgress = (0, 0)
                bulkSelectedItems = []
            }
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
                        
                        // Update with archived metadata (including video info if applicable)
                        if let updatedPhoto = currentSet.photos.first(where: { $0.symbol == symbol }) {
                            dataManager.updatePhoto(
                                photoId: updatedPhoto.id,
                                mediaId: archivedPhoto.mediaId,
                                isArchived: true,
                                uploadStatus: .completed,
                                errorMessage: nil,
                                uploadDate: archivedPhoto.timestamp,
                                isVideo: archivedPhoto.isVideo,
                                videoURL: archivedPhoto.videoURL,
                                videoAspectRatio: archivedPhoto.videoAspectRatio
                            )
                        }
                    } else {
                        // Insert new photo
                        let labels = effectiveSlotLabels
                        let position = labels.firstIndex(of: symbol) ?? labels.count
                        dataManager.insertPhotoAtPosition(
                            setId: currentSet.id,
                            symbol: symbol,
                            filename: filename,
                            imageData: optimizedImageData,
                            position: position
                        )

                        // Update with archived metadata (including video info if applicable)
                        if let newPhoto = currentSet.photos.first(where: { $0.symbol == symbol }) {
                            dataManager.updatePhoto(
                                photoId: newPhoto.id,
                                mediaId: archivedPhoto.mediaId,
                                isArchived: true,
                                uploadStatus: .completed,
                                errorMessage: nil,
                                uploadDate: archivedPhoto.timestamp,
                                isVideo: archivedPhoto.isVideo,
                                videoURL: archivedPhoto.videoURL,
                                videoAspectRatio: archivedPhoto.videoAspectRatio
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
            let bankId = selectedBankIfAvailable?.id
            
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
            : selectedBankIfAvailable.map { dataManager.getPhotosForBank(setId: currentSet.id, bankId: $0.id) } ?? []
        
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

        // Guard: no images loaded — show notification instead of starting an infinite loop
        let readyPhotos = currentSet.photos.filter { $0.imageData != nil && $0.mediaId == nil }
        guard !readyPhotos.isEmpty else {
            print("⚠️ [UPLOAD] No images loaded — aborting upload")
            uploadManager.showingError = String(localized: "upload.error.no_images")
            return
        }

        let rate = instagram.checkRateLimit()
        if rate.actionsUsed >= 25 {
            let message = uploadStartSafetyMessage(rateUsed: rate.actionsUsed)
            print("🛡️ [UPLOAD] Start blocked — too many recent API calls (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("SAFETY BLOCK — upload start blocked: \(rate.actionsUsed)/55 recent API actions", category: .upload)
            uploadManager.safetyBlockMessage = message
            return
        }

        let uploadSafety = InstagramSafetyGate.shared.decision(for: .upload)
        guard uploadSafety.allowed else {
            let message = "Upload paused for safety.\n\nReason: \(uploadSafety.reason).\n\nWait \(uploadSafety.waitSeconds)s before trying again."
            LogManager.shared.warning("SAFETY BLOCK — upload start blocked: \(uploadSafety.reason)", category: .upload)
            uploadManager.safetyBlockMessage = message
            return
        }
        

        // Safe to reset: no active task exists at this point
        uploadManager.resetAllState()

        uploadManager.activeSetId = currentSet.id
        uploadManager.requestPause = false
        uploadManager.uploadPhase = .uploading(photoNumber: 1)
        uploadManager.currentPhaseDescription = String(localized: "Starting upload...")

        let task = Task {
            // GRID ANCHOR (automatic): fetch the first page of visible media and anchor
            // taken_at to 1 second BEFORE the oldest post in that page.
            // Result: when unarchived, the prediction always appears just below every
            // post that existed at upload time — pinned posts stay at top, any new posts
            // uploaded afterwards also stay above it, all without manual configuration.
            do {
                // Anti-bot: wait for cold-start warm-up and network stability
                // before the first API call of the session.
                try await instagram.waitForSessionWarmup()
                try await instagram.waitForNetworkStability()

                let (mediaItems, _) = try await instagram.getUserMediaItems(amount: 21)
                let datedItems = mediaItems.compactMap { $0.takenAt != nil ? $0 : nil }
                                           .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
                if let oldestDate = datedItems.last?.takenAt {
                    uploadTakenAt = oldestDate.addingTimeInterval(-1)
                    print("📍 [GRID ANCHOR] Auto anchor: \(datedItems.count) posts fetched, oldest=\(oldestDate) → taken_at=\(uploadTakenAt!)")
                } else {
                    // No visible posts yet: no override (Instagram places at top, which is correct)
                    uploadTakenAt = nil
                    print("📍 [GRID ANCHOR] No existing posts found — uploading without taken_at override")
                }
            } catch {
                print("⚠️ [GRID ANCHOR] Media fetch failed (\(error)) — uploading without taken_at override")
                uploadTakenAt = nil
            }
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
        // Cancel any pending smart auto-resume task — we are resuming now.
        networkAutoResumeTask?.cancel()
        networkAutoResumeTask = nil

        // B: Network availability check — if the connection is absent or still
        //    stabilising after a recent change, wait it out before firing requests.
        if !instagram.isConnected {
            uploadManager.showingError = "No internet connection.\n\nCheck your WiFi or cellular data and tap Resume when ready."
            LogManager.shared.warning("Resume blocked: no network connection", category: .network)
            return
        }
        if instagram.isNetworkStabilizing {
            let connectingTo = instagram.connectionType
            LogManager.shared.info("Resume: network stabilising (\(connectingTo)) — auto-resume in 15s", category: .network)
            uploadManager.networkReconnectingTo = connectingTo
            uploadManager.networkAutoResumeCountdown = 15
            uploadManager.uploadPhase = .waitingNetwork(attempt: 0)
            uploadManager.currentPhaseDescription = "Connection stabilising — resuming shortly..."
            networkAutoResumeTask = Task { @MainActor in
                for i in stride(from: 15, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    guard case .waitingNetwork(let att) = uploadManager.uploadPhase, att == 0 else { return }
                    uploadManager.networkAutoResumeCountdown = i
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                guard !Task.isCancelled, instagram.isConnected else { return }
                uploadManager.networkAutoResumeCountdown = 0
                uploadManager.networkReconnectingTo = ""
                resumeUpload()
            }
            return
        }

        // Clear challenge gate: user tapped Resume manually, acknowledging they checked Instagram
        uploadManager.requiresManualResumeAfterChallenge = false

        let rate = instagram.checkRateLimit()
        if rate.actionsUsed >= 25 {
            let message = uploadStartSafetyMessage(rateUsed: rate.actionsUsed)
            print("🛡️ [UPLOAD] Resume blocked — too many recent API calls (\(rate.actionsUsed)/55)")
            LogManager.shared.warning("SAFETY BLOCK — upload resume blocked: \(rate.actionsUsed)/55 recent API actions", category: .upload)
            uploadManager.safetyBlockMessage = message
            return
        }

        if InstagramSafetyGate.shared.isInColdStartWindow {
            let remaining = InstagramSafetyGate.shared.coldStartSecondsRemaining
            let message = "Resuming safely. Upload will continue after app warm-up (\(remaining)s)."
            print("⏳ [UPLOAD] Resume delayed — cold-start window \(remaining)s")
            LogManager.shared.info("[COLD-START] Upload resume delayed — \(remaining)s", category: .upload)
            uploadManager.safetyBlockMessage = message
            Task {
                try? await Task.sleep(nanoseconds: UInt64(remaining + Int.random(in: 3...6)) * 1_000_000_000)
                await MainActor.run {
                    guard uploadManager.isPaused,
                          isThisSetActive,
                          !uploadManager.isSyncArchiveActive,
                          !instagram.isLocked,
                          !instagram.isSessionChallenged else { return }
                    uploadManager.safetyBlockMessage = nil
                    resumeUpload()
                }
            }
            return
        }

        let uploadSafety = InstagramSafetyGate.shared.decision(for: .upload)
        guard uploadSafety.allowed else {
            let message = "Upload paused for safety.\n\nReason: \(uploadSafety.reason).\n\nWait \(uploadSafety.waitSeconds)s before resuming."
            LogManager.shared.warning("SAFETY BLOCK — upload resume blocked: \(uploadSafety.reason)", category: .upload)
            uploadManager.safetyBlockMessage = message
            return
        }

        resetErrorState()
        uploadManager.requestPause = false
        uploadManager.invalidateAllTimers()
        // Clear any leftover network-change state from the auto-resume flow.
        uploadManager.networkAutoResumeCountdown = 0
        uploadManager.networkReconnectingTo = ""
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        
        // Update phase immediately
        uploadManager.uploadPhase = .uploading(photoNumber: (uploadManager.failedPhotoIndex ?? 0) + 1)
        uploadManager.currentPhaseDescription = String(localized: "Resuming upload...")
        
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
        uploadManager.currentPhaseDescription = String(localized: "Resuming after skip...")
        
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

    private func isInstagramSafetyPauseError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("safety pause")
            || description.contains("verification pending")
            || description.contains("requires verification")
            || description.contains("challenge_required")
            || description.contains("checkpoint")
            || description.contains("checkpoint_challenge_required")
            || description.contains("instagram verification")
    }

    @MainActor
    private func pauseUploadForSafety(photoIndex: Int, message: String) {
        uploadManager.failedPhotoIndex = photoIndex
        uploadManager.requestPause = false
        uploadManager.invalidateAllTimers()
        uploadManager.uploadPhase = .paused
        uploadManager.currentPhaseDescription = "Upload Paused - Safety"
        uploadManager.safetyBlockMessage = message
        uploadManager.activeTask = nil
        uploadManager.sendUploadSafetyPauseNotification()
        dataManager.updateSetStatus(id: currentSet.id, status: .paused)
        LogManager.shared.warning("SAFETY BLOCK — upload paused: \(message)", category: .upload)
    }

    private func uploadStartSafetyMessage(rateUsed: Int) -> String {
        """
        Upload paused for safety.

        Vault detected \(rateUsed) recent Instagram API actions before starting the upload. Uploading and archiving photos is one of the most sensitive operations, so continuing now could trigger Instagram verification.

        Wait a few minutes, avoid browsing/refreshing profiles, then resume the upload.
        """
    }
    
    // Helper: Check if pause was requested and handle it
    private func checkPauseRequested(atPhotoIndex index: Int) async -> Bool {
        if uploadManager.requestPause {
            print("⏸️ [UPLOAD] Pause requested by user")
            await MainActor.run {
                uploadManager.requestPause = false
                uploadManager.preserveWaitOnAutoPause = false
                uploadManager.invalidateAllTimers()
                uploadManager.failedPhotoIndex = index
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = String(localized: "Upload Paused")
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
        
        // CRITICAL: Check if lockdown is active before starting
        if instagram.isLocked {
            print("🚨 [UPLOAD] Cannot start - lockdown is active")
            await MainActor.run {
                uploadManager.showingError = "Instagram lockdown active. Cannot upload. Wait for lockdown to clear."
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = String(localized: "Upload Paused - Lockdown Active")
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
            await waitWithCountdown(seconds: remainingCooldown, label: String(localized: "Cooldown Active"))
        }

        if startFrom > 0 {
            let preservedWait = uploadManager.remainingWaitSeconds()
            if preservedWait > 0 {
                print("⏳ [UPLOAD] Resuming preserved wait — \(preservedWait)s before next photo")
                LogManager.shared.info("Upload resumed with preserved wait: \(preservedWait)s", category: .upload)
                while true {
                    let remaining = uploadManager.remainingWaitSeconds()
                    if remaining <= 0 { break }
                    if uploadManager.requestPause {
                        if await checkPauseRequested(atPhotoIndex: startFrom) { return }
                    }
                    await MainActor.run {
                        uploadManager.nextPhotoCountdown = remaining
                        uploadManager.uploadPhase = .waiting(nextPhoto: startFrom + 1, remainingSeconds: remaining)
                        uploadManager.currentPhaseDescription = String(format: String(localized: "Next photo in %@"), "\(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                await MainActor.run {
                    uploadManager.clearWaitPersistence()
                    uploadManager.preserveWaitOnAutoPause = false
                }
            }
        }

        let initialRate = instagram.checkRateLimit()
        if initialRate.actionsUsed >= 25 && startFrom == 0 {
            await pauseUploadForSafety(
                photoIndex: startFrom,
                message: uploadStartSafetyMessage(rateUsed: initialRate.actionsUsed)
            )
            return
        }
        
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        
        // ANTI-BOT: Wait if network changed recently (before first upload).
        // waitForUploadSafetyWindow enforces a 15s buffer after any network change
        // (vs. the 4s used by plain waitForNetworkStability) so cellular connections
        // have time to fully establish before Instagram API requests are made.
        do {
            try await instagram.waitForUploadSafetyWindow(label: "upload")
        } catch {
            print("⚠️ [UPLOAD] Network safety window failed: \(error)")
            await MainActor.run {
                dataManager.updateSetStatus(id: currentSet.id, status: .error)
                uploadManager.showingError = "Network error starting upload: \(error.localizedDescription)"
                uploadManager.uploadPhase = .paused
                uploadManager.currentPhaseDescription = String(localized: "Upload Paused - Network Error")
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
        // Rescue pass: catch photos that have a mediaId but are not yet archived.
        // Includes .archiving/.uploaded (normal interrupted states) AND .error (session
        // expired or bot-detected mid-archive — the error handler now leaves those in
        // .archiving, but .error is kept here as a safety net for any edge cases).
        let stuckPhotos = currentSet.photos.filter {
            $0.mediaId != nil && !$0.isArchived &&
            ($0.uploadStatus == .archiving || $0.uploadStatus == .uploaded || $0.uploadStatus == .error)
        }
        if !stuckPhotos.isEmpty {
            print("🔧 [RESCUE] Found \(stuckPhotos.count) photo(s) needing archive recovery...")
            LogManager.shared.warning("Rescue pass: \(stuckPhotos.count) photo(s) with mediaId need archiving (statuses: \(stuckPhotos.map { $0.uploadStatus.rawValue }.joined(separator: ", ")))", category: .upload)

            await MainActor.run {
                uploadManager.uploadPhase = .archiving(photoNumber: 0)
                uploadManager.currentPhaseDescription = String(localized: "Recovering interrupted archives…")
            }

            // ANTI-BOT: Settling pause before the first rescue POST. The app may
            // have just been re-opened after a crash/kill; firing the rescue
            // archive immediately would land a POST right after the cold-start
            // window closes. This 5–10s wait simulates the human moment of
            // "picking the phone back up and re-orienting" and decorrelates the
            // rescue from the launch timestamp. No UX impact: this only runs
            // when there was an interrupted upload from a previous session.
            let settlingSeconds = Double.random(in: 5...10)
            print("⏳ [RESCUE] Settling pause \(String(format: "%.1f", settlingSeconds))s before first rescue archive")
            LogManager.shared.info("Rescue settling pause: \(Int(settlingSeconds))s", category: .upload)
            try? await Task.sleep(nanoseconds: UInt64(settlingSeconds * 1_000_000_000))

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
                    if isInstagramSafetyPauseError(error) {
                        await pauseUploadForSafety(
                            photoIndex: 0,
                            message: """
                            Upload paused for safety.

                            Vault detected Instagram verification or a safety pause while recovering an interrupted archive. It stopped instead of retrying to avoid a stronger checkpoint.
                            """
                        )
                        return
                    }
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

        // If the app/network dies while a photo is in .uploading before a mediaId is
        // saved, it has no rescue path unless we explicitly make it pending again.
        // Otherwise resume-from-index can skip it and leave it visually stuck forever.
        let orphanedUploads = currentSet.photos.filter {
            $0.mediaId == nil && $0.uploadStatus == .uploading
        }
        if !orphanedUploads.isEmpty {
            LogManager.shared.warning("Recovered \(orphanedUploads.count) interrupted upload(s) with no mediaId before resume", category: .upload)
            for orphan in orphanedUploads {
                dataManager.updatePhoto(
                    photoId: orphan.id,
                    mediaId: nil,
                    uploadStatus: .pending,
                    errorMessage: "Recovered interrupted upload"
                )
            }
        }

        let pendingPhotoEntries = currentSet.photos.enumerated().filter { $0.element.mediaId == nil }

        // If retrying, resume by the original photo index. Do NOT drop `startFrom`
        // items from the filtered pending list; completed photos before the failed
        // index are already removed from that list, so dropFirst(startFrom) can skip
        // the actual failed photo and continue with the next letter.
        let photosToUpload = pendingPhotoEntries.filter { $0.offset >= startFrom }

        // Safety: if nothing has imageData ready, stop cleanly (prevents infinite auto-bank recursion)
        let anyReady = photosToUpload.contains { $0.element.imageData != nil }
        if !anyReady {
            print("⚠️ [UPLOAD ALL] No photos with imageData — stopping upload cleanly")
            await MainActor.run {
                uploadManager.showingError = String(localized: "upload.error.no_images")
                uploadManager.uploadPhase = .idle
                uploadManager.activeTask = nil
            }
            dataManager.updateSetStatus(id: currentSet.id, status: .ready)
            return
        }

        let totalPhotos = pendingPhotoEntries.count
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
        
        for (relativeIndex, entry) in photosToUpload.enumerated() {
            let index = entry.offset
            let photo = entry.element
            
            // Check if pause requested
            if await checkPauseRequested(atPhotoIndex: index) { return }
            
            // CRITICAL: Check if lockdown is active (bot detection)
            if instagram.isLocked {
                print("🚨 [UPLOAD] Lockdown is active - STOPPING upload")
                await MainActor.run {
                    dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                    uploadManager.uploadPhase = .paused
                    uploadManager.currentPhaseDescription = String(localized: "Upload Paused - Lockdown Active")
                    uploadManager.activeTask = nil
                }
                return
            }

            let liveRate = instagram.checkRateLimit()
            if liveRate.actionsUsed >= 45 {
                await pauseUploadForSafety(
                    photoIndex: index,
                    message: """
                    Upload paused for safety.

                    Vault has reached \(liveRate.actionsUsed) Instagram actions in the last hour. Continuing to upload/archive now would be risky.

                    Wait before resuming. This protects the account from Instagram verification.
                    """
                )
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
                        ? String(format: String(localized: "Retrying photo #%d (attempt %d)"), index + 1, retryAttempt + 1)
                        : String(format: String(localized: "Uploading photo #%d of %d"), index + 1, totalPhotos)
                }
                
                do {
                    // ANTI-BOT: Allow duplicates for Word/Number Reveal sets
                    let allowDuplicates = (currentSet.type == .word || currentSet.type == .number)
                    let mediaId = try await instagram.uploadPhoto(
                        imageData: imageData,
                        caption: "",
                        allowDuplicates: allowDuplicates,
                        photoIndex: index,
                        takenAt: uploadTakenAt
                    )
                    
                    if let mediaId = mediaId {
                        print("✅ [UPLOAD] Photo #\(index + 1) uploaded. Media ID: \(mediaId)")
                        
                        // Update status: uploaded (waiting for archive).
                        // Pass uploadTakenAt as uploadDate so insertRevealURL later positions
                        // the reveal:// placeholder at the same chronological slot as taken_at,
                        // matching where Instagram will place the photo when unarchived.
                        dataManager.updatePhoto(
                            photoId: photo.id,
                            mediaId: mediaId,
                            uploadStatus: .uploaded,
                            errorMessage: nil,
                            uploadDate: uploadTakenAt   // nil → DataManager defaults to Date()
                        )
                        
                        // Human-like pause before archiving. Simulates the user glancing at
                        // the photo before deciding to hide it. Wide range (15-35s) avoids the
                        // predictable 19-25s window that appeared in bot-detection logs.
                        let waitSeconds = Double.random(in: 15...35)
                        print("   Waiting \(String(format: "%.1f", waitSeconds))s before archive...")
                        try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                        
                        // Check if pause requested during wait
                        if await checkPauseRequested(atPhotoIndex: index) { return }
                        
                        // Update status: archiving
                        dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, uploadStatus: .archiving, errorMessage: nil)
                        
                        // UPDATE PHASE: Archiving
                        await MainActor.run {
                            uploadManager.uploadPhase = .archiving(photoNumber: index + 1)
                            uploadManager.currentPhaseDescription = String(format: String(localized: "Archiving photo #%d..."), index + 1)
                        }
                        
                        // Archive. We just received this mediaId from /media/configure/,
                        // so the photo is known to exist and be public. Skip the extra
                        // /media/{pk}/info/ pre-check to save 1 API action per upload.
                        let archived = try await instagram.archivePhoto(mediaId: mediaId, skipPreCheck: true)
                        
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
                    let isSafetyPause = isInstagramSafetyPauseError(error)

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
                    
                    if isSafetyPause {
                        let streak = await MainActor.run { InstagramService.shared.challengeRequiredStreak }
                        let message: String
                        if streak >= 2 {
                            message = """
                            ⚠️ Verificación pendiente no completada.

                            Instagram sigue bloqueando la subida porque la verificación anterior no se completó en la app de Instagram. Cada reintento sin verificar empeora el bloqueo.

                            Pasos obligatorios antes de reanudar:
                            1. Abre la app de Instagram (o instagram.com)
                            2. Completa la verificación de email/teléfono si aparece
                            3. Espera al menos 10 minutos
                            4. Luego vuelve a reanudar aquí
                            """
                        } else {
                            message = """
                            Upload paused for safety.

                            Instagram is asking for verification or Vault detected a safety pause. The app will not auto-retry because retrying now can turn a warning into a stronger checkpoint.

                            Open Instagram or instagram.com, complete any email/phone verification if shown, then wait a few minutes before resuming.
                            """
                        }
                        LogManager.shared.warning("SAFETY BLOCK — upload stopped at \(photoInfo) (challenge streak:\(streak)): \(error.localizedDescription)", category: .upload)
                        await pauseUploadForSafety(photoIndex: index, message: message)
                        return

                    } else if isSessionExpired {
                        LogManager.shared.error("Session expired at \(photoInfo) - re-login required", category: .auth)

                        // If the photo was already uploaded (has a mediaId in the DB), do NOT
                        // overwrite its .archiving status with .error. The rescue pass at the
                        // start of the next upload will re-archive it automatically.
                        // Only mark as .error when the session expired before the upload itself.
                        let photoAlreadyUploaded = currentSet.photos.first(where: { $0.id == photo.id })?.mediaId != nil
                        if !photoAlreadyUploaded {
                            dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: "Session expired")
                        }
                        // If already uploaded: leave the existing .archiving status intact.
                        // Rescue pass will handle re-archiving on next upload start.
                        
                        await MainActor.run {
                            uploadManager.failedPhotoIndex = index
                            uploadManager.uploadPhase = .sessionExpired
                            uploadManager.currentPhaseDescription = String(localized: "Session Expired - Re-login Required")
                            dataManager.updateSetStatus(id: currentSet.id, status: .error)
                            uploadManager.activeTask = nil
                            uploadManager.sendSessionExpiredNotification()
                        }
                        return
                        
                    } else if isBotError {
                        LogManager.shared.bot("Bot detection triggered at \(photoInfo): \(error.localizedDescription)")
                        // Same guard as session expiry: if photo was already uploaded, don't
                        // clobber its .archiving status. The rescue pass will re-archive it.
                        let photoAlreadyUploadedForBot = currentSet.photos.first(where: { $0.id == photo.id })?.mediaId != nil
                        if !photoAlreadyUploadedForBot {
                            dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: "Bot detected")
                        }
                        
                        await MainActor.run {
                            uploadManager.failedPhotoIndex = index
                            uploadManager.botDetectionTime = Date()
                            uploadManager.botCountdownSeconds = 900
                            
                            uploadManager.uploadPhase = .botLockdown(remainingSeconds: 900)
                            uploadManager.currentPhaseDescription = String(localized: "Bot Detection - Account Locked")
                            
                            uploadManager.botCountdownTimer?.invalidate()
                            uploadManager.botCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                                guard let um = uploadManager else { return }
                                if um.botCountdownSeconds > 0 {
                                    um.botCountdownSeconds -= 1
                                    um.uploadPhase = .botLockdown(remainingSeconds: um.botCountdownSeconds)
                                    um.currentPhaseDescription = String(localized: "Bot Detection - Account Locked")
                                } else {
                                    um.botCountdownTimer?.invalidate()
                                    um.botCountdownTimer = nil
                                    um.uploadPhase = .paused
                                    um.currentPhaseDescription = String(localized: "Upload Paused - Ready to Resume")
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
                            uploadManager.failedPhotoIndex = index
                            uploadManager.isPhotoRejected = true
                            uploadManager.showingError = "Photo #\(index + 1) was rejected\n\nReason: \(error.localizedDescription)\n\nYou can skip this photo or replace it."
                            uploadManager.uploadPhase = .paused
                            uploadManager.currentPhaseDescription = String(localized: "Upload Paused - Photo Rejected")
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
                                uploadManager.currentPhaseDescription = String(localized: "Waiting for connection...")
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
                    uploadManager.currentPhaseDescription = String(format: String(localized: "Next photo in %@"), "\(delaySeconds / 60):\(String(format: "%02d", delaySeconds % 60))")
                    uploadManager.nextPhotoCountdown = delaySeconds
                    
                    uploadManager.nextPhotoTimer?.invalidate()
                    uploadManager.nextPhotoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                        guard let um = uploadManager else { return }
                        let r = um.remainingWaitSeconds()
                        um.nextPhotoCountdown = r
                        um.uploadPhase = .waiting(nextPhoto: index + 2, remainingSeconds: r)
                        um.currentPhaseDescription = String(format: String(localized: "Next photo in %@"), "\(r / 60):\(String(format: "%02d", r % 60))")
                        if r <= 0 {
                            um.nextPhotoTimer?.invalidate()
                            um.nextPhotoTimer = nil
                        }
                    }
                }
                
                // Screen remains on during wait — managed globally by MentalGram1App
                
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
                            if uploadManager.preserveWaitOnAutoPause {
                                print("⏸️ [UPLOAD] Preserving wait countdown for Performance auto-pause")
                                LogManager.shared.info("Upload wait preserved during Performance auto-pause", category: .upload)
                            } else {
                                uploadManager.clearWaitPersistence()
                            }
                            uploadManager.uploadPhase = .paused
                            uploadManager.currentPhaseDescription = String(localized: "Upload Paused")
                            uploadManager.failedPhotoIndex = index + 1
                            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                            uploadManager.activeTask = nil
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                
                await MainActor.run {
                    uploadManager.nextPhotoTimer?.invalidate()
                    uploadManager.nextPhotoTimer = nil
                    uploadManager.clearWaitPersistence()
                }
            }
        } // end for (photos loop)
        
        // ── AUTO-NEXT BANK ────────────────────────────────────────────────
        // For word/number sets: automatically add the next bank and keep uploading,
        // but ONLY if the target bank count hasn't been reached yet.
        let setForBankCheck = dataManager.sets.first(where: { $0.id == currentSet.id })
        let isWordOrNumber = setForBankCheck?.type == .word || setForBankCheck?.type == .number
        let currentBankCount = setForBankCheck?.banks.count ?? 0
        let targetBanks = setForBankCheck?.targetBankCount ?? currentBankCount
        let canAddMoreBanks = currentBankCount < targetBanks
        if isWordOrNumber && !canAddMoreBanks {
            print("✅ [BANK] All \(currentBankCount)/\(targetBanks) banks complete — stopping auto-bank")
            LogManager.shared.success("All \(currentBankCount) banks completed for set '\(setForBankCheck?.name ?? "")'", category: .upload)
        }
        if isWordOrNumber && canAddMoreBanks {
            print("➕ [BANK] Bank \(currentBankCount)/\(targetBanks) complete — auto-adding next bank and continuing upload…")
            LogManager.shared.info("Bank \(currentBankCount)/\(targetBanks) complete — auto-adding next bank", category: .upload)
            let newBank = await MainActor.run { dataManager.addBank(setId: currentSet.id) }
            if newBank != nil {
                // Brief pause (1 cooldown cycle) before starting next bank
                let (hasCooldown, cooldownRemaining) = instagram.isPhotoUploadOnCooldown()
                if hasCooldown && cooldownRemaining > 0 {
                    let wait = cooldownRemaining + Int.random(in: 5...15)
                    print("⏳ [BANK] Waiting \(wait)s cooldown before next bank…")
                    let endTime = Date().addingTimeInterval(Double(wait))
                    await MainActor.run {
                        uploadManager.persistWait(endTime: endTime, nextPhotoIndex: 0)
                        uploadManager.uploadPhase = .waiting(nextPhoto: 1, remainingSeconds: wait)
                        uploadManager.currentPhaseDescription = String(format: String(localized: "Next bank in %@"), "\(wait / 60):\(String(format: "%02d", wait % 60))")
                    }
                    var remaining = wait
                    while remaining > 0 {
                        if uploadManager.requestPause { break }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        remaining -= 1
                    }
                    await MainActor.run { uploadManager.clearWaitPersistence() }
                }
                // Recurse: upload the new bank's pending photos
                await uploadAllPhotos()
                return
            }
        }

        print("\n✅ [UPLOAD ALL] All photos uploaded and archived!")
        LogManager.shared.success("Upload completed for set '\(currentSet.name)' - All \(currentSet.photos.count) photos uploaded", category: .upload)
        await MainActor.run {
            uploadManager.uploadPhase = .completed
            uploadManager.currentPhaseDescription = String(localized: "Upload Completed")
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
            uploadManager.currentPhaseDescription = String(format: String(localized: "Auto-retrying %@ in %ds"), photoInfo, seconds)
            
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
                uploadManager.currentPhaseDescription = String(format: String(localized: "Cooldown %@"), "\(remaining / 60):\(String(format: "%02d", remaining % 60))")
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
            uploadManager.failedPhotoIndex = photoIndex
            uploadManager.activeTask = nil
            
            let pauseEndDate = Date().addingTimeInterval(Double(escalationWaitSeconds))
            uploadManager.escalatedPauseEndTime = pauseEndDate
            uploadManager.escalatedPauseCountdown = escalationWaitSeconds
            uploadManager.uploadPhase = .escalatedPause(remainingSeconds: escalationWaitSeconds)
            uploadManager.currentPhaseDescription = String(localized: "Multiple errors - Cooling down")
            
            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
            
            uploadManager.escalatedPauseTimer?.invalidate()
            uploadManager.escalatedPauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak uploadManager] _ in
                guard let um = uploadManager else { return }
                let left = Int((um.escalatedPauseEndTime ?? Date()).timeIntervalSinceNow)
                if left > 0 {
                    um.escalatedPauseCountdown = left
                    um.uploadPhase = .escalatedPause(remainingSeconds: left)
                    um.currentPhaseDescription = String(localized: "Multiple errors - Cooling down")
                } else {
                    um.escalatedPauseTimer?.invalidate()
                    um.escalatedPauseTimer = nil
                    um.escalatedPauseEndTime = nil
                    um.escalatedPauseCountdown = 0
                    um.uploadPhase = .paused
                    um.currentPhaseDescription = String(localized: "Upload Paused - Ready to Resume")
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
