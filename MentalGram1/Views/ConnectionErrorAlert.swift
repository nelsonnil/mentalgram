import SwiftUI

/// Alert de "Sin Conexión" para ocultar errores técnicos durante el show
struct ConnectionErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let error: InstagramError?
    @State private var showingTechnicalDetails = false
    
    func body(content: Content) -> some View {
        content
            .alert(getLocalizedTitle(), isPresented: $isPresented) {
                Button("OK") {
                    isPresented = false
                }
                
                Button("Info") {
                    showingTechnicalDetails = true
                }
            } message: {
                Text(getLocalizedMessage())
            }
            .alert("⚠️ Error de Instagram", isPresented: $showingTechnicalDetails) {
                Button("Copiar Log") {
                    copyErrorDetails()
                }
                
                Button("Cerrar", role: .cancel) {
                    showingTechnicalDetails = false
                }
            } message: {
                Text(getTechnicalDetails())
            }
    }
    
    private func getLocalizedTitle() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        
        switch language {
        case "es":
            return "📶 Sin Conexión"
        case "fr":
            return "📶 Pas de Connexion"
        case "de":
            return "📶 Keine Verbindung"
        case "it":
            return "📶 Nessuna Connessione"
        case "pt":
            return "📶 Sem Conexão"
        default:
            return "📶 No Connection"
        }
    }
    
    private func getLocalizedMessage() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        
        switch language {
        case "es":
            return "No hay conexión a Internet. Inténtalo de nuevo más tarde."
        case "fr":
            return "Pas de connexion Internet. Réessayez plus tard."
        case "de":
            return "Keine Internetverbindung. Versuchen Sie es später erneut."
        case "it":
            return "Nessuna connessione Internet. Riprova più tardi."
        case "pt":
            return "Sem conexão com a Internet. Tente novamente mais tarde."
        default:
            return "No Internet connection. Please try again later."
        }
    }
    
    private func getTechnicalDetails() -> String {
        guard let error = error else {
            return "Error desconocido"
        }
        
        var details = ""
        
        switch error {
        case .challengeRequired:
            details = """
            Tipo: Challenge Required
            
            Instagram requiere verificación de seguridad.
            
            📋 Pasos a seguir:
            
            1. Abre la app oficial de Instagram
            2. Completa la verificación que te solicite
               (puede ser CAPTCHA, SMS, email, etc.)
            3. Espera 10-15 minutos
            4. Reinicia esta app
            
            ⚠️ Causa probable:
            • Demasiadas acciones seguidas
            • Follow/unfollow rápido
            • Comportamiento detectado como bot
            
            💡 Recomendación:
            Espera más tiempo entre acciones de follow/unfollow
            y simula comportamiento humano (scroll, esperas, etc.)
            """
            
        case .sessionExpired:
            details = """
            Tipo: Sesión Expirada
            
            La sesión de Instagram ha caducado.
            
            📋 Pasos a seguir:
            
            1. Ve a Ajustes
            2. Cierra sesión
            3. Vuelve a iniciar sesión
            
            Esto suele pasar después de:
            • Cambiar contraseña en Instagram
            • Mucho tiempo sin usar la app
            • Instagram detectó actividad sospechosa
            """
            
        case .apiError(let message):
            details = """
            Tipo: Error de API
            
            Mensaje: \(message)
            
            📋 Posibles causas:
            • Rate limit excedido
            • Acción no permitida
            • Cuenta con restricciones
            
            Espera unos minutos e intenta de nuevo.
            """
            
        case .invalidResponse, .invalidURL:
            details = """
            Tipo: Error Técnico
            
            Problema de comunicación con Instagram.
            
            Verifica tu conexión a Internet real
            y vuelve a intentar.
            """
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
