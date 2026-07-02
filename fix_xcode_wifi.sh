#!/bin/bash

echo "🔧 Limpiando cache y reconectando Xcode con iPhone..."
echo ""

# 1. Cerrar Xcode si está abierto
echo "1️⃣ Cerrando Xcode..."
killall Xcode 2>/dev/null
sleep 2

# 2. Limpiar DerivedData
echo "2️⃣ Limpiando DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*
echo "   ✅ DerivedData limpiado"

# 3. Limpiar cache de dispositivos
echo "3️⃣ Limpiando cache de dispositivos..."
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*
echo "   ✅ DeviceSupport limpiado"

# 4. Limpiar módulos precompilados
echo "4️⃣ Limpiando módulos precompilados..."
rm -rf ~/Library/Developer/Xcode/iOS\ Device\ Logs/*
rm -rf ~/Library/Developer/Xcode/Products/*
echo "   ✅ Logs y Products limpiados"

# 5. Resetear lockdownd (servicio de comunicación con iOS)
echo "5️⃣ Reseteando servicio lockdownd..."
sudo launchctl stop com.apple.mobile.lockdown 2>/dev/null
sudo launchctl start com.apple.mobile.lockdown 2>/dev/null
echo "   ✅ lockdownd reiniciado"

# 6. Resetear usbmuxd (servicio de conexión USB/WiFi)
echo "6️⃣ Reseteando servicio usbmuxd..."
sudo killall -9 usbmuxd 2>/dev/null
sleep 1
echo "   ✅ usbmuxd reiniciado"

# 7. Limpiar archivos temporales de Xcode
echo "7️⃣ Limpiando archivos temporales..."
rm -rf /tmp/com.apple.dt.*
rm -rf /tmp/xcodebuild.*
echo "   ✅ Temporales limpiados"

echo ""
echo "✅ ¡Todo limpio!"
echo ""
echo "🔄 Ahora sigue estos pasos:"
echo ""
echo "1. En tu iPhone:"
echo "   • Ve a Ajustes > General > Transferir o restablecer iPhone"
echo "   • Toca 'Restablecer' > 'Restablecer ajustes de red'"
echo "   • (Esto NO borra tus datos, solo resetea WiFi)"
echo ""
echo "2. Después de resetear la red del iPhone:"
echo "   • Reconéctalo a la misma WiFi"
echo "   • Ve a Ajustes > Privacidad y seguridad > Modo desarrollador"
echo "   • Asegúrate de que está ACTIVADO"
echo ""
echo "3. Abre Xcode y ve a:"
echo "   • Window > Devices and Simulators"
echo "   • Conecta el iPhone por cable USB"
echo "   • Marca 'Connect via network'"
echo "   • Espera a que aparezca el ícono de globo al lado del iPhone"
echo "   • Desconecta el cable"
echo ""
echo "4. Si sigue sin funcionar, ejecuta el script alternativo:"
echo "   ./fix_xcode_wifi_nuclear.sh"
echo ""
