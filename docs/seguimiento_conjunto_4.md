# Seguimiento del conjunto 4: ingreso por código temporal

## Punto de partida

El trabajo parte de `feature/conjunto-4-ingreso-por-codigo`, creada sobre el commit `e4b557407a8336595a6f2ec8bbd63d06eefdf302` (`Completa el conjunto 3 de inscripciones`). El árbol estaba limpio antes de crear la rama. Se conserva el modelo canónico existente `courses/{courseId}/enrollments/{studentUid}` y el conjunto 3 de inscripción manual.

Durante la implementación inicial, Codex trabajó solo en código local, reglas e índices preparados para revisión. No publicó Firebase, creó solicitudes o cuentas reales ni ejecutó la app en el TECNO. La publicación de la rama se trata en el cierre del 11 de noviembre.

## Corrección del recorrido y gestión ampliada — 9 de noviembre de 2026

El propietario informó que desplegó las reglas e índices anteriores y que, en el TECNO, dos códigos recién generados terminaban en «El código no es válido o ya no está disponible». Codex no inspeccionó documentos ni registros del servicio real. La causa comprobada localmente es una lectura privada indebida en Dart, reproducible con el contrato real del conjunto 4.

### Causa comprobada antes de ampliar la vigencia

1. El docente genera 16 símbolos válidos y escribe índice y puntero `current` en una transacción, con timestamps de servidor coherentes. Copiar código usa `groupedCode`; el campo estudiante normaliza guiones, espacios y mayúsculas. No se encontró evidencia de un error de transcripción.
2. `findCourseByCode` hacía un `get` permitido de `course_invites/{code}` y después otro de `courses/{courseId}/invitation/current`. El segundo documento es privado del docente propietario. `requestJoin` también lo leía dentro de su transacción.
3. Las reglas deniegan correctamente esas dos lecturas al estudiante. El repositorio convertía la denegación en `inviteUnavailable`, ocultando el paso que fallaba. La suite JS anterior enviaba solicitudes sin leer `current`; los dobles Dart anteriores no aplicaban esa restricción. Por eso no detectaron el desajuste.
4. La nueva regresión Dart `generated and renewed code opens preview and submits without private reads` usa la escritura real del repositorio docente y restringe las lecturas del estudiante. Antes de corregirlo falló con `CourseEntryFailure(inviteUnavailable)` al abrir un código recién generado. Después pasó para generación, ficha, solicitud, renovación y rechazo del anterior.
5. La regresión del emulador `conjunto 4: recorrido Dart usa índice permitido y nunca lee current privado como estudiante` escribe con la misma transacción docente: el índice permite `get`, el `get` y la lectura transaccional de `current` devuelven `permission-denied` y el recorrido corregido guarda solicitudes con el código inicial y el renovado. Se ejecutó por separado y pasó antes de ampliar el esquema.

La solución conserva `current` privado: solo las reglas hacen sus lecturas internas para autorizar el índice y la solicitud. El estudiante vuelve a leer el índice dentro de la transacción de envío; las reglas comprueban de nuevo código actual, estado y vencimiento con hora de servidor al confirmar. Pausar, renovar, desactivar o vencer entre ficha y envío impide la solicitud. No se abrió curso, horario, lista de estudiantes ni perfiles.

La restauración de sesión y «Ya verifiqué» ya hacen `reload()` y `getIdToken(true)` en Auth; la corrección no añadió un requisito nuevo de token ni concede roles. Los fallos de perfil/rol/sesión mantienen su explicación propia. Solo una denegación de lectura del índice se presenta como código no disponible; el diagnóstico conserva paso y código original sin imprimir el mensaje crudo del SDK.

### Gestión ampliada y única fuente de vencimiento

`current.validForSeconds` es la duración total desde `createdAt` confirmado por Firestore. El vencimiento efectivo siempre se deriva como `createdAt + duration.value(validForSeconds, 's')`; no se guarda `expiresAt` ni otra duración en el índice. El rango es **3600 a 7776000 segundos (1 hora a 90 días)** y el predeterminado es **1209600 segundos (14 días)**. La interfaz permite horas o días enteros, valida el rango y muestra fecha y hora antes de editar. Editar cambia la duración total desde la creación original, no suma tiempo desde ahora.

Las invitaciones anteriores de cuatro campos no se migran ni borran: si falta `validForSeconds`, Dart y reglas aplican 14 días. Pausar/reactivar/desactivar conservan forma y timestamp; editar añade la duración al mismo documento; renovar crea un código distinto con cinco campos. El índice público conserva sus cinco campos originales. La ficha estudiante no anuncia una fecha privada que no puede conocer.

| Acción | Cambio confirmado | Condición |
|---|---|---|
| Generar | `current` e índice nuevos y duración elegida, 14 días por defecto | Solo docente propietario verificado. Se elige antes de escribir. |
| Editar vencimiento | Solo `validForSeconds` y `updatedAt` | Mismo código/creación y estado activo o pausado. Vigencias anterior y propuesta deben ser futuras según el servidor. |
| Pausar | `active → paused`, mismo código y duración | Debe seguir sin vencer. El tiempo sigue corriendo. |
| Reactivar | `paused → active`, mismo código y duración | Debe seguir sin vencer según `request.time`. |
| Desactivar | `active/paused → inactive`, mismo código y duración | Definitivo para ese código, incluso si ya venció. No se reactiva, edita ni pausa después. |
| Renovar | Código diferente, índice y creación nuevos, duración elegida | Invalida el anterior; permite reemplazar uno vencido o desactivado. |

No se escriben roles, solicitudes, decisiones ni matrículas al gestionar invitaciones. Una solicitud enviada válidamente puede decidirse después de pausar, vencer o desactivar el código. La aprobación sigue siendo atómica y la matrícula canónica no cambia.

El estado visual refleja `active`, `paused` o `inactive`; la vigencia efectiva la valida el servidor. No se usa `DateTime.now()` en el módulo para bloquear acciones. Si falta la fecha confirmada se muestra espera; se puede actualizar antes de editar. Una escritura aceptada no se vuelve fallida por un error del refresco opcional.

### Diagnóstico seguro para un intento del propietario

La APK debug muestra **Diagnóstico (debug)** debajo del error de consulta o envío. Al expandirlo y pulsar **Copiar diagnóstico** se obtiene solo `course-entry-v2 | paso=... | error=...`. Los pasos distinguen `session`, `profile-get`, `lookup-get` y `request-transaction`; los errores conservan código SDK o categoría local (`not-found`, `invalid-data`, rol/verificación). No contiene código de invitación, correo, UID, tokens, enlaces ni credenciales. Está aislado con `kDebugMode` y no requiere Logcat. La [guía de activación](activacion_conjunto_4.md) describe el intento único.

No se cambió la estructura de índices en esta corrección. Al terminar esta fase, todavía se requería desplegar manualmente las reglas e instalar una APK nueva: la antigua mantenía la lectura privada errónea. El propietario informó después que hizo esa activación y probó el recorrido real; véase el cierre del 11 de noviembre.

## Contrato vigente

### Rutas y documentos

| Ruta | Campos exactos | Uso y permisos previstos |
|---|---|---|
| `courses/{courseId}/invitation/current` | `code` (string de 16 símbolos), `status` (`active`, `paused` o `inactive`), `createdAt` y `updatedAt` (timestamps de servidor), `validForSeconds` (int entre 3600 y 7776000; ausente solo en documentos antiguos) | Configuración única privada del código vigente. Solo el docente verificado propietario puede leer y cambiarla. `createdAt` inicia/reinicia la vigencia; `updatedAt` cambia en cada operación. No se enumera. |
| `course_invites/{code}` | `courseId`, `subject`, `group`, `period` (strings tomados del curso), `createdAt` (timestamp de servidor) | Índice para consulta exacta. No incluye horario, docente, estudiantes, bloques ni datos de perfil. Solo se puede hacer `get` con un código conocido si está asociado a la configuración actual, activa y no vencida; `list` está denegado. |
| `courses/{courseId}/join_requests/{studentUid}` | `studentUid`, `name`, `email`, `studentCode`, `subject`, `group`, `period`, `invitationCode`, `status`, `createdAt`, `decidedBy`, `decidedAt`, `rejectionReason` | Una solicitud estable por estudiante y curso. Crear exige correo verificado, perfil propio válido, invitación vigente, no estar ya inscrito y estado inicial pendiente. `subject`, `group` y `period` son snapshots públicos mínimos cotejados con el curso; permiten consultar la decisión sin leer curso ni horario. El código se conserva solo para que las reglas comprueben que la solicitud se originó en el código actual; la UI no lo muestra ni registra. Enviar de nuevo no crea duplicados y un rechazo no admite reenvío en esta versión. |
| `courses/{courseId}/enrollments/{studentUid}` | Esquema del conjunto 3 sin cambios: `studentUid`, `ownerUid`, `name`, `email`, `studentCode`, `subject`, `group`, `period`, `status: active`, `createdAt` | Matrícula canónica. La aprobación la crea en la misma transacción que marca la solicitud `approved`, o conserva intacta la matrícula manual existente. |

El alfabeto es `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (32 símbolos; excluye `0`, `1`, `I` y `O`); se genera con `Random.secure()`, se normaliza en un validador y se presenta en cuatro grupos de cuatro. La vigencia deriva de creación del servidor más `validForSeconds`, con 14 días por defecto y compatibilidad con documentos antiguos. La interfaz docente muestra fecha y hora confirmadas o espera. Renovar reemplaza `current` y crea el índice atómicamente; el anterior queda no consultable. Pausar conserva código y vencimiento; desactivar es definitivo. Ninguna acción borra solicitudes o matrículas.

La solicitud conserva snapshots mínimos de perfil para que el docente revise la identidad sin abrir `users/{uid}` y snapshots de materia, grupo y período para que el estudiante consulte una decisión aunque el código haya expirado. El padre de la solicitud da el curso y el UID; esos valores no se duplican. Al crear: `status: pending`, `decidedBy: null`, `decidedAt: null` y `rejectionReason: null`. La decisión es inmutable: `pending → approved` con motivo null, o `pending → rejected` con motivo de 1–500 caracteres; ambas usan `decidedBy` del docente propietario y `decidedAt: serverTimestamp()`.

### Transacciones y carreras

- La creación/renovación de invitación escribe `current` e índice nuevo en una sola transacción. Una colisión no puede sobrescribir el índice; como las reglas no permiten sondear invitaciones ajenas o antiguas, el cliente conserva el `permission-denied` sin asumir que es colisión ni reintentar a ciegas.
- La consulta y el envío vuelven a comprobar en el servidor el código actual, activo y antes de su vencimiento efectivo. Una ficha abierta queda obsoleta si el docente pausa, renueva, desactiva o la vigencia termina antes del envío.
- El envío usa como ID estable el UID actual. Lee el índice de invitación, perfil propio, matrícula propia y solicitud propia; no lee `invitation/current`; si ya está inscrito informa ese estado; si existe solicitud pending, la reutiliza; si está rejected, muestra la decisión histórica y no permite reenvío.
- Aprobar actualiza la solicitud y crea la matrícula canónica en una sola transacción. Si una matrícula manual ya existe, la conserva y resuelve pending como approved sin reescribirla. Rechazar solo guarda motivo y decisión; no crea matrícula. Si otra operación resolvió primero, la transacción detecta el estado final y no vuelve a conceder acceso.
- Si la matrícula manual coincide con una solicitud pending, el repositorio actualiza ambas en la misma transacción y la resuelve como approved. Una matrícula manual posterior a rejected deja intacta la decisión histórica y aparece en `Mis materias`. UID estable y transacciones cubren carreras con envío, aprobación, rechazo y matrícula manual.
- Un resultado de escritura confirmado se presenta antes de cualquier refresco secundario; un error posterior de lista no vuelve a ejecutar la decisión. Cada operación captura UID al comenzar y descarta respuestas visibles si la sesión cambió.

### Consultas e índices previstos

| Consulta | Forma | Índice |
|---|---|---|
| Código puntual | `course_invites/{normalizedCode}` (`get`) | Ninguno compuesto. |
| Solicitudes pendientes del docente | Subcolección `join_requests`, `status == pending`, `createdAt DESC`, `__name__ DESC`, paginada | `join_requests`, ámbito `COLLECTION`, estado ASC + fecha DESC + ID DESC. |
| Solicitudes propias del estudiante | `collectionGroup('join_requests')`, `studentUid == auth.uid`, `createdAt DESC`, `__name__ DESC`, paginada | `join_requests`, ámbito `COLLECTION_GROUP`, UID ASC + fecha DESC + ID DESC. |
| Solicitud o matrícula puntual | Documento con ID `studentUid` derivado de Auth | Ninguno compuesto. |

Las reglas permiten listas solo si el filtro de consulta demuestra los mismos límites de propiedad; no se usa el conocimiento del código para leer el curso, el horario, bloques o estudiantes antes de la matrícula.

### Contrato Dart de integración

El nuevo módulo `lib/features/course_entry/` tendrá modelos y estados de invitación/solicitud, validación de código y texto de rechazo, contrato `CourseEntryRepository`, repositorio Firebase y presentación. El contrato exacto es:

```dart
String? get currentUid;
Future<CourseInvitation?> getCurrentInvitation(String courseId);
Future<CourseInvitation> createOrGetInvitation(String courseId, {Duration validity = CourseInvitation.defaultValidity});
Future<CourseInvitation> renewInvitation(String courseId, {Duration validity = CourseInvitation.defaultValidity});
Future<CourseInvitation> updateInvitationValidity(String courseId, Duration validity);
Future<CourseInvitation> pauseInvitation(String courseId);
Future<CourseInvitation> reactivateInvitation(String courseId);
Future<void> deactivateInvitation(String courseId);
Future<CoursePreview> findCourseByCode(String input);
Future<JoinRequestResult> requestJoin(String input);
Future<JoinRequest?> getMyRequest(String courseId);
Future<JoinRequestPage> listMyRequests({JoinRequestCursor? cursor, int pageSize = 25});
Future<JoinRequestPage> listCourseRequests(String courseId, {JoinRequestCursor? cursor, int pageSize = 25});
Future<JoinDecisionResult> decideJoinRequest({
  required String courseId,
  required String studentUid,
  required JoinRequestDecision decision,
  String? rejectionReason,
});
```

`CourseInvitation` contiene `courseId`, `code`, `status`, `createdAt`, `validity` y una expiración derivada del timestamp confirmado más la duración; su estado refleja el `status` guardado y no depende de la hora local. Si la confirmación de `createdAt` aún no llegó, la presentación indica espera. `CoursePreview` contiene `courseId`, `subject`, `group`, `period`, `code` normalizado y un `expiresAt` opcional que el índice público no proporciona; la ficha no anuncia una fecha privada. `JoinRequest` expone el ID/path-derived de curso y estudiante, snapshots de nombre/correo/código y materia/grupo/período, estado, timestamps/actor de decisión y motivo, pero **no** expone `invitationCode` al widget. `JoinRequestResult` distingue `created`, `alreadyPending`, `alreadyRejected` y `alreadyEnrolled`. `JoinDecisionResult` distingue confirmada de ya resuelta; no solicita repetir una decisión. `JoinRequestPage` y cursor ordenan y paginan con `createdAt DESC, __name__ DESC`. `CourseEntryFailure` distingue autenticación, verificación, perfil/rol, código no disponible, operación ya resuelta, entrada inválida, permisos, red, datos inválidos y fallo inesperado.

Los enums concretos son `JoinRequestResultKind { created, alreadyPending, alreadyRejected, alreadyEnrolled }`, `JoinRequestStatus { pending, approved, rejected }`, `JoinRequestDecision { approve, reject }` y `JoinDecisionResultStatus { approved, rejected, alreadyApproved, alreadyRejected }`. `JoinRequestResult` tiene `kind` y `JoinRequest? request` (null solo cuando `alreadyEnrolled`); `JoinDecisionResult` tiene `status`, `JoinRequest? request` y `Enrollment? enrollment`. `CourseInvitation.status` guarda `active|paused|inactive`; una propiedad calcula vencimiento sin alterar el estado persistido.

`createOrGetInvitation` devuelve cualquier invitación actual existente sin sustituirla por su estado o por la hora del teléfono; solo crea cuando no existe. Reemplazar requiere `renewInvitation` explícito. `renewInvitation` emite explícitamente otro código y está disponible sin condición local de vencimiento. `deactivateInvitation` es idempotente. `findCourseByCode` no lee horario ni bloques. `requestJoin` comprueba código/estado de matrícula/solicitud en una transacción con hora de servidor. `decideJoinRequest` resuelve una solicitud una sola vez y mantiene aprobación y matrícula en una transacción. El repositorio de inscripciones conserva la responsabilidad de la matrícula canónica y resuelve un documento `pending` en la misma transacción cuando el flujo manual agrega a esa persona. No cambia una decisión `rejected` histórica. Formularios y navegación no acceden directamente a Firestore.

El widget `CourseEntryRepositoryScope` inyecta el nuevo repositorio a presentación. La capa visual recibe también el `EnrollmentRepository` existente donde necesita abrir la materia aprobada; no debe duplicar la consulta ni el modelo de curso.

## Referencia visual vigente

Se consultó en modo lectura la página `01 · Aula Presente · Rediseño` del archivo vigente. Los frames antiguos `90 · Archivo · Sistema anterior` y `91 · Archivo · Prototipo anterior` no son referencia.

| Frame exacto | ID | Adaptación funcional prevista |
|---|---|---|
| M01 · Gestionar estudiantes | `2005:12218` | Entradas reales a invitación y solicitudes. |
| M11 · Invitar al curso | `2005:13358` | Mostrar código vigente y expiración derivada; se omite clave adicional. |
| M16 · Invitación lista | `2005:14241` | Código agrupado, copiar/compartir texto y entrar a solicitudes. |
| M35 · Código listo para compartir | `4009:10130` | Copiar código/mensaje; no se ofrece enlace de app. |
| M29 · Gestionar invitación | `4007:8395` | Estado guardado activo, pausado o desactivado, vencimiento confirmado y acciones separadas. |
| M30 · Renovar invitación | `4007:8467` | Confirmar renovación y advertir que el código previo deja de servir. |
| M31 · Desactivar invitación | `4007:8539` | Confirmar; preserva solicitudes y matrículas existentes. |
| M32 · Invitación actualizada | `4007:8611` | Resultado confirmado desde Firestore. |
| C06 · Vincular materias | `30:8` | Un único código de invitación; se elimina el campo de clave adicional. |
| X23 · Invitación no válida | `2005:15833` | Mensaje genérico para código desconocido, vencido o inactivo. |
| C14 · Confirmar curso | `2006:5950` | Materia, grupo y período solamente; se ocultan horario/docente hasta aprobar. |
| C06P · Vinculación pendiente | `30:15` | Estado real pending/approved/rejected y acceso a consulta posterior. |
| M12 · Solicitudes de ingreso | `2005:13480` | Solicitudes reales del curso propio y estados de carga/vacío/error. |
| M17 · Revisar solicitud | `2005:13599` | Perfil snapshot y fecha de solicitud; decisión/motivo reales, no fecha de ingreso supuesta. |
| E14 · Cursos encontrados | `2005:10714` | Resumen sin cantidades ni estudiantes de ejemplo. |
| E02 · Mis materias | `30:18` | Reutiliza la lista canónica tras aprobación. |

Figma define Manrope, título 28/36, cuerpo 16/24, botón 16/24, secundario 14/21, caption 12/18; colores principales `#031310`, `#0B2420`, `#214039`, `#65F4C8`, `#F4FAF7`, `#B7CCC4`, `#55736A` y `#83C6FA`. Las capturas de referencia consultadas incluyen C06, M11, C14, M12, M17, M16, M29–M32, C06P, X23, E14 y E02. Se añadieron comprobaciones de widgets a 320/390/430 px lógicos, escala de texto 1.6 y teclado abierto; no se hizo comparación pixel a pixel de un render Flutter con Figma.

## Implementación y comprobaciones

### Resultado integrado

La rama `feature/conjunto-4-ingreso-por-codigo` se creó desde el commit del conjunto 3 indicado arriba. Al cerrar la fase del 9 de noviembre estaba integrada localmente, todavía sin commit, push ni despliegue de Codex. Las pantallas usan los frames vigentes señalados y los recursos Manrope/tema ya presentes. Se omitió la contraseña adicional y el enlace profundo de Figma porque el flujo acordado usa solo el código y no configura enlaces de app.

### Diagnóstico del límite de expresiones y corrección

La línea base de la suite se reprodujo en Firestore Emulator `1.22.0`, con Firebase CLI `15.32.1`, proyecto ficticio `demo-aula-presente-firestore-rules-tests` y el archivo local `firestore.rules`. El diagnóstico del emulador mostró literalmente `Unable to evaluate the expression as the maximum of 1000 expressions to evaluate has been reached`; no fue un fallo de conexión, configuración ni límite de lecturas de documentos. Las pruebas seguían aprobadas porque esperaban cualquier rechazo, así que no acreditaban la condición prevista.

Los casos afectados y su operación eran:

| Prueba | Operación negativa y condición que debía rechazarla | Evidencia del emulador antes del cambio |
|---|---|---|
| `conjunto 3: directorio impide publicación ajena, sin verificar o falsificada` | Crear una entrada con sesión ausente/no verificada, UID ajeno, email/nombre que no coincide con el perfil, campos extra o timestamp del cliente; actualizar UID o eliminar desde otra cuenta. | `create` en `student_directory` alrededor de `L1022` y `update` en `L1024` agotaban las 1.000 expresiones. `canWriteDirectory` repetía el chequeo de perfil entre `verifiedStudent()` y `directoryMatchesCurrentProfile()`. |
| `conjunto 3: nuevo titular verificado recupera correo liberado sin tomar una entrada vigente` | Crear una entrada mientras el correo aún pertenecía a otra persona; tras liberar el correo, impedir que el titular anterior lo borre o vuelva a publicarlo. | Mismos diagnósticos `create @ L1022` / `update @ L1024`, dentro de `canWriteDirectory` y `directoryMatchesCurrentProfile`. |
| `conjunto 3: otro docente, estudiante y admin no pueden crear ni alterar matrículas` | Crear con estudiante, docente ajeno, admin o sin sesión; modificar una matrícula ya creada. | `create @ L1093` / `update @ L1094` agotaban el presupuesto dentro de `canCreateEnrollment`, que seguía por perfil, curso, directorio y reglas de solicitud antes de descartar identidad/operación. |
| `conjunto 3: matrícula exige directorio y snapshots íntegros sin campos extra` | Crear sin directorio actual o con UID, propietario, identidad, snapshots, estado, timestamp o campos distintos; impedir perfil docente en vez de estudiante. | `create @ L1093` agotaba el presupuesto en `canCreateEnrollment` y `canCreateEnrollmentForOwnedCourse`. |
| `conjunto 3: reintento es único; paginación, conteos y roles combinados conservan acceso` | Reescribir con `setDoc` una matrícula existente, que debe permanecer inmutable. | `update @ L1094` agotaba el presupuesto antes de una denegación normal. |
| `conjunto 3: código opcional, perfil obsoleto y verificación controlan la matrícula` | Rechazar un directorio obsoleto y una inscripción que no coincide con UID/identidad permitidos. | `create @ L1093` agotaba el presupuesto en la validación completa de inscripción. |
| `conjunto 4: las invitaciones exigen curso propio y una colisión no sobrescribe` | El docente dueño de otro curso intenta crear una invitación con un código que ya indexa otro curso. | `create @ L1067` para `invitation/current` evaluaba snapshots cruzados antes de descartar la colisión; el emulador informó el tope. |
| `conjunto 4: aprobar crea matrícula y decisión en una transacción; ambos son inmutables` | Crear directamente la matrícula mientras la solicitud sigue `pending`, omitiendo la resolución atómica a `approved`. | `create @ L1093` agotaba el presupuesto en el chequeo enrollment/solicitud. La alternativa válida en la misma prueba aprueba y crea la matrícula en la transacción conjunta. |
| `conjunto 4: inscripción manual durante pending requiere resolver ambas escrituras juntas` | Crear matrícula con `enrollIdempotently` mientras la solicitud sigue pendiente, sin cambiarla a `approved` en el mismo commit. | `create @ L1093` agotaba el presupuesto al evaluar curso/directorio/solicitud; la escritura conjunta permitida resuelve ambas rutas. |

Se mantuvieron las protecciones y se ordenaron chequeos para descartar antes de lecturas costosas: `canWriteDirectory` valida identidad y después comprueba una vez el perfil actual; `canCreateEnrollment` usa ramas condicionales por identidad, propietario, forma y timestamp antes de consultar solicitud/curso/directorio; la invitación rechaza el código existente antes de evaluar snapshots; y la resolución manual comprueba primero si hay una solicitud pendiente. Se combinó la lógica de renovación/desactivación sin abrir permisos. Se conservan identidad, propiedad, roles, vigencia de servidor, snapshots, `getAfter()` atómico, estados finales inmutables y las garantías previas.

Las pruebas afectadas ahora usan `assertPermissionDenied`, que exige el código SDK `permission-denied` en lugar de cualquier rechazo. La prueba de colisión compara una creación válida con código único y otra operación del mismo docente/curso con código tomado; aprobación e inscripción manual contrastan la escritura aislada denegada con la transacción válida. La suite de la corrección anterior del presupuesto pasó 63/63 y el log no contiene diagnósticos del límite de 1.000 expresiones. Los números de línea anteriores corresponden al archivo previo a la corrección.

### Comprobaciones locales

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Aprobado, sin problemas. |
| `flutter test --reporter expanded` | Aprobado, 163 pruebas y 0 fallos. Incluye dominio/repositorio, decisiones idempotentes, integración con inscripción manual y widgets nuevos. |
| Widgets adaptables | Aprobados en anchos lógicos de 320, 390 y 430 px, escala de texto 1.6 y casos con teclado abierto; se cubrieron listas, diálogo de rechazo y confirmación de renovación. No sustituye la prueba visual manual en el TECNO ni una comparación pixel a pixel con Figma. |
| Firestore Emulator, proyecto ficticio `demo-aula-presente-firestore-rules-tests` | Aprobado, 70/70 casos de la suite. Incluye regresiones de conjuntos anteriores, invitaciones, expiración, solicitudes, decisiones, matrícula atómica e inscripción manual. No se desplegaron las reglas ni índices. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` y validación JSON de `firestore.indexes.json` | Aprobadas. |
| `git diff --check` | Aprobado; Git solo informó avisos de conversión LF/CRLF de Windows. |
| `flutter build apk --debug` | Aprobado tras la corrección del estado de vigencia. APK: `build/app/outputs/flutter-apk/app-debug.apk` (226,372,526 bytes). Gradle imprimió avisos no bloqueantes de acceso nativo Java y compatibilidad futura del Kotlin Gradle Plugin de plugins Firebase. |

La suite actual de reglas exige `permission-denied` en las negativas que antes agotaban expresiones. El log de suite completa registró 70/70 aprobados y ninguna coincidencia con el diagnóstico de 1.000 expresiones. Las pruebas siguen aisladas en el emulador ficticio.

Las pruebas Flutter controlan fechas de creación de 2000 y 2099 para demostrar que el estado no depende del reloj local y que una fecha antigua no bloquea la acción explícita de renovar. Codex no probó contra Firebase real, creó cuentas/solicitudes reales ni ejecutó el TECNO CM6. La activación y la prueba real posterior fueron informadas por el propietario; véase [activacion_conjunto_4.md](activacion_conjunto_4.md).

### Validación de esta ampliación

El 9 de noviembre se ejecutaron `flutter analyze` sin problemas, las 163 pruebas Flutter y 70/70 pruebas en Firestore Emulator (proyecto ficticio, cero diagnósticos del límite de 1.000 expresiones), y `flutter build apk --debug`. La suite conserva las regresiones anteriores y añade el recorrido fiel Dart, estado/vigencia, legacy, aislamiento, ficha abierta, inmutabilidad e historia. El repositorio Dart se prueba con dobles que ahora prohíben la lectura privada; el emulador ejecuta las operaciones equivalentes con las reglas reales locales, no el plugin Dart sobre Android.

Se renderizaron y revisaron con Manrope las vistas de invitación, gestión y diálogo de renovación en 390×844. Los PNG locales `build/c4-review-*.png` contienen solo fixtures ficticios. Se reutiliza el icono de materia `assets/figma/51a24.svg` (24×24) y los componentes existentes. Los widgets también prueban 320/390/430 px, escala 1.6 y teclado. Las diferencias ya existentes del contenedor/navegación respecto a Figma no se refactorizaron; no equivale a validación visual en el TECNO.

La APK de esa fase quedó en `build/app/outputs/flutter-apk/app-debug.apk`. Codex no desplegó, probó Firebase real, creó datos reales ni ejecutó la app en el teléfono. Tampoco había hecho commit, push, merge ni cambios en `main` o la release al 9 de noviembre.

Se abrió además la APK como ZIP y se comprobó que su `kernel_blob.bin` contiene los marcadores nuevos `course-entry-v2`, `validForSeconds`, `Editar vencimiento` y `Confirmar pausa`. Esto acredita que el artefacto incluye la versión nueva; no es una ejecución Android.

## Cierre de presentación y validación — 11 de noviembre de 2026

**Reporte del propietario con Firebase real en el TECNO:** publicó reglas e índices; generó y renovó códigos con vigencias diferentes; comprobó que un código desactivado no se puede usar como estudiante; envió una solicitud con un código nuevo; la aprobó como docente; y vio materia y horario en Mis materias. Son pruebas manuales informadas por el propietario, no ejecutadas ni observadas por Codex.

**Simplificación de Codex:** Gestionar invitación muestra siempre el código, estado y vencimiento, incluso después de guardar un cambio. El estado «Activo» es el valor almacenado y no afirma que el código siga dentro del plazo; la validación al consultar y enviar continúa en Firestore. Copiar código está visible para el estado activo. La pantalla habitual ofrece Renovar, Editar y Desactivar, sin botón Pausar; Reactivar aparece si la invitación ya estaba pausada. Desactivado solo permite renovar. Renovar advierte que reemplaza el código compartido y Desactivar conserva su confirmación. Se retiraron de esa pantalla y del selector de vigencia las explicaciones de Firestore, reloj del servidor, relojes desfasados y permisos internos. Los fallos nombran la acción y dan un paso útil, sin convertir una denegación real de permisos en éxito.

La limpieza quitó el caso `pause` del controlador de la pantalla y las pruebas de ese botón. Conservó `pauseInvitation` en el repositorio, `paused` en el dominio, las reglas y pruebas de datos/emulador: sirven para documentos ya pausados y para la transición segura a Reactivar. Conservó el diagnóstico de consulta/envío solo en modo debug y tras un error, sin códigos, correos, UID ni tokens. No se quitaron rutas, recursos ni operaciones de solicitud, decisión o matrícula.

| Comprobación de Codex en este cierre | Resultado |
|---|---|
| `flutter analyze` | Aprobado, sin problemas. |
| `flutter test --reporter expanded` | 165 pruebas aprobadas; incluye copia del código, ausencia de Pausar, salida de un estado pausado, errores por permisos, acciones conectadas y regresiones compartidas. |
| Widget adaptable | M29 comprobado a 320, 390 y 430 px lógicos con escala 1.6; diálogo de renovación con teclado. Sin excepciones de layout en esas pruebas. |
| `git diff --check` | Aprobado; avisos de conversión LF/CRLF sin errores de contenido. |
| `flutter build apk --debug` | Aprobado; `build/app/outputs/flutter-apk/app-debug.apk`, 226,372,526 bytes. `kernel_blob.bin` incluye Copiar, Editar y Desactivar y ya no incluye Pausar ni Confirmar pausa. |
| Reglas en Firestore Emulator | Se aprovecha la evidencia anterior de 70/70 y cero diagnósticos del límite de 1.000 expresiones. No se repitió porque esta limpieza no cambió reglas ni índices. |

**Pendiente:** revisión visual de la nueva pantalla en el TECNO con esta APK. Codex no ejecutó la app en el teléfono ni modificó Firebase real. `firestore.rules` y `firestore.indexes.json` son parte de la implementación completa de la rama, pero no se cambiaron durante esta simplificación; el propietario informó que ya los publicó. No se requiere otro despliegue de Firebase para este ajuste de presentación. [Guía de revisión](activacion_conjunto_4.md).
