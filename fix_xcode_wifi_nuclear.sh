#!/bin/bash

echo "💣 OPCIÓN NUCLEAR: Limpieza completa de Xcode"
echo "⚠️  Esto puede tardar unos minutos..."
echo ""

read -p "¿Estás seguro? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]
then
    echo "Cancelado"
    exit 1
fi

echo ""
echo "🧹 Iniciando limpieza nuclear..."
echo ""

# Cerrar todo lo relacionado con Xcode
echo "1️⃣ Cerrando todas las aplicaciones de desarrollo..."
killall Xcode 2>/dev/null
killall Simulator 2>/dev/null
killall "Instruments" 2>/dev/null
killall "Interface Builder" 2>/dev/null
sleep 3

# Limpiar TODO el cache de Xcode
echo "2️⃣ Limpiando TODO el cache de Xcode..."
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Developer/Xcode/Archives
rm -rf ~/Library/Developer/Xcode/Products
rm -rf ~/Library/Developer/Xcode/iOS\ Device\ Logs
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport
rm -rf ~/Library/Developer/Xcode/watchOS\ DeviceSupport
rm -rf ~/Library/Developer/Xcode/tvOS\ DeviceSupport
rm -rf ~/Library/Caches/com.apple.dt.Xcode
echo "   ✅ Cache de Xcode limpiado"

# Limpiar preferencias de dispositivos
echo "3️⃣ Limpiando preferencias de dispositivos..."
defaults delete com.apple.dt.Xcode 2>/dev/null
rm -rf ~/Library/Preferences/com.apple.dt.Xcode.plist 2>/dev/null
echo "   ✅ Preferencias eliminadas"

# Resetear servicios del sistema
echo "4️⃣ Reseteando servicios del sistema..."
sudo killall -9 usbmuxd
sudo launchctl stop com.apple.mobile.lockdown
sleep 2
sudo launchctl start com.apple.mobile.lockdown
echo "   ✅ Servicios reseteados"

# Limpiar temporales
echo "5️⃣ Limpiando archivos temporales del sistema..."
sudo rm -rf /private/var/folders/*/T/com.apple.dt.*
sudo rm -rf /private/var/folders/*/C/com.apple.dt.*
rm -rf /tmp/com.apple.dt.*
rm -rf /tmp/xcodebuild.*
echo "   ✅ Temporales limpiados"

# Limpiar cache de CoreSimulator
echo "6️⃣ Limpiando CoreSimulator..."
xcrun simctl shutdown all 2>/dev/null
xcrun simctl erase all 2>/dev/null
rm -rf ~/Library/Developer/CoreSimulator/Caches
echo "   ✅ Simuladores limpiados"

echo ""
echo "💥 ¡Limpieza nuclear completada!"
echo ""
echo "🔄 Reinicia tu Mac ahora para mejores resultados"
echo ""
echo "Después del reinicio:"
echo "1. Conecta el iPhone por cable USB"
echo "2. Abre Xcode"
echo "3. Ve a Window > Devices and Simulators"
echo "4. Marca 'Connect via network'"
echo "5. Espera el ícono de globo"
echo "6. Desconecta el cable"
echo ""
