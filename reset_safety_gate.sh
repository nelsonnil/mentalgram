#!/bin/bash

echo "⚠️  ADVERTENCIA: Esto desactiva protecciones anti-bot"
echo "Solo usa esto para testing, NO en producción"
echo ""

read -p "¿Estás seguro? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]
then
    echo "Cancelado"
    exit 1
fi

echo ""
echo "🔓 Reseteando Safety Gates..."
echo ""

# Resetear todos los UserDefaults relacionados con safety gates
defaults delete com.magonil.MentalGram1 safetyGate.coldStartWindowStartedAt 2>/dev/null
defaults delete com.magonil.MentalGram1 safetyGate.lastPerformanceEntryAt 2>/dev/null
defaults delete com.magonil.MentalGram1 safetyGate.lastProfileRefreshAt 2>/dev/null
defaults delete com.magonil.MentalGram1 safetyGate.lastPaginationAt 2>/dev/null
defaults delete com.magonil.MentalGram1 safetyGate.lastColdStartResetAt 2>/dev/null

# Resetear timestamps de profile pic
defaults delete com.magonil.MentalGram1 last_profile_pic_change_timestamp 2>/dev/null
defaults delete com.magonil.MentalGram1 autoPic_lastUploadedAssetId 2>/dev/null
defaults delete com.magonil.MentalGram1 autoPic_lastUploadedHash 2>/dev/null

echo "✅ Safety gates reseteados"
echo ""
echo "Ahora:"
echo "1. Cierra COMPLETAMENTE la app MentalGram1"
echo "2. Espera 5 segundos"
echo "3. Abre la app de nuevo"
echo "4. Ve directamente a Performance"
echo "5. Debería subir la foto automáticamente"
echo ""
echo "⚠️  Si Instagram te bloquea después, es porque esto desactiva"
echo "   las protecciones. Usa pull-to-refresh en su lugar."
echo ""
