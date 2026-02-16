import SwiftUI
import Combine

// MARK: - Upload Manager (Singleton)
// Single source of truth for all upload state.
// uploadPhase is THE state — everything else derives from it.

class UploadManager: ObservableObject {
    static let shared = UploadManager()
    
    // MARK: - Upload Progress Struct
    struct UploadProgressInfo {
        var current: Int = 0
        var total: Int = 0
    }
    
    // MARK: - Core State (uploadPhase is the single source of truth)
    @Published var activeSetId: UUID? = nil
    @Published var uploadPhase: UploadPhase = .idle
    @Published var currentPhaseDescription = ""
    @Published var uploadProgress = UploadProgressInfo()
    
    // MARK: - Pause Request (checked by upload loop)
    @Published var requestPause = false
    
    // MARK: - Active Upload Task (to detect orphaned states)
    var activeTask: Task<Void, Never>? = nil
    
    // MARK: - Computed Properties (derived from uploadPhase)
    var isUploading: Bool {
        switch uploadPhase {
        case .uploading, .archiving, .waiting, .cooldown, .autoRetrying, .waitingNetwork:
            return true
        default:
            return false
        }
    }
    
    var isPaused: Bool {
        uploadPhase == .paused
    }
    
    var isActive: Bool {
        // Any phase that means "this set has an ongoing operation"
        switch uploadPhase {
        case .idle, .completed:
            return false
        default:
            return true
        }
    }
    
    var hasError: Bool {
        switch uploadPhase {
        case .botLockdown, .sessionExpired, .escalatedPause:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Error State
    @Published var showingError: String? = nil
    @Published var failedPhotoIndex: Int? = nil
    @Published var isPhotoRejected = false
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
        isPhotoRejected = false
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
        uploadPhase = .idle
        currentPhaseDescription = ""
        uploadProgress = UploadProgressInfo()
        consecutiveAutoRetries = 0
        nextPhotoCountdown = 0
        cooldownRetryDisabledUntil = nil
        requestPause = false
        activeTask?.cancel()
        activeTask = nil
        
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
    
    // MARK: - Clear Stuck State
    // Call on app launch or when starting a new upload to recover from inconsistent states
    func clearStuckState() {
        // If we have an activeSetId but no running task, we're stuck
        if activeSetId != nil && activeTask == nil {
            switch uploadPhase {
            case .uploading, .archiving, .waiting, .cooldown, .autoRetrying, .waitingNetwork:
                // These phases require an active task - if no task, transition to paused
                print("⚠️ [UPLOAD MANAGER] Detected stuck state (\(uploadPhase)) - transitioning to paused")
                uploadPhase = .paused
                currentPhaseDescription = "Upload Paused"
            case .idle:
                // idle with activeSetId but no task = stuck, reset
                if let setId = activeSetId,
                   let set = DataManager.shared.sets.first(where: { $0.id == setId }),
                   set.status == .completed {
                    uploadPhase = .completed
                    currentPhaseDescription = "Upload Completed"
                } else {
                    uploadPhase = .paused
                    currentPhaseDescription = "Upload Paused"
                }
            default:
                // .paused, .escalatedPause, .botLockdown, .sessionExpired, .completed
                // These are valid states without a running task
                break
            }
        }
        
        // If no activeSetId but phase isn't idle/completed, reset
        if activeSetId == nil && uploadPhase != .idle && uploadPhase != .completed {
            print("⚠️ [UPLOAD MANAGER] No active set but phase is \(uploadPhase) - resetting to idle")
            resetAllState()
        }
    }
    
    // MARK: - Restore Timers (called on view appear)
    func restoreTimersIfNeeded() {
        // First, detect and fix stuck states
        clearStuckState()
        
        // Restore bot lockdown timer
        if case .botLockdown(let seconds) = uploadPhase, seconds > 0 {
            botCountdownSeconds = seconds
            botCountdownTimer?.invalidate()
            botCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.botCountdownSeconds > 0 {
                    self.botCountdownSeconds -= 1
                    self.uploadPhase = .botLockdown(remainingSeconds: self.botCountdownSeconds)
                    self.currentPhaseDescription = "Bot Detection - Account Locked"
                } else {
                    self.botCountdownTimer?.invalidate()
                    self.botCountdownTimer = nil
                    self.uploadPhase = .paused
                    self.currentPhaseDescription = "Upload Paused - Ready to Resume"
                }
            }
        }
        
        // Restore escalated pause timer
        if case .escalatedPause(let seconds) = uploadPhase, seconds > 0 {
            escalatedPauseCountdown = seconds
            escalatedPauseTimer?.invalidate()
            escalatedPauseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.escalatedPauseCountdown > 0 {
                    self.escalatedPauseCountdown -= 1
                    self.uploadPhase = .escalatedPause(remainingSeconds: self.escalatedPauseCountdown)
                    self.currentPhaseDescription = "Multiple errors - Cooling down"
                    if self.escalatedPauseCountdown <= 0 {
                        self.escalatedPauseTimer?.invalidate()
                        self.escalatedPauseTimer = nil
                        self.uploadPhase = .paused
                        self.currentPhaseDescription = "Upload Paused - Ready to Resume"
                    }
                }
            }
        }
        
        // Restore cooldown timer
        if let cooldownUntil = cooldownRetryDisabledUntil, Date() < cooldownUntil {
            let remaining = Int(cooldownUntil.timeIntervalSinceNow)
            uploadPhase = .cooldown(remainingSeconds: remaining)
            currentPhaseDescription = "Cooldown Active"
            
            cooldownTimer?.invalidate()
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
        
        // Restore nextPhoto countdown timer
        if case .waiting(let nextPhoto, _) = uploadPhase, nextPhotoCountdown > 0 {
            nextPhotoTimer?.invalidate()
            nextPhotoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.nextPhotoCountdown > 0 {
                    self.nextPhotoCountdown -= 1
                    self.uploadPhase = .waiting(nextPhoto: nextPhoto, remainingSeconds: self.nextPhotoCountdown)
                } else {
                    self.nextPhotoTimer?.invalidate()
                    self.nextPhotoTimer = nil
                }
            }
        }
        
        // Restore autoRetry countdown timer
        if case .autoRetrying(_, let attempt) = uploadPhase, autoRetryCountdown > 0 {
            autoRetryTimer?.invalidate()
            autoRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.autoRetryCountdown > 0 {
                    self.autoRetryCountdown -= 1
                    self.uploadPhase = .autoRetrying(remainingSeconds: self.autoRetryCountdown, attempt: attempt)
                } else {
                    self.autoRetryTimer?.invalidate()
                    self.autoRetryTimer = nil
                }
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
