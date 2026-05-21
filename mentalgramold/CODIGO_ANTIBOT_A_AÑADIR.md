# 🔒 CÓDIGO ANTI-BOT A AÑADIR

## ✅ LO QUE YA TIENE EL ARCHIVO ACTUAL:
- ✅ Import Network
- ✅ @Published var isLocked, lockReason, lockUntil
- ✅ @Published var isConnected, connectionType  
- ✅ deviceId persistente
- ✅ Todas las funciones originales (getExploreFeed, searchUsers, etc.)

## ❌ LO QUE FALTA AÑADIR:

### 1. Sesiones separadas (reemplazar urlSession):
```swift
// Reemplazar:
private var urlSession: URLSession = { ... }()

// Por:
private lazy var getSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    config.waitsForConnectivity = true  // Safe for GET requests
    return URLSession(configuration: config)
}()

private lazy var postSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    config.waitsForConnectivity = false  // CRITICAL: Don't auto-retry POSTs
    return URLSession(configuration: config)
}()

private let networkMonitor = NWPathMonitor()
private let networkQueue = DispatchQueue(label: "com.vault.network")
```

### 2. Network monitoring functions (añadir después de init()):
```swift
// MARK: - Network Monitoring

private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
        DispatchQueue.main.async {
            self?.isConnected = (path.status == .satisfied)
            self?.connectionType = self?.getConnectionType(path) ?? "unknown"
            print("📶 [NETWORK] Connection: \(self?.connectionType ?? "unknown") - \(path.status == .satisfied ? "Connected" : "Disconnected")")
        }
    }
    networkMonitor.start(queue: networkQueue)
}

private func getConnectionType(_ path: NWPath) -> String {
    if path.usesInterfaceType(.wifi) {
        return "WiFi"
    } else if path.usesInterfaceType(.cellular) {
        return "Cellular"
    } else {
        return "Unknown"
    }
}

private func waitForConnection(timeout: TimeInterval = 30) async throws {
    let start = Date()
    while !isConnected {
        if Date().timeIntervalSince(start) > timeout {
            throw InstagramError.networkError("Connection timeout after \(Int(timeout))s")
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

// MARK: - Bot Detection & Lockdown

private func checkForBotSignals(data: Data) async throws {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }
    
    let status = json["status"] as? String ?? ""
    let message = json["message"] as? String ?? ""
    let messageLower = message.lowercased()
    
    if json["challenge"] != nil || messageLower.contains("challenge_required") {
        print("🚨 BOT DETECTED: Challenge required")
        await triggerLockdown(
            reason: "Instagram is asking for verification (challenge_required). Open Instagram app and complete the verification, then come back.",
            duration: 600
        )
        throw InstagramError.botDetected("Challenge required")
    }
    
    if messageLower.contains("login_required") {
        print("🚨 BOT DETECTED: Login required")
        await triggerLockdown(
            reason: "Instagram invalidated your session. This may indicate suspicious activity was detected.",
            duration: 1800
        )
        throw InstagramError.botDetected("Session invalidated")
    }
    
    if let spam = json["spam"] as? Bool, spam == true {
        print("🚨 BOT DETECTED: Spam flag")
        await triggerLockdown(
            reason: "Instagram flagged this as spam. Stop all activity and wait.",
            duration: 600
        )
        throw InstagramError.botDetected("Flagged as spam")
    }
    
    if messageLower.contains("action blocked") || messageLower.contains("temporarily blocked") {
        print("🚨 BOT DETECTED: Action blocked")
        await triggerLockdown(
            reason: "Instagram has temporarily blocked actions. Do NOT retry. Wait at least 15 minutes.",
            duration: 900
        )
        throw InstagramError.botDetected("Action blocked")
    }
    
    if status == "fail" {
        await MainActor.run { consecutiveErrors += 1 }
        
        if consecutiveErrors >= 3 {
            print("🚨 PRECAUTIONARY LOCKDOWN: 3 consecutive API fails")
            await triggerLockdown(
                reason: "Multiple consecutive errors detected. Pausing all activity as a precaution to avoid triggering bot detection.",
                duration: 300
            )
        }
    }
}

@MainActor
private func triggerLockdown(reason: String, duration: TimeInterval) {
    isLocked = true
    lockReason = reason
    lockUntil = Date().addingTimeInterval(duration)
    
    print("🔒 [LOCKDOWN] Activated for \(Int(duration/60)) minutes")
    print("🔒 [LOCKDOWN] Reason: \(reason)")
}

@MainActor
func unlock() {
    isLocked = false
    lockReason = ""
    lockUntil = nil
    consecutiveErrors = 0
    print("🔓 [LOCKDOWN] Deactivated")
}

@MainActor
func emergencyLogout() {
    session = .empty
    isLoggedIn = false
    KeychainService.shared.deleteSession()
    
    unlock()
    
    if let cookies = HTTPCookieStorage.shared.cookies {
        for cookie in cookies where cookie.domain.contains("instagram.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
    
    URLCache.shared.removeAllCachedResponses()
    
    print("🚨 [EMERGENCY] Full logout and cache clear completed")
}
```

### 3. Modificar init() - añadir al final:
```swift
// Al final de init(), antes del closing brace:
startNetworkMonitoring()
```

### 4. Añadir nuevos casos a InstagramError enum:
```swift
// Añadir estos casos:
case networkError(String)
case botDetected(String)

// Añadir estos en errorDescription:
case .networkError(let msg): return "Network Error: \(msg)"
case .botDetected(let msg): return "⚠️ Safety Lock: \(msg)"

// Añadir estas propiedades computadas:
var isNetworkError: Bool {
    if case .networkError = self { return true }
    return false
}

var isBotDetection: Bool {
    if case .botDetected = self { return true }
    return false
}
```

### 5. Modificar apiRequest() - Añadir AL INICIO:
```swift
// AL INICIO de la función apiRequest(), antes de guard let url:
if isLocked {
    throw InstagramError.botDetected("App is in lockdown mode. Wait for countdown to finish.")
}

if !isConnected {
    print("📶 [NETWORK] No connection detected, waiting...")
    try await waitForConnection()
}
```

### 6. Modificar apiRequest() - Cambiar sesión:
```swift
// Reemplazar:
let (data, response) = try await urlSession.data(for: request)

// Por:
let session = (method == "GET") ? getSession : postSession

let (data, response): (Data, URLResponse)
do {
    (data, response) = try await session.data(for: request)
} catch let error as URLError {
    print("🌐 [NETWORK] URLError: \(error.localizedDescription)")
    throw InstagramError.networkError(error.localizedDescription)
}
```

### 7. Modificar apiRequest() - Añadir checks de bot:
```swift
// DESPUÉS de verificar httpResponse.statusCode, ANTES de return data:
if httpResponse.statusCode == 429 {
    await triggerLockdown(reason: "Rate limited by Instagram. Too many requests.", duration: 300)
    throw InstagramError.botDetected("Rate limited (HTTP 429). Wait 5 minutes.")
}

// AL FINAL, ANTES de return data:
try await checkForBotSignals(data: data)
await MainActor.run { consecutiveErrors = 0 }
```

### 8. Modificar otros lugares que usan urlSession:
```swift
// Buscar TODAS las líneas con:
urlSession.data(for: request)

// Y reemplazar por:
postSession.data(for: request)  // Para uploads/POST
// o
getSession.data(for: request)   // Para GET
```

---

## 🎯 SIGUIENTE PASO:

Dime si quieres que:
1. **Yo lo implemente todo ahora** (puede tomar tiempo pero será completo)
2. **Tú lo copies manualmente** (tienes el código arriba)
3. **Lo hagamos en pasos** (primero sesiones, luego funciones, etc.)

¿Cuál prefieres?
