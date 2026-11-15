# Seguimiento del conjunto 7 · actualización de lista desde Excel

## Alcance y punto de partida

Implementación del conjunto 7 en la rama `feature/conjunto-7-actualizacion-lista-excel`, basada directamente en `b6cb49ebf2923244a17b7a0d186f03c4c33b7990` (conjunto 6). El remoto comprobado es `https://github.com/CJUAN25/aula-presente.git`. Este cierre publica la rama con un commit y push normal; no hace merge, no despliega reglas/índices y no modifica `main` ni `v0.1.0-entrega-1`. La prueba manual con Firebase real y en TECNO fue reportada por el propietario, no ejecutada por Codex.

El conjunto añade comparación de lista completa, selección explícita de cambios, autorizaciones pendientes sin UID y vinculación automática cuando el estudiante verificado demuestra el correo y código exactos. Mantiene aparte el flujo C6 **Solo agregar estudiantes**, la inscripción canónica, roles y cursos. No se añadieron sesiones ni cálculos de asistencia, QR, Bluetooth, Storage, Cloud Functions o servidor.

## Ajuste final: historial de matrícula por curso

### Hallazgo reportado y causa comprobada

El propietario reportó que una persona reincorporada dejaba de aparecer en **Retirados e histórico**, aunque **Ver historial de inscripción** seguía mostrando ingreso, retiro confirmado y reincorporación confirmada. El código confirma que **Retirados** consulta el estado canónico actual `withdrawn`. La reincorporación actualiza el mismo documento canónico a `active`, por lo que salir de esa lista operativa es correcto; lo que faltaba era una entrada general para encontrar su historial.

### Solución integrada

- Se agregó **Gestionar estudiantes → Historial de matrícula**, contextualizado con materia, grupo y período del curso abierto.
- La lista usa `loadCourseRosterSnapshot()` y las cuatro páginas completas del roster del curso. No presenta una página parcial como si fuera el total.
- Cada persona se resuelve por `rosterEntryId`; matrículas antiguas sin ese dato usan `legacy:{studentUid}`. La matrícula canónica gana ante una autorización pendiente coincidente; una autorización `linked` no crea una fila duplicada. No se unen personas por nombre o parecido de correo.
- La lista no lee subcolecciones de eventos fila por fila ni escribe datos. Al tocar una fila, el mismo detalle individual carga los eventos canónicos; si existió autorización pendiente, los eventos de autorización se leen de forma diferida y aparecen separados. La vinculación no se presenta como un segundo ingreso ni sustituye la fecha efectiva.
- Si dos consultas que se solapan devuelven estados incompatibles, el modelo compara `lastStatusChangedAt` y `createdAt`; ante empate exacto con estados distintos devuelve error recuperable en vez de elegir un estado arbitrario.
- **Retirados** conserva la consulta `withdrawn`; la ficha de una matrícula activa y el historial general abren el mismo detalle. Las respuestas tardías de otra sesión no se muestran.

La vista reutiliza las reglas, índices y formas de consulta ya existentes. Este ajuste no cambia esquema persistido, reglas, índices, importación, vinculación ni transiciones y no requiere otro despliegue de Firebase. `firestore.rules` y `firestore.indexes.json` siguen teniendo los cambios previos de C7 respecto a la base C6; no se alteraron durante este ajuste.

### Evidencia separada

### Pruebas manuales reportadas por el propietario

En dos momentos distintos, el propietario probó el conjunto en el TECNO con Firebase real:

1. **Recorrido principal:** altas desde Excel, vinculación posterior de una inscripción pendiente, selección de retiros y reincorporación. Reportó que el flujo funcionó y el historial individual se conservó.
2. **Ajuste final:** la persona reincorporada aparece una sola vez como **Activa** en **Historial de matrícula**, conserva **Ingreso**, **Retiro confirmado** y **Reincorporación confirmada**, la ficha abre ese mismo historial y no aparece en **Retirados**.

**Historial de matrícula** permite encontrar a cualquier persona inscrita del curso aunque hoy esté activa; **Retirados** es la lista operativa de quienes siguen retirados. El historial individual permanece accesible. Estos resultados son reporte del propietario: Codex no ejecutó ni observó la app en el teléfono y no verificó Firebase real.

### Verificaciones locales tras el ajuste final

Estas verificaciones se ejecutaron después de integrar el ajuste y antes del cierre/publicación: `flutter analyze` limpio; `flutter test --reporter compact` **281/281**; Firestore Rules Emulator **80/80**; `git diff --check` aprobado con avisos habituales LF/CRLF; y `flutter build apk --debug` aprobada. APK: `build/app/outputs/flutter-apk/app-debug.apk` (**218.606.974 bytes**). El emulador usó exclusivamente el proyecto ficticio `demo-aula-presente-firestore-rules-tests`; las pruebas locales no prueban Firebase real ni la ejecución en el TECNO.

### Comprobaciones del cierre/publicación (15 de noviembre de 2026)

Se volvió a revisar el diff completo respecto a la base, los fixtures, la configuración remota y las referencias de `main` y `v0.1.0-entrega-1`. En esta fase documental se validan el JSON de índices y `git diff --check`; no se repiten la suite Flutter, el emulador ni la compilación. No se ejecuta `firebase deploy`.

## Interfaz consultada

Se revisó en modo lectura la página vigente `01 · Aula Presente · Rediseño` del archivo Figma. No se usaron las páginas de archivo y no se cambió Figma.

| Frames vigentes | Nodo Figma | Aplicación en Flutter |
|---|---|---|
| M01 · Gestionar estudiantes / M02 · Importar Excel | `2005:12218` / `2005:12383` | Dos entradas docentes: actualización comparada C7 y solo altas C6; el curso abierto fija el destino. |
| M06 · Comparar actualización | `2005:12747` | Totales de nuevos, sin cambios, posibles retiros y filas por revisar. |
| M20 · Seleccionar estudiantes nuevos | `4006:8058` | Selección individual y acciones de seleccionar/desmarcar dentro de cada grupo elegible. |
| M07 · Seleccionar retiros | `2005:12892` | Retiros solo para lista completa confiable y desmarcados por defecto. |
| M21 · Confirmar actualización / M22 · Actualización aplicada | `4006:8130` / `4006:8202` | Revisión final, confirmación y resultado separado por fila/transición. |
| M28 · Sin cambios seleccionados | `4006:8562` | Estado sin selección; volver a la revisión no escribe. |
| M10 · Pendiente de cuenta | `2005:13251` | Explicación de autorización guardada y vinculación tras verificar correo/código. |
| M14 · Estudiantes / M15 · Retirados / M33 · Reincorporar | `2005:13829` / `2005:14115` / `4009:9850` | Integración con roster activo, historial y reapertura explícita de una autorización. |

Las vistas reutilizan AppTheme, Manrope, iconos y componentes de cursos. Las pruebas de widget incluyen anchos lógicos 320, 390 y 430 con escala de texto 1.6. Esto no es una comparación pixel a pixel; queda revisar el diseño final en el TECNO.

## Contrato de datos

### Autorización pendiente

La ruta es `courses/{courseId}/pending_enrollments/{emailExact}`. `emailExact` es el correo validado sin espacios exteriores, conservado exactamente como identidad y como ID; `rosterEntryId` usa el mismo valor y permite mantener una identidad de roster aunque cambie después el correo de Auth. No se copia el libro Excel.

El mapa completo usa estos campos: `courseId`, `ownerUid`, `subject`, `group`, `period`, `email`, `studentCode`, `name`, `status`, `effectiveStartDate`, `rosterEntryId`, `studentUid`, `authorizedAt`, `linkedAt`, `createdAt`, `updatedAt`, `lastEventId`, `lastStatusChangedAt`. Los valores iniciales son `status: 'pending'`, `studentUid: null`, `linkedAt: null`, `lastEventId: null`, `lastStatusChangedAt: null`; las horas de autorización/creación/actualización provienen de `serverTimestamp()`. Una importación repetida con la misma identidad no duplica. Si el mismo correo se presenta con otro código, el documento no se reemplaza y queda por revisar. El nombre es un snapshot de presentación, no una clave de identidad.

Las transiciones posteriores agregan el evento inmutable `courses/{courseId}/pending_enrollments/{emailExact}/status_events/{operationId}` con `fromStatus`, `toStatus`, `effectiveDate`, `changedAt` y `changedBy`. `changedAt` es `serverTimestamp()`; `effectiveDate` es fecha civil UTC a medianoche. El ID fijo `link` identifica de forma idempotente la única transición a `linked` en esa subcolección y no concatena correos largos. Las transiciones permitidas son `pending → linked`, `pending → withdrawn` y `withdrawn → pending`. El evento inicial no se inventa: la propia creación confirmada representa la autorización.

### Matrícula e historial canónicos

La ruta que da acceso sigue siendo `courses/{courseId}/enrollments/{studentUid}`. Las altas nuevas incluyen `rosterEntryId` y `effectiveStartDate`. Cuando se crea una matrícula al vincular un pendiente, curso, nombre autorizado, correo, código, ID estable y fecha efectiva se copian en una transacción junto con el cambio a `linked` y su evento. Si ya existe una matrícula activa del mismo UID/curso con correo y código coincidentes, se reutiliza sin reescribirla. En datos C5/C6 legacy se admite solo que falten juntos `rosterEntryId` y `effectiveStartDate`; no se agregan campos retroactivamente y se conserva `createdAt`, el snapshot y la fecha civil derivada. Una pareja moderna presente debe coincidir. Una matrícula retirada no se reactiva automáticamente; exige reincorporación explícita. Para altas directas, C3 manuales y C4, las escrituras cotejan la identidad y no duplican una matrícula.

Los eventos C5 de matrícula incluyen ahora `effectiveDate`, además de `fromStatus`, `toStatus`, `changedAt` y `changedBy`. Una decisión de `active/withdrawn` y su evento continúan siendo atómicos; `createdAt` no se reinicia. Los documentos C5/C6 sin `rosterEntryId` ni `effectiveStartDate` se leen sin migración, con identidad estable de compatibilidad `legacy:{studentUid}` y fecha civil derivada de `createdAt - 5 horas`. Los eventos anteriores sin `effectiveDate` derivan su fecha civil de `changedAt - 5 horas` (Bogotá UTC−5).

### Fechas y límites

`AcademicDate` serializa fecha civil como UTC a 00:00, no como hora del dispositivo. La fecha actual se evalúa en `America/Bogota` a partir del reloj validado por Rules; Colombia no aplica horario de verano. Alta o reincorporación usa una fecha dentro del calendario; para un curso todavía futuro se permite solo `course.startDate`, nunca programar otra alta futura. Un retiro no se puede programar en el futuro. Una autorización o matrícula todavía no iniciada puede cancelarse con fecha efectiva no posterior a hoy de Bogotá ni a `course.endDate`; la fecha no puede preceder la autorización/creación ni invertir el último evento válido. Para el intervalo activo, ingreso/reincorporación incluye el día elegido y retiro lo excluye. Los accesos se actualizan tras la transacción confirmada; no se generan asistencias ni faltas.

Durante la revisión se corrigió un límite de fecha del selector: si el curso ya comenzó pero una autorización pendiente empieza después de hoy, el docente ahora puede cancelarla hoy. `pending_enrollment_date_policy.dart` refleja la misma rama `effectiveStartDate > hoy` que usa el repositorio. Tres pruebas de dominio cubren el caso, el inicio aún futuro y el retiro después de empezar el tramo.

## Comparación y consultas

**Solo agregar estudiantes** acepta una lista parcial y hace consultas puntuales por identidad; quienes no aparecen no se alteran. **Comparar lista completa** obtiene desde servidor las páginas de matrículas activas/retiradas y autorizaciones pendientes/retiradas antes de ofrecer retiros. La hoja debe contener filas no vacías, sin duplicados ni conflictos de identidad, y el snapshot debe completarse sin error. Posibles retiros aparecen desmarcados. Una lectura incompleta, fila inválida, correo/código ambiguo o datos contradictorios bloquea retiros; las altas elegibles se pueden procesar en la modalidad parcial. Retirados que reaparecen requieren acción explícita de reincorporación o reapertura.

Al confirmar se revalida la sesión, candidato, propietario y estado revisado; cada persona se procesa mediante una transacción independiente. Algunas filas pueden guardarse aunque otras fallen. Los resultados distinguen guardado, sin cambios, requiere revisión y fallo/sin confirmación. Un refresco posterior no convierte una escritura confirmada en error. El ID de evento estable se conserva para reintentos inciertos.

Consultas e índices:

- Docente: `courses/{courseId}/pending_enrollments`, `status == pending|withdrawn`, `createdAt DESC, __name__ DESC`, paginado. Índice `COLLECTION`: `status ASC, createdAt DESC, __name__ DESC`.
- Estudiante: `collectionGroup('pending_enrollments')`, `email == Auth.email`, `studentCode == users/{uid}.studentCode`, `status == 'pending'`, `createdAt DESC, __name__ DESC`, con cursor. Índice `COLLECTION_GROUP`: `email ASC, studentCode ASC, status ASC, createdAt DESC, __name__ DESC`.
- Lista completa: cuatro consultas docentes paginadas en el servidor; cualquier página fallida invalida la comparación para retiros.

Los índices históricos se conservan. Rules deniega enumeración general de perfiles, directorio, matrículas y pendientes; el alumno consulta únicamente autorizaciones con correo y código exactos. La aprobación del docente y la prueba de identidad del estudiante son distintas. Si hay una solicitud C4 `pending`, solo se resuelve como `approved` en la misma transacción cuando curso, UID, correo, código y autorización coinciden; el nombre es descriptivo, no clave, y la matrícula conserva el snapshot que ya tenía. Si la identidad no coincide, la solicitud sigue pendiente para revisión docente. No se concede un permiso general para que el alumno apruebe solicitudes.

## Archivos principales

- `lib/features/excel_import/`: comparación y coordinación, lectura C6 reutilizada, pasos de interfaz y resultados parciales.
- `lib/features/enrollments/domain/pending_enrollment*.dart`: modelo, páginas, cursor, cambios e informes de vínculo.
- `lib/features/enrollments/data/firestore_enrollment_repository.dart`: consultas y transacciones de autorización, historial, roster completo y vinculación.
- `lib/features/enrollments/presentation/`: accesos docentes, pendientes/historial, y actualización automática del espacio estudiante.
- `lib/features/course_entry/data/firestore_course_entry_repository.dart`: compatibilidad de aprobación C4 con una autorización C7 coincidente.
- `firestore.rules`, `firestore.indexes.json`: protección y consultas del conjunto; requieren activación manual futura.
- `test/features/`, `test/fixtures/excel_import/`: pruebas locales y libros ficticios `.xls` de 35 filas y `.xlsx` mixto.

## Verificación y activación

## Verificación local inicial del conjunto 7 (14 de noviembre de 2026)

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Aprobado, sin problemas. |
| `flutter test --reporter compact` | **261/261 aprobadas.** Incluye regresiones de importación, selección, fechas, legacy, C3/C4 y pantallas. |
| Firestore Rules Emulator | **80/80 aprobadas**, 0 fallidas y ningún diagnóstico `maximum of 1000 expressions`. Proyecto ficticio `demo-aula-presente-firestore-rules-tests`; CLI 15.32.1, Node 24.14.1, JBR 25.0.2. |
| Subconjunto dirigido Rules C5 | 2/2 aprobado sin errores del límite de expresiones. |
| Subconjunto dirigido de reglas C7 | 5/5 aprobado; incluye consulta del estudiante, escrituras parciales/fechas, link con C4 y legacy, y conciliación manual. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` | Aprobado. |
| `firestore.indexes.json` y `firebase.json` | JSON válido; nueve índices, sin definiciones equivalentes duplicadas; dos índices de `pending_enrollments` con alcances correctos. |
| `git diff --check` | Aprobado; solo avisos normales de conversión LF/CRLF en Windows. |
| `flutter build apk --debug` | Aprobado. APK: `build/app/outputs/flutter-apk/app-debug.apk` (218,586,430 bytes). Gradle mostró avisos no bloqueantes de acceso nativo JDK y de la compatibilidad futura KGP de `firebase_auth`/`firebase_core`. |

No se modificaron dependencias, por lo que no fue necesario ejecutar `flutter pub get`. La suite del emulador usa SDK de JavaScript para comprobar reglas y operaciones atómicas; no ejecuta el repositorio Flutter/Dart contra Firestore Emulator. Los widgets Flutter y repositorios Dart tienen pruebas separadas con datos/dobles locales.

Durante la integración, el emulador reveló que algunas denegaciones estaban agotando el límite de 1.000 expresiones, incluso una creación válida heredada de C5. Se eliminó una validación de forma duplicada y se redujo la comprobación repetida entre el cambio del pendiente y su evento sin quitar validaciones: cada mitad requiere la otra mediante `getAfter()`. El helper de pruebas considera fallido cualquier `permission-denied` causado por ese límite. La corrida completa final quedó en 80/80 y el log no contiene ese diagnóstico.

La suite de Rules usa exclusivamente `demo-aula-presente-firestore-rules-tests`; no contacta la base real. Codex no desplegó reglas ni índices, no creó cuentas ni registros reales y no ejecutó la app en el TECNO. Posteriormente el propietario reportó pruebas manuales reales del recorrido principal y del ajuste final de historial, descritas arriba; Codex no las observó ni verificó qué revisión exacta de reglas/índices está desplegada.

El propietario debe desplegar manualmente `firestore.rules` e `firestore.indexes.json` antes de validar contra Firebase real. No se ejecutó `firebase deploy`. Si el índice `COLLECTION_GROUP` está construyéndose, esperar a que Firebase lo muestre como habilitado antes de iniciar la búsqueda; `failed-precondition` indica que la consulta no está lista, no que la identidad esté autorizada. La prueba completa paso a paso está en [activacion_conjunto_7.md](activacion_conjunto_7.md). El estado final local y lo que queda por verificar se registran en [estado_actual.md](estado_actual.md).
