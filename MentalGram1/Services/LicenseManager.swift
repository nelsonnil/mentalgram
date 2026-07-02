//
//  LicenseManager.swift
//  MentalGram1
//
//  Sistema de licencias local con códigos firmados
//

import Foundation
import CryptoKit
import Combine

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
    
    // 100 códigos de licencia generados - Distribuye estos códigos a tus usuarios
    private let validLicenses: Set<String> = [
        "2KWOA6-BGUNQ-ZXU825-GLECMT-T6JF4",
        "MA4O7-WOZHR-ZAGQY-4QQUW-OWR9F",
        "FMT6Q-IVMCYD-0B3GQ-IVW4BI-7MWRK",
        "HHDJVA-X4X37Y-YDBJA-NHBGZD-NWZM7",
        "JQGQS-53BRE8-6VV8W-XN6EIC-WHSI7",
        "A7FLN-H5JID3-0F08OP-T527VO-WI49TM",
        "IRO2Q5-GE2YT-L189MX-02FAD-S8JR0",
        "O6Z02-95WGKI-H1KVD-995LT-SPZ09",
        "K2LUX-INZK4-PUBDEI-RW6SAG-W6HKQ",
        "XME0W-W3ZI5J-LA636-H1JRZ-S0FP1",
        "ZHJ0O-6MI97-XO343-NSTIXR-EBV0N",
        "YHA8X6-IXO5MV-YCXJ9M-ZV92Q-G2OGJ",
        "CA0ED7-PIGZW9-TK9R5N-TY2VEV-OOSYBH",
        "JJ8U0F-RN90AP-M23OUU-3PL9M7-CZNCL",
        "NO29O-ABL60V-MFWL0-5L1GVX-9V7L9",
        "VUSY1F-BMO90E-HLUZI-KCN58K-O49AX",
        "XZ2KW-WWE9N-R9P0RN-3WYWMV-NFDEG",
        "YI2PO-YOEGZ-T5KYU-4NCAT-NMAQT",
        "4SPBU-UPM49Z-DM9R1I-JQM0PZ-40RYE3",
        "VGU4A-U0B2IS-MKEYI-LCTVWB-IRNPV5",
        "V97YNC-5X22W-TIUO3-MKXDE-F194O",
        "0CILPU-R2T9C3-S3HRMO-IDZI7-F1UTD2",
        "UWIL39-SI716U-FBJYPK-IAHJ4S-P2R1I",
        "L0C5N1-RRFEX-1NE9NX-S5HHCR-4ZIKVD",
        "Y2PTO4-8EXBIT-9SWDG-35TSR-DJVTSL",
        "35KQ9G-7EDPV-DAK8D-ZCH4L-EQW5DT",
        "QQY60I-EOROM-0GT4JP-QUUY1Y-FM4I2",
        "XN1RYM-LJVI6M-T58GN-6QW5CU-ZUGYAP",
        "HS7P1T-MXRMB-VUOSRP-026GH-YG2GK9",
        "NBO0I-RT1M93-P6B9P-VI14I9-5GOAU",
        "PVFM1R-27O0F-Y5869Q-CQ2ZB-XJ38G",
        "1725I-BGLU5-GO5IJ0-Z7XW8-3TWUT8",
        "B00V74-XNX3G-ET7CP-H9L8SN-SMC69",
        "SQAU8-OCDQY-18KMXK-M2PBY6-XSJ1I",
        "KMQ547-9C5AZR-K5VLR1-VN9HX6-2PZFMU",
        "I7DKGM-2N3MVL-D5NAJU-TNXO9-L1F3I",
        "GPS9U8-T5KUJU-RWMIRO-216G4-IJFNK",
        "I9D137-BHNT9A-ZAWC2-9UUSSU-VLN4MT",
        "1VBJF-TA0UYO-2PLLU-RD6URN-J2LXNC",
        "IAUEZ-IP1E8-K89TVG-NP5VKG-54V5BP",
        "2S1845-0RF86I-YUUZM-243QB-FQ3UP8",
        "M15W22-ON1ZBZ-OJKAAE-FS5GF-ZEHBE",
        "PVTRHB-UA9YE-98EPDP-L9OC8G-KKVLG6",
        "FV944W-KJ1EXH-R36AR0-EE6BK-DQZSM8",
        "VPV5H6-X8HAW-MKGD4I-VAL4W-7H1NY",
        "8SUVS9-TS7Y5-8WU3LD-JKP7I-BKH4NV",
        "G6SURV-AEVVL-MAG80V-N35P7-5G3XK",
        "JKR8OK-WQF7V-8Z0L6-U24KS9-TLCLL",
        "U2S00Z-V47CL-J68R8L-J7YO6-TCVO1",
        "EK19IU-1SY9K-NARFXU-7E47Y0-JRBOE",
        "B6FXXW-NBN80-PN6GOI-SN471-BBBS3B",
        "SNVWO-I2PRGS-BHB6W-9Y7L6U-24AFW0",
        "5UN6I-6LV6R-IID40-VSCDEK-0Z2ACN",
        "ZV8KU-ZBQ16O-BJDH2U-6CTSE-KPXQPU",
        "6B6SD-7TNCU-ATJKM4-6CYMC-8HQWG",
        "Z2TZ7N-K0XWQ-MNMKH1-47ZB8-LQ1NXQ",
        "HR0O2I-D2M7I-G6LXR-IAH558-8ZGCNV",
        "GQ99C-H3JE2-L4VVZH-AY2TU9-1XFEQE",
        "0OSF75-KGMBW-ZXYK7X-0P46X-XGN60",
        "8W8QTL-L3D71C-1PR8M-8B6WH-0F57R",
        "GIOUX-XOBE0-4HAG0-BVOA0-7KD2VC",
        "4N37Z-HLFVP-EIEY0S-HZEP3-G3NIM",
        "WLRGR-RP7GBH-301AT3-O33T8N-W5ATJY",
        "LCTX8E-50OAU-RFQH11-9IPDY6-MHTAAE",
        "0ED5C-3CKU64-3PP4S-E9Y7XY-LM472",
        "DQRDN-INWK0-T2TKW5-SKCR2-QYIIK",
        "8EU1BL-3MRIY-LBP6X-K2SHHR-M4G5G",
        "4BQYL-VGNQY-473LD-WFCQ2-DL107",
        "KNT6K-E470WF-1KO8T-07H7M-HTTI7",
        "O5H8Q-4BD5O3-PJ93E-65KFL-8BKM6",
        "BDM1N4-CUMC7-BKY8KB-XHROX-V87G99",
        "D0SZ9-TYCC9-I9LN32-HHVTC-IAL6LL",
        "42CFK-DS0JR-Y5UZC-EDEEWY-B49I6W",
        "VCPUMT-D9XGBI-1J8BYU-BNU3SD-OB65QU",
        "IVLEN-EKOH0-KOVUAK-UB03TT-T51XMG",
        "WPU4R-1Z2AIM-YES2T-XGRFSO-W235D",
        "P5EGD-UUJ5KF-1WGPN-9GVO8-SPDXYV",
        "AARI6-6MTI8J-0ZILV-PU4HR-H78IVN",
        "0BMMC-V1NA1-JJA7E-GUCW1F-X3VHT",
        "PMOBI-OOHE5-93TK8X-57AYC-JCXH5J",
        "876Y7D-289WXH-HRPXD6-92TEJR-KH1MTZ",
        "OXD1E-PZVCT9-84GKK5-HHQ7Y-DVRFR3",
        "R1D4WK-NYBPGL-39XYG-WV1J5-S9OJU",
        "DY8I1-NN8C5N-DD7UOM-86OO5Q-P8DKLZ",
        "6WFOG-WDC3Z-WFCO3-15YVHR-3X2PP",
        "XHNHEJ-G6KSR-O6784-YSI01M-H19341",
        "0O6AW6-WQPVNY-ZGDJJC-KYKXH-UBCX8D",
        "QNVAUI-BN7OR-OHXEU-R9C9A0-YN8AFR",
        "22L6Z-S0U4G-NAQBT-QZBMD-8QV7LM",
        "MK0PN-W8UDUD-QOD1S-NCKNTA-YM4R60",
        "ZK3JHN-Y32D8-TNTSS-80OEWC-PF5A5",
        "FT2KU-8MO1XX-C9VSY-LEL7N-WGU5VX",
        "5EZYJ-2A2SX-QBPHYV-4TOVBJ-I4GSY1",
        "JT9NY2-BK3MN6-Z4JKIR-TS1MV-0JKWI2",
        "R5FW0-PFDDOX-IQUBAK-QAZQO-NGIMG",
        "F174H2-3T8UDU-HEOBFU-LNH3Y-D4MTO",
        "3YECV-ND1VSB-37HXY-D820U-3V1GP7",
        "OCCMQ-3RY3L-LHEQPG-6J21IA-9SB1V",
        "9DM9G-YORB1-ENPSC-E4Z1U-1OSKG",
        "L2DB4-BPUCYC-1HWSE3-FCT9Z2-S4WRV"
    ]
    
    private init() {
        loadActivationState()
    }
    
    // MARK: - Public Interface
    
    /// Verifica si el usuario necesita activar una licencia
    var needsActivation: Bool {
        // PROVISIONAL RELEASE: license activation is temporarily disabled for this
        // build. Keep the activation code/codes in place so it can be re-enabled by
        // restoring `return !isActivated`.
        return false
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
