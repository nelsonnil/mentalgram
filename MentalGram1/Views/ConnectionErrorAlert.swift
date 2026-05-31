import SwiftUI

/// Disguised "No Connection" alert to hide technical errors during a magic show
struct ConnectionErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let error: InstagramError?
    @State private var showingTechnicalDetails = false

    func body(content: Content) -> some View {
        content
            .alert("No Connection", isPresented: $isPresented) {
                Button("OK") {
                    isPresented = false
                }
                Button("Info") {
                    showingTechnicalDetails = true
                }
            } message: {
                Text("No Internet connection. Please try again later.")
            }
            .alert("Error Details", isPresented: $showingTechnicalDetails) {
                Button("Copy Log") {
                    copyErrorDetails()
                }
                Button("Close", role: .cancel) {
                    showingTechnicalDetails = false
                }
            } message: {
                Text(getTechnicalDetails())
            }
    }

    private func getTechnicalDetails() -> String {
        guard let error = error else { return "Unknown error" }

        switch error {
        case .challengeRequired:
            return """
            Type: Verification Required

            Instagram requires a security check.

            1. Open the official Instagram app
            2. Complete the verification (CAPTCHA, SMS, email…)
            3. Wait 10–15 minutes
            4. Restart this app
            """

        case .sessionExpired:
            return """
            Type: Session Expired

            Your session has ended.

            1. Go to Settings
            2. Log out and log back in
            """

        case .apiError:
            return """
            Type: Service Unavailable

            Instagram is temporarily unavailable.
            Please wait a moment and try again.
            """

        case .invalidResponse, .invalidURL:
            return """
            Type: Connection Error

            Could not reach the server.
            Check your internet connection and try again.
            """

        case .uploadFailed:
            return """
            Type: Upload Error

            Could not upload the content.
            Try again or use a different file.
            """

        case .notLoggedIn:
            return """
            Type: Not Logged In

            Go to Settings and connect your account.
            """

        case .networkError:
            return """
            Type: Network Error

            Check your Wi-Fi or mobile data and try again.
            """

        case .botDetected:
            return """
            Type: Safety Pause

            A brief pause is active to protect your account.
            Wait for the countdown to finish, then continue.
            """
        }
    }

    private func copyErrorDetails() {
        UIPasteboard.general.string = getTechnicalDetails()
        print("📋 [ALERT] Error details copied to clipboard")
    }
}

extension View {
    func connectionErrorAlert(isPresented: Binding<Bool>, error: InstagramError?) -> some View {
        modifier(ConnectionErrorAlert(isPresented: isPresented, error: error))
    }
}
