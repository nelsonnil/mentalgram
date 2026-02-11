import SwiftUI

// MARK: - Set Detail View

struct SetDetailView: View {
    let set: PhotoSet
    @ObservedObject var dataManager = DataManager.shared
    @ObservedObject var instagram = InstagramService.shared
    
    @State private var selectedBankIndex = 0
    @State private var isUploading = false
    @State private var isPaused = false
    @State private var uploadProgress: (current: Int, total: Int) = (0, 0)
    @State private var showingError: String?
    
    var currentSet: PhotoSet {
        dataManager.sets.first(where: { $0.id == set.id }) ?? set
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Stats
                statsSection
                
                // Status & Actions
                statusSection
                
                // Banks Tabs (for word/number)
                if !currentSet.banks.isEmpty {
                    banksTabsSection
                }
                
                // Photos Grid
                photosGridSection
            }
            .padding()
        }
        .navigationTitle(currentSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(showingError != nil), presenting: showingError) { _ in
            Button("OK") { showingError = nil }
        } message: { error in
            Text(error)
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 20) {
            StatCard(title: "Total", value: "\(currentSet.totalPhotos)", icon: "photo.stack")
            StatCard(title: "Uploaded", value: "\(currentSet.uploadedPhotos)", icon: "arrow.up.circle")
            if !currentSet.banks.isEmpty {
                StatCard(title: "Banks", value: "\(currentSet.banks.count)", icon: "square.stack.3d.up")
            }
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: currentSet.status.icon)
                Text(currentSet.status.label)
                    .font(.headline)
            }
            .foregroundColor(currentSet.status.color)
            
            if currentSet.status == .ready {
                Button(action: startUpload) {
                    Label("Start Upload", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
            } else if currentSet.status == .uploading {
                VStack(spacing: 12) {
                    ProgressView(value: Double(uploadProgress.current), total: Double(uploadProgress.total))
                        .tint(isPaused ? .orange : .purple)
                    
                    Text(isPaused ? "⏸️ Paused - \(uploadProgress.current) / \(uploadProgress.total)" : "📤 Uploading - \(uploadProgress.current) / \(uploadProgress.total)")
                        .font(.caption)
                        .foregroundColor(isPaused ? .orange : .secondary)
                    
                    // Pause/Resume Button
                    Button(action: togglePause) {
                        Label(isPaused ? "Resume Upload" : "Pause Upload", systemImage: isPaused ? "play.fill" : "pause.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isPaused ? Color.green : Color.orange)
                            .cornerRadius(8)
                    }
                }
            } else if currentSet.status == .paused {
                VStack(spacing: 12) {
                    ProgressView(value: Double(uploadProgress.current), total: Double(uploadProgress.total))
                        .tint(.orange)
                    
                    Text("⏸️ Upload Paused - \(uploadProgress.current) / \(uploadProgress.total)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Button(action: resumeUpload) {
                        Label("Resume Upload", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                }
            } else if currentSet.status == .completed {
                // Quick Actions para sets completados
                quickActionsSection
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
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
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(10)
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
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(10)
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
            HStack(spacing: 12) {
                ForEach(currentSet.banks.indices, id: \.self) { index in
                    Button(action: { selectedBankIndex = index }) {
                        Text(currentSet.banks[index].name)
                            .font(.subheadline.weight(selectedBankIndex == index ? .bold : .regular))
                            .foregroundColor(selectedBankIndex == index ? .white : .purple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedBankIndex == index ? .purple : Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Photos Grid
    
    private var photosGridSection: some View {
        let photosToShow = currentSet.banks.isEmpty 
            ? currentSet.photos 
            : dataManager.getPhotosForBank(setId: currentSet.id, bankId: currentSet.banks[selectedBankIndex].id)
        
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(photosToShow) { photo in
                PhotoItemView(photo: photo, setId: currentSet.id)
            }
        }
    }
    
    // MARK: - Upload Controls
    
    private func startUpload() {
        Task {
            await uploadAllPhotos()
        }
    }
    
    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            print("⏸️ [UPLOAD] User paused upload")
        } else {
            print("▶️ [UPLOAD] User resumed upload")
        }
    }
    
    private func resumeUpload() {
        isPaused = false
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        Task {
            await uploadAllPhotos()
        }
    }
    
    private func uploadAllPhotos() async {
        print("🚀 [UPLOAD ALL] Starting upload process...")
        print("   Total photos to upload: \(currentSet.photos.count)")
        
        // CRITICAL: Check if lockdown is active before starting
        if instagram.isLocked {
            print("🚨 [UPLOAD] Cannot start - lockdown is active")
            await MainActor.run {
                showingError = "⚠️ Instagram lockdown active. Cannot upload. Wait for lockdown to clear."
            }
            return
        }
        
        isUploading = true
        dataManager.updateSetStatus(id: currentSet.id, status: .uploading)
        
        // ANTI-BOT: Wait if network changed recently (before first upload)
        do {
            try await instagram.waitForNetworkStability()
        } catch {
            print("⚠️ [UPLOAD] Network stability check failed: \(error)")
            await MainActor.run {
                isUploading = false
                dataManager.updateSetStatus(id: currentSet.id, status: .error)
                showingError = "Network error starting upload: \(error.localizedDescription)"
            }
            return
        }
        
        let photosToUpload = currentSet.photos.filter { $0.mediaId == nil }
        uploadProgress = (0, photosToUpload.count)
        
        print("   Photos needing upload: \(photosToUpload.count)")
        
        for (index, photo) in photosToUpload.enumerated() {
            // Check if paused
            if isPaused {
                print("⏸️ [UPLOAD] Paused by user")
                await MainActor.run {
                    dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                    isUploading = false
                }
                return
            }
            
            // CRITICAL: Check if lockdown is active (bot detection)
            if instagram.isLocked {
                print("🚨 [UPLOAD] Lockdown is active - STOPPING upload")
                await MainActor.run {
                    dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                    isUploading = false
                    showingError = "⚠️ Instagram lockdown active. Upload paused for safety. Wait for lockdown to clear before resuming."
                }
                return
            }
            
            print("\n--- Photo \(index + 1)/\(photosToUpload.count) ---")
            print("   Symbol: \(photo.symbol)")
            print("   Filename: \(photo.filename)")
            print("   Has imageData: \(photo.imageData != nil)")
            
            guard let imageData = photo.imageData else {
                print("❌ [UPLOAD ALL] No imageData for photo \(photo.id)")
                continue
            }
            
            // Update photo status: uploading
            dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .uploading, errorMessage: nil)
            
            do {
                // Upload photo
                print("   Starting upload for \(photo.symbol)...")
                
                // ANTI-BOT: Allow duplicates for Word/Number Reveal sets (letters/numbers repeat)
                let allowDuplicates = (currentSet.type == .word || currentSet.type == .number)
                let mediaId = try await instagram.uploadPhoto(
                    imageData: imageData,
                    caption: "",
                    allowDuplicates: allowDuplicates,
                    photoIndex: index
                )
                
                if let mediaId = mediaId {
                    print("✅ [UPLOAD ALL] Photo uploaded. Media ID: \(mediaId)")
                    // Update status: uploaded (waiting for archive)
                    dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, uploadStatus: .uploaded, errorMessage: nil)
                    
                    // Wait before archiving
                    let waitSeconds = Double.random(in: 5...10)
                    print("   Waiting \(String(format: "%.1f", waitSeconds))s before archive...")
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    
                    // Check if paused during wait
                    if isPaused {
                        print("⏸️ [UPLOAD] Paused by user during wait")
                        await MainActor.run {
                            dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                            isUploading = false
                        }
                        return
                    }
                    
                    // Update status: archiving
                    dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, uploadStatus: .archiving, errorMessage: nil)
                    
                    // Archive
                    print("   Archiving...")
                    let archived = try await instagram.archivePhoto(mediaId: mediaId)
                    
                    if archived {
                        print("✅ [UPLOAD ALL] Photo archived successfully")
                        // Update status: completed
                        dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, isArchived: true, uploadStatus: .completed, errorMessage: nil)
                    } else {
                        print("❌ [UPLOAD ALL] Archive failed - STOPPING upload")
                        // Update status: error
                        dataManager.updatePhoto(photoId: photo.id, mediaId: mediaId, isArchived: false, uploadStatus: .error, errorMessage: "Archive failed - Manual review needed")
                        
                        // CRITICAL: STOP upload, don't continue
                        await MainActor.run {
                            showingError = "Archive failed. Please check connection and Instagram status before retrying."
                            dataManager.updateSetStatus(id: currentSet.id, status: .error)
                            isUploading = false
                        }
                        return
                    }
                    
                    uploadProgress.current = index + 1
                    
                    // ANTI-BOT: Delay before next photo
                    // Current: 2-4 min (moderate risk, faster uploads)
                    // Conservative: 3-6 min (lower risk, safer for new accounts)
                    // Aggressive: 1.5-3 min (higher risk, only for established accounts)
                    if index < photosToUpload.count - 1 {
                        let delaySeconds = Double.random(in: 120...240) // 2-4 min (moderate)
                        print("   Waiting \(String(format: "%.0f", delaySeconds))s before next photo...")
                        
                        // Split sleep into 1-second chunks to check pause more frequently
                        for _ in 0..<Int(delaySeconds) {
                            if isPaused {
                                print("⏸️ [UPLOAD] Paused by user during delay")
                                await MainActor.run {
                                    dataManager.updateSetStatus(id: currentSet.id, status: .paused)
                                    isUploading = false
                                }
                                return
                            }
                            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        }
                    }
                } else {
                    print("❌ [UPLOAD ALL] Upload returned nil media ID")
                }
            } catch {
                print("❌ [UPLOAD ALL] Error: \(error)")
                
                // Build detailed error info about which photo failed
                let photoInfo = "Photo #\(index + 1) (\(photo.symbol))"
                
                // Check if it's a bot detection error
                let errorDescription = error.localizedDescription.lowercased()
                let isBotError = errorDescription.contains("challenge") || 
                                 errorDescription.contains("spam") || 
                                 errorDescription.contains("login_required") ||
                                 errorDescription.contains("checkpoint")
                
                // Mark photo as error with detailed message
                let errorMsg = isBotError ? "⚠️ Bot detection - STOP" : error.localizedDescription
                dataManager.updatePhoto(photoId: photo.id, mediaId: nil, uploadStatus: .error, errorMessage: errorMsg)
                
                await MainActor.run {
                    if isBotError {
                        showingError = "⚠️ Instagram flagged activity at \(photoInfo).\n\nWAIT at least 10 minutes before retrying. Do NOT open Instagram app during this time."
                    } else {
                        // Show which specific photo failed
                        showingError = "❌ Upload failed at \(photoInfo)\n\nError: \(error.localizedDescription)\n\nCheck connection and retry manually."
                    }
                    dataManager.updateSetStatus(id: currentSet.id, status: .error)
                    isUploading = false
                }
                return
            }
        }
        
        print("\n✅ [UPLOAD ALL] All photos uploaded and archived!")
        dataManager.updateSetStatus(id: currentSet.id, status: .completed)
        isUploading = false
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
    
    @ObservedObject var instagram = InstagramService.shared
    @ObservedObject var dataManager = DataManager.shared
    @State private var isProcessing = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Photo
            if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            
            // Info
            VStack(spacing: 4) {
                Text(photo.symbol)
                    .font(.caption.bold())
                    .lineLimit(1)
                
                if let uploadDate = photo.uploadDate {
                    Text(uploadDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Status - Detailed based on uploadStatus
                statusBadge(for: photo)
                
                // Action Buttons - MÁS GRANDES Y VISIBLES
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
                                        colors: [Color.green, Color.green.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(color: Color.green.opacity(0.3), radius: 3, x: 0, y: 2)
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
                                .padding(.horizontal, 8)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
            .foregroundColor(.purple)
            
        case .archiving:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Archiving...")
            }
            .font(.caption2)
            .foregroundColor(.purple)
            
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

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.purple)
            
            Text(value)
                .font(.title3.bold())
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
