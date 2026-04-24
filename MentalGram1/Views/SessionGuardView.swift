import SwiftUI

/// Full-screen overlay shown whenever `InstagramService.isSessionExpired` is true.
///
/// PUBLIC face (what a spectator sees): identical to the OS "No Internet Connection" screen
/// so nothing looks suspicious during a performance.
///
/// PRIVATE access (magician only): tap the subtle "Info" button in the bottom-right corner
/// to open the real reason + a "Re-login" sheet that auto-fills saved credentials.
struct SessionGuardView: View {
    @ObservedObject private var instagram = InstagramService.shared
    @State private var showMagicianPanel = false
    @State private var showRelogin = false
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "wifi.slash")
                    .font(.system(size: 70))
                    .foregroundColor(.gray)

                Text("No Internet Connection")
                    .font(.title2.weight(.semibold))

                Text("Check your connection and try again.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: retryConnection) {
                    if isRetrying {
                        ProgressView()
                            .frame(width: 200, height: 44)
                    } else {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 44)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .disabled(isRetrying)
                .padding(.top, 10)

                Spacer()

                // Subtle magician-only info button (bottom-right corner).
                HStack {
                    Spacer()
                    Button(action: { showMagicianPanel = true }) {
                        Image(systemName: "info.circle")
                            .font(.callout)
                            .foregroundColor(.gray.opacity(0.35))
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showMagicianPanel) {
            MagicianSessionPanel(showRelogin: $showRelogin, dismissPanel: {
                showMagicianPanel = false
            })
        }
        .sheet(isPresented: $showRelogin) {
            ReloginSheet(isPresented: $showRelogin)
        }
    }

    private func retryConnection() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            _ = await instagram.validateSession()
            await MainActor.run { isRetrying = false }
        }
    }
}

// MARK: - Magician panel sheet

private struct MagicianSessionPanel: View {
    @ObservedObject private var instagram = InstagramService.shared
    @Binding var showRelogin: Bool
    let dismissPanel: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var reason: String {
        if instagram.challengeRequiredStreak >= 2 {
            return String(format: String(localized: "session.reason.challenge"), instagram.challengeRequiredStreak)
        }
        return String(localized: "The Instagram session has expired. This happens after a password change, prolonged inactivity, or suspicious activity detection.")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.orange)

                    Text("Session Problem")
                        .font(.title2.weight(.bold))

                    Text(reason)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 8)

                Divider()

                VStack(spacing: 12) {
                    Button(action: {
                        dismissPanel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showRelogin = true
                        }
                    }) {
                        Label("Re-login to Instagram", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }

                    if KeychainService.shared.loadCredentials() != nil {
                        Text("Saved credentials will be auto-filled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No saved credentials. You will need to type them manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Return to app without logout (to navigate to Settings and re-login)
                VStack(spacing: 10) {
                    Button(action: {
                        instagram.dismissSessionExpiredOverlay()
                        dismiss()
                    }) {
                        Label(String(localized: "session.panel.return_to_app"), systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.indigo)
                            .cornerRadius(12)
                    }

                    Text(String(localized: "session.panel.return_to_app.hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal)

                Divider()

                // Emergency options
                VStack(spacing: 8) {
                    Button(action: {
                        instagram.emergencyLogout()
                        dismiss()
                    }) {
                        Text("Emergency Logout")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    Text("Emergency logout clears the session and requires a full login.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
