import SwiftUI

/// Vista que explica qué hacer cuando Instagram requiere un challenge
struct ChallengeRequiredView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                
                // Title
                Text("error.challenge_title")
                    .font(.title.bold())
                
                // Explanation
                VStack(alignment: .leading, spacing: 16) {
                    Text("error.challenge_desc")
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    
                    Text("error.challenge_why")
                        .font(.headline)
                    
                    Text("challenge.why_reasons")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("error.challenge_how")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .fontWeight(.bold)
                            Text("integrations.open_service")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .fontWeight(.bold)
                            Text("integrations.login")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .fontWeight(.bold)
                            Text("error.challenge_step1")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("4.")
                                .fontWeight(.bold)
                            Text("error.challenge_wait")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("5.")
                                .fontWeight(.bold)
                            Text("challenge.reopen_app")
                        }
                    }
                    .font(.subheadline)
                    
                    Text("challenge.warning")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(12)
                
                // Button
                Button(action: onDismiss) {
                    Text("action.got_it")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(32)
        }
    }
}

/// Modificador para mostrar alerta de challenge automáticamente
extension View {
    func challengeRequiredAlert(isPresented: Binding<Bool>) -> some View {
        self.overlay(
            Group {
                if isPresented.wrappedValue {
                    ChallengeRequiredView {
                        isPresented.wrappedValue = false
                    }
                    .transition(.opacity)
                }
            }
        )
    }
}
