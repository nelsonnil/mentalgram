import SwiftUI
import Combine

// MARK: - Upload Manager (Singleton)
// Persists upload state across view lifecycle so navigating away and back
// doesn't lose timers, phase info, or progress.

class UploadManager: ObservableObject {
    static let shared = UploadManager()
    
    // MARK: - Upload Progress Struct
    struct UploadProgressInfo {
        var current: Int = 0
        var total: Int = 0
    }
    
    // MARK: - Core Upload State
    @Published var activeSetId: UUID? = nil
    @Published var isUploading = false
    @Published var isPaused = false
    @Published var uploadPhase: UploadPhase = .idle
    @Published var currentPhaseDescription = ""
    @Published var uploadProgress = UploadProgressInfo()
    
    // MARK: - Error State
    @Published var showingError: String? = nil
    @Published var failedPhotoIndex: Int? = nil
    @Published var isBotDetection = false
    @Published var isPhotoRejected = false
    @Published var isNetworkError = false
    @Published var botDetectionTime: Date? = nil
    @Published var botCountdownSeconds: Int = 0
    @Published var cooldownRetryDisabledUntil: Date? = nil
    
    // MARK: - Auto-Retry State
    @Published var consecutiveAutoRetries: Int = 0
    @Published var autoRetryCountdown: Int = 0
    @Published var escalatedPauseCountdown: Int = 0
    @Published var nextPhotoCountdown: Int = 0
    
    // MARK: - Timers (internal, not @Published)
    var botCountdownTimer: Timer?
    var cooldownTimer: Timer?
    var nextPhotoTimer: Timer?
    var autoRetryTimer: Timer?
    var escalatedPauseTimer: Timer?
    
    private init() {}
    
    // MARK: - Reset Error State
    func resetErrorState() {
        showingError = nil
        failedPhotoIndex = nil
        isNetworkError = false
        isPhotoRejected = false
        isBotDetection = false
        botCountdownSeconds = 0
        botCountdownTimer?.invalidate()
        botCountdownTimer = nil
        autoRetryTimer?.invalidate()
        autoRetryTimer = nil
        autoRetryCountdown = 0
        escalatedPauseTimer?.invalidate()
        escalatedPauseTimer = nil
        escalatedPauseCountdown = 0
    }
    
    // MARK: - Reset All State (when upload completes or is cancelled)
    func resetAllState() {
        resetErrorState()
        activeSetId = nil
        isUploading = false
        isPaused = false
        uploadPhase = .idle
        currentPhaseDescription = ""
        uploadProgress = UploadProgressInfo()
        consecutiveAutoRetries = 0
        nextPhotoCountdown = 0
        cooldownRetryDisabledUntil = nil
        
        invalidateAllTimers()
    }
    
    // MARK: - Invalidate All Timers
    func invalidateAllTimers() {
        botCountdownTimer?.invalidate()
        botCountdownTimer = nil
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        autoRetryTimer?.invalidate()
        autoRetryTimer = nil
        escalatedPauseTimer?.invalidate()
        escalatedPauseTimer = nil
        nextPhotoTimer?.invalidate()
        nextPhotoTimer = nil
    }
    
    // MARK: - Restore Timers (called on view appear)
    func restoreTimersIfNeeded() {
        // Restore bot lockdown timer
        if isBotDetection && botCountdownSeconds > 0 {
            uploadPhase = .botLockdown(remainingSeconds: botCountdownSeconds)
            currentPhaseDescription = "Bot Detection - Account Locked"
            
            if botCountdownTimer == nil {
                botCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if self.botCountdownSeconds > 0 {
                        self.botCountdownSeconds -= 1
                        self.uploadPhase = .botLockdown(remainingSeconds: self.botCountdownSeconds)
                    } else {
                        self.botCountdownTimer?.invalidate()
                        self.botCountdownTimer = nil
                    }
                }
            }
        }
        
        // Restore escalated pause timer
        if escalatedPauseCountdown > 0 {
            uploadPhase = .escalatedPause(remainingSeconds: escalatedPauseCountdown)
            currentPhaseDescription = "Multiple errors - Cooling down"
            
            if escalatedPauseTimer == nil {
                escalatedPauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if self.escalatedPauseCountdown > 0 {
                        self.escalatedPauseCountdown -= 1
                        self.uploadPhase = .escalatedPause(remainingSeconds: self.escalatedPauseCountdown)
                        if self.escalatedPauseCountdown <= 0 {
                            self.escalatedPauseTimer?.invalidate()
                            self.escalatedPauseTimer = nil
                            self.uploadPhase = .paused
                            self.currentPhaseDescription = "Upload Paused - Ready to Resume"
                        }
                    }
                }
            }
        }
        
        // Restore cooldown timer
        if let cooldownUntil = cooldownRetryDisabledUntil, Date() < cooldownUntil {
            let remaining = Int(cooldownUntil.timeIntervalSinceNow)
            uploadPhase = .cooldown(remainingSeconds: remaining)
            currentPhaseDescription = "Cooldown Active"
            
            if cooldownTimer == nil {
                cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if let until = self.cooldownRetryDisabledUntil {
                        let remaining = Int(until.timeIntervalSinceNow)
                        if remaining > 0 {
                            self.uploadPhase = .cooldown(remainingSeconds: remaining)
                        } else {
                            self.cooldownTimer?.invalidate()
                            self.cooldownTimer = nil
                            self.cooldownRetryDisabledUntil = nil
                        }
                    }
                }
            }
        }
        
        // Basic state restoration
        if isUploading && uploadPhase == .idle {
            if isPaused {
                uploadPhase = .paused
                currentPhaseDescription = "Upload Paused"
            } else {
                let photoNum = uploadProgress.current + 1
                uploadPhase = .uploading(photoNumber: photoNum)
                currentPhaseDescription = "Uploading photo #\(photoNum) of \(uploadProgress.total)"
            }
        }
        
        // Check if the active set is completed
        if let setId = activeSetId,
           let set = DataManager.shared.sets.first(where: { $0.id == setId }),
           set.status == .completed {
            uploadPhase = .completed
            currentPhaseDescription = "Upload Completed"
        }
    }
}
