//
//  LicenseActivationView.swift
//  MentalGram1
//
//  Vista de activación de licencia para nuevos usuarios
//

import SwiftUI

struct LicenseActivationView: View {
    @ObservedObject var license = LicenseManager.shared
    @State private var licenseCode: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var isActivated: Bool = false
    @FocusState private var codeFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Fondo degradado oscuro
            LinearGradient(
                colors: [Color(hex: "0F0F0F"), Color(hex: "1C1C1E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo / Icono
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "8A2BE2"), Color(hex: "4B0082")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "key.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 32)
                
                // Título
                Text("Activación de Licencia")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)
                
                Text("Ingresa el código de licencia que recibiste")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                
                // Campo de código
                VStack(alignment: .leading, spacing: 8) {
                    TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $licenseCode)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .padding(16)
                        .background(Color(hex: "2C2C2E"))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(codeFieldFocused ? Color(hex: "8A2BE2") : Color.clear, lineWidth: 2)
                        )
                        .focused($codeFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { activateLicense() }
                    
                    Text("Formato: 5 grupos de 5-6 caracteres separados por guión")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                
                // Botón de activar
                Button(action: activateLicense) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("Activar Licencia")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "8A2BE2"), Color(hex: "4B0082")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color(hex: "8A2BE2").opacity(0.3), radius: 8, y: 4)
                }
                .disabled(licenseCode.isEmpty)
                .opacity(licenseCode.isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Información de contacto
                VStack(spacing: 8) {
                    Text("¿No tienes un código de licencia?")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Text("Contacta al desarrollador para obtener uno")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "8A2BE2"))
                }
                .padding(.bottom, 40)
            }
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK") {
                if isActivated {
                    // La activación fue exitosa, el overlay se cerrará automáticamente
                }
            }
        }
    }
    
    private func activateLicense() {
        codeFieldFocused = false
        
        let result = license.activate(code: licenseCode)
        alertMessage = result.message
        isActivated = (result == .success)
        showAlert = true
        
        if result == .success {
            // Feedback háptico de éxito
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // Feedback háptico de error
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Preview

struct LicenseActivationView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseActivationView()
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
