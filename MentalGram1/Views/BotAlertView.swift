import SwiftUI
import UIKit
import Combine

/// Explicit "Instagram flagged this account" screen.
///
/// Shown when Instagram detects automated-looking activity (challenge / restriction /
/// rate-limit lockdown) AND the user is NOT inside a live performance. During a live
/// show the disguised "No Internet" screen is shown instead (see LockdownView /
/// SessionGuardView) so spectators never see this.
///
/// The goal here is the opposite of the disguise: tell the magician EXACTLY what
/// happened and what to do, with explicit numbered steps and a clear Log Out button,
/// so they stop using the burned session instead of uploading into a stronger block.
struct BotAlertView: View {
    @ObservedObject private var instagram = InstagramService.shared
    @State private var showLogoutConfirm = false
    @State private var timeRemaining: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 58))
                        .foregroundColor(.red)
                        .padding(.top, 48)

                    Text("Instagram flagged this account")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Instagram detected automated-looking activity and asked for a security check. To protect your account, STOP now and follow these steps. Do not keep uploading, archiving or refreshing.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if !timeRemaining.isEmpty {
                        VStack(spacing: 2) {
                            Text("Safety pause")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(timeRemaining)
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        stepRow("1", "Stop now. Don't upload, archive or refresh anything in this app.")
                        stepRow("2", "Open the official Instagram app and complete any verification it asks for (\"It was me\", code, photo, etc.).")
                        stepRow("3", "Wait several hours before doing anything — ideally 24 hours after a strong block.")
                        stepRow("4", "Only then, log out below and log back in to continue.")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Uploads paused for safety")
                                .font(.subheadline.weight(.semibold))
                            Text(uploadCooldownMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Button(action: openInstagram) {
                        Label("Open Instagram to verify", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Button(role: .destructive, action: { showLogoutConfirm = true }) {
                        Label("Log out & reset device", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Text("Logging out clears the saved session, cookies and cache, and resets the device identity. Use it only if the verification didn't help or the block keeps coming back. Do NOT immediately log back in and resume uploading.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer(minLength: 28)
                }
            }
        }
        .alert("Log out and reset?", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { instagram.emergencyLogout() }
        } message: {
            Text("You'll need to log in again. Make sure you completed the Instagram verification first, and that you waited before retrying.")
        }
        .onReceive(timer) { _ in updateCountdown() }
        .onAppear { updateCountdown() }
    }

    /// Human-readable description of the post-bot upload cooldown. Photo uploads
    /// stay blocked even after logging out and back in; revealing photos and live
    /// Performance keep working.
    private var uploadCooldownMessage: String {
        let remaining = UploadManager.shared.remainingUploadRestrictionSeconds()
        if remaining > 0 {
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            let eta = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            return "Photo uploads stay blocked for about \(eta) — even if you log out and log back in. Revealing photos and live Performance still work normally."
        }
        return "Photo uploads stay blocked for about 24 hours after a strong block — even if you log out and log back in. Revealing photos and live Performance still work normally."
    }

    private func stepRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.red)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func updateCountdown() {
        guard let until = instagram.lockUntil, until > Date() else {
            timeRemaining = ""
            return
        }
        let remaining = max(0, Int(until.timeIntervalSinceNow))
        timeRemaining = String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func openInstagram() {
        guard let appURL = URL(string: "instagram://app") else { return }
        UIApplication.shared.open(appURL) { success in
            if !success, let webURL = URL(string: "https://www.instagram.com/") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}
