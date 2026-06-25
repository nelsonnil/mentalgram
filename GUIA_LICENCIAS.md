# 🔑 Guía de Gestión de Licencias - MentalGram

## 📖 Índice
1. [Cómo Funciona el Sistema](#cómo-funciona-el-sistema)
2. [Generar Códigos de Licencia](#generar-códigos-de-licencia)
3. [Añadir Códigos a la App](#añadir-códigos-a-la-app)
4. [Distribuir Códigos a Usuarios](#distribuir-códigos-a-usuarios)
5. [Gestión de Usuarios](#gestión-de-usuarios)
6. [Preguntas Frecuentes](#preguntas-frecuentes)

---

## 🔍 Cómo Funciona el Sistema

### Sistema Actual: Lista de Códigos Embebida
- Los códigos válidos están **dentro de la app** en `LicenseManager.swift`
- Cuando un usuario ingresa un código, la app verifica si está en la lista
- ✅ **Ventaja**: No necesitas servidor, todo es local
- ⚠️ **Limitación**: Debes actualizar la app para añadir nuevos códigos

### Usuarios Existentes (Grandfathering)
La app detecta automáticamente usuarios existentes y les da acceso sin código:
- ✅ Si tienen sesión de Instagram guardada
- ✅ Si tienen sets creados
- ✅ Si tienen backup en iCloud
- ✅ Si tienen configuraciones previas

### Usuarios Nuevos
- Ven una pantalla de activación al abrir la app por primera vez
- Deben ingresar un código válido para usar la app
- El código se guarda localmente y permanece activado

---

## 🎲 Generar Códigos de Licencia

### Opción 1: Usar el Script Python (Recomendado)

He creado un script llamado `generar_licencias.py` en la carpeta del proyecto.

#### Generar 1 código aleatorio:
```bash
cd /Users/nil/Desktop/MentalGram1
python3 generar_licencias.py
```

Ejemplo de salida:
```
Código generado:
  H2BYEC-3DL7XE-FJ4CJS-708SC-H3GBJG
```

#### Generar múltiples códigos (ej: 10):
```bash
python3 generar_licencias.py 10
```

Ejemplo de salida:
```
Generando 10 código(s)...

1. H2BYEC-3DL7XE-FJ4CJS-708SC-H3GBJG
2. 9ZJELI-8L6JI6-WXA8OT-Z699M-USYGV
3. FB4ZY6-I38U76-T9UHX-QLENM3-Z85PO
...
```

#### Generar código personalizado con nombre de usuario:
```bash
python3 generar_licencias.py --usuario "Pedro Martinez"
```

Ejemplo de salida:
```
Usuario: Pedro Martinez
Código:  PEDRO-KBOYF-YVSXF-9E7WRS-69NUJ2
```

### Opción 2: Generar Manualmente

Formato: **5 segmentos** de **5-6 caracteres** alfanuméricos separados por guión

Ejemplo válido:
```
MAGIC1-TRICK2-FORCE3-PERF4-USER5
ABCDE-12345-FGHIJ-67890-KLMNO
```

Puedes usar cualquier combinación de:
- Letras mayúsculas: A-Z
- Números: 0-9

---

## 📝 Añadir Códigos a la App

### Paso 1: Abrir el Archivo de Licencias

Abre el archivo:
```
/Users/nil/Desktop/MentalGram1/MentalGram1/Services/LicenseManager.swift
```

### Paso 2: Localizar la Lista de Códigos

Busca esta sección (alrededor de la línea 25):

```swift
// Lista de códigos válidos firmados - en producción, esto vendría de un archivo o generador
private let validLicenses: Set<String> = [
    "SPIIOS-T8384-5PEKS-2B3FR-YYTHX",
    "VAULT1-MAGIC-TRICK-FORCE-ABC12",
    "MENTAL-GRAM1-TLFGT-PERFO-XYZ99",
    "MAGICO-12345-ABCDE-FGHIJ-KLMNO",
    "TESTFL-IGHTX-PRODU-CTION-VER01"
]
```

### Paso 3: Añadir Nuevos Códigos

Simplemente añade los nuevos códigos a la lista:

```swift
private let validLicenses: Set<String> = [
    // Códigos existentes
    "SPIIOS-T8384-5PEKS-2B3FR-YYTHX",
    "VAULT1-MAGIC-TRICK-FORCE-ABC12",
    
    // Nuevos códigos añadidos
    "H2BYEC-3DL7XE-FJ4CJS-708SC-H3GBJG",  // Usuario: Juan Pérez
    "PEDRO-KBOYF-YVSXF-9E7WRS-69NUJ2",   // Usuario: Pedro Martinez
    "9ZJELI-8L6JI6-WXA8OT-Z699M-USYGV",  // Usuario: María García
]
```

💡 **Tip**: Añade comentarios con el nombre del usuario para llevar control

### Paso 4: Guardar y Compilar

1. Guarda el archivo (`Cmd+S`)
2. Compila la app en Xcode
3. Sube a TestFlight
4. Los nuevos códigos estarán disponibles en la nueva versión

---

## 📤 Distribuir Códigos a Usuarios

### Plantilla de Mensaje para Enviar:

```
🎩 ¡Bienvenido a MentalGram!

Tu código de licencia personal es:

🔑 XXXXX-XXXXX-XXXXX-XXXXX-XXXXX

Instrucciones:
1. Abre la app MentalGram
2. Verás una pantalla de activación
3. Ingresa tu código exactamente como aparece arriba
4. Presiona "Activar"

⚠️ Importante:
- Este código es único y personal
- No lo compartas con otros usuarios
- Se activará automáticamente una vez ingresado

Si tienes problemas, contáctame.

¡Disfruta de MentalGram! 🎭
```

### Consejos de Distribución

1. **Mantén un Registro**: Crea una hoja de cálculo con:
   - Nombre del usuario
   - Código asignado
   - Fecha de envío
   - Estado (activo/usado)

2. **Envío Seguro**: 
   - Envía por mensaje directo
   - No publiques códigos públicamente
   - Confirma que el usuario lo recibió

3. **Un Código por Usuario**: 
   - No reutilices códigos
   - Genera uno nuevo para cada usuario

---

## 👥 Gestión de Usuarios

### Verificar si un Usuario Está Activado

Los usuarios pueden verificar su estado en:
- Settings → DATA & INFO → Licencia

Estados posibles:
- ✅ "Activada" con checkmark verde = Licencia válida
- "Usuario grandfathered" = Acceso automático (usuario antiguo)
- Botón "Activar" = Sin licencia activa

### Revocar un Código (Futura Actualización)

Para revocar acceso a un usuario:
1. Elimina su código de `validLicenses` en `LicenseManager.swift`
2. Compila y sube nueva versión a TestFlight
3. El usuario NO podrá reactivar con ese código en la nueva versión
4. **Nota**: Si ya está activado, seguirá funcionando hasta que reinstale

### Resetear Licencia (Solo para Testing)

En modo DEBUG, puedes añadir un botón para desactivar la licencia:

```swift
#if DEBUG
if developerMode {
    Button("Desactivar Licencia (DEBUG)") {
        LicenseManager.shared.deactivate()
    }
}
#endif
```

---

## ❓ Preguntas Frecuentes

### ¿Cuántos códigos puedo tener?
No hay límite. Puedes tener cientos o miles de códigos en la lista.

### ¿Puedo cambiar el formato de los códigos?
Sí, pero tendrías que modificar la validación en `LicenseManager.swift`:

```swift
private func isValidFormat(_ code: String) -> Bool {
    // Modifica esta regex según tu nuevo formato
    let pattern = "^[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}-[A-Z0-9]{5,6}$"
    ...
}
```

### ¿Qué pasa si un usuario reinstala la app?
- Si es usuario existente con backup: Se reactiva automáticamente (grandfathering)
- Si es usuario nuevo: Debe volver a ingresar su código

### ¿Puedo ver qué usuarios han activado su código?
No con el sistema actual. Toda la validación es local en el dispositivo del usuario.

Para tracking, necesitarías:
1. Un servidor backend
2. API para registrar activaciones
3. Modificar `LicenseManager` para enviar datos al servidor

### ¿Es seguro este sistema?
- ✅ **Para TestFlight (300 usuarios)**: Sí, es suficientemente seguro
- ⚠️ **Para App Store pública**: Necesitarías algo más robusto

Alguien técnico podría:
- Descompilar la app y ver los códigos embebidos
- Compartir un código válido con otros

**Recomendación para mayor seguridad** (si lo necesitas):
1. Códigos vinculados a dispositivo (UUID)
2. Validación con servidor remoto
3. Códigos de un solo uso

---

## 🔧 Mejoras Futuras (Opcional)

Si quieres evolucionar el sistema, podrías:

### 1. Códigos con Límite de Tiempo
```swift
struct License {
    let code: String
    let expiryDate: Date
}
```

### 2. Códigos de Un Solo Uso
Marcar códigos como "usados" en iCloud para compartir estado entre reinstalaciones.

### 3. Servidor de Validación
- Crear API REST simple
- Validar códigos en tiempo real
- Tracking de uso por código

### 4. Generación con Firma Criptográfica
Usar algoritmos de firma digital para que puedas generar códigos válidos sin necesidad de actualizar la app.

---

## 📞 Soporte

Si necesitas ayuda:
1. Revisa esta guía primero
2. Prueba los comandos de ejemplo
3. Verifica que los códigos tengan el formato correcto

---

**Última actualización**: Junio 2026  
**Versión del sistema**: 1.0  
**Compatibilidad**: iOS 15+
