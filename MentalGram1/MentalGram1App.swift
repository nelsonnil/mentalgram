//
//  MentalGram1App.swift
//  MentalGram1
//
//  Created by NELSON SUÁREZ ARTEAGA on 8/2/26.
//

import SwiftUI
import UserNotifications
import Combine
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Detect Jetsam/OOM kills from the previous session BEFORE the new
        // running marker overwrites the old one.
        CrashLoggerService.checkAndLogPreviousSessionCrash()
        // Install crash logger as early as possible so any subsequent crash
        // (including during app startup) is captured and written to disk.
        CrashLoggerService.install()
        CrashLoggerService.shared.recordAction("app launched")
        _ = BackupRoutineManager.shared
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
           BackupRoutineManager.shared.queueShortcutItem(shortcutItem) {
            LogManager.shared.info("Backup routine shortcut received in launch options", category: .general)
            return false
        }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        LogManager.shared.info("Backup routine shortcut received by AppDelegate", category: .general)
        completionHandler(BackupRoutineManager.shared.handleShortcutItem(shortcutItem))
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Remove the "running" marker so the next launch does not mistake
        // a normal user-initiated kill for a Jetsam/OOM crash.
        CrashLoggerService.markCleanExit()
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        LogManager.shared.info("Backup routine shortcut received on scene launch", category: .general)
        _ = BackupRoutineManager.shared.queueShortcutItem(shortcutItem)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        LogManager.shared.info("Backup routine shortcut received by SceneDelegate", category: .general)
        completionHandler(BackupRoutineManager.shared.handleShortcutItem(shortcutItem))
    }
}

@main
struct MentalGram1App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var instagram  = InstagramService.shared
    @ObservedObject var backup     = CloudBackupService.shared
    @ObservedObject var license    = LicenseManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showRestoreBanner = false
    /// True while a fresh-install restore is actively pulling data from iCloud, so the user
    /// sees an intentional "Restoring…" overlay instead of an apparent freeze.
    @State private var restoreInProgress = false
    /// Timestamp when the app last entered background. Used to decide whether
    /// to open a warm-resume lockdown window on the next .active transition.
    @State private var lastBackgroundedAt: Date? = nil
    /// Background time threshold (seconds) above which a warm-resume window is opened.
    private let warmResumeThreshold: TimeInterval = 300 // 5 minutes
    /// True once grandfathering check has been performed
    @State private var grandfatheringChecked = false

    init() {
        requestNotificationPermission()
        requestCameraPermission()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .overlay {
                    if instagram.isLocked {
                        LockdownView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: instagram.isLocked)
                // Session expired overlay — shown whenever session is dead and no lockdown is active.
                // Disguised as "No Internet" to the spectator; magician accesses re-login via Info button.
                .overlay {
                    if instagram.isSessionExpired && !instagram.isLocked {
                        SessionGuardView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: instagram.isSessionExpired)
                // Restore banner — shown once after auto-restore on first install
                .overlay(alignment: .top) {
                    if showRestoreBanner {
                        RestoreBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 60)
                            .onTapGesture { withAnimation { showRestoreBanner = false } }
                    }
                }
                .animation(.spring(response: 0.4), value: showRestoreBanner)
                // Fresh-install restore overlay — intentional progress UI while iCloud pulls data.
                .overlay {
                    if restoreInProgress {
                        RestoreProgressOverlay()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: restoreInProgress)
                // PROVISIONAL RELEASE: license activation is temporarily disabled.
                // Keep LicenseManager/LicenseActivationView in the project so it can be
                // re-enabled later, but do not block users in this version.
                /*
                .overlay {
                    if license.needsActivation {
                        LicenseActivationView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: license.isActivated)
                */
                .onOpenURL { url in
                    URLActionManager.shared.handleURL(url)
                }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    // PROVISIONAL RELEASE: license activation is temporarily disabled.
                    // checkLicenseGrandfathering()
                    handleFirstLaunch()
                    // Backups are manual-only. Do not upload local state/photos on launch,
                    // because a bad local state could overwrite the user's good backup.
                    // Exception: one-time background sync of existing set photo *files* to
                    // iCloud Drive so they survive a reinstall. This does not touch the KV
                    // backup and only runs once per install.
                    ensurePhotosInCloudDrive()
                    // Self-heal: if any set references a photo file that is missing on disk
                    // (e.g. iCloud Drive was slow during the first post-reinstall launch),
                    // pull the photos again. Idempotent — skips files already present.
                    ensurePhotosRestoredIfMissing()
                }
        }
        .onChange(of: scenePhase) { phase in
            let um = UploadManager.shared
            switch phase {
            case .background:
                CrashLoggerService.shared.recordLifecycle("background")
                UIApplication.shared.isIdleTimerDisabled = false
                if um.activeTask != nil || um.isUploading || um.isActive {
                    LogManager.shared.warning("Upload left foreground — uploads cannot continue for hours in background. phase=\(um.uploadPhase)", category: .upload)
                }
                um.beginBackgroundWork()
                lastBackgroundedAt = Date()
                // Auto-backup removed: backups are manual-only (Back up now in Settings).
                // This prevents the app from overwriting a good iCloud backup during
                // migrations, updates, or partial-restore states.
            case .active:
                CrashLoggerService.shared.recordLifecycle("active")
                UIApplication.shared.isIdleTimerDisabled = true
                um.endBackgroundWork()
                um.restoreTimersIfNeeded()
                // ANTI-BOT: If the app was in background for a long time, open a
                // short warm-resume lockdown window so the first automatic-call
                // pattern after foregrounding does not look like a fresh bot
                // login burst to Instagram.
                if let bgAt = lastBackgroundedAt {
                    let bgDuration = Date().timeIntervalSince(bgAt)
                    if bgDuration >= warmResumeThreshold {
                        InstagramSafetyGate.shared.markWarmResume()
                    }
                }
                lastBackgroundedAt = nil
                // ANTI-BOT: Clear any "network changed during upload" flag that
                // may have been set during the background period when no upload
                // was actually running. Stops stale flags from leaking into the
                // next upload session.
                if !um.isUploading && !um.isPaused {
                    InstagramService.shared.networkChangedDuringUpload = false
                }
                // Resume any interrupted auto re-archive (accounts for time elapsed while killed)
                ForceNumberRevealSettings.shared.restoreIfNeeded()
            default:
                break
            }
        }
    }

    // MARK: - License Grandfathering

    /// Verifica si el usuario es existente y le otorga acceso automático sin código de licencia
    private func checkLicenseGrandfathering() {
        guard !grandfatheringChecked else { return }
        grandfatheringChecked = true
        
        // Si ya está activado, no hacer nada
        guard license.needsActivation else { return }
        
        // Criterios de grandfathering: usuario existente con datos previos
        let isExistingUser = hasExistingUserData()
        
        if isExistingUser {
            print("🎁 [LICENSE] Usuario existente detectado - otorgando acceso grandfathered")
            license.grantGrandfatheredAccess()
        } else {
            print("👤 [LICENSE] Usuario nuevo - se requiere código de activación")
        }
    }
    
    /// Determina si es un usuario existente basándose en datos previos
    private func hasExistingUserData() -> Bool {
        // 1. Verificar si tiene una sesión de Instagram guardada
        let hasSession = !InstagramService.shared.session.sessionId.isEmpty
        if hasSession {
            print("   ✓ Tiene sesión de Instagram guardada")
            return true
        }
        
        // 2. Verificar si tiene sets creados
        let hasSets = !DataManager.shared.sets.isEmpty
        if hasSets {
            print("   ✓ Tiene sets creados")
            return true
        }
        
        // 3. Verificar si tiene backups en iCloud (needsCloudRestore es true cuando hay backup)
        let hasBackup = CloudBackupService.shared.needsCloudRestore || (
            CloudBackupService.shared.iCloudAvailable &&
            NSUbiquitousKeyValueStore.default.object(forKey: "com.vault.backup.date") != nil
        )
        if hasBackup {
            print("   ✓ Tiene backup en iCloud")
            return true
        }
        
        // 4. Verificar UserDefaults para cualquier configuración previa
        let hasAnySettings = UserDefaults.standard.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix("com.vault.") || 
            key.contains("instagram") || 
            key.contains("performance") ||
            key.contains("bio_") ||
            key.contains("note_")
        }
        if hasAnySettings {
            print("   ✓ Tiene configuraciones previas")
            return true
        }
        
        print("   ✗ No se encontraron datos de usuario existente")
        return false
    }

    // MARK: - One-time iCloud Drive photo migration

    /// Runs once per install in the background. Uploads any set photo files that
    /// are on disk but have not yet been synced to iCloud Drive. This makes
    /// existing users' photos recoverable after a reinstall going forward.
    private func ensurePhotosInCloudDrive() {
        let key = "com.vault.drivePhotosInitialSyncDone.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let drive = iCloudDriveSync.shared
        let fm = FileManager.default
        let localRoot = drive.localPhotosRoot
        guard fm.fileExists(atPath: localRoot.path) else { return }
        guard let subfolders = try? fm.contentsOfDirectory(at: localRoot, includingPropertiesForKeys: nil),
              subfolders.contains(where: { $0.hasDirectoryPath }) else { return }

        print("☁️ [DRIVE] One-time initial sync: uploading existing set photos to iCloud Drive…")
        drive.syncAllPhotosToCloud { uploaded, skipped, _ in
            print("☁️ [DRIVE] One-time initial sync complete — \(uploaded) uploaded, \(skipped) already present")
        }
        // Also upload the cover screenshot and lockscreen wallpaper if they exist locally
        let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if FileManager.default.fileExists(atPath: docsRoot.appendingPathComponent("fake_homescreen.jpg").path) {
            HomeScreenIllusionService.shared.uploadToCloud()
        }
        if LockscreenInputSettings.shared.hasWallpaper {
            LockscreenInputSettings.shared.uploadWallpaperToCloud()
        }
        if AmnesiaCarouselSettings.shared.filledCount > 0 {
            AmnesiaCarouselSettings.shared.uploadImagesToCloud()
        }
    }

    // MARK: - Self-healing photo restore

    /// Set when a fresh-install restore runs this launch — the restore already pulls every
    /// photo, so the self-heal must not duplicate that work.
    private static var didRestoreThisLaunch = false
    /// Guards the self-heal to one attempt per app process (onAppear can fire repeatedly).
    private static var selfHealRanThisProcess = false

    /// Safety net: if any set references a local photo file that is missing — but iCloud is
    /// available with a backup — re-pull the photos from iCloud Drive. This covers the case
    /// where the container wasn't ready during the first post-reinstall launch.
    ///
    /// IMPORTANT: this used to run on EVERY cold start with no limit, so a file that simply
    /// can't materialize (never uploaded, iCloud slow/offline) made the app re-attempt — and
    /// time out — on every launch, which the user perceived as a "pause". It is now:
    ///   • run at most once per process,
    ///   • skipped while a fresh-install restore is already pulling everything,
    ///   • backed off across launches (1h → 6h → 24h) when it keeps failing,
    ///   • fully off the main thread.
    private func ensurePhotosRestoredIfMissing() {
        guard CloudBackupService.shared.iCloudAvailable else { return }
        guard !Self.selfHealRanThisProcess else { return }
        guard !Self.didRestoreThisLaunch else { return }

        let ud = UserDefaults.standard
        let lastAttempt = ud.double(forKey: "selfHeal_lastAttempt")
        let failStreak  = ud.integer(forKey: "selfHeal_failStreak")
        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval
        switch failStreak {
        case 0:  minInterval = 0
        case 1:  minInterval = 3600          // 1h
        case 2:  minInterval = 6 * 3600      // 6h
        default: minInterval = 24 * 3600     // 24h cap
        }
        if lastAttempt > 0, now - lastAttempt < minInterval { return }
        Self.selfHealRanThisProcess = true

        // Scan for missing files OFF the main thread, then pull in the background.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let hasMissing = DataManager.shared.sets
                .flatMap { $0.photos }
                .contains { photo in
                    guard let path = photo.imagePath, !path.isEmpty else { return false }
                    return !FileManager.default.fileExists(
                        atPath: docsRoot.appendingPathComponent(path).path)
                }
            guard hasMissing else {
                // Everything present — clear any back-off so a future genuine miss runs promptly.
                ud.set(now, forKey: "selfHeal_lastAttempt")
                ud.set(0, forKey: "selfHeal_failStreak")
                return
            }

            print("☁️ [DRIVE] Missing local set photo(s) detected — pulling from iCloud Drive")
            LogManager.shared.info("Self-heal: pulling missing set photos from iCloud Drive", category: .general)
            ud.set(now, forKey: "selfHeal_lastAttempt")
            iCloudDriveSync.shared.downloadAllPhotosFromCloud { count in
                if count > 0 {
                    ud.set(0, forKey: "selfHeal_failStreak")   // success → reset back-off
                    DispatchQueue.main.async { DataManager.shared.notifyPhotosChanged() }
                } else {
                    ud.set(failStreak + 1, forKey: "selfHeal_failStreak")  // failed → back off
                }
            }
        }
    }

    // MARK: - First-launch restore

    private func handleFirstLaunch() {
        let backup = CloudBackupService.shared
        guard backup.needsCloudRestore else { return }

        print("☁️ [BACKUP] Fresh install detected with existing cloud backup — restoring...")
        let restored = backup.restoreFromCloud()
        backup.markInstallComplete()

        if restored {
            // The restore pulls every photo itself — block the per-launch self-heal so the
            // two don't run at once.
            Self.didRestoreThisLaunch = true
            // Reload DataManager so the restored sets JSON is picked up
            DataManager.shared.reloadAfterRestore()

            // Show an intentional "Restoring…" overlay while iCloud Drive downloads run, so
            // the wait reads as progress instead of a freeze.
            withAnimation { restoreInProgress = true }

            // Download set images from iCloud Drive — this is the long pole, so it gates the
            // overlay. The cover screenshot / wallpaper / carousel are small and optional.
            iCloudDriveSync.shared.downloadAllPhotosFromCloud { count in
                print("☁️ [BACKUP] Restore complete: \(count) photo files downloaded")
                DispatchQueue.main.async {
                    if count > 0 { DataManager.shared.notifyPhotosChanged() }
                    finishRestoreOverlay()
                }
            }
            HomeScreenIllusionService.shared.downloadFromCloud { found in
                print("☁️ [BACKUP] Cover screenshot restore: \(found ? "✅ restored" : "not found in cloud")")
            }
            LockscreenInputSettings.shared.downloadWallpaperFromCloud { found in
                print("☁️ [BACKUP] Lockscreen wallpaper restore: \(found ? "✅ restored" : "not found in cloud")")
            }
            AmnesiaCarouselSettings.shared.downloadImagesFromCloud { count in
                print("☁️ [BACKUP] Carousel slot images restore: \(count) image(s)")
            }

            // Safety net: never let the overlay stick if a download hangs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                if restoreInProgress { finishRestoreOverlay() }
            }
        }
    }

    /// Dismisses the restore overlay and shows the brief "restored" confirmation banner.
    private func finishRestoreOverlay() {
        guard restoreInProgress else { return }
        withAnimation { restoreInProgress = false }
        withAnimation { showRestoreBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showRestoreBanner = false }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            }
        }
    }

    /// Request camera access at app launch so the system dialog appears on
    /// first install rather than interrupting the first Performance session.
    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print(granted
                      ? "📸 [PERM] Camera access granted at launch"
                      : "⚠️ [PERM] Camera access denied at launch")
            }
        case .authorized:
            print("📸 [PERM] Camera access already granted")
        default:
            break
        }
    }
}

// MARK: - Lockdown View (Disguised as "No Internet Connection")

struct LockdownView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var showDetails = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeRemaining: String = ""
    /// True once the lockdown timer has expired — requires manual confirmation when streak >= 2.
    @State private var lockExpiredPendingConfirm: Bool = false

    private var isChallenge: Bool { instagram.challengeRequiredStreak >= 1 }

    var body: some View {
        Group {
            // During a live show: keep the disguised "No Internet" look so a spectator
            // never sees a security warning. Outside a show (Sets / Settings): show the
            // explicit bot-detection screen with steps + Log Out.
            if instagram.isPerformanceActive {
                disguisedBody
            } else {
                BotAlertView()
            }
        }
    }

    private var disguisedBody: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "wifi.slash")
                    .font(.system(size: 70))
                    .foregroundColor(.gray)

                Text("No Internet Connection")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)

                Text(instagram.challengeRequiredStreak >= 2
                    ? "This keeps happening. Try logging out and back in."
                    : "Check your connection and try again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Countdown visible directly in the main view (not just in the detail sheet)
                if !timeRemaining.isEmpty && !lockExpiredPendingConfirm {
                    Text(timeRemaining)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(isChallenge ? .orange : .secondary)
                        .padding(.vertical, 4)
                }

                if lockExpiredPendingConfirm && isChallenge {
                    // Challenge lockdown finished — ask user to confirm they verified
                    VStack(spacing: 10) {
                        Text("Verify first, then tap Resume")
                            .font(.footnote)
                            .foregroundColor(.orange)
                        Button(action: {
                            instagram.unlock()
                            instagram.isSessionChallenged = false
                            lockExpiredPendingConfirm = false
                        }) {
                            Text("Resume")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 44)
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.top, 4)
                } else if instagram.challengeRequiredStreak >= 2 {
                    Button(action: { instagram.emergencyLogout() }) {
                        Text("Log Out & Retry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    .padding(.top, 4)
                } else {
                    Button(action: {}) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top, 4)
                }

                Spacer()

                HStack {
                    Spacer()
                    Button(action: { showDetails = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.45))
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showDetails) {
            LockdownDetailsSheet()
        }
        .onReceive(timer) { _ in
            updateTimeRemaining()
            guard let lockUntil = instagram.lockUntil, Date() >= lockUntil else { return }
            // When challenge streak >= 1, require manual "Resume" tap to confirm the user
            // verified in Instagram before unlocking. For safety-only lockdowns, auto-unlock.
            if isChallenge && !lockExpiredPendingConfirm {
                lockExpiredPendingConfirm = true
                timeRemaining = ""
            } else if !isChallenge {
                instagram.unlock()
            }
        }
    }

    private func updateTimeRemaining() {
        guard !lockExpiredPendingConfirm else { return }
        guard let lockUntil = instagram.lockUntil else {
            timeRemaining = ""
            return
        }
        let remaining = lockUntil.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = ""
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            timeRemaining = String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Lockdown Details Sheet

struct LockdownDetailsSheet: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var secondsRemaining: Int = 0
    @State private var isUnlocked = false
    @State private var showRestartAlert = false
    @Environment(\.dismiss) var dismiss

    // challenge_required → el mago debe ir a Instagram a verificar
    // otro motivo        → solo hay que esperar el contador
    private var isChallengeLockdown: Bool {
        instagram.challengeRequiredStreak > 0
    }

    private var countdownText: String {
        if isUnlocked { return "0:00" }
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Icono + título ────────────────────────────────────
                    VStack(spacing: 10) {
                        Image(systemName: isChallengeLockdown
                              ? "hand.raised.fill"
                              : "shield.fill")
                            .font(.system(size: 52))
                            .foregroundColor(isChallengeLockdown ? .orange : .red)

                        Text(isChallengeLockdown
                             ? String(localized: "lockdown.challenge.title")
                             : String(localized: "lockdown.safety.title"))
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(isChallengeLockdown
                             ? String(localized: "lockdown.challenge.subtitle")
                             : String(localized: "lockdown.safety.subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 8)

                    // ── Contador regresivo ────────────────────────────────
                    VStack(spacing: 6) {
                        Text(isUnlocked
                             ? String(localized: "lockdown.countdown.ready")
                             : String(localized: "lockdown.countdown.label"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(countdownText)
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .foregroundColor(isUnlocked ? .green : .orange)
                            .animation(.easeInOut, value: isUnlocked)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background((isUnlocked ? Color.green : Color.orange).opacity(0.08))
                    .cornerRadius(16)

                    // ── Pasos a seguir ────────────────────────────────────
                    if isChallengeLockdown {
                        ldStepBox(color: .orange) {
                            ldStep(n: "1", icon: "arrow.up.right.square",
                                   text: String(localized: "lockdown.challenge.step1"))
                            ldStep(n: "2", icon: "checkmark.shield",
                                   text: String(localized: "lockdown.challenge.step2"))
                            ldStep(n: "3", icon: "arrow.uturn.left",
                                   text: String(localized: "lockdown.challenge.step3"))
                            ldStep(n: "4", icon: "clock",
                                   text: String(localized: "lockdown.challenge.step4"))
                        }
                    } else {
                        ldStepBox(color: .blue) {
                            ldStep(n: "1", icon: "hand.raised",
                                   text: String(localized: "lockdown.safety.step1"))
                            ldStep(n: "2", icon: "iphone.slash",
                                   text: String(localized: "lockdown.safety.step2"))
                            ldStep(n: "3", icon: "checkmark.circle",
                                   text: String(localized: "lockdown.safety.step3"))
                        }
                    }

                    Spacer(minLength: 8)

                    // ── Botones ───────────────────────────────────────────
                    VStack(spacing: 12) {

                        if isChallengeLockdown {
                            Button {
                                instagram.unlock()
                                instagram.isSessionChallenged = false
                                dismiss()
                            } label: {
                                Label(String(localized: "lockdown.challenge.btn.resume"),
                                      systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                        }

                        Button {
                            instagram.unlock()
                            instagram.isSessionChallenged = false
                            dismiss()
                        } label: {
                            Text(isChallengeLockdown
                                 ? String(localized: "lockdown.challenge.btn.skip")
                                 : String(localized: "lockdown.safety.btn.skip"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        Button {
                            instagram.emergencyLogout()
                            showRestartAlert = true
                        } label: {
                            Text(String(localized: "lockdown.btn.logout"))
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(12)
                        }
                        .alert(String(localized: "session.panel.restart.title"), isPresented: $showRestartAlert) {
                            Button(String(localized: "common.ok"), role: .cancel) { dismiss() }
                        } message: {
                            Text(String(localized: "session.panel.restart.message"))
                        }

                        Text(String(localized: "lockdown.btn.logout.note"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle(isChallengeLockdown
                             ? String(localized: "lockdown.challenge.nav")
                             : String(localized: "lockdown.safety.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "lockdown.btn.close")) { dismiss() }
                }
            }
            .onReceive(timer) { _ in updateCountdown() }
            .onAppear { updateCountdown() }
        }
    }

    // MARK: - Helpers

    private func updateCountdown() {
        guard let lockUntil = instagram.lockUntil else {
            secondsRemaining = 0
            isUnlocked = true
            return
        }
        let remaining = lockUntil.timeIntervalSinceNow
        if remaining <= 0 {
            secondsRemaining = 0
            isUnlocked = true
            instagram.unlock()
        } else {
            secondsRemaining = Int(remaining)
            isUnlocked = false
        }
    }

    @ViewBuilder
    private func ldStepBox(color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07))
        .cornerRadius(14)
    }

    private func ldStep(n: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 26, height: 26)
                Text(n)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            Label(text, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
