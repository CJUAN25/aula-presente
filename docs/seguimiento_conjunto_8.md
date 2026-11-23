# Seguimiento del conjunto 8 — asistencia manual

## Revalidación del 22/11/2026

El propietario comprobó en TECNO el cambio de Ausente a Presente en la segunda hora y la aprobación por encuentro. Reportó que el cambio inverso se anunciaba como guardado aunque no cambiaba la marca, que el historial por horas no podía consultar la solicitud y que las vistas docentes tardaban en abrir. Punto de partida de C8: `605ac9f3b8017f7c212c99ae53df65fdff34267e`.

### Edición docente

Una prueba del diálogo con la marca previa Presente reprodujo el fallo exacto: **esperado 60, obtenido 0**. El formulario anterior reutilizaba los minutos ausentes previos y convertía 0 de vuelta en Presente. La pantalla ahora fija el tramo al abrir el diálogo, muestra identidad y horario, y calcula la ausencia con la duración del modelo o una unidad por encuentro. El guardado sin cambio conserva también las ausencias parciales. Una corrección real mantiene el evento con actor, hora, valores anterior/nuevo y motivo vacío. La fila se actualiza con la respuesta de la transacción y el estado sin cambio tiene mensaje propio.

Referencia: PDF vigente, página 49, **Registro manual**. Se reutilizó el diálogo del tema, con Presente y Ausente según el contrato C8 y sin los campos de motivo y minutos. Las pruebas dirigidas de interfaz y repositorio pasaron 39/39 tras el cambio. Commit recuperable por el título «Corrige la edición binaria de asistencia finalizada». Siguiente módulo: permisos y estado de las justificaciones por horas.

## Estado final de C8 — listo para TECNO — 17/11/2026

**Código:** `feature/conjunto-8-asistencia-manual-v2`, commit de implementación `ee031927a7189dc024d12c23d5fc0d58dcb92645`; `origin` confirmó el mismo SHA. El commit incluye solo la corrección de C8, reglas, pruebas y documentación indicada en su diff. Un commit documental posterior registra la activación verificada. La rama original se conserva sin modificar.

**Pruebas locales de cierre:** `flutter test --reporter expanded` **359/359**; `flutter analyze` sin problemas; `firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"` **109/109** con Java **21.0.13**; `flutter build apk --debug` correcto; `git diff --check` correcto. Los avisos/rechazos registrados en el log del emulador pertenecen a intentos negativos esperados; la suite terminó con 0 fallos. No hay emulador Android disponible y Codex no instaló/ejecutó la app en TECNO.

**APK que debe probarse:** `build/app/outputs/flutter-apk/app-debug.apk`, paquete `com.juanceron.aulapresente`, `versionName=1.0.1`, `versionCode=2`, **193.529.327 bytes**, SHA-256 **`6D1FB39B44B73D1F4608D7972C55391E5B2B8F6C327BB410BE7B2126259E3CC9`**. La ruta completa en este equipo es `C:\Users\juand\OneDrive\Documentos\UNIVERSIDAD\TRABAJOS U\8. SEMESTRE\MOVIL\proyecto_movil\build\app\outputs\flutter-apk\app-debug.apk`.

**Rules activas:** se confirmó por Firebase CLI que el proyecto `aula-presente-movil-juan-2026` está activo y es el único proyecto de esta cuenta; el despliegue usó `--only firestore:rules`. Antes, `cloud.firestore` apuntaba a `dde0d939-bf83-4950-9323-d37dfce705e6`; después apunta a **`projects/aula-presente-movil-juan-2026/rulesets/7f545ef7-bcf8-4fb8-ab62-63f1134a7042`**. `updateTime=2026-11-17T06:55:52.591420Z`, o **17/11/2026 01:55:52 (Colombia)**. Se descargó el ruleset, contenía un solo `firestore.rules` de 155.764 bytes, y coincidió exactamente con el archivo local tras normalizar saltos CRLF/LF. SHA-256 del archivo local en Windows: **`69BC301EDDC9B4C61E3FC790E87F607E90B99B014243904264FFD3DD188BEAAE`**. No se desplegaron índices ni configuración, no se modificaron datos reales y no hay índice nuevo requerido.

### Orden recomendado para validar en el TECNO

Usa el proyecto publicado y cuentas autorizadas existentes; evita alterar las sesiones reales que reportaron el incidente. Registra la versión de APK y usa un encuentro de ensayo para los casos destructivos.

1. Instala la APK anterior conservando datos. En un curso por horas de ensayo, cambia **Ausente → Presente** en el segundo tramo de una sesión finalizada. Verifica que el primer tramo no cambie y que la vista del estudiante refleje el resultado actualizado. Repite para una clase normal y una reprogramada si están disponibles; no vuelvas a crear sesiones.
2. Abre **Anular asistencia** y pulsa **Cancelar**: la sesión debe conservar estado, marcas y proyección. En otra sesión de ensayo ya finalizada, confirma la anulación; restaura la misma sesión y confirma que recupera las marcas/cálculo, conserva el historial y no duplica filas. Interrumpe la restauración después de un lote solo en datos de ensayo; reabre y pulsa **Continuar restauración**.
3. Desde una ausencia propia, envía una justificación breve. Comprueba que **Pendiente** no descuenta la falta ni los minutos y que el botón evita reenvío. Como docente propietario, aprueba esa solicitud; como estudiante, verifica que solo esa falta/minutos bajen y que el total de clases/horas se mantenga.
4. Para otra ausencia de ensayo, envía una solicitud y haz que el propietario la rechace. Confirma que la falta sigue contando, la decisión aparece, no se puede reenviar y se muestra «Si tienes dudas, comunícate con tu docente».
5. Repite una decisión/doble pulsación con dos clientes si puedes: debe quedar una sola solicitud y un solo descuento. Confirma que una cuenta docente ajena no puede leer ni decidir solicitudes, y que cada estudiante solo puede consultar su propia solicitud/resultado publicado.
6. Mide **Preparar lista**, **Completar lista** y **Ver asistencia** en un encuentro de ensayo, junto con conteo de estudiantes y conectividad. La lista debe aparecer cuando los datos requeridos estén listos; historial/publicación secundarios pueden seguir cargando. Comprueba que demora/fallo muestre progreso o error y que matrícula efectiva y publicación sigan verificándose.

La hora y hash anteriores demuestran el estado de Firebase y la APK local al compilar. No prueban el comportamiento de esa APK con FlutterFire/red real ni sustituyen esta validación manual del TECNO.

## Ampliación y corrección de C8 — 17/11/2026 — APK 1.0.1+2

**Punto de partida:** rama local `feature/conjunto-8-asistencia-manual-v2`, HEAD `46a8893d518c87b6337d73b194ac4aa801f568c7`. Se conservaron los cinco archivos con cambios/alta local de la revisión visual previa. El propietario confirmó en el TECNO que puede registrar, finalizar y consultar asistencia. Reportó rechazo al corregir **Ausente → Presente** después de finalizar, en la clase normal del 16/11 10:00–12:00 y la reprogramada 06:00–08:00. Esas pruebas físicas son del propietario. Codex no operó el teléfono.

### Parche y corrección finalizada

`git apply --check C:/Users/juand/Downloads/aula-presente-c8-correccion-finalizada.patch` pasó sin conflictos; después se aplicó. Se mantuvieron sus **dos regresiones** de segunda hora normal/reprogramada, ajustando la fecha del caso normal al 16/11. El parche evita revalidar identidad/esquema completo en una corrección cuando el allowlist ya los mantiene inmutables: revalida resultado y segmentos, y conserva la transacción de fila, proyección, evento y versión de sesión. Se rechazaron alteraciones de fecha y unidades inválidas. Esto corrige otra ruta de evaluación costosa de Rules, distinta del cierre ya publicado anteriormente.

Una prueba de widgets adicional ejecuta las pantallas docente y estudiante con **FirestoreAttendanceRepository real y un almacén sintético**: corrige 11:00–12:00 de ausente a presente, sin motivo, conserva 10:00–11:00 presente y 120 minutos totales, y el estudiante ve 0 % de faltas. Las dos regresiones JS ejecutan transacciones equivalentes contra Firestore Emulator; ninguna de estas pruebas constituye FlutterFire ejecutado en Android.

### Motivos opcionales, anulación y restauración

- Corrección, anulación, reprogramación, cancelación y registro posterior aceptan un motivo vacío (máximo 500 caracteres si se escribe). El diálogo conserva **Cancelar**; cancelar devuelve `null`, confirmar sin texto devuelve `''`. No se inventa un motivo ni se elimina un motivo histórico. Un motivo tardío ya almacenado no se reemplaza.
- Los eventos privados conservan actor, hora del servidor y valores anterior/nuevo. El historial docente muestra el cambio, fecha en Colombia y los motivos existentes. Las escrituras de calendario del cliente añaden `attendance_calendar/{occurrenceId}/events/{version}` con copia anterior/nueva y auditoría, en la misma transacción; estas entradas son inmutables y solo las lee el propietario.
- Solo una anulación de una sesión que **ya había sido finalizada** ofrece **Restaurar asistencia**. Conserva las marcas privadas, la identidad de sesión, su finalización original, los motivos/eventos históricos y `publishedAt` de cada fila.
- La restauración pasa `voided → restoring → finalized`, con un único evento persistido `restore`. Reconstruye las proyecciones desde la nómina/tramos, en lotes de hasta diez, verifica todos los resultados y finalmente cambia el estado. Si se interrumpe, **Continuar restauración** reutiliza el evento y omite filas ya correctas. No recrea sesiones ni habilita marcas durante la restauración.
- Se probaron interrupciones antes de la primera fila y después del primer lote de **10/12** filas; el reintento completó doce resultados con un solo evento de restauración y sin duplicar unidades. Una restauración completada puede recibir después una corrección normal; la metadata de anulación queda como historia.
- Durante `voiding` y `restoring`, las proyecciones de estudiantes diferentes convergen por fila. Una consulta puede conservar la última fila publicada o mostrar una fila ya restaurada mientras termina el resto; un `get` directo sigue exigiendo padre `finalized/voided`. No se promete atomicidad entre estudiantes distintos.

### Solicitud del estudiante y decisión docente

Esta ampliación fue solicitada expresamente el 17/11; sustituye la restricción anterior de C8 que solo contemplaba justificaciones ya revisadas por el docente. No recibe adjuntos.

Ruta privada: **`courses/{courseId}/attendance_requests/{sessionId}|{rosterEntryId}|{segmentId o meeting}`**. El documento tiene `sessionId`, `rosterEntryId`, `studentUid`, `segmentId`, `text`, `status`, `createdAt`, `decidedAt`, `decidedBy`, `eventId`. Estados: `pending → approved/rejected`. Texto obligatorio de 1–500 caracteres. La identidad y UID se derivan de Auth/matrícula, no de formularios.

| Acción | Resultado y protección |
| --- | --- |
| Estudiante: **Consultar asistencia → ausencia propia → Solicitar justificación → Enviar solicitud** | Solo correo/perfil verificados y matrícula canónica activa; ausencia publicada de sesión finalizada. Una solicitud por encuentro o tramo. Dos pulsaciones/transacciones usan el mismo ID. No se solicita sobre una hora presente o ya cubierta. |
| Solicitud pendiente | Se muestra pendiente y la falta **sigue contando**. No cambia ni el total ni la cobertura del resultado; la solicitud se carga aparte de la lista. |
| Docente propietario: leer texto y **Aprobar** | Transacción de cinco documentos: solicitud, fila, proyección, evento y sesión. Cubre una unidad por encuentro o los minutos ausentes actuales del tramo; mantiene ausencia original y denominador. No toca el otro tramo. |
| Docente propietario: **Rechazar** | Misma auditoría/transacción; cobertura cero, falta sigue contando. Si la marca ya fue corregida a presente, puede rechazar la solicitud pendiente sin volver a crear una ausencia. |
| Decisión repetida | La misma decisión vuelve como operación ya aplicada; no añade evento ni descuento. Una decisión contraria sobre una solicitud decidida se rechaza. Rules mantiene la decisión inmutable. |
| Estudiante: resultado | Aprobada o rechazada, envío deshabilitado y **«Si tienes dudas, comunícate con tu docente»**. Actualizar la consulta vuelve a cargar resultado y decisión. |
| Privacidad | Estudiante puede obtener únicamente sus IDs de solicitud, no enumerar solicitudes, consultar nómina/eventos ni escribir resultados/decisiones. Docente ajeno, cuenta sin verificar o matrícula retirada se rechazan. Solo el propietario lista las solicitudes de la sesión. |

Se conservan la revisión docente manual y las correcciones auditadas previas. Una corrección posterior puede cambiar una marca y su cobertura con un nuevo evento; no crea otra solicitud ni altera el texto/decisión histórica.

### Medición previa y carga progresiva

Muestras del repositorio con 12 estudiantes sintéticos y 5 ms artificiales por lectura, antes de cambiar la carga de pantalla:

| Operación | Antes (ms) | Después (ms) | Interpretación |
| --- | ---: | ---: | --- |
| Preparar lista | 238 | 237 | Sin nueva optimización ni reducción de validaciones. |
| Completar lista | 203 | 193 | Variación local; no se atribuye una mejora nueva. |
| Leer lista/tramos | 22 | 21 | La lectura necesaria se conserva. |
| Comprobar publicación finalizada | 79 | 80 | La comprobación sigue completa; ahora es secundaria para mostrar la lista. |

Antes, la pantalla esperaba primero publicación y después el historial junto con la lista. Ahora obtiene sesión, nómina completa y tramos, muestra la lista y carga historial, solicitudes y comprobación de publicación aparte. Mide `[C8] abrir pantalla / leer sesión`, `/ leer datos necesarios para la lista`, `/ lista disponible`, `/ historial secundario` y `/ comprobar publicación secundaria`. Mientras comprueba publicación no anuncia publicación completa ni habilita correcciones sobre un estado sin confirmar. Cada tarea secundaria conserva su error visible y su guardia de sesión/época; el historial ya no bloquea la lista. Un test retiene historial/publicación con `Completer`, avanza 500 ms del reloj de widgets y comprueba que la lista está disponible antes de liberarlos.

Los snapshots, eventos de matrícula, comprobaciones por fecha efectiva y barreras de versión no se redujeron. Preparar/completar mantiene 6 snapshots, 24 historiales y 72 vínculos en el ensayo. Los tiempos son muestras locales, no mediciones ni promesas para el TECNO/Firebase real. Logs: `build/c8-new-latency-before.log`, `build/c8-new-latency-after.log`.

### Verificación final de esta ampliación

| Comprobación | Resultado |
| --- | --- |
| Suite Flutter completa | **359/359**, incluidas pantallas de ambos roles, doble envío, resultados aprobados/rechazados, corrección sin motivo, Cancelar anulación, restauración reanudable y prueba de pantalla con repositorio real sintético. |
| Flutter dirigido C8/acceso estudiante | **80/80**; UI de horas **18/18**. Incluye tamaños 320/390/430 y texto ampliado, más los ajustes visuales locales previos. |
| Firestore Emulator completo | **109/109**; dos regresiones del parche, solicitudes por encuentro/horas, aprobación/rechazo, reintentos, roles/matrícula y restauración/auditoría. Cero diagnósticos de límite de 1.000 expresiones en la ejecución final. |
| Análisis, JS y diff | `flutter analyze` sin problemas, `node --check` y `git diff --check` aprobados. |
| APK | Debug **1.0.1+2**, compilada sin instalar. El aviso futuro de Built-in Kotlin no impidió compilar. |

Evidencia local ignorada por Git: `build/c8-new-full-flutter.log`, `build/c8-new-flutter.log`, `build/c8-new-rules.log`, `build/c8-new-analyze.log`, `build/c8-new-apk.log`, `build/c8-new-integration-widget.log`, `build/c8-new-visual.log`. No se crearon cuentas reales ni se enviaron correos. No se desplegó Firebase ni se ejecutó el TECNO. Los cambios permanecen en la rama local v2, sin commit/push nuevo.

### Publicación y prueba en el TECNO para 1.0.1+2

**Primero publicar el único `firestore.rules` completo de esta revisión y después instalar la APK 1.0.1+2.** Las reglas publicadas que ya permitieron el cierre no bastan para solicitudes/restauración y la nueva corrección. No se añadieron índices ni otra configuración de Firebase; la consulta docente de solicitudes usa igualdad por `sessionId` y orden por ID, con paginación de 100. No requiere Cloud Functions ni Storage.

APK: `build/app/outputs/flutter-apk/app-debug.apk`, **193.529.327 bytes**, SHA-256 **`6D1FB39B44B73D1F4608D7972C55391E5B2B8F6C327BB410BE7B2126259E3CC9`**. Se comprobó en el APK `com.juanceron.aulapresente`, `versionName=1.0.1`, `versionCode=2`. SHA-256 del único `firestore.rules` local: **`69BC301EDDC9B4C61E3FC790E87F607E90B99B014243904264FFD3DD188BEAAE`**. Estas huellas sustituyen las anteriores para la próxima prueba. Repetir construcción: `flutter build apk --debug`. Para reglas, el propietario publica en `aula-presente-movil-juan-2026`, base `(default)`, sin reemplazar el archivo por un fragmento.

1. **Corregir:** instalar la nueva APK conservando datos. Abrir la clase normal del 16/11 10:00–12:00 y la reprogramada original 05/11 → 16/11 06:00–08:00. Elegir el segundo tramo, **Corregir registro → Presente → Guardar corrección**, con motivo vacío. Verificar primera hora intacta, total 120 min y consulta propia del estudiante actualizada. No recrear sesiones.
2. **Motivos y Cancelar:** en un encuentro de ensayo, abrir **Anular asistencia → Cancelar** y comprobar que nada cambia. Repetir confirmando vacío. Probar también reprogramar, cancelar clase y registrar posteriormente sin motivo; los motivos históricos no deben desaparecer del historial privado.
3. **Restaurar:** anular un ensayo que estuviera finalizado, comprobar que deja de sumar unidades y pulsar **Restaurar asistencia**. Verificar mismas marcas, mismo encuentro, mismo resultado/cálculo previo. Para interrupción usar exclusivamente el ensayo: recuperar conexión, actualizar y **Continuar restauración**. Reabrir al terminar no debe sumar otra vez ni duplicar evento/resultado. No usar la clase real atascada para inducir cortes.
4. **Solicitar:** con estudiante verificado y matrícula activa, abrir una ausencia propia publicada y enviar texto breve. Por horas, elegir una hora ausente, no una presente. Pulsar dos veces no debe duplicar. Mientras esté pendiente, la falta sigue contando. Otra cuenta no debe ver la solicitud ni su resultado.
5. **Decidir:** con el docente dueño, abrir esa sesión y localizar **Solicitudes de justificación**. Leer texto, **Aprobar** y actualizar como estudiante. Solo se descuenta la unidad o los minutos ausentes de esa hora; el total se mantiene. Probar **Rechazar** con otra ausencia: no descuenta. En ambos casos se bloquea reenviar y aparece el mensaje de contacto. Repetir apertura no vuelve a descontar.
6. **Demoras:** comprobar que lista/tramos aparecen mientras se carga historial/publicación, que el estado de comprobación no simula éxito y que un fallo ofrece reintento. En debug, recoger solo etiquetas/duraciones `[C8]`, sin datos personales. Registrar versión, hora, acción, cantidad de estudiantes y segundos observados.

La publicación de las nuevas reglas, el APK realmente instalado y todos estos resultados físicos siguen pendientes del propietario. Los apartados siguientes conservan antecedentes y no sustituyen esta guía de la versión 1.0.1+2.

## Revisión visual y de recorrido — 16/11/2026

Punto de partida: `feature/conjunto-8-asistencia-manual-v2`, commit `46a8893d518c87b6337d73b194ac4aa801f568c7`, árbol limpio. Esta revisión añade ajustes locales de presentación y pruebas; conserva el arreglo del cierre publicado en ese commit. No modifica el repositorio de datos, el cálculo, la matrícula, `firestore.rules` ni índices.

### Referencia que se pudo abrir

Se intentó abrir `https://www.figma.com/design/XP9LIZClkFzVNf17jUXjGU/NUEVA-CORRECCION?node-id=25-57`: el conector requiere reautenticación y el lector web no pudo abrirlo. La ruta del PDF en la solicitud era un marcador; se localizó **`../FIGMA/NUEVA CORRECCION.pdf`** (158 páginas, productor Figma, páginas de 390 × 844). SHA-256: `5F9AD8A69E6AD6EA958D0370EAAEE2977E9DA8AAFD6562C208D75FD2A0D03FD3`. Se renderizaron y revisaron visualmente solo las páginas **42, 45, 46, 47, 48, 55, 56 y 144**, relacionadas con el recorrido docente. El PDF no conserva nombres/IDs de marcos ni permite confirmar la correspondencia exacta con la página online; por eso las referencias siguientes son **páginas del PDF**, sin atribuirles IDs de Figma.

No se localizó una pantalla específica titulada **Registrar asistencia por horas** en la exportación. Las páginas 55/56 son la referencia comprobada de la lista; los tramos y sus estados se adaptaron al contrato C8. No se declara que esa pantalla falte en el archivo online, al que no hubo acceso.

### Comparación del resultado final

| Pantalla o flujo | Referencia original (marco o página) | Cómo quedó en la app | Motivo de la diferencia |
| --- | --- | --- | --- |
| Elegir clase y continuar un registro | PDF p. 42, **Calendario del curso**; p. 45, **Preparar asistencia** | Se conserva **Curso → Asistencia → Gestionar → clase**. La tarjeta identifica fecha efectiva/original y ofrece la acción del estado persistido. Se verificó **Continuar cierre → misma sesión**. | El calendario previsto no crea asistencia automáticamente. Preparar, abrir, continuar y consultar responden al estado real y a la hora efectiva; no se incorporan métodos Bluetooth/QR o plazos automáticos del prototipo. |
| Lista docente abierta | PDF p. 56, **Estudiantes**, y p. 46, **Sesión en curso** | La lista tiene búsqueda, contadores de Presentes/Ausentes/Pendientes y tarjetas con nombre, estado y hora. Los botones Presente/Ausente actúan dentro de la fila y resaltan la marca seleccionada. | La toma manual es el flujo C8; permite registrar sin abrir un formulario por cada persona. Se conservan Manrope, fondo oscuro, acento menta, tarjetas redondeadas e iconos del tema existente. No se añade el gráfico de Bluetooth/tardanzas. |
| Buscar estudiante | PDF pp. 55/56, **Buscar estudiante · Nombre o código** | Campo **Buscar estudiante · Nombre o correo**, filtro local sin consultas nuevas, estado **Sin coincidencias** y conservación del texto después de reintentar. Los contadores siguen representando la lista completa del tramo. | C8 guarda nombre e identidad académica por correo en la nómina, pero no código. No se añade otra lectura de perfiles/matrículas ni se promete buscar un campo ausente. |
| Registrar asistencia por horas | Sin pantalla específica localizada; adaptación de la lista de pp. 55/56 | Encabezado compacto **Asistencia por horas**, modalidad, fecha efectiva, fecha original si se reprogramó, selector **Tramo de la clase**, minutos y resumen del tramo. Marcar afecta solo la hora elegida. Las acciones masivas confirman toda la lista del tramo, incluso con búsqueda activa. | El contrato C8 cuenta minutos por tramos; no hay referencia específica verificable de ese selector. Se reutilizan `CoursePanel`, campos y botones actuales. Se corrigió el desbordamiento del selector con texto ampliado a 320 px. |
| Revisar y corregir una sesión cerrada | PDF p. 55, **Estudiantes · registro cerrado**; p. 48, **Registro manual** | El selector de tramo sigue visible después de finalizar. **Corregir registro** abre el diálogo del estudiante y tramo, con marca, minutos acotados y motivo obligatorio. Se comprobó cambiar la segunda hora a 30 min sin tocar la primera. | Antes el selector solo existía en `inProgress` y la segunda hora no era accesible para revisión. Se conserva el diálogo auditado y las marcas Presente/Ausente del contrato, en lugar de Tarde/reapertura del prototipo. |
| Guardar y finalizar | PDF p. 46, **Cerrar registro**, y p. 47, **¿Terminamos el registro?** | Primero se muestran búsqueda y filas; después **Guardar y continuar después** y **Finalizar registro**. Las marcas se guardan al seleccionarlas. La finalización conserva la confirmación explícita de pendientes y la opción de volver a completar. | Evita ofrecer el cierre antes de recorrer la lista. Se mantiene la confirmación existente con `AlertDialog` y unidades de C8; no se convierte una marca pendiente en ausencia sin confirmación. |
| Carga prolongada y error | PDF p. 144, **Conexión interrumpida**, como referencia general; sin variante específica de lista C8 | `AttendanceWaitStatus` al inicio, aviso de demora desde 8 s y `AttendanceErrorCard` persistente con Reintentar. Se ocultan las filas/acciones hasta completar la carga; un fallo al marcar sigue visible tras recargar. | Se reutilizan los componentes actuales. No se muestra éxito ni se habilitan escrituras sobre datos incompletos. La recarga consulta el estado persistido antes del reintento. |
| Cierre reanudable | Sin referencia específica localizada; p. 47 solo muestra confirmación de cierre | Tarjeta **Cierre en curso → Continuar finalización**, sin controles de marcado. Se conserva la sesión y se pueden revisar sus dos tramos. | El cierre puede interrumpirse; la recuperación conserva IDs, marcas y la corrección funcional previa. No se crea otra sesión ni se ofrece una reapertura que cambie su estado. |
| Publicación pendiente y finalización comprobada | Sin referencia específica localizada en la exportación | **Publicación pendiente → Reintentar publicación** o **Registro finalizado → Verificar publicación** aparecen antes de la lista. Se distinguen sesión finalizada y resultado publicado; un aviso nuevo sustituye el anterior para que no persista “pendiente” tras un reintento exitoso. | La publicación converge por estudiante y debe poder reanudarse. Se reutiliza `CourseStateCard`; no se anuncia publicación completa si quedan filas sin confirmar. |
| Navegación y distribución | PDF pp. 55/56 con barra Inicio/Cursos/Perfil | Se mantiene el retorno al calendario y el recorrido dentro del curso. Las filas, búsqueda y acciones pueden desplazarse; el estado de cierre/publicación queda al inicio. | La pantalla está anidada en el curso y conserva su navegación existente. No se añade una barra global que reinicie el contexto ni acciones de matrícula fuera de esta revisión. No se declara fidelidad píxel a píxel. |

### Verificación local realizada

Se ejecutaron **las pantallas reales de producción** `TeacherAttendanceScreen` y `TeacherAttendanceSessionScreen` en `flutter test`, con repositorio controlado, identidades ficticias y dos tramos. Se interactuó con navegación, búsqueda, marcas, corrección, error/reintento y cierre/publicación, y se inspeccionaron PNG del resultado. Esto es ejecución y render de widgets; **no es una ejecución completa del APK con FlutterFire en Android**. `flutter emulators` no encontró emuladores Android disponibles. No se operó el TECNO ni se contactó Firebase real.

- `flutter analyze`: sin problemas.
- Pruebas Flutter dirigidas de asistencia y acceso estudiantil: **67/67**, incluidas **10** del nuevo `attendance_hours_flow_test.dart`. Incluyen 320/390/430 px con texto 1.6, marca solo en la segunda hora, corrección con motivo sin alterar la primera, búsqueda sin lecturas adicionales, carga lenta, error persistente y misma sesión al reanudar. El test previo de navegación se actualizó al título de horas.
- Firestore Emulator: **2/2** regresiones `C8 closing rescheduled minutes` (2/12 estudiantes), sin diagnósticos de límite de 1.000 expresiones. Se conservan permisos, marcas, IDs y publicación idempotente. No se repitió la suite completa de 101 reglas en esta revisión visual.
- `flutter build apk --debug`: aprobado. Conserva el aviso de compatibilidad futura de Built-in Kotlin.
- `git diff --check`: aprobado.

Evidencia local ignorada por Git: `build/c8-visual/reference-*.png`, `after-*.png`, `visual-tests.log`, `flutter-tests.log`, `closing-rules.log`, `analyze.log` y `apk.log`. Las capturas muestran pantallas desplazadas cuando el paso requiere alcanzar una fila o una acción. Para repetir las capturas sintéticas:

```powershell
$env:C8_VISUAL_CAPTURE = 'after'
flutter test test/features/attendance/presentation/attendance_hours_flow_test.dart --reporter expanded
Remove-Item Env:C8_VISUAL_CAPTURE
flutter test test/features/attendance test/features/courses/presentation/student_course_access_test.dart --reporter expanded
flutter analyze
```

### APK y comprobaciones pendientes en el TECNO

APK recompilada: `build/app/outputs/flutter-apk/app-debug.apk`, **218.912.577 bytes**, SHA-256 **`11B193FC617BF5443A2E70CD64DFE744750FDF13895B18A42604AFD2603B7B71`**. Esta huella sustituye la APK anterior para probar la interfaz revisada. Las reglas conservan SHA-256 `F8C9C9E7557DA55739F5884582DA342F16B7C9D200E5538657157ACF877DF6E5`: no hay una nueva versión de reglas por estos ajustes visuales; la publicación de las reglas del arreglo anterior sigue por confirmar con el propietario.

1. Instalar esta APK conservando datos y sesiones. Confirmar que están publicadas las reglas del arreglo del cierre antes de intentar la recuperación real.
2. **Mis cursos → Lógica → Asistencia → Gestionar**, elegir la clase original 05/11 reprogramada al 16/11 06:00–08:00. **Continuar cierre → Continuar finalización** debe conservar marcas, identidad y un resultado por estudiante. Reintentar publicación si se indica pendiente.
3. En **Ver asistencia**, cambiar entre 06:00–07:00 y 07:00–08:00, comprobar ambas marcas originales y usar búsqueda. Para probar marcas/correcciones, usar un encuentro de ensayo; verificar que solo cambie el tramo elegido, con motivo si ya está finalizado.
4. Comprobar teclado, desplazamiento, búsqueda sin coincidencias, texto ampliado y botones de guardar/finalizar después de la lista. En un ensayo con conectividad interrumpida, comprobar espera/error y reintento sin duplicados. No inducir cortes durante la recuperación de la sesión real atascada.
5. Comprobar la consulta propia del estudiante ya publicado. Las pruebas locales no validan la APK instalada, las reglas realmente publicadas, los tiempos de red ni la representación en el TECNO.

Los apartados siguientes conservan los antecedentes y sus verificaciones originales.

## Incidente de cierre — punto de partida del 16/11/2026

Verificados antes de editar: rama `feature/conjunto-8-asistencia-manual`, HEAD `bed4ac83fd1d82b53080df0af1d2dc467208d4e4`, remoto `https://github.com/CJUAN25/aula-presente.git` y `git status --short` vacío.

El propietario publicó manualmente las reglas de su VS Code en `aula-presente-movil-juan-2026`, base `(default)`. La versión exacta publicada y la APK instalada siguen por confirmar. En Lógica reprogramada al **16/11/2026 06:00–08:00**, **Por horas**, pudo entrar y alcanzar **Finalizando**, pero **Continuar finalización** devuelve `permission-denied`. También hay esperas largas en **Preparar lista**, **Completar lista** y **Ver lista**. Codex no ejecutó esos recorridos ni inspeccionó datos reales. No se presupone que sea el mismo fallo de preparación documentado abajo.

Esta revisión reprodujo y corrigió el cierre y midió las etapas antes de optimizar, como se detalla a continuación. La publicación y la prueba en TECNO quedan a cargo del propietario. Los apartados posteriores a esta revisión conservan resultados históricos.

### Causa comprobada del cierre

La prueba nueva `C8 closing rescheduled minutes` parte de una sesión **ya `closing/ready`**, reprogramada del 05/11 al **16/11/2026 06:00–08:00**, con dos tramos de 60 minutos y marcas existentes. Usa exclusivamente identidades sintéticas y Firestore Emulator con proyecto `demo-aula-presente-firestore-rules-tests`.

Con las reglas del HEAD inicial, la primera llamada equivalente a `_stageRecords` falla con `permission-denied`: el `create` de **`courses/course/attendance_records/course|block|2026-11-05|student@example.test`**, junto con el incremento de versión de **`courses/course/attendance_sessions/course|block|2026-11-05`**, supera **1.000 expresiones**. El log señala `validAttendanceRecordSegmentAt` (línea 2768 del archivo inicial) y el `allow create` de `attendance_records` (3363). No era un rechazo de la fecha reprogramada ni faltaba permiso docente en esa reproducción. El padre queda en `closing`, sin publicar resultados. Evidencia local ignorada por Git: `build/c8-closing-before.log`.

El validador de **proyecciones** seguía evaluando 24 posiciones aunque solo hubiera dos tramos; era distinto del validador de **nómina** corregido previamente. La publicación `staged → published` y el `get` propio del estudiante también necesitaban margen de evaluación. El ajuste conserva un único `firestore.rules`:

- Corta la cola al tamaño real de segmentos y valida directamente cada segmento presente.
- Reutiliza valores de unidades/horas y evita listas de claves duplicadas. Todos los campos obligatorios se acceden y validan; una clave faltante deniega, y la lista exacta de claves permitidas se conserva.
- Evita ocho comparaciones de identidad/horario ya garantizadas por `diff().affectedKeys().hasOnly(...)` en **cada** rama permitida. Publicar solo cambia visibilidad, fecha de publicación y actualización.
- Evalúa primero las condiciones que rechazan borradores, identidades ajenas o transiciones inválidas. El chequeo docente descarta primero perfiles sin `teacher`, conservando la misma validación completa de perfil/correo para quien sí tiene el rol. Esto evita que el `get` estudiantil gaste el presupuesto en una rama docente que no le corresponde.

La regresión cubre **2 y 12 estudiantes**, lotes de hasta 10, interrupción después de preparar la primera proyección, reintento sin incrementar versión cuando no faltan filas, cierre del mismo padre y publicación repetida sin duplicados ni cambio de `publishedAt`. Compara la nómina y las marcas antes/después. Un control separado en `inProgress` prueba las dos marcas del propietario verificado; el fixture de recuperación permanece ya en `closing`. Estudiante y docente ajeno no pueden registrar. El estudiante consulta y obtiene solo su fila publicada; no lee otra identidad, nómina, eventos o borradores ni escribe resultados. También se rechazan claves faltantes/extra, marcas inválidas, exceso de unidades, horario/identidad alterados y creación sin versión atómica del padre.

La prueba Dart `resumes the same closing rescheduled hours session after a denied stage` ejecuta el repositorio real sobre un adaptador controlado: fuerza el rechazo al preparar resultados, verifica el diagnóstico de etapa, reabre el repositorio, finaliza y conserva las dos marcas y un resultado por persona. No equivale a ejecutar FlutterFire en Android contra el emulador. La causa está probada localmente; su correspondencia exacta con los documentos y reglas publicados en Firebase real sigue pendiente.

### Medición de esperas y cambios del cliente

Se añadió `AttendanceOperationTrace`: cronometra etapas con `Stopwatch`, emite `[C8] operación / etapa: N ms` solo en debug y admite un observador en pruebas. Las etiquetas no contienen IDs, nombres, correos, marcas ni motivos. Se registran también las etapas que fallan. Un rechazo al cerrar identifica ahora, por ejemplo, **preparar resultados privados (permission-denied)**.

Medición reproducible del **repositorio Dart**, con 12 estudiantes sintéticos, dos tramos y **5 ms de latencia artificial por lectura**, antes/después en esta sesión:

| Acción/etapa | Antes (ms) | Después (ms) |
| --- | ---: | ---: |
| Preparar: cuenta / borrador / modalidad | 18 / 7 / 9 | 11 / 7 / 7 |
| Preparar: matrículas e historial | 268 | 65 |
| Preparar: transacción inicial | 56 | 34 |
| Preparar: tramos / nómina | 23 / 110 | 16 / 45 |
| Preparar: revalidación de fuentes / confirmar lista | 84 / 37 | 21 / 33 |
| **Preparar total** | **622** | **247** |
| Completar: matrículas e historial | 246 | 54 |
| Completar: nómina / revalidación de fuentes | 101 / 80 | 35 / 20 |
| **Completar total** | **520** | **199** |
| **Ver lista y tramos** | **43** | **23** |
| Comprobar publicación al abrir una finalizada (12 filas publicadas, por encuentro) | **300** | **102** |

Son muestras locales, no promedios, garantías de tiempo ni mediciones de Internet/Firebase real/TECNO. Las pequeñas etapas varían con el equipo; las diferencias grandes se explican por las esperas seriales eliminadas. Logs: `build/c8-latency-before.log`, `build/c8-latency-after.log`, `build/c8-finalized-latency-before.log`, `build/c8-finalized-latency-after.log` (ignorados por Git).

Los historiales y vínculos de personas distintas ahora se leen en ventanas de **hasta seis**, con todas sus páginas en orden. Las lecturas independientes dentro de una transacción se lanzan juntas, siempre antes de escribir; los chunks de escritura siguen ordenados y limitados a 10. Las verificaciones de resultados se hacen en ventanas de seis. La pantalla consulta nómina/tramos/eventos en paralelo, omite tramos en modo por encuentro y solicita hasta 100 filas por página para evitar repetir cuenta/sesión cada 25 personas.

**Se conserva** la resolución por fecha efectiva, las tres comprobaciones del snapshot por preparación, los chequeos posteriores de vínculos, la revisión completa de marcas/resultados y las barreras de versión. En el ensayo de preparar+completar permanecen **6 snapshots, 24 consultas de historial y 72 lecturas de vínculos**; no se presenta como una reducción de lecturas en ese caso. Se reutiliza un historial de autorización exacta si ya fue leído en la misma operación, sin caché entre reintentos. Un error de historial sigue bloqueando `ready`; la prueba comprueba ese bloqueo y la concurrencia máxima. No se abren consultas estudiantiles adicionales ni cambia el índice.

Preparar/Completar y la carga/guardado del detalle muestran progreso; después de ocho segundos indican que la operación tarda y cuentan el tiempo. El avance confirmado se conserva y el error al abrir queda visible en pantalla, además del diagnóstico. No se abandona una escritura por un timeout de interfaz ni se anuncia éxito por una lectura parcial.

### Verificación de esta revisión

Resultados nuevos de esta sesión:

| Comprobación | Resultado y alcance |
| --- | --- |
| `flutter analyze` | Sin problemas. |
| Pruebas Flutter dirigidas | **57/57**, incluyendo recuperación de cierre por horas, fallo de historial concurrente, demora/error visible y presentación a 320/390/430 px con texto ampliado. No se repitió toda la suite Flutter. |
| Suite completa Firestore Emulator | **101/101**; incluye los dos casos nuevos de cierre de 2/12 estudiantes, control de marcas del dueño y permisos previos. **0** diagnósticos `maximum of 1000 expressions` en `firestore-debug.log` de esta ejecución final. Los `permission-denied` de casos negativos son esperados. |
| JavaScript y diff | `node --check` y `git diff --check` aprobados; Git avisa de normalización LF/CRLF sin errores de whitespace. |
| `flutter build apk --debug` | Aprobado; APK local recompilada, sin instalar. Gradle conserva un aviso de compatibilidad futura de plugins con Built-in Kotlin; no impidió la compilación. |

La suite usa el SDK JS contra el emulador y transacciones equivalentes a Dart. Las pruebas Dart ejecutan el repositorio con adaptadores controlados; las mediciones con 5 ms artificiales no usan red ni constituyen FlutterFire en Android contra el emulador. No se contactó Firebase real ni se operó el TECNO. Evidencia local: `build/c8-rules-full.log`, `build/c8-flutter-tests.log`, `build/c8-analyze.log` y `build/c8-apk.log`.

Comandos desde la raíz:

```powershell
flutter analyze
flutter test test/features/attendance test/features/courses/presentation/student_course_access_test.dart --reporter expanded
flutter test test/features/attendance/data/firestore_attendance_repository_test.dart --plain-name 'C8 latency profile' --reporter expanded
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"
# Solo la regresión del cierre:
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "node --test --test-concurrency=1 --test-name-pattern=C8.closing.rescheduled tools/firestore_rules_tests/firestore_rules.test.js"
node --check tools/firestore_rules_tests/firestore_rules.test.js
git diff --check
flutter build apk --debug
```

### APK, reglas y repetición exacta en el TECNO

**Hace falta publicar las reglas nuevas e instalar la APK recompilada**, porque cambiaron tanto Rules como el cliente. Esta sesión ya compiló `build/app/outputs/flutter-apk/app-debug.apk`: **218.911.055 bytes**, SHA-256 **`2605B40076B58E6BFA7BD090BC76A8204168CA9A1626C61BEC2ABA5C98F4AC62`**. El único `firestore.rules` local tiene SHA-256 **`F8C9C9E7557DA55739F5884582DA342F16B7C9D200E5538657157ACF877DF6E5`**. Son huellas de los archivos locales de esta revisión, no de los artefactos anteriores usados por el propietario. `HEAD` sigue siendo la base inicial: estos cambios están en el árbol de trabajo, sin commit/push.

1. Como propietario, publica **solo** este `firestore.rules` revisado en `aula-presente-movil-juan-2026`, base `(default)`. Registra la hora/versión de la publicación y confirma que corresponde al archivo completo de esta revisión. No se modificaron índices; conserva `attendance_records` habilitado.
2. Instala la APK indicada sobre la app existente y registra su huella/versión. No borres datos, anules ni recrees sesiones para esta recuperación.
3. Con el docente verificado dueño de Lógica: **Mis cursos → Lógica → Asistencia → Gestionar**. Selecciona la ocurrencia original **05/11**, reprogramada al **16/11/2026 06:00–08:00**, **Por horas**. No elijas la otra clase del 16/11.
4. En la tarjeta **Finalizando**, pulsa **Continuar cierre** y, dentro, **Continuar finalización**. Comprueba que las marcas de 06:00–07:00 y 07:00–08:00 se conservan y que termina en **Finalizada**. Si había pendientes, revisa la confirmación explícita antes de convertirlas en ausencias. Si la publicación queda pendiente, reinténtala en la misma sesión.
5. Sal y vuelve a **Ver asistencia**: debe seguir siendo el mismo encuentro, con las mismas marcas y una sola proyección por estudiante. Comprueba por separado que la clase normal del 16/11 sigue distinta.
6. Con una cuenta estudiante ya verificada y con matrícula activa, abre **Mis materias → Lógica → Consultar asistencia**. Debe aparecer solo su resultado publicado y coincidir con sus marcas. En el caso sintético ausente/presente serían 60 minutos ausentes de 120; en el curso real compara con las marcas que realmente tenía. Otra cuenta solo ve su propio resultado, si lo tiene.
7. Mide desde cada pulsación hasta el resultado: **Preparar lista**, **Completar lista** y **Ver asistencia/lista**; usa un encuentro de ensayo para preparación, sin alterar la nómina cerrada de Lógica. Anota tamaño de lista, modalidad, acción, segundos, resultado y versión de APK/reglas. El mensaje de demora debe mantenerse hasta terminar o mostrar el error. Si falla, comparte etapa y código de **Diagnóstico**, sin datos personales; los logs `[C8]` permiten separar las etapas en la APK debug.

La publicación y todos estos pasos manuales son del propietario y continúan pendientes. No se ejecutó `firebase deploy`, no se crearon cuentas reales ni se enviaron correos.

## Antecedente de entrega — 16 de noviembre de 2026

La rama `feature/conjunto-8-asistencia-manual`, basada en el cierre C7 `55b9336bb39ea157345a2f659e4876bfbf5f938f`, contiene el módulo de asistencia, la integración con cursos y matrícula, las reglas de C8, las pruebas y esta documentación. Está preparada para revisión de código. La corrección de reintento pasó las verificaciones locales, pero falta probar esta APK concreta en el TECNO; por eso no se declara terminada la validación real del conjunto.

El repo es `CJUAN25/aula-presente`. Para identificar el commit de esta entrega usa `git rev-parse HEAD` estando en la rama indicada. El cierre se comparte como rama de trabajo y no modifica `main` ni la release anterior.

## Hallazgos y correcciones

### Reintentar una nómina incompleta

El 16/11 el propietario reportó `permission-denied` al reintentar las sesiones del 12/11 → 15/11 10:00–12:00, 05/11 → 16/11 06:00–08:00 y una clase normal del 16/11 10:00–12:00. La etiqueta “Preparada / Reintentar preparación” indicaba un estado incompleto, pero no demostraba que las tres sesiones tuvieran una misma causa. No se inspeccionaron ni repararon sus documentos reales.

Flutter conserva el ID estable de la ocurrencia y revalida la matrícula a la fecha efectiva. Al recuperar una sesión `preparing/building`, reconcilia filas que faltan y refresca la identidad de filas existentes solo si aún no tienen marcas. No crea otra sesión, no cambia marcas previas ni fusiona dos clases del mismo día.

En el emulador, una reproducción de la transacción real con dos tramos de 60 minutos agotó el límite de 1.000 expresiones de Rules. Los validadores recorrían repetidamente 24 posiciones posibles aunque la clase solo tuviera dos tramos. La regla ahora valida una vez la fila resultante y corta la evaluación anidada al conteo real de tramos. La propiedad, el rol, la verificación, las marcas y las claves exactas siguen protegidos.

Se reprodujo además un fallo distinto: si la matrícula cambiaba durante una preparación incompleta, el conteo guardado al iniciar no coincidía con la lista revalidada y Rules no permitía confirmarla. Se permite cambiar el conteo solo al pasar de `preparing/building` a `preparing/ready`, con cero marcas y todas las filas pendientes. Después de `ready`, el conteo vuelve a ser inmutable. El repositorio verifica las fuentes y filas antes de confirmar.

El motivo tardío usa la fecha y hora efectivas en `America/Bogota`. Un borrador iniciado a tiempo puede reanudarse después sin pedir un motivo nuevo. Si una preparación antigua quedó sin motivo y empezó tarde o no conserva su fecha de creación, la app solicita el motivo; Rules permite completar ese campo una sola vez en la misma sesión incompleta.

### Acción principal de la lista docente

La tarjeta refleja el estado persistido. Una lista incompleta se muestra como **Lista incompleta → Completar lista**, nunca como “Preparada”. Al alcanzar la hora efectiva, la acción conduce al registro; una clase futura permite preparar la lista y no iniciar marcas antes de tiempo. Continuar sesión/cierre, ver asistencia o completar anulación se ofrecen según el estado. Reprogramar, cancelar y anular permanecen como opciones secundarias. Los errores técnicos se consultan en **Diagnóstico**.

### Otros fallos C8 cubiertos en el mismo conjunto

La integración mantiene el flujo de borrador/publicación/corrección y la consulta propia del estudiante. También incluye reanudación de anulación sin cambiar `publishedAt` ni duplicar el evento, y la proyección mínima `student_calendar` para mostrar Cancelada/Reprogramada sin motivos internos ni acceso a cursos ajenos. La cancelación no suma ausencia ni unidades.

## Archivos y comportamiento clave

- `lib/features/attendance/`: dominio, validación, repositorio Firestore, sesión de docente, consulta del estudiante y lista de clases.
- `lib/app/attendance_repository_scope.dart`, `lib/app/aula_presente_app.dart` y `lib/features/courses/presentation/course_detail_screen.dart`: conexión de Asistencia con el curso.
- `lib/features/courses/**`, `lib/features/enrollments/**` y `lib/features/course_entry/**`: selección de modalidad al crear curso y datos de matrícula/historial usados por la nómina en la fecha efectiva.
- `firestore.rules`: permisos y transiciones de asistencia, calendario de estudiante, preparación y recuperación.
- `firestore.indexes.json`: índice compuesto `attendance_records` con `rosterEntryId ASC`, `visibility ASC`, `effectiveDate DESC` y `__name__ DESC` para la consulta publicada del estudiante.
- `test/features/attendance/**` y `tools/firestore_rules_tests/firestore_rules.test.js`: regresiones de cálculo, repositorio, presentación y permisos.
- `docs/arquitectura.md`, `docs/activacion_conjunto_8.md` y este seguimiento: esquema, activación y recorrido retomable.

## Verificaciones locales

Resultados de la corrección C8 del 16/11, anteriores a este cambio de README y seguimiento:

| Comprobación | Resultado | Alcance |
| --- | --- | --- |
| `flutter analyze` | Aprobado, sin problemas | Análisis estático de la rama. |
| `flutter test test/features/attendance test/features/courses/presentation/student_course_access_test.dart --reporter expanded` | **53/53** | Pruebas afectadas: reintento, estados de tarjeta, publicación, corrección, consulta, calendario y anulación. No se repitió toda la suite Flutter en esa corrección. |
| Firestore Rules Emulator | **99/99** | Incluye clase normal, las dos reprogramadas, conteo al completar, publicación, permisos del estudiante y denegaciones esperadas. No accede a Firebase real. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` | Aprobado | Sintaxis del conjunto JavaScript. |
| `flutter build apk --debug` | Aprobado | APK en `build/app/outputs/flutter-apk/app-debug.apk`. No se instaló en un teléfono. |
| `git diff --check` | Aprobado en la corrección C8 | En esta publicación documental se vuelve a ejecutar. |

La suite de permisos usa el emulador local `demo-aula-presente-firestore-rules-tests`. Sus SDK JavaScript ejecutan operaciones equivalentes; las pruebas Dart usan repositorios controlados. No son una prueba de FlutterFire contra producción. La guía de comandos y dependencias está en [pruebas de reglas](../tools/firestore_rules_tests/README.md).

## Firebase real y prueba manual

El propietario reportó que en TECNO con Firebase real ya funcionan guardar borrador, publicar, consultar como estudiante, corregir Ausente → Presente, recuperar una anulación y ver cambios de calendario. Codex no ejecutó la app en el TECNO ni alteró documentos reales. Aún falta repetir con la APK final el reintento de las sesiones del 15 y 16 indicado abajo.

El proyecto es `aula-presente-movil-juan-2026`, base `(default)`. El propietario reportó que el índice `attendance_records` aparece **Habilitado**. El manifiesto C8 lo declara; la corrección de reintento no modificó índices. No despliegues índices si la entrada correspondiente sigue habilitada.

La corrección posterior del 16/11 sí cambió `firestore.rules`. La última publicación que Codex consultó en solo lectura era anterior a esta corrección; no se verificó un despliegue posterior. Para probar el ajuste contra Firebase real, una persona autorizada debe publicar el `firestore.rules` de esta rama. En este cierre no se desplegaron reglas ni índices, no se crearon cuentas y no se modificaron datos reales.

## Siguiente acción exacta en el TECNO

1. Publica únicamente el `firestore.rules` de esta rama en el proyecto indicado, cuando la persona autorizada haya revisado el diff. Conserva el índice que ya aparece habilitado; no hace falta ejecutar un despliegue de índices para esta corrección.
2. Instala `build/app/outputs/flutter-apk/app-debug.apk` compilada desde esta rama.
3. Abre el mismo curso y selecciona por fecha **efectiva** y hora: 15/11 10:00–12:00 (reprogramada desde el 12/11), 16/11 06:00–08:00 (desde el 05/11) y la clase normal 16/11 10:00–12:00.
4. En cada sesión que muestre lista incompleta, pulsa **Completar lista**. No borres, anules ni recrees sesiones. Si la app solicita motivo tardío, complétalo; el motivo guardado se reutiliza. Comprueba que las marcas previas y los estudiantes se conserven y que las dos clases del 16 sigan separadas.
5. Completa las marcas, finaliza y consulta el registro propio desde la cuenta estudiante. Anota qué encuentro se probó. Si vuelve a fallar, abre **Diagnóstico** y comparte solo la etapa y el código, sin nombres, correos ni códigos de estudiante.

La guía paso a paso para el recorrido docente/estudiante está en [activación C8](activacion_conjunto_8.md). La prueba manual de la APK corregida y la confirmación de las reglas activas son los pendientes; no se deben presentar como verificaciones realizadas por Codex.
