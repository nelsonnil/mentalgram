# Sets y Post Prediction

## ¿Qué es un Set?

Un **Set** es una colección de imágenes que preparas con antelación y que la app gestiona de forma automática en tu cuenta de Instagram. Cada imagen dentro del Set corresponde a **una letra o un número**, formando así un "banco visual" completo listo para ser usado en cualquier momento.

Existen dos tipos de Sets:

- **Set de Letras** — cada imagen representa una letra del alfabeto (A, B, C … Z, incluyendo caracteres especiales según el idioma).
- **Set Numérico** — cada imagen representa un dígito del 0 al 9.

Puedes crear tantos Sets como necesites y organizarlos por temática, estilo o propósito.

---

## Cómo se prepara un Set

### 1. Carga de imágenes

Al crear un Set eliges cuántos **bancos** quieres tener. Cada banco contiene una imagen para cada letra o número del alfabeto. Lo importante es entender que **cada banco corresponde a una posición dentro de la palabra o secuencia que revelarás**:

- La **primera letra** de la revelación se toma del banco 1.
- La **segunda letra** se toma del banco 2.
- La **tercera letra** del banco 3, y así sucesivamente.

Esto significa que el número de bancos determina directamente **la longitud máxima de la palabra o secuencia que puedes revelar**. Con 5 bancos podrás revelar palabras de hasta 5 letras; con 9 bancos, de hasta 9 letras. Cada posición siempre se cubre con su banco correspondiente, manteniendo el orden y la independencia de cada post en Instagram.

Puedes cargar las imágenes de dos maneras:

- **Usando una plantilla prediseñada** — la app incluye colecciones de imágenes listas para usar con distintos estilos visuales (por ejemplo, letras sobre fondo de ciudad, estilo tipográfico clásico, etc.).
- **Subiendo tus propias imágenes** — personaliza completamente tu Set con fotos propias, diseños a medida o cualquier contenido que se adapte a tu concepto.

### 2. Subida progresiva a Instagram

Una vez configurado el Set, la app comienza a subir las imágenes a tu cuenta de Instagram de forma **gradual y escalonada**. Este ritmo controlado es fundamental para evitar que Instagram detecte actividad inusual.

A medida que cada imagen se sube correctamente, se **archiva automáticamente** en tu perfil. Esto significa que el post existe en Instagram pero no es visible para nadie en tu grid público; está guardado en la sección de archivados, listo para ser activado.

---

### ⚠️ Recomendaciones importantes durante la subida

Para garantizar una subida correcta y sin interrupciones, es fundamental tener en cuenta lo siguiente:

**No uses la app mientras se están subiendo las imágenes.**
Cada acción dentro de la app genera llamadas a la API de Instagram. Si realizas otras acciones durante la subida —navegar por la app, cambiar ajustes, explorar contenido— se producen solicitudes adicionales que pueden interferir con el proceso o aumentar el riesgo de que Instagram detecte actividad anómala.

**No cambies de red Wi-Fi ni de conexión.**
Un cambio de red durante la subida puede interrumpir el proceso o causar errores que requieran volver a empezar desde ese punto.

**La pantalla no entrará en reposo.**
La app mantendrá el dispositivo activo de forma automática mientras sube. No es necesario tocar la pantalla para que continúe. Puedes dejarla conectada a la corriente y subir el Set durante la noche sin preocuparte.

**Puedes salir de la app temporalmente.**
Si necesitas usar el dispositivo para otra cosa, puedes salir de la app. Cuando sea el momento de subir la siguiente imagen, recibirás una **notificación** avisándote para que regreses. Al volver a la app, la subida continuará automáticamente desde donde se quedó.

> **Recomendación general:** la forma más sencilla y segura de preparar un Set completo es dejarlo subiendo durante la noche, con el dispositivo enchufado, la app abierta y sin usar el móvil para nada más. Al día siguiente tu Set estará listo.

---

## Post Prediction: cómo funciona la revelación

**Post Prediction** es la funcionalidad que transforma tu Set en una predicción visual en tiempo real. Cuando seleccionas una letra o número, la app **desarchivar** ese post concreto de Instagram, haciéndolo visible en tu perfil públicamente, pero en su **posición original** dentro del grid, con su **fecha original** de subida.

### La clave del efecto

Cuando un post se archivó hace semanas o meses y luego se desarchivar, Instagram lo devuelve exactamente al mismo lugar que ocupaba. Esto significa que:

- Aparece **intercalado con posts antiguos**, no al principio del perfil.
- Mantiene su **fecha original**, como si siempre hubiera estado ahí.
- Para encontrarlo hay que hacer **scroll hacia abajo**, lo que refuerza la ilusión de que el post existía desde mucho antes.

El resultado es un post que parece haber sido publicado en el pasado —antes de que el espectador supiera el número o la letra— funcionando como una predicción irrefutable registrada en Instagram.

---

## Cómo se selecciona qué revelar

La app ofrece tres formas distintas de indicar qué letra o número se quiere revelar:

### URL Scheme
La predicción puede activarse desde fuera de la app mediante un enlace especial. Esto permite integraciones con otras apps, atajos de Siri, o flujos automatizados donde simplemente se envía el valor a revelar y la app lo gestiona sola en segundo plano.

### OCR (reconocimiento óptico de caracteres)
Apunta la cámara a cualquier superficie donde aparezca escrito un número o una palabra —una pizarra, una pantalla, un papel— y la app lo lee automáticamente, activando la imagen correspondiente sin necesidad de tocar nada más.

### Grid Input (selección manual)

El Grid Input es el método de introducción más visual e intuitivo, diseñado para usarse discretamente durante una actuación en directo.

La interfaz muestra el perfil de Instagram de forma idéntica a como se ve en la app real. El grid de posts actúa como teclado numérico visual: cada post tiene un dígito asignado según su posición en la cuadrícula:

- **Posts del 1 al 9** → dígitos del **1 al 9** respectivamente.
- **Posts 10, 11 y 12** → dígito **0**. Cualquiera de los tres equivale al mismo valor, lo que da margen para llegar al cero de forma natural con un simple deslizamiento adicional.

Para introducir un dígito, **desliza hacia la izquierda o la derecha** hasta posicionarte sobre el post que representa el número deseado. A medida que navegas por el grid, **los dígitos se van acumulando automáticamente**. En pantalla aparece un indicador visible que muestra en todo momento la secuencia que llevas construida, permitiéndote componer números de varios dígitos sin perder el hilo.

Cuando el número está completo, **pulsas el icono de posts** (la cuadrícula) y ese gesto actúa como confirmación. La app valida el valor introducido y lanza inmediatamente el proceso de revelación.

El resultado es una interacción que, vista desde fuera, parece simplemente alguien navegando por su propio perfil de Instagram con total naturalidad.

---

## Tiempos de revelación y feedback de vibración

### Lo que ocurre en la app

En el momento en que confirmas el valor, **la app actualiza tu perfil de forma inmediata**. La vista de Performance dentro de la app refleja al instante el cambio: los posts correspondientes aparecen como visibles, con su posición y fecha originales. No hay espera desde el punto de vista de la app.

### Lo que ocurre en Instagram real

Instagram real tarda un poco más, ya que la app debe **desarchivar cada foto de forma individual** con un pequeño margen entre cada una para no generar actividad sospechosa. Entre cada letra o dígito hay una pausa de aproximadamente **2 segundos**. El tiempo total es muy reducido:

- **1 letra o dígito** — visible en Instagram en **2–3 segundos**.
- **3 letras** — aproximadamente **8–10 segundos** en total.
- **5 letras (una palabra como "MAGIC")** — alrededor de **12–15 segundos**.
- **Secuencias más largas** — escalan de forma lineal, sumando unos 2–3 segundos por cada letra adicional.

Durante este proceso la app trabaja en segundo plano y no requiere ninguna acción adicional por tu parte.

### Vibración: la señal de que todo está listo

Cuando el último post ha sido desarchivado correctamente en Instagram y la revelación está completa, **el dispositivo vibra**. Esa vibración es la confirmación de que en ese preciso momento la predicción es visible para cualquier persona que visite el perfil desde Instagram real.

No necesitas comprobar nada manualmente. La vibración es la señal definitiva: **si vibra, está listo**.

---

