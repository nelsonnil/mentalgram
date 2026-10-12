# Notas para la auditoría de optimización

Registro de todo lo observado durante la recuperación (octubre 2026). Cada nota indica dónde se vio y qué se propone. Sirve de base para la Fase 3 de `PLAN_RECUPERACION.md`.

---

## A. Endpoints e Instagram

| Fecha | Observación | Evidencia | Propuesta |
|---|---|---|---|
| 12-oct | La build 153 (la buena) recibe **429** en `/users/{id}/info/`, `/accounts/current_user/?edit=true` y `/highlights/{id}/highlights_tray/` | Capturas Proxyman (`.captures/build153_requests.json`) | Tratarlos como endpoints retirados, no como límite temporal. Migrar a sus equivalentes GraphQL y no reintentar |
| 12-oct | Perfil (cuadrícula + datos básicos del usuario) = `IGProfileTimelineQuery` en `/graphql/query`. La respuesta llega **en trozos** (una línea JSON por trozo con `path`/`label`); el primero trae lo esencial y los demás añaden campos a cada foto | Capturas | Pintar la cuadrícula con el primer trozo, sin esperar al resto |
| 12-oct | Reels = `ClipsProfileQuery`, que también trae `follower_count` en `media.user` | Capturas | Reutilizar ese dato y no pedir la cabecera aparte |
| 12-oct | Bio en la build 153 = `POST /accounts/set_biography/` (el código usa `/accounts/edit_profile/`) | Capturas | Cambiar; probablemente es más ligero (no reenvía el perfil entero) |
| 12-oct | La subida de 1 foto se hace como carrusel de 1 (`configure_sidecar`) y va precedida de un `GET current_user?edit=true` que da 429. La subida funciona igual | Capturas | Quitar ese GET previo: no aporta nada y suma una llamada fallida en cada subida |
| 12-oct | `usertags`, `friendships/followers`, `notes/get_notes`, `only_me`, `undo_only_me`, `only_me_feed`, `discover/topical_explore` siguen igual (HTTP 200) | Capturas | Sin cambios |
| 12-oct | La build 153 pide `only_me_feed` en 12 páginas seguidas (cada 4–5 s) al abrir el selector de archivadas | Capturas | Valorar paginar bajo demanda (cargar más al hacer scroll) |

| 12-oct | `IGProfileTimelineQuery` con `count: 1` responde HTTP 200 con la cuenta, pero con **0 fotos** y `more_available: false` | Consola Vault Dev | Vale para validar la sesión (y es ligera: 2 KB), pero no sirve como "primera página" |
| 12-oct | Al entrar en Performance se pedía el perfil dos veces seguidas: cabecera y cuadrícula. Ahora la primera página se reutiliza durante 30 s | `fetchProfileInfoUnshared` + `getUserMediaItems` | Revisar en la auditoría si hay más llamadas duplicadas al entrar |
| 12-oct | Tras el login, la app pedía `/accounts/current_user/` (429) para obtener el usuario y validar la sesión, y entraba en lockdown de 5 min. Ya está cambiado a la consulta GraphQL | `fetchUsername`, `validateSession`, `probeSession` | Hecho. Queda `prefetchEditFieldsIfNeeded` (también usa `current_user`, para la bio); desaparecerá al pasar a `set_biography` |

| 12-oct | `www.instagram.com/api/v1/users/web_profile_info/` también da **429** (con una página HTML). **Ya no hay fuente para seguidos, nº de publicaciones y biografía** | Consola Vault Dev | **Pendiente**: capturar de dónde los saca la build 153 (posiblemente otra consulta GraphQL) |
| 12-oct | `POST /clips/user/` (reels) responde **400 `feedback_required`** y la app se bloqueaba 15 min. La build 153 usa `ClipsProfileQuery`. Ya está cambiado | `getUserReels`, `getUserReelsPage` | Hecho. `feedback_required` en lecturas ya no bloquea |
| 12-oct | La paginación de `IGProfileTimelineQuery` necesita **`max_id` + `profile_grid_items_cursor`**; solo con `max_id` devuelve siempre la primera página y la app marcaba "no hay más". Ahora se guardan juntos en un cursor `maxId\|gridCursor` | `fetchProfileTimeline`, `profileTimelineVariables` | Hecho (commit 6ada7c1). La marca `perf_no_more_pages_*` se guarda demasiado pronto (si el cursor se repite); revisar en la auditoría |
| 12-oct | Las respuestas GraphQL renombran algunos campos con un prefijo (`1ltaken_at`, `1fvideo_duration`) | `ClipsProfileQuery` | Se normalizan; a tener en cuenta en cualquier consulta GraphQL nueva |

## B. Frenos internos de la app (posibles falsos "límites de Instagram")

| Fecha | Observación | Dónde | Propuesta |
|---|---|---|---|
| 12-oct | Cualquier 429 provoca un **lockdown global de 300 s**, aunque venga de una lectura opcional (highlights, info) | `InstagramService.apiRequest` (~L2126) | Un 429 en una lectura solo debe desactivar ese endpoint, nunca bloquear la app entera |
| 12-oct | Presupuesto local de **55 acciones/hora**; a partir de 45 pasa a "solo caché" y deja de cargar reels/etiquetadas/highlights sin avisar | `checkRateLimit` (~L1487), `shouldUseCacheOnlyForOptionalCalls` (~L1538) | Revisar si tiene sentido; como mínimo, mostrarlo en logs y UI |
| 12-oct | **Cold start de 45 s** sin llamadas automáticas al abrir la app; también hay ventanas de 25 s (reanudar), 120 s (tras mutación) y 300 s (antes de subir / tras reveal) | `InstagramSafetyGate` (~L8429–8450) | Medir si hacen falta. Hacen que la app parezca rota ("no refresca") |
| 12-oct | Marcas `users_info_broken` guardadas **7 días** (perfil propio) / 24 h (global) en UserDefaults | `fetchProfileInfoUnshared` (~L3304–3385) | Desaparecerán al migrar a GraphQL; si no, reducirlas y hacerlas visibles |
| 12-oct | 5 respuestas `status:fail` seguidas → lockdown preventivo de 300 s, aunque el fallo sea del código (cookies, token) | `checkForBotSignals` (~L513) | Distinguir fallos de formato/sesión de señales reales de bot |
| 12-oct | Si no hay caché local del perfil, Performance **cancela la entrada y te saca** ("no usable local replica cache"). Para el usuario parece que la app "se sale" | `PerformanceView` (preload decision / entry held) | Mostrar un estado de carga o un mensaje claro en lugar de salir |
| 12-oct | Volver a entrar en Performance en menos de unos segundos activa "re-entry too soon — cache-only" | SafetyGate performance entry throttle | Revisar si hace falta |
| 12-oct | Límites por acción de SafetyGate: bio 180 s, nota 150 s, reveal 150 s, pull-refresh 120 s, paginación 6 páginas cada 10 min, archivar 8 cada 10 min… | `InstagramSafetyGate.decision` (~L8746) | Revisar uno por uno con datos reales |

| 12-oct | **Decisión (commit 8adcc58)**: los frenos de lectura empeoraban la app sin protegerla. Ahora: el cupo de 55/h solo cuenta escrituras (GET y GraphQL no); cold start y warm resume a 0 s; sin límites de paginación, Explore, búsqueda ni perfil visitado; sin pausa de reentrada en Performance ni la de 3 min tras archivar; ventana tras mutación de 120 → 30 s | `apiRequest`, `InstagramSafetyGate` | **Se mantienen** los frenos de escrituras (bio, nota, reveal, archivar, subir) y las reacciones a señales reales (challenge, login_required, 429/feedback en escrituras). Revisarlos al probar cada función |

## C. Código y estructura

| Fecha | Observación | Dónde | Propuesta |
|---|---|---|---|
| 12-oct | El código de GitHub **no compilaba**: la tarjeta de Instapick de `HomeView` era del modelo antiguo (9 fotos + archivar las "b") y el resto del código del modelo nuevo (5 publicaciones). Ya está arreglado | `HomeView.swift` (InstapickSettingsCard) | Compilar siempre antes de hacer push. Añadir un build automático (CI) |
| 12-oct | `InstagramService.swift` tiene ~9.200 líneas: perfil, subida, archivo, notas, bio y frenos en un solo archivo | — | Dividir por áreas (Perfil, Subida, Archivo, Mutaciones, SafetyGate) |
| 12-oct | Varias implementaciones paralelas de la carga del perfil (`/users/info` → `current_user` → `/feed/user` → `web_profile_info`, más reconciliaciones) | `fetchProfileInfoUnshared` (~L3276–4060) | Unificar en un solo flujo basado en GraphQL |
| 12-oct | Varias rutas de subida: `uploadPhoto`, `uploadPhotoForSidecar` + `configureSidecar`, Amnesia, Instapick y foto de perfil, cada una con su `rupload` | ~L5058, ~L5564, ~L5831, ~L6042, ~L7141 | Un único helper de `rupload` + `configure_sidecar` |
| 12-oct | Comentarios con historial largo de diagnósticos (v1–v19) dentro del código | p. ej. `uploadPhoto` (~L5250–5300) | Limpiar; dejar solo las restricciones vigentes |
| 12-oct | No hay tests ni scheme compartido en el repo | `project.pbxproj` | Añadir al menos un scheme compartido y tests del parseo de respuestas (con las capturas como datos de prueba) |

## D. Sincronización

| Fecha | Observación | Dónde | Propuesta |
|---|---|---|---|
| 12-oct | Piezas implicadas: `DataManager`, `ProfileMediaReconciler`, `ProfileCacheService`, `ManualInstagramRefresh`, Sync & Archive (`SetDetailView` ~L1849) | Inventario | Auditar juntas en la Fase 3 |
| 12-oct | Sync & Archive comprueba cada foto con `GET /media/{pk}/info/` (1 llamada por foto) | `getMediaIsArchived` (~L1579) | Usar el listado `only_me_feed` (unas pocas llamadas para todo) y comparar en local |

## E. Proceso

| Fecha | Observación | Propuesta |
|---|---|---|
| 12-oct | Se perdieron 22 builds de trabajo porque no se subieron a GitHub | Commit + push tras cada build buena |
| 12-oct | Para probar sin pisar la build de TestFlight se usa la variante `com.nelsonnil.vault.dev` ("Vault Dev") | Mantenerla como flujo habitual de desarrollo |
