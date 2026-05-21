import SwiftUI
import WebKit

// MARK: - Login View

struct LoginView: View {
    @ObservedObject var instagram = InstagramService.shared
    @State private var showCookieWarning = false
    @State private var showWebLogin = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Logo
            VStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.purple)
                
                Text("MindUp")
                    .font(.largeTitle.bold())
                
                Text("Photo Portfolio Manager")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Login button
            VStack(spacing: 16) {
                Button(action: { showCookieWarning = true }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Connect Account")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(14)
                }
                
                Text("Secure authentication required")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .sheet(isPresented: $showCookieWarning) {
            CookieConsentWarningView {
                showCookieWarning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showWebLogin = true
                }
            }
        }
        .sheet(isPresented: $showWebLogin) {
            InstagramWebLoginView(isPresented: $showWebLogin)
        }
    }
}

// MARK: - Cookie Consent Warning

private struct CookieConsentWarningView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Important before logging in")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Read this before continuing")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Cookie notice
                    VStack(alignment: .leading, spacing: 14) {
                        cookieRow(
                            icon: "checkmark.shield.fill",
                            iconColor: Color.orange,
                            title: "Accept all cookies",
                            body: "Instagram will show a cookie banner when the page loads. You must tap **\"Allow all cookies\"** (or equivalent). Without cookies the session cannot be saved and the login will fail."
                        )

                        Divider()

                        cookieRow(
                            icon: "key.fill",
                            iconColor: Color.purple,
                            title: "Why are cookies needed?",
                            body: "This app connects to Instagram using the same session cookies your browser uses. Accepting cookies lets Instagram create the **sessionid** token that the app reads to authenticate your account securely."
                        )

                        Divider()

                        cookieRow(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: Color(hex: "FF9F0A"),
                            title: "If you see a verification step",
                            body: "Instagram may ask you to verify your identity (email or phone code). Complete it normally — the app will resume the session automatically once verification is done."
                        )
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(14)

                    // Step summary
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Steps once the page opens")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        stepRow(number: "1", text: "Tap **\"Allow all cookies\"** on the cookie banner")
                        stepRow(number: "2", text: "Enter your Instagram username and password")
                        stepRow(number: "3", text: "Complete any verification Instagram requests")
                        stepRow(number: "4", text: "The app closes the browser automatically once you are in")
                    }

                    // Continue button
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I understand — open Instagram")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.purple)
                        .cornerRadius(14)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func cookieRow(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(.init(body))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
            }
            Text(.init(text))
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}

// MARK: - Instagram Web Login (WKWebView)

struct InstagramWebLoginView: UIViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Register message handler to capture credentials from the JS submit listener
        config.userContentController.add(context.coordinator, name: "credentialsCapture")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

        if let url = URL(string: "https://www.instagram.com/accounts/login/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: InstagramWebLoginView
        /// Tracks whether we already auto-filled credentials in this session.
        private var didAutoFill = false
        /// Captures the last credentials the user typed in the form (via JS).
        private var capturedUsername: String?
        private var capturedPassword: String?

        init(parent: InstagramWebLoginView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }

            // Only act on the login page
            if url.contains("instagram.com/accounts/login") || url.contains("instagram.com/") {

                // 1. Auto-fill credentials from Keychain (only once per WebView session)
                if !didAutoFill, let creds = KeychainService.shared.loadCredentials() {
                    didAutoFill = true
                    let escapedUser = creds.username
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    let escapedPass = creds.password
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")

                    // Wait briefly for React/JS to render the form before injecting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let js = """
                        (function() {
                            var userField = document.querySelector('input[name="username"]');
                            var passField = document.querySelector('input[name="password"]');
                            if (userField) {
                                var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                                nativeInputValueSetter.call(userField, "\(escapedUser)");
                                userField.dispatchEvent(new Event('input', { bubbles: true }));
                            }
                            if (passField) {
                                var nativeInputValueSetter2 = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                                nativeInputValueSetter2.call(passField, "\(escapedPass)");
                                passField.dispatchEvent(new Event('input', { bubbles: true }));
                            }
                        })();
                        """
                        webView.evaluateJavaScript(js) { _, _ in
                            print("🔑 [LOGIN] Auto-filled credentials from Keychain")
                        }
                    }
                }

                // 2. Inject script to capture credentials the user types
                let captureJS = """
                (function() {
                    if (window.__mgCredCaptureInstalled) return;
                    window.__mgCredCaptureInstalled = true;
                    document.addEventListener('submit', function() {
                        var u = document.querySelector('input[name="username"]');
                        var p = document.querySelector('input[name="password"]');
                        if (u && p) {
                            window.webkit.messageHandlers.credentialsCapture.postMessage({
                                username: u.value,
                                password: p.value
                            });
                        }
                    }, true);
                })();
                """
                webView.evaluateJavaScript(captureJS)
            }

            // 3. Check cookies — if session is valid, login was successful
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let instagramCookies = cookies.filter { $0.domain.contains("instagram.com") }
                let hasSession = instagramCookies.contains { $0.name == "sessionid" && !$0.value.isEmpty }
                let hasUserId  = instagramCookies.contains { $0.name == "ds_user_id"  && !$0.value.isEmpty }

                guard hasSession && hasUserId else { return }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }

                    // Save credentials to Keychain if we captured them
                    if let u = self.capturedUsername, let p = self.capturedPassword, !u.isEmpty, !p.isEmpty {
                        KeychainService.shared.saveCredentials(username: u, password: p)
                    }

                    // Reset challenge counters so the app resumes cleanly
                    let svc = InstagramService.shared
                    svc.challengeRequiredStreak = 0
                    svc.isSessionChallenged = false

                    svc.setSessionFromCookies(cookies: instagramCookies)
                    self.parent.isPresented = false
                    print("✅ [LOGIN] Re-login successful — session restored")
                }
            }
        }

        // Receive captured credentials from JS message handler
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "credentialsCapture",
                  let body = message.body as? [String: String] else { return }
            capturedUsername = body["username"]
            capturedPassword = body["password"]
            print("🔑 [LOGIN] Credentials captured from form submit")
        }
    }
}

// MARK: - Wrapper sheet with "Re-login" title

struct ReloginSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            InstagramWebLoginView(isPresented: $isPresented)
                .navigationTitle("Re-login")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { isPresented = false }
                    }
                }
        }
    }
}
