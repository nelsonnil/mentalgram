# Plan de recuperación y verificación — MentalGram (Vault)

Fecha: 12-oct-2026
Punto de partida: código de GitHub (build 131, 19-jul-2026). El código de las builds 132–153 se perdió con el Mac anterior.
Referencia de "cómo debe funcionar": capturas de red de la build 153 (TestFlight), guardadas sin datos de sesión en `.captures/build153_requests.json` (no se sube a GitHub).

---

## 0. Principios de trabajo (no negociables)

1. **Un 429 o un `status:fail` no es motivo para esperar.** La propia build 153 recibe 429 en `/users/{id}/info/`, `/accounts/current_user/` y `/highlights/{id}/highlights_tray/`. Eso indica que Instagram está retirando esos endpoints, no que la cuenta esté castigada. Ante un error, se busca el endpoint o el formato que usa la build 153 y se cambia el código. No se espera a que "se pase".
2. **Los frenos internos de la app no deben confundirse con Instagram.** La app tiene muchos frenos propios: presupuesto de 55 acciones/hora, SafetyGate, lockdown, ventanas de silencio de 25 s a 300 s, marcas de "endpoint roto" guardadas durante días y modo "solo caché". Durante las pruebas se activa un **modo diagnóstico**. Ese modo registra cada freno interno con el prefijo `[LOCAL-GATE]` y cada respuesta real de Instagram con su código HTTP y su cuerpo. Así sabemos siempre quién bloquea, si la app o Instagram.
3. **Cada arreglo se compara con la captura de la build 153**: mismo endpoint, mismos parámetros y mismas cabeceras. Si algo no está capturado, se captura antes de programarlo.
4. **Todo se guarda en git** con un commit por arreglo y un push a GitHub al final de cada fase. No se vuelve a perder trabajo.

---

## 1. Preparación (Fase 0)

| # | Tarea | Resultado esperado |
|---|---|---|
| 0.1 | Crear la rama `recuperacion-api` y hacer commit del cambio de versión ya hecho (Instagram 428.0.0.47.67 / 961145276 / Bloks `7189b949…`) | Rama en GitHub |
| 0.2 | Compilar una **variante de desarrollo con otro bundle id** (`com.nelsonnil.vault.dev`, nombre "Vault Dev") | Se instala **al lado** de la build 153 de TestFlight sin reemplazarla |
| 0.3 | Instalar en el iPhone por cable desde la terminal (`xcodebuild` + `devicectl`) y lanzar con la consola conectada | Veo en directo todos los logs de la app mientras se usa |
| 0.4 | Añadir el **modo diagnóstico** (solo en Debug): registrar cada freno local con `[LOCAL-GATE]`; registrar las respuestas de Instagram con HTTP, endpoint y los primeros 300 bytes; botón para borrar las marcas "endpoint roto" y los lockdowns guardados en UserDefaults | Ningún freno local queda oculto |
| 0.5 | Iniciar sesión en Vault Dev (WKWebView) con el proxy del iPhone **desactivado** | Sesión válida; logs `[Auth]` correctos |

---

## 2. Capturas que faltan de la build 153

Se hacen con Proxyman, con el proxy activado **después** de iniciar sesión.

| Falta | Cómo capturarlo | Para qué |
|---|---|---|
| `www.instagram.com` completo | Abrir el perfil propio desde cero; exportar el dominio `www.instagram.com` | De dónde salen **seguidos, nº de publicaciones y biografía** |
| Highlights | Abrir un perfil con highlights y esperar a que aparezcan | `highlights_tray` da 429; hay que ver qué consulta usa ahora (probablemente GraphQL) |
| Perfil de otra persona | Buscar un usuario, abrir su perfil y bajar por la cuadrícula | Confirmar la paginación y la cabecera de otros perfiles |
| Amnesia | Subir un set Amnesia completo | Comparar `rupload` + `configure_sidecar` con varias fotos |
| Instapick | Una subida e intercambio de foto | Igual |
| Bio / nota / foto de perfil | Cambiar cada una una vez | Confirmar que los endpoints no cambiaron |
| Búsqueda / Explore / seguir | Buscar, abrir Explore, seguir y dejar de seguir | Confirmar endpoints |

---

## 3. Arreglos de API (Fase 1)

Orden de prioridad y estado según las capturas:

| # | Función | Código actual | Build 153 (capturado) | Acción |
|---|---|---|---|---|
| 1.1 | Versión cliente | 390 + Bloks `0a3a…` | 428 + Bloks `7189…` | **HECHO** |
| 1.2 | Cuadrícula del perfil (propio y ajeno) + paginación | GET `/feed/user/{id}/` | POST `/graphql/query` · `IGProfileTimelineQuery` · `client_doc_id=56030350814417327502004290437` · paginación por `max_id` = `next_max_id` (y `profile_grid_items_cursor`) | Nuevo `fetchProfileTimeline(userId:count:maxId:)`; la respuesta llega **por trozos** (una línea JSON por trozo, con `path` + `label`) que hay que fusionar en cada `media`. Convertir a `InstagramMediaItem`. Dejar `/feed/user` como respaldo |
| 1.3 | Cabecera del perfil (nombre, foto, privado, verificado) | `/users/{id}/info/` (429) | `user` dentro de `IGProfileTimelineQuery` | Leerla de la respuesta 1.2 |
| 1.4 | Seguidores | `/users/{id}/info/` | `follower_count` en `media.user` (GraphQL) | Extraer de la respuesta GraphQL |
| 1.5 | Seguidos, nº de publicaciones, biografía | `/users/{id}/info/` → `web_profile_info` | **Pendiente de captura** (sección 2) | Tras capturar |
| 1.6 | Reels | POST `/clips/user/` | POST `/graphql/query` · `ClipsProfileQuery` · `client_doc_id=209049231614685382737238866578` · `data.target_user_id`, `page_size=50`, `max_id`; paginación por `paging_info` | Nuevo `fetchClipsProfile(...)` |
| 1.7 | Highlights | GET `highlights_tray` (429 también en la build 153) | **Pendiente de captura** | Tras capturar |
| 1.8 | Etiquetadas | GET `/usertags/{id}/feed/` | Igual (HTTP 200) | Solo verificar |
| 1.9 | Lista de seguidores | GET `/friendships/{id}/followers/` | Igual (HTTP 200) | Solo verificar |
| 1.10 | Notas (leer) | GET `/notes/get_notes/` | Igual (HTTP 200) | Solo verificar |
| 1.11 | Bio | POST `/accounts/edit_profile/` | Build 153 usa **POST `/accounts/set_biography/`** | Cambiar al endpoint nuevo; copiar el body de la captura |
| 1.12 | Subida de foto | rupload + `configure_sidecar` (1 hijo) | Igual | Solo verificar (tras 1.1) |
| 1.13 | Archivar / desarchivar / listado archivado | `only_me` / `undo_only_me` / `only_me_feed` | Igual | Solo verificar |
| 1.14 | `current_user` previo al `configure_sidecar` | GET `current_user?edit=true` | Igual, y también da 429 (la subida funciona igualmente) | Asegurar que un 429 aquí **no** dispara lockdown ni aborta la subida |
| 1.15 | Gestión de 429 | Cualquier 429 → lockdown global de 300 s | — | Un 429 en una **lectura** opcional (info, highlights, current_user) solo marca ese endpoint y pasa a la alternativa. Nunca bloquea toda la app |
| 1.16 | Explore | GET `/discover/topical_explore/` | Igual (HTTP 200) | Solo verificar |

---

## 4. Verificación función por función (Fase 2)

Cada prueba se hace en Vault Dev con la consola conectada. "OK" significa: funciona en pantalla, los logs muestran HTTP 200 / `status:ok` y no hay ningún `[LOCAL-GATE]` inesperado.

### 4.1 Sesión
- [ ] Login WKWebView (con el proxy desactivado)
- [ ] Cerrar y reabrir la app: la sesión se mantiene
- [ ] Logout y relogin
- [ ] Una sesión caducada muestra el aviso de reconexión, no un lockdown

### 4.2 Perfil propio (Performance)
- [ ] Carga en frío: cabecera completa (nombre, foto, seguidores, seguidos, publicaciones, bio)
- [ ] Cuadrícula: primeras 12 fotos
- [ ] **Paginación**: bajar hasta el final, sin repetidos ni huecos, y con el mismo total que Instagram
- [ ] Carruseles: se muestran con el icono y el número de fotos
- [ ] Vídeos en la cuadrícula
- [ ] Pestaña **Reels**: lista y paginación
- [ ] Pestaña **Etiquetadas**
- [ ] **Highlights**: portadas y títulos
- [ ] Nota actual visible
- [ ] Pull to refresh
- [ ] Refrescar desde Instagram (Ajustes)
- [ ] La caché se muestra al instante al reabrir y luego se actualiza

### 4.3 Perfil de otra persona / búsqueda
- [ ] Buscar usuario
- [ ] Abrir perfil: cabecera completa
- [ ] Cuadrícula + paginación
- [ ] Reels / etiquetadas / highlights
- [ ] Seguir / dejar de seguir
- [ ] Perfil privado: mensaje correcto
- [ ] Lista de seguidores / seguidos

### 4.4 Explore
- [ ] Carga del feed
- [ ] Paginación

### 4.5 Mutaciones de perfil
- [ ] Cambiar bio (también la acróstica)
- [ ] Crear nota y borrar nota
- [ ] Cambiar foto de perfil
- [ ] Reset de perfil (restaurar bio, nota y foto originales)

### 4.6 Sets: subida y archivo
- [ ] Crear set y subir **1 foto** (aparece en Instagram)
- [ ] Subir set de **varias fotos**: todas se suben y se archivan en orden
- [ ] **Sync & Archive**: detecta las que faltan archivar
- [ ] Selector de fotos archivadas: lista completa con paginación
- [ ] **Reveal** (desarchivar): aparece en el perfil
- [ ] **Hide** (re-archivar)
- [ ] Quick Reveal

### 4.7 Amnesia
- [ ] Subir carrusel(es) Amnesia
- [ ] Intercambio de fotos (swap)
- [ ] Restaurar

### 4.8 Instapick
- [ ] Subir carrusel Instapick
- [ ] Swap de slot
- [ ] Restaurar slots

### 4.9 Force Post / Force Reel / predicciones
- [ ] Selectores de publicación y reel de otros usuarios
- [ ] Detección de likes / publicaciones por IA

### 4.10 Errores y frenos
- [ ] Un 429 en una lectura no bloquea la app entera
- [ ] Un challenge real muestra la pantalla de challenge
- [ ] Logs y crash logs exportables desde Ajustes

---

## 5. Auditoría de sincronización y optimización (Fase 3, cuando todo funcione)

1. **Inventario de llamadas por pantalla**: cuántas peticiones hace cada acción (abrir la app, entrar en Performance, subir un set…) y comparación con la build 153.
2. **Sincronización**: revisar `DataManager`, `ProfileMediaReconciler`, `ProfileCacheService`, `ManualInstagramRefresh` y Sync & Archive. Buscar estados desincronizados (foto marcada archivada que no lo está, huecos en la paginación, fotos fantasma).
3. **Frenos internos**: dejar solo los que tienen sentido. Quitar o reducir los que bloquean sin motivo real: marcas "roto" de 7 días, lockdown global por 429 de lectura, ventanas de silencio largas.
4. **Caché**: reglas claras de cuándo mostrar caché y cuándo refrescar.
5. **Duplicados**: unificar las 2–3 implementaciones de la carga de perfil y de la subida en una sola por función.
6. Informe final con cambios propuestos, riesgo de cada uno y orden de aplicación.

---

## 6. Qué necesito del usuario en cada fase

- **Fase 0**: tener el iPhone conectado por cable y desbloqueado, aceptar "Confiar en este ordenador" y, la primera vez, permitir el certificado de desarrollador en Ajustes → General → VPN y gestión de dispositivos.
- **Sección 2**: hacer las capturas pendientes con la build 153 de TestFlight.
- **Fase 2**: tocar en el iPhone lo que te pida (yo leo los logs en directo) y decirme lo que ves en pantalla.
