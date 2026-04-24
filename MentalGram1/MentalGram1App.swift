//
//  MentalGram1App.swift
//  MentalGram1
//
//  Created by NELSON SUÁREZ ARTEAGA on 8/2/26.
//

import SwiftUI
import UserNotifications
import Combine

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct MentalGram1App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var instagram  = InstagramService.shared
    @ObservedObject var backup     = CloudBackupService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showRestoreBanner = false

    init() {
        requestNotificationPermission()
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
                .onOpenURL { url in
                    URLActionManager.shared.handleURL(url)
                }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    handleFirstLaunch()
                }
        }
        .onChange(of: scenePhase) { phase in
            let um = UploadManager.shared
            switch phase {
            case .background:
                UIApplication.shared.isIdleTimerDisabled = false
                um.beginBackgroundWork()
                CloudBackupService.shared.syncToCloud()
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                um.endBackgroundWork()
                um.restoreTimersIfNeeded()
                // Resume any interrupted auto re-archive (accounts for time elapsed while killed)
                ForceNumberRevealSettings.shared.restoreIfNeeded()
            default:
                break
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
            // Reload DataManager so the restored sets JSON is picked up
            DataManager.shared.reloadAfterRestore()
            // Download set images from iCloud Drive in background
            iCloudDriveSync.shared.downloadAllPhotosFromCloud { count in
                print("☁️ [BACKUP] Restore complete: \(count) photo files downloaded")
            }
            withAnimation { showRestoreBanner = true }
            // Auto-hide after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showRestoreBanner = false }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            }
        }
    }
}

// MARK: - Lockdown View (Disguised as "No Internet Connection")

struct LockdownView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var showDetails = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeRemaining: String = ""
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
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
                
                if instagram.challengeRequiredStreak >= 2 {
                    Button(action: {
                        instagram.emergencyLogout()
                    }) {
                        Text("Log Out & Retry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    .padding(.top, 10)
                } else {
                    Button(action: {}) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: { showDetails = true }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showDetails) {
            LockdownDetailsSheet()
        }
        .onReceive(timer) { _ in
            updateTimeRemaining()
            if let lockUntil = instagram.lockUntil, Date() >= lockUntil {
                instagram.unlock()
            }
        }
    }
    
    private func updateTimeRemaining() {
        guard let lockUntil = instagram.lockUntil else {
            timeRemaining = "Unknown"
            return
        }
        let remaining = lockUntil.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = "Unlocking..."
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
                            dismiss()
                        } label: {
                            Text(String(localized: "lockdown.btn.logout"))
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(12)
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
