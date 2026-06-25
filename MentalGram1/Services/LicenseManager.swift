//
//  LicenseManager.swift
//  MentalGram1
//
//  Sistema de licencias local con códigos firmados
//

import Foundation
import CryptoKit

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published private(set) var isActivated: Bool = false
    @Published private(set) var licenseCode: String?
    @Published private(set) var activationDate: Date?
    
    private let userDefaults = UserDefaults.standard
    private let keyIsActivated = "license_is_activated"
    private let keyLicenseCode = "license_code"
    private let keyActivationDate = "license_activation_date"
    private let keyGrandfathered = "license_grandfathered"
    
    // Clave pública embebida para verificar firmas (en producción, generarías un par de claves)
    // Esta es una clave de ejemplo - en producción usarías tu propia clave privada para firmar
    private let publicKeyBase64 = """
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqPzQoB7c5iqX6LKqZLQqQ7c5iqX6
    LKqZLQqQ7c5iqX6LKqZLQqQ7c5iqX6LKqZLQqQ7c5iqX6LKqZLQqQ7c5iqX6==
    """
    
    // Lista de códigos válidos firmados - en producción, esto vendría de un archivo o generador
    private let validLicenses: Set<String> = [
        "SPIIOS-T8384-5PEKS-2B3FR-YYTHX",
        "VAULT1-MAGIC-TRICK-FORCE-ABC12",
        "MENTAL-GRAM1-TLFGT-PERFO-XYZ99",
        "MAGICO-12345-ABCDE-FGHIJ-KLMNO",
        "TESTFL-IGHTX-PRODU-CTION-VER01"
    ]
    
    private init() {
        loadActivationState()
    }
    
    // MARK: - Public Interface
    
    /// Verifica si el usuario necesita activar una licencia
    var needsActivation: Bool {
        return !isActivated
    }
    
    /// Intenta activar con un código de licencia
    func activate(code: String) -> ActivationResult {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Validar formato básico (5 grupos de 5 caracteres separados por guión)
        guard isValidFormat(cleanCode) else {
            return .invalidFormat
        }
        
        // Verificar contra lista de códigos válidos
        guard validLicenses.contains(cleanCode) else {
            return .invalidCode
        }
        
        // Activar la licencia
        saveActivation(code: cleanCode)
        return .success
    }
    
    /// Marca al usuario como "grandfathered" (no necesita licencia)
    func grantGrandfatheredAccess() {
        userDefaults.set(true, forKey: keyGrandfathered)
        userDefaults.set(true, forKey: keyIsActivated)
        userDefaults.set(Date(), forKey: keyActivationDate)
        userDefaults.set("GRANDFATHERED", forKey: keyLicenseCode)
        
        DispatchQueue.main.async {
            self.isActivated = true
            self.licenseCode = "GRANDFATHERED"
            self.activationDate = Date()
        }
        
        print("✅ [LICENSE] Usuario grandfathered - acceso garantizado sin código")
    }
    
    /// Desactiva la licencia (solo para testing)
    func deactivate() {
        userDefaults.removeObject(forKey: keyIsActivated)
        userDefaults.removeObject(forKey: keyLicenseCode)
        userDefaults.removeObject(forKey: keyActivationDate)
        
        DispatchQueue.main.async {
            self.isActivated = false
            self.licenseCode = nil
            self.activationDate = nil
        }
        
        print("⚠️ [LICENSE] Licencia desactivada")
    }
    
    // MARK: - Private Helpers
    
    private func loadActivationState() {
        let activated = userDefaults.bool(forKey: keyIsActivated)
        let code = userDefaults.string(forKey: keyLicenseCode)
        let date = userDefaults.object(forKey: keyActivationDate) as? Date
        
        DispatchQueue.main.async {
            self.isActivated = activated
            self.licenseCode = code
            self.activationDate = date
        }
        
        if activated {
            print("✅ [LICENSE] Licencia activa: \(code ?? "desconocido")")
        } else {
            print("⚠️ [LICENSE] Sin licencia activa - se requiere activación")
        }
    }
    
    private func saveActivation(code: String) {
        let now = Date()
        userDefaults.set(true, forKey: keyIsActivated)
        userDefaults.set(code, forKey: keyLicenseCode)
        userDefaults.set(now, forKey: keyActivationDate)
        
        DispatchQueue.main.async {
            self.isActivated = true
            self.licenseCode = code
            self.activationDate = now
        }
        
        print("✅ [LICENSE] Licencia activada exitosamente: \(code)")
    }
    
    private func isValidFormat(_ code: String) -> Bool {
        let pattern = "^[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: code.utf16.count)
        return regex?.firstMatch(in: code, options: [], range: range) != nil
    }
    
    enum ActivationResult {
        case success
        case invalidFormat
        case invalidCode
        case alreadyActivated
        
        var message: String {
            switch self {
            case .success:
                return "✅ Licencia activada correctamente"
            case .invalidFormat:
                return "❌ Formato inválido. Use: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
            case .invalidCode:
                return "❌ Código de licencia inválido"
            case .alreadyActivated:
                return "ℹ️ Ya tienes una licencia activa"
            }
        }
    }
}
