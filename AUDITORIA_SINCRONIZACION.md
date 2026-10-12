# Auditoría de sincronización y plan de corrección

Fecha: 12 de octubre de 2026. Rama `recuperacion-api`.

## 1. Objetivo

La cuadrícula de Performance tiene que ser **una copia exacta del perfil real de Instagram**: las mismas publicaciones y en el mismo orden, sin fotos de más ni de menos.

- Si el mago cambia algo **desde la app** (subir, archivar, desarchivar, reveal, Amnesia, Instapick), la copia se actualiza al momento y sin esperar a Instagram.
- Si cambia algo **desde Instagram** (publicar, borrar, archivar, desarchivar, fijar), la app no puede saberlo hasta refrescar. Pero **tras un refresco tiene que quedar exactamente igual** que Instagram, cambie lo que cambie y en la posición que sea.
- Los sets (qué foto está subida, con qué id y si está archivada) tienen que coincidir siempre con el estado real en Instagram.

## 2. Cómo funciona hoy

| Pieza | Qué hace |
|---|---|
| `ProfileCacheService` | Guarda la copia del perfil en disco (`profile.json`): lista de publicaciones, cursor de páginas y cabecera. Tiene dos formas de guardar: **con fusión** (`saveProfile`, conserva las fotos antiguas que no vinieron en la respuesta) y **autoritativa** (`saveProfileAuthoritative`, guarda tal cual) |
| `ProfileMediaReconciler.applyExactFetchedPrefix` | Al refrescar, pone arriba exactamente lo que devolvió Instagram y conserva debajo las fotos locales "más antiguas que la última página leída" |
| `reconcileSetPhotosMissingFromSyncedFeed` | Marca como archivadas las fotos de sets que deberían haber salido en la parte leída y no salieron |
| Refresco de Performance (tirar hacia abajo) | Lee **solo la página 1** (unas 12 publicaciones) |
| Botón "Refresh from Instagram" | Permite elegir entre 1, 2 o 3 páginas (12, 24 o 36 publicaciones). La opción "Repair" lee 4 |
| Scroll al final de la cuadrícula | Pide la página siguiente y **añade al final** lo que no estaba |
| Refresco silencioso (tras reveal, subida, etc.) | Lee la página 1 y conserva el resto como estaba |
| Acciones desde la app | Actualizan la copia local al instante (`removeMediaEverywhere`, `insertMediaURL`, overlays `reveal://`) |
| Sync & Archive (`SetDetailView`) | Comprueba las fotos del set una a una con `GET /media/{id}/info/` |

## 3. Problemas encontrados

### Crítico (ya corregido hoy, commit a96c48e)

**S0. El cursor nuevo hacía creer a la app que el perfil estaba completo.**
- Al arreglar la paginación, el cursor pasó a ser `maxId|token`. La función `cursorPK`, que calcula hasta dónde se ha leído, no entendía ese formato y devolvía "sin cursor", es decir, "Instagram ya devolvió el perfil entero".
- En el refresco de las 11:50 esto **quitó 21 publicaciones de la copia**; por eso Performance tenía 54 de las 69. También podría haber marcado como archivadas fotos de sets, aunque esta vez no ocurrió.
- Corregido: ahora entiende el formato nuevo. Además, un cursor que no se pueda leer nunca se interpreta como "perfil completo" (se conserva lo antiguo y no se archiva nada).

### Graves (causan desajustes reales)

**S1. Refrescar solo mira las primeras 12 publicaciones.**
Lo que cambie más abajo no se detecta nunca:
- Una publicación antigua **borrada o archivada desde Instagram** se queda en la copia como fantasma.
- Una publicación antigua **desarchivada desde Instagram** (vuelve a su fecha original, en mitad de la cuadrícula) no aparece.
- Si se **publican muchas de golpe** (por ejemplo 50), solo entran las 12 primeras. Entre ellas y las antiguas queda un hueco de 38 que falta.

**S2. El scroll añade al final, sin colocar en su sitio.**
Siguiendo el ejemplo anterior, al hacer scroll se cargan las publicaciones nuevas 13–33, pero se añaden **detrás de las antiguas**: el orden queda mal. Además, la paginación solo añade: nunca quita fantasmas ni corrige el orden.

**S3. Al paginar se descartan publicaciones para que la cuadrícula sea múltiplo de 3, pero el cursor avanza igual.**
Esas 1 o 2 publicaciones no se vuelven a pedir nunca: faltan para siempre en la copia (`loadMoreMedia`, `urlsToDisplay`).

**S4. Las rutas automáticas fusionan en lugar de reemplazar.**
- La carga al entrar, la paginación y el refresco silencioso usan el guardado con fusión, que **vuelve a añadir lo antiguo** que ya no existe.
- Solo los refrescos manuales son autoritativos, y solo en las páginas leídas.

**S5. Los sets solo se corrigen en un sentido.**
- El refresco marca fotos como archivadas si faltan, pero **nunca marca como visible** una foto de set que el mago desarchivó desde Instagram.
- Tampoco detecta una foto de set **borrada** en Instagram (ni visible ni archivada): el set la sigue dando por buena y un reveal fallaría en directo.

**S6. Límite de 100 publicaciones.**
`maxPhotosOwnProfile = 100`: en cuentas con más de 100 la copia nunca está completa. Hay que decidir si se acepta. Con un límite, la sincronización tiene que saber dónde termina la parte copiada.

### Medios

**S7. Varios caminos distintos para lo mismo.**
- Refresco de Performance, refresco sin Performance (`ManualInstagramRefresh`), refresco silencioso, paginación y Sync & Archive.
- Cada uno tiene su propia lógica de fusión y de reveals. Un arreglo en uno no llega a los demás: es la razón por la que los fallos "volvían".

**S8. La marca `perf_no_more_pages_*` se guarda demasiado pronto.**
Si un cursor se repite, la app decide que no hay más páginas y deja de paginar en las siguientes sesiones.

**S9. Sync & Archive hace una llamada por foto (`/media/{id}/info/`).**
Con sets grandes son muchas llamadas. El listado de archivadas (`only_me_feed`) da lo mismo en unas pocas páginas.

**S10. Los reveals pendientes (`reveal://`) dependen de que Instagram los devuelva en la página 1.**
Una foto revelada con fecha antigua cae más abajo y se queda como pendiente hasta que alguna página la incluya. Con la sincronización completa este caso desaparece.

## 4. Plan de corrección

Idea central: **una única función de sincronización completa**, que todos los refrescos usen y que deje la copia idéntica a Instagram. Como ahora las lecturas no tienen frenos y 69 publicaciones son unas 4–6 peticiones (unos segundos), leerlo todo en cada refresco es asumible y elimina de raíz S1, S2, S4 y S10.

### Fase A — Sincronización completa (núcleo)

1. **`ProfileSyncEngine.fullSync()`** (nuevo, en un solo sitio):
   - Lee todas las páginas de `IGProfileTimelineQuery` hasta que Instagram diga que no hay más, o hasta el límite decidido en S6.
   - Lee la cabecera (Polaris) en paralelo.
   - Construye la lista nueva **en memoria**. Solo si termina bien la guarda de golpe (guardado autoritativo). Si falla a mitad, **no toca nada**: la copia anterior sigue intacta. Nunca se queda a medias.
   - Comprobación final: el número de publicaciones leídas tiene que coincidir con `media_count` de la cabecera. Si no coincide, se registra y se reintenta una vez.
2. **Overlays locales** (`reveal://`, Amnesia, Instapick): se vuelven a colocar encima de la lista nueva con la lógica que ya existe. Un reveal se confirma si su id aparece en *cualquier* página, no solo en la 1.
3. **Reconciliación de sets en los dos sentidos** con la lista completa:
   - El id está en el perfil → `isArchived = false`.
   - No está en el perfil pero sí en archivadas (`only_me_feed`, leído en la misma sincronización) → `isArchived = true`.
   - No está en ninguno → se marca como **"falta en Instagram"** y se avisa en el set, para no hacer un reveal que fallaría.
4. **Todos los refrescos pasan por aquí**: tirar hacia abajo en Performance, el botón de Ajustes/Sets (el selector de 1/2/3 páginas desaparece) y Repair.

### Fase B — Rutas automáticas y paginación

5. **Al entrar en Performance**: se pinta la copia local al instante y en segundo plano se hace una comprobación ligera (página 1 + cabecera).
   - Si la página 1 coincide con la copia y `media_count` no cambió, no se hace nada más.
   - Si algo difiere, se lanza `fullSync()` en segundo plano.
   - Así se detectan también los cambios hechos desde Instagram sin que el mago tenga que refrescar.
6. **Paginación por scroll**: deja de "añadir al final". Si la copia está completa, no hace falta pedir nada. Si no lo está (límite S6), cada página se aplica por rango (`applyAuthoritativePageRange`), con lo que se quitan los fantasmas y se respeta el orden.
7. **Quitar el recorte a múltiplos de 3** (S3). Instagram tampoco lo hace: la última fila puede quedar incompleta.
8. **Refresco silencioso** tras acciones: usa la comprobación ligera del punto 5 en lugar de su propia fusión.
9. La marca "no hay más páginas" solo se guarda cuando Instagram devuelve explícitamente que no hay más (S8).

### Fase C — Acciones desde la app

10. Cada acción actualiza la copia al instante, como ahora:
    - Subir y archivar no cambia la cuadrícula.
    - Desarchivar o hacer reveal añade la foto en su posición por fecha.
    - Archivar la quita.

    Además deja programada una **confirmación**: unos segundos después, la comprobación ligera verifica que Instagram refleja lo mismo. Si no, se lanza `fullSync()`.
11. Sync & Archive pasa a usar el listado de archivadas más la lista completa del perfil en lugar de una llamada por foto (S9).

### Fase D — Pruebas (con el laboratorio, sin que tengas que tocar nada)

Cada caso se prueba en Vault Dev y se compara la copia (`profile.json`) con Instagram, publicación por publicación:

| Caso | Cómo se provoca | Resultado esperado |
|---|---|---|
| Sin cambios | Refrescar dos veces | Copia idéntica, 69/69, mismo orden |
| Publicación nueva desde Instagram | La publicas tú | Aparece la primera |
| Muchas nuevas (simulado) | Copia local recortada artificialmente | Se rellena entera y en orden |
| Archivada desde Instagram (antigua, posición 40) | La archivas tú | Desaparece de la copia; si es de un set, el set la marca archivada |
| Desarchivada desde Instagram | La desarchivas tú | Aparece en su posición por fecha; el set la marca visible |
| Borrada desde Instagram | La borras tú | Desaparece; si es de un set, aviso "falta en Instagram" |
| Fijada (pin) | La fijas tú | Aparece arriba, como en Instagram |
| Subida + archivo desde la app | Subir un set | La cuadrícula no cambia; los ids del set son correctos |
| Reveal / desarchivar desde la app | Reveal de prueba | Aparece al instante y sigue igual tras refrescar |
| Fallo de red a mitad de sincronización | Cortar la red durante el refresco | La copia anterior queda intacta |
| Caché borrada | Repair | Se reconstruye completa |

Para las pruebas que requieren cambios en Instagram (archivar, borrar, fijar), te pediré permiso antes, o que los hagas tú desde Instagram, y yo compruebo el resultado.

### Fase E — Optimización general (pendiente de las notas)

12. Quitar el `GET current_user` antes de `configure_sidecar` (sobra en cada subida).
13. Sustituir las ~10 llamadas a `web_profile_info` (siempre 429) por `fetchPolarisProfile`.
14. Un 429 en una lectura opcional no debe bloquear toda la app 300 s; solo ese endpoint.
15. Revisar el cupo de 55 escrituras/hora frente a subidas grandes (26 fotos ≈ 104 acciones) y mostrar en pantalla cuándo se pausa y por qué.
16. Unificar las rutas de subida (`rupload` + `configure_sidecar`) en una sola.
17. Dividir `InstagramService.swift` (~9.700 líneas) por áreas y añadir tests del reconciliador con capturas reales como datos.

## 5. Orden de trabajo propuesto

1. Fase A (núcleo) y su batería de pruebas. Es lo que resuelve los desajustes.
2. Fase B y Fase C.
3. Fase E.

Cada fase termina con una build en Vault Dev, las pruebas de la tabla, commit y push.
