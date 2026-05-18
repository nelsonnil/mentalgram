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
    /// Shown briefly after a failed "Try Again" so the user knows what to do next.
    @State private var retryFailed = false

    /// True when no Keychain credentials are saved — first-time / unconfigured user.
    private var hasNoCredentials: Bool {
        KeychainService.shared.loadCredentials() == nil
    }

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

                // Feedback shown for 4 seconds after a failed retry
                if retryFailed {
                    Text(String(localized: "session.retry_failed_hint"))
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                Spacer()

                // Subtle magician-only info button (bottom-right corner).
                HStack {
                    Spacer()
                    Button(action: { showMagicianPanel = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.gray.opacity(0.45))
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.light)
        // First-time / no-credentials user: open the magician panel automatically so
        // they don't have to discover the hidden "i" button to reach the login flow.
        .onAppear {
            if hasNoCredentials {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showMagicianPanel = true
                }
            }
        }
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
        retryFailed = false
        Task {
            let result = await instagram.validateSession()
            await MainActor.run {
                isRetrying = false
                if result == .expired || result == .challenged {
                    withAnimation { retryFailed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation { retryFailed = false }
                    }
                }
            }
        }
    }
}

// MARK: - Magician panel sheet

/// Internal so other views (e.g. SetDetailView) can reuse the same explanation
/// sheet instead of duplicating the localized copy.
struct MagicianSessionPanel: View {
    @ObservedObject private var instagram = InstagramService.shared
    @Binding var showRelogin: Bool
    let dismissPanel: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var context: InstagramService.SessionExpiredContext {
        // Treat challenge streak >= 1 as .challenge even if stored context differs
        instagram.challengeRequiredStreak >= 1 ? .challenge : instagram.sessionExpiredContext
    }

    private var headerIcon: String {
        switch context {
        case .restriction: return "hand.raised.fill"
        case .challenge:   return "shield.slash.fill"
        case .normal:      return "key.slash.fill"
        case .unknown:     return "exclamationmark.lock.fill"
        }
    }

    private var headerColor: Color {
        switch context {
        case .restriction: return .orange
        case .challenge:   return .red
        case .normal:      return .orange
        case .unknown:     return .orange
        }
    }

    private var titleKey: LocalizedStringKey {
        switch context {
        case .restriction: return "session.panel.title.restriction"
        case .challenge:   return "session.panel.title.challenge"
        default:           return "session.panel.title.normal"
        }
    }

    private var reasonKey: String {
        switch context {
        case .restriction: return String(localized: "session.reason.restriction")
        case .challenge:   return String(format: String(localized: "session.reason.challenge"), instagram.challengeRequiredStreak)
        default:           return String(localized: "session.reason.normal")
        }
    }

    // For restriction context, re-login should only happen AFTER the restriction lifts.
    private var reloginIsRecommendedNow: Bool {
        context != .restriction
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: headerIcon)
                            .font(.system(size: 52))
                            .foregroundColor(headerColor)

                        Text(titleKey)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Explanation
                    Text(reasonKey)
                        .font(.callout)
                        .foregroundColor(.primary.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    Divider()

                    // Primary action: log in again
                    VStack(spacing: 10) {
                        Button(action: {
                            dismissPanel()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showRelogin = true
                            }
                        }) {
                            Label(String(localized: "session.panel.relogin"), systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(reloginIsRecommendedNow ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }

                        if context == .restriction {
                            Text(String(localized: "session.panel.relogin.restriction_hint"))
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                        } else if KeychainService.shared.loadCredentials() != nil {
                            Text(String(localized: "session.panel.credentials_saved"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(String(localized: "session.panel.credentials_missing"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Divider()

                    // Secondary: clear all data and log out (last resort)
                    VStack(spacing: 6) {
                        Button(action: {
                            instagram.emergencyLogout()
                            dismiss()
                        }) {
                            Label(String(localized: "session.panel.emergency_logout"), systemImage: "trash")
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.07))
                                .cornerRadius(12)
                        }

                        Text(String(localized: "session.panel.emergency_logout.hint"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
            .navigationTitle(String(localized: "session.panel.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "session.panel.close")) { dismiss() }
                }
            }
        }
    }
}
