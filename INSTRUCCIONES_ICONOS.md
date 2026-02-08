# 📱 Cómo Importar Iconos SVG en Xcode

Sigue estos pasos para importar los iconos personalizados de Instagram en tu proyecto.

## 🎯 Paso 1: Abrir Assets en Xcode

1. Abre tu proyecto `MentalGram1.xcodeproj` en Xcode
2. En el navegador de archivos (izquierda), busca la carpeta **`Assets.xcassets`**
3. Haz clic en **`Assets.xcassets`** para abrirla

## 📥 Paso 2: Importar los SVG

Para cada icono SVG, haz lo siguiente:

1. **Dentro de Assets.xcassets**, haz clic derecho → **"New Image Set"**
2. Nombra el Image Set exactamente como se indica abajo
3. En el panel derecho, en **"Attributes Inspector"**:
   - **Render As**: Selecciona **"Template Image"** (importante para que pueda cambiar de color)
   - **Scale**: Mantén **"Single Scale"**
4. **Arrastra el archivo SVG** desde Finder a la casilla **"Universal"**

### Lista de iconos a importar:

| Archivo SVG | Nombre en Xcode | Uso |
|-------------|-----------------|-----|
| `home.svg` | `instagram_home` | Barra inferior - Home |
| `search.svg` | `instagram_search` | Barra inferior - Search |
| `reels.svg` | `instagram_reels` | Barra inferior - Reels |
| `messages.svg` | `instagram_messages` | Barra inferior - Messages |
| `plus.svg` | `instagram_plus` | Header - Botón crear |
| `menu.svg` | `instagram_menu` | Header - Menú hamburguesa |
| `grid.svg` | `instagram_grid` | Tab - Grid de fotos |
| `reels_tab.svg` | `instagram_reels_tab` | Tab - Reels |
| `tagged.svg` | `instagram_tagged` | Tab - Etiquetado |
| `chevron_down.svg` | `instagram_chevron_down` | Header - Dropdown username |

## ✅ Paso 3: Verificar Importación

Una vez importados todos:
1. Deberías ver 10 nuevos Image Sets en Assets.xcassets
2. Cada uno debe mostrar el icono SVG
3. Todos deben tener **Render As: Template Image**

## 🚀 Paso 4: Compilar

Una vez importados todos los iconos:
1. Presiona **⌘ + B** para compilar
2. El código ya está actualizado para usar estos iconos
3. Los iconos ahora serán réplicas exactas de Instagram

---

## 📍 Ubicación de los archivos:
```
/Users/nil/Desktop/MentalGram1/MentalGram1/Assets/InstagramIcons/
```

## ⚠️ Nota importante:
- TODOS los iconos deben tener **"Render As: Template Image"** 
- Esto permite que cambien de color dinámicamente (negro/blanco según el tema)
- Los nombres DEBEN ser exactos para que el código funcione
