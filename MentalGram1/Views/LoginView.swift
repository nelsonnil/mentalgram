import SwiftUI
import WebKit

// MARK: - Login View

struct LoginView: View {
    @ObservedObject var instagram = InstagramService.shared
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
                Button(action: { showWebLogin = true }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Connect Instagram")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .cornerRadius(14)
                }
                
                Text("Login securely via Instagram")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .sheet(isPresented: $showWebLogin) {
            InstagramWebLoginView(isPresented: $showWebLogin)
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
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        
        // Load Instagram login page
        if let url = URL(string: "https://www.instagram.com/accounts/login/") {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: InstagramWebLoginView
        
        init(parent: InstagramWebLoginView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if user is logged in by looking at cookies
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let instagramCookies = cookies.filter { $0.domain.contains("instagram.com") }
                
                let hasSession = instagramCookies.contains { $0.name == "sessionid" && !$0.value.isEmpty }
                let hasUserId = instagramCookies.contains { $0.name == "ds_user_id" && !$0.value.isEmpty }
                
                if hasSession && hasUserId {
                    // Successfully logged in!
                    DispatchQueue.main.async {
                        InstagramService.shared.setSessionFromCookies(cookies: instagramCookies)
                        self.parent.isPresented = false
                    }
                }
            }
        }
    }
}
