//
//  MentalGram1App.swift
//  MentalGram1
//
//  Created by NELSON SUÁREZ ARTEAGA on 8/2/26.
//

import SwiftUI
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
            HomeView()
                .overlay {
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
                
                Text("Check your connection and try again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: {}) {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 44)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
                
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
    @State private var timeRemaining: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
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
        }
    }
}
