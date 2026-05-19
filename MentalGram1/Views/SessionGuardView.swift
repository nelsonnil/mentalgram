import SwiftUI
import UIKit

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
    @State private var showRestartAlert = false
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
    @State private var showAdvancedOptions = false

    /// True when re-login has been attempted and failed ≥ 2 times — guides user to emergency logout.
    private var isStuckInLoop: Bool { instagram.reloginFailCount >= 2 }

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

                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "session.panel.instagram_first.title"), systemImage: "1.circle.fill")
                            .font(.headline)
                        Text(String(localized: "session.panel.instagram_first.body"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Divider()

                    // Primary action: log in again
                    VStack(spacing: 10) {
                        Button(action: openInstagramApp) {
                            Label(String(localized: "session.panel.open_instagram"), systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.black)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            dismissPanel()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showRelogin = true
                            }
                        }) {
                            Label(String(localized: "session.panel.relogin_after_instagram"), systemImage: "arrow.triangle.2.circlepath")
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

                    // ── Stuck-loop warning ─────────────────────────────────
                    // Shown when re-login has been attempted ≥ 2 times without success.
                    if isStuckInLoop {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "session.panel.stuck.title"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.orange)
                                Text(String(localized: "session.panel.stuck.message"))
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Button(action: { withAnimation { showAdvancedOptions.toggle() } }) {
                        HStack {
                            Text(String(localized: "session.panel.advanced_options"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(isStuckInLoop ? .orange : .secondary)
                        .padding(.horizontal)
                    }

                    if showAdvancedOptions {
                        VStack(alignment: .leading, spacing: 14) {

                            // ── What this does ────────────────────────────
                            Text(String(localized: "session.panel.emergency_logout.hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            // ── Step-by-step instructions ─────────────────
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(localized: "session.panel.emergency_steps.intro"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary.opacity(0.8))

                                ForEach([
                                    ("1", String(localized: "session.panel.emergency_step.1")),
                                    ("2", String(localized: "session.panel.emergency_step.2")),
                                    ("3", String(localized: "session.panel.emergency_step.3")),
                                    ("4", String(localized: "session.panel.emergency_step.4")),
                                ], id: \.0) { number, text in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(number)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Color.red.opacity(0.75))
                                            .clipShape(Circle())
                                        Text(text)
                                            .font(.caption)
                                            .foregroundColor(.primary.opacity(0.75))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                            // ── Button ────────────────────────────────────
                            Button(action: {
                                instagram.emergencyLogout()
                                showRestartAlert = true
                            }) {
                                Label(String(localized: "session.panel.emergency_logout"), systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                            .alert(String(localized: "session.panel.restart.title"), isPresented: $showRestartAlert) {
                                Button(String(localized: "common.ok"), role: .cancel) { dismiss() }
                            } message: {
                                Text(String(localized: "session.panel.restart.message"))
                            }
                        }
                        .padding(.horizontal)
                    }

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
            .onAppear {
                if isStuckInLoop {
                    showAdvancedOptions = true
                }
            }
        }
    }

    private func openInstagramApp() {
        guard let appURL = URL(string: "instagram://app") else { return }
        UIApplication.shared.open(appURL) { success in
            if !success, let webURL = URL(string: "https://www.instagram.com/") {
                UIApplication.shared.open(webURL)
            }
        }
    }
}
