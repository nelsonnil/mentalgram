import SwiftUI
import UserNotifications

@main
struct VaultApp: App {
    @ObservedObject var instagram = InstagramService.shared
    
    init() {
import UserNotifications
import Combine

@main
struct MentalGram1App: App {
    @ObservedObject var instagram = InstagramService.shared
    
    init() {
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            // ALWAYS show HomeView - never show LoginView directly
            // Login is hidden in Settings (long press on version number)
            // This is for App Store review safety
            HomeView()
                .overlay {
                    // LOCKDOWN OVERLAY: Disguised as "No Internet Connection"
                    if instagram.isLocked {
                        LockdownView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: instagram.isLocked)
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
// This view appears when Instagram detects bot behavior.
// It looks like a generic network error to spectators during a magic show.

struct LockdownView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var showDetails = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeRemaining: String = ""
    
    var body: some View {
        ZStack {
            // Full screen background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Generic "no connection" icon
                Image(systemName: "wifi.slash")
                    .font(.system(size: 70))
                    .foregroundColor(.gray)
                
                Text("No Internet Connection")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                
                Text("Check your connection and try again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Decoy "Try Again" button (does nothing, just looks real)
                Button(action: {
                    // Shake animation to look like it tried
                }) {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 44)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
                
                Spacer()
                
                // Subtle info button - only the magician knows about this
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
            // Auto-unlock when countdown expires
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

// MARK: - Lockdown Details Sheet (Hidden - only for the magician)

struct LockdownDetailsSheet: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeRemaining: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Real reason
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Safety Lock Active")
                        .font(.title2.weight(.bold))
                    
                    Text(instagram.lockReason)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Countdown
                VStack(spacing: 8) {
                    Text("Auto-unlock in:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(timeRemaining)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(16)
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Label("Do NOT open Instagram", systemImage: "xmark.circle")
                    Label("Do NOT retry any action", systemImage: "xmark.circle")
                    Label("Wait for countdown to finish", systemImage: "clock")
                    Label("Then wait 5 more minutes", systemImage: "hourglass")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                // Emergency actions
                VStack(spacing: 12) {
                    Button("Force Unlock (Risky)") {
                        instagram.unlock()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    
                    Button("Emergency Logout") {
                        instagram.emergencyLogout()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.red)
                }
            }
            .padding()
            .navigationTitle("Safety Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onReceive(timer) { _ in
                updateTimeRemaining()
            }
        }
    }
    
    private func updateTimeRemaining() {
        guard let lockUntil = instagram.lockUntil else {
            timeRemaining = "--:--"
            return
        }
        let remaining = lockUntil.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = "0:00"
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            timeRemaining = String(format: "%d:%02d", minutes, seconds)
                    LockdownView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .animation(.easeInOut, value: instagram.isLocked)
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error)")
            }
        }
    }
}

// MARK: - Lockdown View (Disguised as "No Internet" to protect magic performance)

struct LockdownView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var remainingTime: String = ""
    @State private var timer: Timer?
    @State private var showDetails = false
    @State private var showEmergencyAlert = false
    
    var body: some View {
        ZStack {
            // Full screen overlay
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // DISGUISED: Looks like a normal "No Connection" screen
                Image(systemName: "wifi.slash")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                
                Text("No Internet Connection")
                    .font(.title2.bold())
                
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // "Try Again" that does nothing (safe decoy)
                Button(action: {
                    // Do nothing visible - just a decoy button for spectators
                }) {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Small "info" button - only the magician knows to tap this
                Button(action: { showDetails = true }) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showDetails) {
            // REAL details - only the magician sees this
            LockdownDetailsSheet(
                remainingTime: $remainingTime,
                showEmergencyAlert: $showEmergencyAlert
            )
        }
        .onAppear { startCountdown() }
        .onDisappear { timer?.invalidate() }
        .alert("Emergency Logout", isPresented: $showEmergencyAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Logout & Clear All", role: .destructive) {
                instagram.emergencyLogout()
            }
        } message: {
            Text("This will:\n\n- Log you out completely\n- Clear all cookies and cache\n- You will need to login again\n\nUse this only if Instagram keeps blocking your actions.")
        }
    }
    
    private func startCountdown() {
        updateCountdown()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateCountdown()
        }
    }
    
    private func updateCountdown() {
        guard let until = instagram.lockUntil else {
            remainingTime = ""
            return
        }
        
        let remaining = until.timeIntervalSinceNow
        
        if remaining <= 0 {
            timer?.invalidate()
            instagram.unlock()
            return
        }
        
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        remainingTime = String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Lockdown Details Sheet (Hidden - only magician sees this)

struct LockdownDetailsSheet: View {
    @ObservedObject var instagram = InstagramService.shared
    @Binding var remainingTime: String
    @Binding var showEmergencyAlert: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Real status
                    Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    
                    Text("Safety Lock Active")
                        .font(.title2.bold())
                    
                    // Reason
                    Text(instagram.lockReason)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    
                    // Countdown
                    if !remainingTime.isEmpty {
                        VStack(spacing: 4) {
                            Text("Auto-unlock in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(remainingTime)
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                        }
                    }
                    
                    Divider()
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What to do:")
                            .font(.headline)
                        
                        InstructionRow(icon: "xmark.circle", color: .red, text: "Do NOT open Instagram app")
                        InstructionRow(icon: "xmark.circle", color: .red, text: "Do NOT retry any actions")
                        InstructionRow(icon: "clock", color: .orange, text: "Wait for the countdown")
                        InstructionRow(icon: "checkmark.circle", color: .green, text: "When unlocked, wait a few more minutes before using the app")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    Divider()
                    
                    // Emergency actions
                    VStack(spacing: 12) {
                        Text("If this keeps happening:")
                            .font(.headline)
                        
                        Button(action: { showEmergencyAlert = true; dismiss() }) {
                            Label("Emergency Logout", systemImage: "power")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.gradient)
                                .cornerRadius(12)
                        }
                        
                        Text("Clears session, cookies, and cache.\nYou will need to login again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
