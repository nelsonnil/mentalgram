# Instagram Notes API — Diagnóstico y Fixes

## Problemas identificados (cronológico)

### Intento 1 — Body sin URL-encoding (`apiRequest` genérico)
El helper `apiRequest` construye el body como:
```swift
body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
```
**Problema**: los valores NO se percent-encodean. Si el csrfToken contiene `+`, `/` o `=`
(frecuente en tokens de sesión Instagram), el body queda malformado y el servidor lo rechaza
con la respuesta genérica `"status":"fail"`.

### Intento 2 — Parámetros faltantes
Body enviado:
```
audience, text, _csrftoken, _uid, _uuid, uuid (UUID DIFERENTE al _uuid)
```
**Problemas**:
- `type` es requerido por la API de Notes de Instagram (valor: `"text_post"`)
- `device_id` es requerido (debe coincidir con `_uuid`)
- `uuid` se generaba con `UUID().uuidString` → valor DIFERENTE a `_uuid` → incoherencia que Instagram detecta como fraude

### Intento 3 — UUID incoherente
`_uuid` = clientUUID (persistente)
`uuid`  = UUID().uuidString (nuevo en cada llamada)
Dos UUIDs distintos en el mismo request es una señal de bot.

### Problema de User-Agent (iOS 26.x)
El dispositivo real ejecuta iOS 26.3.1 (beta 2026). El User-Agent resultante es:
```
Instagram 426.0.0.30.91 (iPhone16,2; iOS 26_3_1; ...)
```
Instagram versión 426 nunca fue lanzada para iOS 26. Esta incoherencia puede hacer que
endpoints sensibles (como Notes) rechacen el request. Se mitiga clampeando la versión de iOS
a un máximo de 18_x en el User-Agent.

## Fix aplicado (2026-04-28)
- `createNote` ahora usa un request propio con `URLComponents` para percent-encoding correcto
- Añadidos `device_id` (= clientUUID) y `type = "text_post"`
- Eliminado `uuid` redundante; ahora solo se envía `_uuid`
- User-Agent clamped: si el sistema reporta iOS ≥ 19, se reporta `18_0` para compatibilidad
- Log del body exacto antes de enviarlo para facilitar debugging futuro

## Respuesta esperada tras el fix
```json
{"status": "ok"}
```
