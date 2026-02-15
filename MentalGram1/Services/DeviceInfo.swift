import Foundation
import UIKit

/// Detecta el modelo del iPhone y genera información de device para Instagram
struct DeviceInfo {
    static let shared = DeviceInfo()
    
    let modelIdentifier: String
    let modelName: String
    let screenWidth: Int
    let screenHeight: Int
    let scale: Double
    let iosVersion: String
    
    private init() {
        // Detectar modelo de iPhone
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        self.modelIdentifier = identifier
        self.modelName = Self.getModelName(for: identifier)
        
        // Detectar resolución de pantalla
        let screen = UIScreen.main
        self.scale = Double(screen.scale)
        self.screenWidth = Int(screen.nativeBounds.width)
        self.screenHeight = Int(screen.nativeBounds.height)
        
        // Detectar versión de iOS
        let version = UIDevice.current.systemVersion
        self.iosVersion = version.replacingOccurrences(of: ".", with: "_")
        
        print("📱 [DEVICE] Model: \(modelName) (\(modelIdentifier))")
        print("📱 [DEVICE] Screen: \(screenWidth)x\(screenHeight) @\(scale)x")
        print("📱 [DEVICE] iOS: \(version)")
    }
    
    /// Instagram app version - MUST be updated periodically to stay current
    /// Last verified: Feb 2026 (from real user agent data)
    /// Check latest at: https://apps.apple.com/app/instagram/id389801252
    let appVersion = "390.0.0.28.85"
    let appVersionCode = "765313520"
    
    /// Device locale matching the real device settings
    var deviceLocale: String {
        Locale.current.identifier.replacingOccurrences(of: "-", with: "_")
    }
    
    /// Device language
    var deviceLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
    
    /// Genera User-Agent para Instagram basado en el dispositivo real
    var instagramUserAgent: String {
        return "Instagram \(appVersion) (\(modelIdentifier); iOS \(iosVersion); \(deviceLocale); \(deviceLanguage); scale=\(String(format: "%.2f", scale)); \(screenWidth)x\(screenHeight); \(appVersionCode))"
    }
    
    /// Mapeo de identificadores de modelo a nombres legibles
    private static func getModelName(for identifier: String) -> String {
        switch identifier {
        // iPhone 16 Series
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
            
        // iPhone 15 Series
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
            
        // iPhone 14 Series
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
            
        // iPhone 13 Series
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
            
        // iPhone 12 Series
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
            
        // iPhone 11 Series
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
            
        // iPhone XS/XR Series
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
            
        // iPhone X Series
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
            
        // iPhone SE
        case "iPhone12,8": return "iPhone SE (2nd gen)"
        case "iPhone14,6": return "iPhone SE (3rd gen)"
            
        // Simulator
        case "i386", "x86_64", "arm64":
            if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return "Simulator (\(simModel))"
            }
            return "Simulator"
            
        default:
            return identifier
        }
    }
    
    /// Determina si la pantalla es pequeña (para ajustar UI)
    var isSmallScreen: Bool {
        return screenWidth <= 1170 // iPhone 13/14/15 Pro y menores
    }
    
    /// Determina si la pantalla es grande (Pro Max)
    var isLargeScreen: Bool {
        return screenWidth >= 1284 // iPhone 13/14/15 Pro Max y mayores
    }
}
