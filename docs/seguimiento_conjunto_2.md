# Seguimiento del conjunto 2: cursos y calendario inicial

## Contrato fijado antes del trabajo paralelo

Alcance: creación y consulta de cursos propios por una cuenta verificada con el rol `teacher`, calendario calculado desde el horario recurrente y agenda docente. No se implementan matrículas, alumnos, sesiones de asistencia, QR, Bluetooth, justificaciones, reportes, edición ni borrado de cursos.

### Esquema persistido

Curso padre: `courses/{courseId}`. `courseId` es un identificador aleatorio generado una vez al iniciar el borrador; se conserva durante navegación, errores y reintentos. No se guarda un campo `id` duplicado. Los bloques se guardan como hijos en `courses/{courseId}/weekly_blocks/{blockId}`; el padre enumera sus IDs en orden canónico. Padre y todos sus bloques se crean en el mismo commit atómico.

| Campo | Tipo Firestore | Restricción |
| --- | --- | --- |
| `ownerUid` | string | Lo añade el repositorio desde Firebase Auth; nunca proviene del formulario. Debe ser el UID autenticado. |
| `subject` | string | Obligatorio; 1–120 caracteres después de normalizar espacios. |
| `group` | string | Obligatorio; 1–40 caracteres. |
| `period` | string | Obligatorio; 1–32 caracteres. Texto libre, sin catálogo institucional. |
| `program` | string | Obligatorio; 1–120 caracteres. Texto libre, sin catálogo institucional. |
| `timezone` | string | Exactamente `America/Bogota`. |
| `startDate` | timestamp | Fecha académica inclusiva normalizada a 00:00:00 UTC; representa una fecha civil, no un instante de clase. |
| `endDate` | timestamp | Igual que `startDate`; no anterior y máximo 365 días después (366 fechas contando ambos extremos). |
| `weeklyBlockIds` | list<string> | De 1 a 8 IDs estables y únicos, ordenados por `(weekday, startMinute, endMinute, id)`. Debe existir exactamente un documento hijo por cada ID. |
| `status` | string | Valor inicial fijo `planned`; no se deriva del reloj. |
| `schemaVersion` | int | Valor inicial fijo `1`. |
| `createdAt` | timestamp | `serverTimestamp()`; debe coincidir con `request.time`. |
| `updatedAt` | timestamp | `serverTimestamp()`; debe coincidir con `request.time`. |

Cada documento hijo tiene exclusivamente estos campos; `blockId` es el ID estable del documento y no se duplica como campo:

| Campo | Tipo | Restricción |
| --- | --- | --- |
| `weekday` | int | 1=lunes, 2=martes, …, 7=domingo. |
| `startMinute` | int | Minuto local desde medianoche, entre 0 y 1439; Dart lo presenta como `HH:mm`. |
| `endMinute` | int | Entre 0 y 1439; estrictamente posterior a `startMinute`, sin cruzar medianoche. |
| `room` | string o null | Opcional; máximo 60 caracteres cuando contiene texto. |
| `order` | int | Posición 0–7 en `weeklyBlockIds`. |

La serialización normaliza bloques en orden canónico `(weekday, startMinute, endMinute, id)`, sin cambiar sus IDs ni imponer ese orden a la lista visual del formulario. Las reglas exigen que la lista padre y las posiciones de los hijos coincidan uno-a-uno, que todos los hijos existan después del mismo commit, y que cada bloque tenga una ocurrencia dentro del rango. Cada hijo comprueba sus vecinos con `getAfter()` y rechaza desorden o solapamiento en el mismo día; dos bloques consecutivos se permiten. Esta separación mantiene la autoridad de Firestore y permite probar el máximo de ocho sin exceder el límite de expresiones de una sola evaluación.

El repositorio no materializa encuentros ni documentos en `sessions`. `createdAt` y `updatedAt` son los únicos instantes; el calendario se deriva de `startDate`, `endDate`, `timezone` y los documentos hijos `weekly_blocks`.

### Contratos Dart compartidos

- Dominio de `courses`: `Course`, `CourseDraft`, `CourseCursor`, `CoursePage`, `CourseCreationResult` y `CourseRepository`.
- `Course` contiene el ID del documento, dueño, los campos persistidos y `DateTime? createdAt/updatedAt`; estos timestamps pueden ser null en la respuesta inmediata a una creación recién confirmada porque el servidor no ha devuelto su valor.
- `CourseDraft` conserva el `id` de operación y los campos editables. No contiene `ownerUid`, estado, versión, zona seleccionable ni fechas de auditoría.
- `CourseRepository` ofrece `getOwnCoursePage({CourseCursor? cursor, int pageSize = 25})`, `getAllOwnCourses({int pageSize = 25})` y `createCourse(CourseDraft draft)`. El UID se resuelve dentro del repositorio desde Firebase Auth.
- `CourseCreationResult` devuelve el `Course` conocido y `wasAlreadyCreated`. Reutilizar el mismo ID y datos normalizados devuelve el documento existente; reutilizarlo con datos diferentes produce `idempotencyConflict`, sin sobrescribir.
- `CourseFailureKind`: `unauthenticated`, `emailNotVerified`, `profileInvalid`, `teacherRoleRequired`, `permissionDenied`, `network`, `idempotencyConflict`, `invalidCourse` y `unknown`.
- Dominio de `schedule`: `AcademicDate`, `WeeklyBlock`, `CourseSchedule`, `PlannedMeeting`, `MeetingConflict`, validación y una sola función `generatePlannedMeetings(...)`. `AcademicDate` valida año/mes/día mediante construcción UTC y comprobación inversa; no usa la zona del teléfono.
- Los métodos de agenda y de detección de cruces consumen páginas hasta el final. Una página vacía por sí sola no acredita que se consultó todo.

### Calendario y conflictos

`America/Bogota` es la zona fija para interpretar horas de bloque. El generador recorre las fechas civiles inclusivas, selecciona cada `weekday`, crea ocurrencias `PlannedMeeting` y las ordena por fecha, hora de inicio y `blockId`. La clave estable es `courseId|blockId|YYYY-MM-DD`, basada en la fecha original del horario; una futura reprogramación podrá referenciar esa misma clave como excepción sin cambiar la identidad original.

La vista previa D17, D04, D22 y D24 consumen el mismo generador. Los eventos se presentan como **previstos**; el paso del tiempo no crea sesiones ni marca asistencia. No se aplican festivos ni excepciones en esta etapa. Dos bloques consecutivos se aceptan; bloques del mismo día que se solapan, IDs duplicados, bloques repetidos o un horario sin encuentros se rechazan.

Antes de confirmar se recorren todos los cursos propios paginados. Hay conflicto informativo si los rangos de fechas se intersectan, existe una fecha de ocurrencia común en esa intersección y los intervalos horarios se solapan ese día. No hay reserva global entre dispositivos. Si no se pudo completar la consulta, la UI informa el error y no presenta “sin conflictos”.

### Investigación del aviso de conflictos (29 de octubre de 2026)

El usuario reportó en su TECNO, con Firebase real, que al crear **Lógica** (martes y jueves 08:00–09:00) apareció un aviso de 17 encuentros frente a **Móvil** (lunes 08:00–10:00 y viernes 06:00–10:00). Informó que las reglas y los índices ya están publicados. No se consultaron los documentos reales, no se confirmó el rango de fechas ni la interpretación AM/PM, y no se ejecutó la app en el teléfono durante esta investigación.

El recorrido inspeccionado es D19 (día ISO 1–7 y hora de `TimeOfDay` en formato 24 h) → `CourseDraft.normalized()` → `generatePlannedMeetings` → `getAllOwnCourses` (todas las páginas y los documentos `weekly_blocks`, consultados del servidor) → `findScheduleConflicts` → diálogo D17 → `createCourse`. La serialización usa `weekday` ISO, minutos desde medianoche y fechas civiles a medianoche UTC, reconstruidas sin la zona del teléfono. El comparador ya exigía la misma fecha y el solapamiento estricto `inicioA < finB && inicioB < finA`; omite el ID del propio borrador. El estado `_saving` impide editar o iniciar una segunda comprobación mientras la lectura o el diálogo están pendientes; las lecturas fallidas producen error y no una lista vacía.

**Reproducción sintética:** con el rango inclusivo de prueba 2026-11-02 a 2026-11-15 y los cuatro bloques reportados, la implementación anterior devolvió cero conflictos. La prueba de presentación con días distintos tampoco abrió el diálogo. Por tanto, este ensayo no reproduce ni explica el aviso de 17; sus valores reales siguen sin inspeccionar y no se atribuye el aviso a la comparación de días u horas. Una causa confirmada distinta fue el **conteo por parejas**: si un encuentro del borrador coincidía con dos cursos, el detector devolvía dos elementos y el diálogo decía dos encuentros. Una prueba que esperaba un encuentro falló antes de la corrección con resultado real de dos.

`lib/features/schedule/application/schedule_conflict_detector.dart` ahora conserva un solo conflicto por ID estable del encuentro candidato (`courseId|blockId|YYYY-MM-DD`). El diálogo existente usa la longitud de esa lista: cuenta encuentros distintos del curso nuevo y conserva la advertencia de cruces verdaderos. No cambiaron el generador, la lectura del repositorio, la transacción, las reglas ni los índices.

Pruebas añadidas: caso sintético Móvil/Lógica, solapamiento parcial, límites consecutivos, igualdad, contención, períodos separados, deduplicación y flujo de creación con días distintos, cruce verdadero, corrección del borrador, confirmación única y error de lectura. La prueba manual pendiente es revisar, sin alterar los cursos, los días, horas en formato 24 h y fechas que muestra el detalle guardado de Móvil y la revisión del borrador de Lógica, y repetir la acción en la APK nueva. Si persiste un aviso con esos datos realmente disjuntos, se necesitará evidencia no sensible de esas vistas para localizar la diferencia entre los datos observados y los usados por la app.

Comprobaciones de esta investigación: la prueba nueva de deduplicación falló antes del cambio (esperaba 1 y recibió 2); la prueba sintética de los días reportados pasó antes del cambio con cero. Después, `flutter analyze` terminó sin problemas, `flutter test` aprobó 95 pruebas y `flutter build apk --debug` generó la APK. No se ejecutó el emulador de reglas porque no cambiaron reglas, consultas ni contratos de Firestore; tampoco se accedió a Firebase real o al teléfono. Queda pendiente confirmar con la APK nueva y los valores visibles reales si el aviso de 17 persiste.

### Continuación del diagnóstico — 2 de noviembre de 2026

El usuario confirmó que el aviso persiste al ejecutar nuevamente desde VS Code y que solo tiene Móvil guardado. Un período menor produjo 13 coincidencias; la captura muestra martes/jueves en la vista previa. Esto no demuestra los días que devuelve el repositorio para el curso existente. La corrección anterior del conteo no explica el aviso de días disjuntos y la causa continúa pendiente.

Se añadió una comprobación debug de solo lectura y un informe que vincula todos los cruces con los cursos, bloques, fechas y horas que realmente consume el detector, mediante alias sin UID, nombres ni IDs reales. El diálogo y el informe comparten una única evaluación inmutable. El botón **Diagnosticar sin guardar (debug)** permite obtener la evidencia sin crear Lógica; **Ver diagnóstico** dentro del aviso conserva exactamente esa comprobación. La lógica de solapamiento, los permisos y la transacción no cambiaron.

Ahora hay pruebas del repositorio Dart real con respuestas controladas del SDK: sus documentos hijos lunes/viernes se reconstruyen como lunes/viernes y no cruzan martes/jueves; una respuesta sintética con días coincidentes produce fechas concretas trazables. Se cubren además paginación, fallos de hijos, cambio de cuenta, privacidad del informe, consulta sin escritura, copia y cierre durante una lectura pendiente. Esto no verifica todavía el SDK nativo Android ni los valores del servidor real. El método de captura, los archivos responsables y la interpretación están en [diagnostico_conflictos_horarios.md](diagnostico_conflictos_horarios.md). No se requiere publicar reglas ni índices.

Verificación de esta continuación: `flutter analyze` sin problemas, `flutter test --reporter expanded` con 106 pruebas aprobadas y `flutter build apk --debug` correcto. No se ejecutaron Firebase real, el emulador ni el TECNO; las reglas y el acceso a datos mantienen su implementación anterior. Falta que el usuario copie el diagnóstico de la ejecución real para demostrar la causa y decidir su corrección.

### Evidencia recibida del teléfono y causa del aviso

El informe debug enviado por el usuario tiene un único curso existente, distinto del borrador, y período 2026-11-01 a 2027-02-28. Lógica llega como martes/jueves 08:00–09:00; **el curso existente llega como lunes 08:00–10:00 y martes 06:00–10:00**, con `weekdayIso: 2` en su segundo bloque. Las 17 parejas son exactamente los 17 martes entre ambos períodos, entre cursos distintos. Esto explica el aviso y descarta en esta ejecución el autocruce, la comparación entre días distintos y la duplicación del conteo. El diagnóstico no demuestra por qué el bloque existente llega como martes en lugar del viernes esperado.

Se añadieron dos regresiones: reproducción exacta de las fechas y los 17 cruces, con cero al sustituir martes por viernes solo en datos sintéticos; y recorrido del formulario lunes/viernes hasta el borrador de guardado y sus documentos canónicos, que conserva días `[1, 5]` y las horas indicadas. Ambas pasaron sin cambiar código productivo. El repositorio lee el entero `weekday` sin remapeo; no se inspeccionó el documento real ni se modificaron cursos, reglas, índices o permisos. Falta comprobar qué muestra el detalle de Móvil después de actualizar para decidir una corrección controlada de sus datos si corresponde. Véase [resultado del informe](diagnostico_conflictos_horarios.md#resultado-del-informe-recibido).

Verificación posterior al informe: `flutter analyze` sin problemas y `flutter test --reporter expanded` con 108 pruebas aprobadas. Solo cambiaron dos archivos de pruebas y cuatro documentos de seguimiento; no se reconstruyó una APK ni se ejecutó Firebase o el teléfono porque el código productivo mantuvo su implementación.

**Confirmación final del usuario:** Móvil efectivamente tiene lunes 08:00–10:00 y martes 06:00–10:00. Coincide con el diagnóstico y explica los cruces con Lógica los martes 08:00–09:00. Se cierra este caso como advertencia correcta de un solapamiento real. No se demostró un error de conversión ni hace falta modificar el detector o los cursos. La referencia inicial a viernes no correspondía al horario confirmado. Esta última actualización fue solo documental y no requirió repetir pruebas.

### Persistencia, acceso e idempotencia

- Crear y consultar requieren Authentication activa, correo verificado, perfil válido y `teacher` en `users/{uid}.roles`. Tener únicamente `student` o `admin` no habilita cursos.
- `get` del ID aún inexistente se permite solo a un docente actual para que la transacción compruebe disponibilidad del ID. Si el curso existe, solo su dueño puede leer el padre y sus bloques. Conocer un ID ajeno no permite leerlo.
- `list` solo admite consultas restringidas con `ownerUid == request.auth.uid`; administración no obtiene acceso por ser admin.
- `create` valida todos los campos del padre y de cada bloque (hasta ocho), fechas, solapes, propietario, pertenencia de todos los hijos al commit y timestamps de servidor. `update` y `delete` quedan denegados a clientes.
- La creación ejecuta una transacción: lee el ID estable del padre y sus bloques; crea si no existe; si existe y los campos normalizados coinciden, devuelve el curso como ya creado; si difieren, informa conflicto. No usa `add()` y no relee el documento después del commit para declarar éxito.
- La respuesta inmediata de creación conserva los datos conocidos y no inventa timestamps. La navegación se ejecuta después de recibir el resultado; si cambió la cuenta, no se abre el curso bajo otro UID. El borrador permanece en pantalla para reintentar con el mismo ID y no se guarda ni reenvía automáticamente al reiniciar.
- Listas ordenan padres por `createdAt` descendente e ID de documento; cursor compuesto por timestamp e ID. El filtro de propietario y el orden usan índice compuesto. Cada padre carga los hijos ordenados por `order`; `getAllOwnCourses` recorre páginas y reconstruye cada curso para agenda y verificación de cruces.

### Figma y navegación

La referencia es la página `01 · Aula Presente · Rediseño` (`25:57`), sin consultar las páginas archivadas. Frames revisados: D01 `30:34`, D02 `30:35`, D03 `30:36`, D03G1 `30:49`, D04 `30:37`, D15 `2005:10871`, D16 `2005:10975`, D17 `2005:11106`, D19 `2005:11378`, D22 `2005:11715`, D24 `2005:11871` y X26 `2005:16175`.

El flujo de alta es D02 → D15 → D16 → D19 (añadir/editar un bloque) → D16 → D17 → D03/D04. Se conserva el borrador al avanzar y volver; descartar con cambios exige confirmación. D01 y D24 presentan los cursos y encuentros reales del docente. D03 y D03G1 son una sola vista dinámica, no cursos fijados al ejemplo Figma. Acciones de matrícula, asistencia, reprogramación, cancelación, edición recurrente, invitaciones y métricas de estudiantes permanecen no disponibles.

Figma mide 390×844 y usa Manrope, fondo `#031310`, superficies `#0B2420`/`#214039`, primario `#65F4C8`, texto `#F4FAF7`, muted `#B7CCC4`, outline `#55736A` e información `#83C6FA`. La implementación reutiliza `AppTheme` y recursos locales; no fija el tamaño del dispositivo. Verificación responsive requerida en 320/390/430 px lógicos y texto 1.5×.

## Línea base previa a la integración — 29 de octubre de 2026

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Aprobado; sin problemas. |
| `flutter test` | Aprobado; 49 pruebas. |
| Firestore Emulator, proyecto ficticio `demo-aula-presente-firestore-rules-tests` | Aprobado; 31 pruebas. |
| `flutter build apk --debug` | Aprobado. Avisos no bloqueantes del JDK y de Kotlin Gradle Plugin en `firebase_auth`/`firebase_core`. |

No se consultó ni modificó Firebase real. No se publicó ninguna configuración. Figma se leyó en modo solo lectura. Sin validación en el TECNO CM6.

## Propiedad de archivos para el trabajo paralelo

| Responsable | Archivos exclusivos |
| --- | --- |
| Agente A — dominio y calendario | `lib/features/courses/domain/**`, `lib/features/courses/application/**`, `lib/features/schedule/domain/**`, `lib/features/schedule/application/**`, `test/features/courses/domain/**`, `test/features/courses/application/**`, `test/features/schedule/**` |
| Agente B — datos y seguridad | `lib/features/courses/data/**`, `firestore.rules`, `firebase.json`, `firestore.indexes.json`, `tools/firestore_rules_tests/**` (excepto `node_modules`) |
| Agente C — presentación | `lib/features/courses/presentation/**`, `test/features/courses/presentation/**` |
| Coordinación | `lib/app/**`, integración de `lib/features/auth/presentation/auth_screens.dart`, `test/widget_test.dart`, README/AGENTS y documentación fuera de READMEs de cursos/horarios |

No editarán archivos de otro propietario. La coordinación integra los tres aportes y solicita una revisión independiente después de cerrar las comprobaciones locales.

## Hallazgos de integración y resolución

- La primera representación con ocho bloques embebidos en el padre superó el límite de 1000 expresiones de Rules en Firestore Emulator. Se probó sin quitar validaciones; el máximo y algunas denegaciones no cabían en una sola evaluación del padre.
- Se mantuvo el agregado atómico, pero los valores del horario pasaron a `courses/{courseId}/weekly_blocks/{blockId}`. El padre guarda los IDs ordenados. Una sola transacción crea padre e hijos; Rules usa `getAfter()` para exigir los hijos, sus posiciones, ocurrencias y continuidad sin solapes. El emulador validó el máximo y la suite final sin errores de presupuesto.
- La revisión independiente encontró que un reintento con el mismo `courseId` y otros IDs de bloque intentaba leer primero IDs alternativos y se clasificaba como `permissionDenied`. El repositorio ahora lee los hijos referenciados por el padre existente y devuelve `idempotencyConflict` al comparar, sin consultar rutas alternativas ni sobrescribir. Una regresión confirma que el curso y bloque originales permanecen intactos. No fue necesario cambiar reglas para este arreglo.
- La revisión encontró que `docs/estado_actual.md` seguía diciendo que cursos no existían; se actualizó con el conjunto 2 y las limitaciones comprobadas.
- La suite de reglas usa SDK de JavaScript contra el emulador: prueba el esquema, transacciones y permisos, pero no ejecuta el repositorio Dart directamente contra el emulador. La serialización del dominio y la presentación Flutter se prueban por separado.

## Cierre local

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Aprobado, sin problemas. |
| `flutter test` | Aprobado, 85 pruebas. |
| `firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"` | Aprobado, 41/41; máximo de ocho bloques, ocurrencia en un día y regresiones del conjunto 1 incluidas. Cero errores de 1000 expresiones. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` | Aprobado. |
| `flutter build apk --debug` | Aprobado; APK `build/app/outputs/flutter-apk/app-debug.apk`. Avisos no bloqueantes de Java y Kotlin Gradle Plugin de `firebase_auth`/`firebase_core`. |

No se desplegaron reglas ni índices, no se contactó Firebase real, no se crearon datos de prueba reales y no se ejecutó la app en el TECNO CM6. La lectura de Figma fue de solo lectura; no hubo comparación de captura renderizada de Flutter con Figma.

## Revisión independiente

El revisor examinó seguridad, navegación, transacción, calendario, presentación y alcance sin editar. Confirmó el hallazgo de idempotencia, la limitación documental y que la suite JS no equivale a integración Dart-emulador. Tras corregir el primer hallazgo, confirmó que el repositorio lee los hijos guardados, devuelve `idempotencyConflict`, no altera datos y no requiere ampliar reglas. No encontró otro defecto confirmado de seguridad o navegación en el alcance revisado.
