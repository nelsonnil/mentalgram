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
                Text("Verificación Requerida")
                    .font(.title.bold())
                
                // Explanation
                VStack(alignment: .leading, spacing: 16) {
                    Text("El servicio ha detectado actividad inusual y requiere que completes una verificación.")
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    
                    Text("**¿Por qué pasó esto?**")
                        .font(.headline)
                    
                    Text("• Cambio reciente de device ID\n• Demasiadas peticiones en poco tiempo\n• Se detectó comportamiento sospechoso")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("**¿Cómo solucionarlo?**")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .fontWeight(.bold)
                            Text("Abre la **app oficial** del servicio conectado")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .fontWeight(.bold)
                            Text("Inicia sesión con tu cuenta")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .fontWeight(.bold)
                            Text("Completa el **challenge de verificación** (captcha, código SMS, email, etc.)")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("4.")
                                .fontWeight(.bold)
                            Text("Espera **15-30 minutos**")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("5.")
                                .fontWeight(.bold)
                            Text("Vuelve a abrir esta app")
                        }
                    }
                    .font(.subheadline)
                    
                    Text("⚠️ **Importante:** NO intentes hacer logout/login repetidamente. Esto empeora la situación.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(12)
                
                // Button
                Button(action: onDismiss) {
                    Text("Entendido")
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
