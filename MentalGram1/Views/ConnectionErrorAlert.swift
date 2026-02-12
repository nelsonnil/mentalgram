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
        guard let error = error else {
            return "Unknown error"
        }
        
        var details: String
        
        switch error {
        case .challengeRequired:
            details = """
            Type: Challenge Required
            
            Instagram requires security verification.
            
            Steps to follow:
            
            1. Open the official Instagram app
            2. Complete the verification it asks for
               (could be CAPTCHA, SMS, email, etc.)
            3. Wait 10-15 minutes
            4. Restart this app
            
            Probable cause:
            - Too many actions in a row
            - Fast follow/unfollow
            - Behavior detected as bot
            
            Recommendation:
            Wait longer between follow/unfollow actions
            and simulate human behavior (scroll, pauses, etc.)
            """
            
        case .sessionExpired:
            details = """
            Type: Session Expired
            
            The session has expired.
            
            Steps to follow:
            
            1. Go to Settings
            2. Log out
            3. Log in again
            
            This usually happens after:
            - Changing your password
            - Long time without using the app
            - Suspicious activity detected
            """
            
        case .apiError(let message):
            details = """
            Type: API Error
            
            Message: \(message)
            
            Possible causes:
            - Rate limit exceeded
            - Action not allowed
            - Account restrictions
            
            Wait a few minutes and try again.
            """
            
        case .invalidResponse, .invalidURL:
            details = """
            Type: Technical Error
            
            Communication problem with the server.
            
            Check your real Internet connection
            and try again.
            """
            
        case .uploadFailed:
            details = """
            Type: Upload Error
            
            Could not upload content.
            
            Possible causes:
            - File too large
            - Unsupported format
            - Connection problem
            
            Try again or use a different file.
            """
            
        case .notLoggedIn:
            details = """
            Type: Not Logged In
            
            You are not logged in.
            
            Steps to follow:
            
            1. Go to Settings
            2. Long press on version number
            3. Connect your account
            
            If you already logged in, try closing
            the app completely and reopening it.
            """
            
        case .networkError(let message):
            details = """
            Type: Network Error
            
            Connection problem: \(message)
            
            Steps to follow:
            
            1. Check your WiFi/Mobile Data
            2. Try again in a few seconds
            
            This error is temporary and safe to retry.
            """
            
        case .botDetected(let message):
            details = """
            Type: Security Detection
            
            Reason: \(message)
            
            IMPORTANT - Do NOT take any action:
            
            1. Do NOT open Instagram
            2. Do NOT retry any action in this app
            3. WAIT for the time shown on screen
            4. After unlocking, wait 5-10 more minutes
            
            Unusual activity was detected.
            Ignoring these instructions may result in
            permanent account suspension.
            
            ⚠️ IF YOU ARE PERFORMING A TRICK:
            STOP IMMEDIATELY. Do not reveal/hide more photos.
            End the trick naturally without continuing.
            """
        }
        
        // Add additional context if message contains specific keywords
        if let error = error {
            let errorDesc = error.errorDescription ?? ""
            if errorDesc.lowercased().contains("please wait") {
                details += """
                
                
                💡 This is a cooldown error, not a connection issue.
                Wait the specified time before retrying.
                """
            }
        }
        
        return details
    }
    
    private func copyErrorDetails() {
        let details = getTechnicalDetails()
        UIPasteboard.general.string = details
        print("📋 [ALERT] Error details copied to clipboard")
    }
}

extension View {
    func connectionErrorAlert(isPresented: Binding<Bool>, error: InstagramError?) -> some View {
        modifier(ConnectionErrorAlert(isPresented: isPresented, error: error))
    }
}
