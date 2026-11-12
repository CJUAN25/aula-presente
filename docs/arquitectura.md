# Arquitectura y reglas del producto

## Organización

- `main.dart` solo inicia Flutter y delega en `app/`.
- `app/` reúne la configuración de la aplicación, el tema y los repositorios conectados.
- `core/` contiene configuración transversal, errores y componentes que de verdad se reutilicen. Evita convertirlo en un cajón de cualquier función.
- `features/` separa capacidades del producto. Cada módulo podrá incorporar presentación, lógica de negocio y acceso a datos cuando empiece a implementarse; no se crean capas vacías por anticipado.
- `demo_records` es un CRUD académico temporal, asociado a la cuenta, separado de cursos oficiales y eliminable sin afectar esos módulos.

El mapa de módulos y sus responsabilidades está en [lib/features/README.md](../lib/features/README.md).

## Decisiones y límites

- Una cuenta puede tener permisos de estudiante, docente o ambos. La autorización docente y administrativa procede de una fuente confiable; elegir un rol en la interfaz no concede permisos. El alta de solicitud no concede `teacher`: una aprobación manual con transacción protegida por reglas lo agrega al perfil.
- Los cursos oficiales distinguen materia, grupo y período. El docente autorizado define cursos y horarios; el estudiante consulta horarios de cursos vinculados.
- El conjunto 3 inicia la matrícula con un vínculo activo y fecha de ingreso del servidor. Su evolución futura conservará vigencia e historial de retiros/reincorporaciones; el ingreso tardío no genera faltas anteriores.
- Las sesiones corresponden a ocurrencias concretas del horario. Cambios, cancelaciones, reposiciones y clases extraordinarias deben evitar contar dos veces una sesión.
- Bluetooth, QR y registro manual operan sobre la misma sesión y deben prevenir duplicados. NFC es una posibilidad futura.
- Correcciones manuales requieren motivo e historial. Las justificaciones pueden adjuntar PDF.
- Las importaciones de Excel deben mostrar altas y posibles retiros, permitir selección y exigir confirmación antes de aplicar cambios. Las coincidencias automáticas requieren código estudiantil y correo verificado; los conflictos se revisan.
- Los informes pueden cubrir estudiante, materia, docente y conjunto de cursos registrados en la app. La unidad académica definitiva para calcular faltas (sesiones u horas) sigue pendiente y no se debe codificar como regla cerrada.
- Firebase Core, Firebase Authentication y Cloud Firestore están integrados para Android. La autenticación consulta el perfil en `users/{uid}` y habilita solo los espacios presentes en los roles del perfil cuando el correo está verificado. Estudiante accede a `demo_records`; docente ve sus cursos y agenda reales, sin datos simulados; administración entra a la bandeja de solicitudes. El repositorio usa el UID autenticado y las reglas autorizan cada operación.

## Autenticación real

El módulo de autenticación usa Firebase Authentication y Firestore mediante `lib/features/auth/data/firebase_auth_repository.dart`; formularios y navegación permanecen en presentación. El registro crea la cuenta, actualiza el nombre de Firebase Auth, guarda el perfil con `roles: ["student"]` y envía la verificación en español. La contraseña solo se entrega a Firebase Auth durante la solicitud: no se guarda en Firestore ni en almacenamiento local.

El inicio de sesión lleva a verificación cuando el correo está pendiente. Después de volver de la bandeja de entrada, «Ya verifiqué mi correo» recarga el usuario y su token antes de resolver el perfil. La restauración de sesión repite esa comprobación. Sin perfil, con correo inconsistente, sin permiso `student` o si Firestore no responde, la app explica el estado y no abre una vista protegida.

La corrección de correo pide la contraseña actual y vuelve a autenticar la cuenta. Luego llama a `verifyBeforeUpdateEmail`; el perfil solo se sincroniza con el correo nuevo después de que Firebase confirme el cambio y el correo verificado. El cierre de sesión invalida la sesión de Firebase y reemplaza la navegación protegida. La recuperación usa el enlace de acción predeterminado de Firebase, que lleva a la página web alojada por Firebase para establecer la nueva contraseña; no hay formulario interno de cambio.

Las entradas de vista previa X01, C03S, C11, C04 y C08D del menú oculto de bienvenida son previews de depuración. No autentican, no modifican cuentas y no conceden roles; solo están disponibles en modo debug y no son destinos de producción.

## Solicitud de acceso docente

La solicitud se guarda en `teacher_access_requests/{uid}`, con el UID del usuario autenticado como ID y el siguiente esquema exacto:

| Campo | Tipo | Uso y restricciones |
| --- | --- | --- |
| `uid` | string | Debe coincidir con el UID autenticado y el ID del documento. |
| `name` | string | Snapshot de `users/{uid}.name` al solicitar; 1–100 caracteres. |
| `email` | string | Snapshot de `users/{uid}.email`; debe coincidir con el correo verificado de Authentication. |
| `studentCode` | string o null | Snapshot del perfil, máximo 40 caracteres si contiene texto. No acredita condición docente. |
| `status` | string | `pending`, `approved` o `rejected`. Al crear debe ser `pending`. |
| `createdAt` | timestamp | Timestamp de servidor, inmutable para clientes. |
| `decidedBy` | string o null | UID del administrador que resolvió; null al crear. |
| `decidedAt` | timestamp o null | Timestamp de servidor de decisión; null al crear. |
| `rejectionReason` | string o null | Null al crear; para rechazo, texto de 1–500 caracteres. |

La persona solicitante puede crear y consultar únicamente el documento con su UID, después de verificar el correo, pero no actualizarlo ni borrarlo. Los administradores verificados consultan la cola filtrada por `status == 'pending'` y fecha; no pueden listar `users`. `firebase.json` referencia `firestore.rules` e `firestore.indexes.json`, que contiene el índice compuesto `status ASC, createdAt ASC` para esa consulta.

La aprobación es una transición única `pending → approved` y una actualización atómica que incorpora solo `teacher` a `users/{uid}.roles`; conserva roles existentes, `student`, y todos los otros campos del perfil. Las reglas usan `getAfter()` para rechazar aprobación sin concesión simultánea y concesión sin aprobación simultánea. Un administrador no puede resolver su solicitud ni conceder `admin`. El rechazo exige motivo y deja inalterados los roles. Toda decisión final es inmutable para clientes; no se permite reabrir solicitudes rechazadas en esta entrega.

Las operaciones de creación y decisión requieren correo verificado. La app verifica el perfil y el correo antes de crear la solicitud. Las pantallas muestran que una solicitud no concede acceso, identifican cambios en el perfil frente al snapshot, ofrecen estados y reintento si el servidor no responde, y ocultan detalles si cambia la cuenta. La guía de primer administrador y publicación manual está en [activacion_acceso_docente.md](activacion_acceso_docente.md).

## Esquema inicial de Cloud Firestore

El cliente usa el esquema de la base (default) del proyecto aula-presente-movil-juan-2026. Las escrituras deben usar exactamente estos campos:

| Ruta | Campos esperados | Reglas de acceso |
| --- | --- | --- |
| users/{uid} | name: string (1–100 caracteres), email: string (3–254), studentCode: string \| null (si es texto, 1–40), roles: string[] | Solo el usuario cuyo UID coincide con {uid} puede crear y leer directamente su perfil. El alta requiere que email coincida con el correo del token de Firebase Auth, pero no exige que ya esté verificado. La creación fija roles en ["student"]. El usuario puede editar name, email y studentCode; el correo solo puede cambiarse cuando el token indique que fue verificado. roles no puede cambiarse desde el cliente. Las consultas de lista y la eliminación del perfil se deniegan. |
| users/{uid}/demo_records/{recordId} | title: string (1–120), description: string (0–1000), createdAt: timestamp, updatedAt: timestamp | El UID de la ruta debe ser el usuario autenticado. Crear, leer (incluida la consulta de lista), editar y eliminar exige correo verificado. En creación, ambos timestamps deben ser serverTimestamp(); al editar, createdAt permanece igual y updatedAt usa serverTimestamp(). No se almacena un uid adicional en el registro porque el propietario ya está fijado por la ruta. |

El perfil puede crearse y leerse antes de verificar el correo para permitir el paso de registro y la verificación posterior. El cambio de correo del perfil requiere `email_verified == true` en el token y que el correo coincida con el token. Las cuatro operaciones de `demo_records` requieren correo verificado. La app solo muestra este acceso dentro del perfil `student`; el repositorio toma el UID de la sesión vigente y no acepta un UID de la interfaz. El rol se representa como arreglo para permitir que una cuenta pueda tener varios permisos en el futuro; solo un flujo confiable podrá agregar `teacher` o `admin`. La app cliente no incluye ese otorgamiento. El acceso directo a cualquier otro documento queda denegado por defecto.

El módulo `lib/features/demo_records/` separa el contrato y el modelo (`domain/`), la validación (`application/`), Cloud Firestore (`data/`) y las pantallas de lista, detalle y formulario (`presentation/`). Cada documento almacena solo `title` (texto de 1 a 120 caracteres), `description` (texto de 0 a 1000 caracteres), `createdAt` y `updatedAt` (timestamps). Crear envía timestamps de servidor para ambos campos; editar solo cambia título, descripción y `updatedAt`, por lo que conserva `createdAt`. Las consultas se limitan a la subcolección bajo el UID autenticado. No se agrega un campo `uid`, no se cambian roles y estos datos no participan en cursos, matrículas ni asistencia.

## Diseño visual

La referencia vigente es la página `01 · Aula Presente · Rediseño` del [archivo Figma](https://www.figma.com/design/XP9LIZClkFzVNf17jUXjGU/NUEVA-CORRECION). Las páginas `90 · Archivo · Sistema anterior` y `91 · Archivo · Prototipo anterior` son históricas y no se deben usar para implementar.

## Verificación y evidencias

Las capturas de futuras pruebas se guardarán solo después de generarlas y revisarlas. Deben usar datos de prueba o estar anonimizadas; no se inventan evidencias ni se incluyen capturas sensibles.

## Conjunto funcional 2: cursos y calendario inicial

El módulo `lib/features/courses/` cubre creación y consulta de cursos propios por docentes verificados. `lib/features/schedule/` contiene bloques semanales, fechas académicas y la generación determinista de encuentros previstos. El flujo no crea matrícula, sesiones de asistencia ni documentos por cada ocurrencia.

### Esquema persistido de cursos

El curso y sus bloques semanales se escriben juntos mediante una transacción de Firestore. El horario se guarda como documentos hijos para que las reglas puedan validar los ocho bloques y sus vecinos dentro del límite de expresiones por documento; no se guardan ocurrencias/sesiones. La fuente única del horario son esos documentos hijos; el padre solo contiene sus IDs y el orden canónico.

Ruta padre: `courses/{courseId}`. `courseId` es aleatorio y estable durante el borrador y los reintentos; no se duplica dentro del documento.

| Campo | Tipo | Restricción |
| --- | --- | --- |
| `ownerUid` | string | UID de Authentication, añadido por el repositorio. |
| `subject` | string | Obligatorio, 1–120 caracteres después de normalizar espacios. |
| `group` | string | Obligatorio, 1–40 caracteres. |
| `period` | string | Obligatorio, 1–32 caracteres; texto libre. |
| `program` | string | Obligatorio, 1–120 caracteres; texto libre, sin catálogo oficial supuesto. |
| `timezone` | string | Exactamente `America/Bogota`. |
| `startDate`, `endDate` | timestamp | Fechas civiles inclusivas normalizadas a medianoche UTC; máximo 366 fechas contando extremos. |
| `weeklyBlockIds` | list<string> | De 1 a 8 IDs únicos en orden canónico `(weekday, startMinute, endMinute, id)`. Cada ID corresponde exactamente a un documento hijo. |
| `status` | string | `planned` al crear. No cambia automáticamente por el reloj. |
| `schemaVersion` | int | `1` en esta versión. |
| `createdAt`, `updatedAt` | timestamp | Ambos timestamps del servidor al crear. |

Ruta de bloque: `courses/{courseId}/weekly_blocks/{blockId}`. El ID de documento es el identificador estable del bloque (20–40 caracteres seguros para ruta) y no se duplica como campo.

| Campo | Tipo | Restricción |
| --- | --- | --- |
| `weekday` | int | 1=lunes, 2=martes, …, 7=domingo. |
| `startMinute` | int | Minuto local desde medianoche, de 0 a 1439; se convierte a `HH:mm` en Dart. |
| `endMinute` | int | De 0 a 1439 y estrictamente mayor que `startMinute`; no cruza medianoche. |
| `room` | string o null | Opcional; máximo 60 caracteres cuando contiene texto. |
| `order` | int | Posición 0–7 en `weeklyBlockIds`; reglas verifican que el ID y posición coincidan. |

Firestore Rules valida que el padre enumere entre 1 y 8 hijos existentes en la misma escritura atómica, que cada bloque tenga el esquema y rangos válidos, produzca al menos una ocurrencia dentro de las fechas y se ordene sin solaparse con sus vecinos. Los bloques consecutivos son válidos. La unicidad de IDs se comprueba mediante la correspondencia uno-a-uno entre la lista del padre y el campo `order` de cada hijo. Los clientes no pueden añadir hijos después ni actualizar o borrar cursos/bloques.

### Calendario y zona académica

`AcademicDate` representa año, mes y día como fecha civil independiente de la zona del dispositivo. Su serialización Firestore es un timestamp UTC a las 00:00. `startDate` y `endDate` se incluyen. Las horas de cada bloque se interpretan en `America/Bogota`; no son instantes UTC almacenados.

Una única función de `schedule` genera ocurrencias para la vista previa, calendario guardado y agenda. Cada `PlannedMeeting` se identifica de manera estable como `courseId|blockId|YYYY-MM-DD`, usando la fecha original del horario. Una función de dominio separada detecta cruces entre cursos cuando coinciden la fecha concreta y las horas solapadas; el aviso cuenta cada encuentro afectado del curso nuevo una sola vez mediante su ID estable, incluso si coincide con varios cursos. La revisión requiere recorrer todos los cursos propios paginados; si falla una página, no se afirma que no haya conflictos. La comprobación es informativa y no bloquea otros dispositivos. No se excluyen festivos ni se aplican excepciones todavía.

Las ocurrencias se muestran como previstas, no como sesiones abiertas o realizadas. El tiempo transcurrido no registra asistencia ni genera ausencias. Al añadir reprogramaciones, se conserva la clave de la fecha original como referencia de la excepción; la sesión de asistencia será otra entidad en una entrega posterior.

Para investigar el aviso persistente, `checkScheduleConflicts` conserva una evaluación inmutable con sus entradas, encuentros generados y todas las parejas que justifican el conteo. El alta usa esa evaluación; las herramientas de diagnóstico de presentación están limitadas a `kDebugMode` y permiten consultar sin guardar. La exportación usa solo fechas/días/horas y alias locales; no serializa perfiles, títulos, aulas, UID ni IDs reales. No almacena ni transmite informes automáticamente. El alcance y las limitaciones están en [diagnostico_conflictos_horarios.md](diagnostico_conflictos_horarios.md).

### Permisos y ciclo de creación

Las reglas permiten crear y consultar cursos solo a una cuenta autenticada y verificada cuyo perfil `users/{uid}` coincida con el correo del token y tenga `teacher` en `roles`. Ser admin sin `teacher` no concede acceso académico. `get` de un ID inexistente se permite al docente vigente para revisar la disponibilidad en una transacción; un documento existente solo lo puede leer su dueño. Las consultas `list` deben incluir `ownerUid == request.auth.uid`. La lectura de `weekly_blocks` exige el mismo propietario del curso y rol vigente. El cliente no puede editar ni borrar cursos o bloques en esta etapa.

La creación valida el modelo también en el cliente, pero Firestore Rules mantiene la autoridad del servidor. Una transacción lee el padre y los hijos necesarios antes de escribir; crea el padre y todos los bloques en un único commit. Las reglas usan `getAfter()` para rechazar un padre incompleto, bloques fuera de la lista y solapamientos. Con el ID estable del borrador, el repositorio reconoce como ya creada la misma carga normalizada si existe y rechaza una carga distinta sin sobrescribir. No realiza una lectura posterior para convertir un commit confirmado en fallo; devuelve el ID y los datos conocidos, con timestamps nulos si el servidor todavía no devolvió sus valores. Navegación y mensajes se ejecutan fuera de la transacción y solo tras confirmación.

Listas y agendas consultan documentos padre filtrados por propietario; cada curso carga sus 1–8 bloques desde su subcolección ordenada por `order`. `getAllOwnCourses` recorre todas las páginas necesarias y reconstruye el modelo tipado. La ordenación de cursos es por `createdAt` descendente y el ID de documento descendente, con cursor compuesto. El índice compuesto requerido se mantiene junto al índice de solicitudes docentes en `firestore.indexes.json`; la subcolección solo usa el índice ascendente de campo que Firestore crea automáticamente.

La activación manual de reglas, índice y recorrido de prueba del conjunto 2 está en [activacion_conjunto_2.md](activacion_conjunto_2.md). En esa etapa no se creaban inscripciones; el conjunto 3 añade el vínculo sin alterar el esquema del curso ni el cálculo de horarios. Festivos, sesiones, asistencia, QR, Bluetooth, cambios avanzados de curso, cancelaciones y reportes siguen fuera del alcance.

## Conjunto funcional 3: inscripción manual y materias del estudiante

`lib/features/enrollments/` separa contrato y modelos, validación, repositorio Firebase y pantallas. Una cuenta existente con rol `student` y correo verificado puede publicar su propia entrada mínima en `student_directory/{email}`. El docente busca por **correo exacto conocido**; no existe una consulta de lista de perfiles ni una cuenta creada desde su sesión. En el formulario se puede cotejar además el código estudiantil, que puede faltar en cuentas antiguas. El nombre, el correo y el código mostrados proceden del perfil de la cuenta y se revisan antes de confirmar. Son datos declarados por la persona, no una acreditación institucional.

La entrada del directorio contiene exactamente `uid`, `name`, `email`, `studentCode` (string o null) y `updatedAt` (timestamp de servidor). El ID del documento es el correo del token, igual al correo del perfil; se rechazan campos adicionales. Solo una cuenta con `student` y correo verificado puede publicar sus propios datos; una entrada de un titular vigente no puede ser tomada por otra cuenta. El titular puede borrar su entrada. Si el antiguo titular cambia de correo y deja una entrada que ya no coincide con su perfil, el nuevo titular verificado de ese correo puede sustituirla por sus propios datos. Solo un docente verificado y autorizado puede consultar por ID; `list` se deniega. Las reglas cotejan la entrada con el perfil actual al leerla, para que un cambio posterior de nombre, código o correo no devuelva información obsoleta. Al volver a abrir el espacio estudiante se publica la entrada vigente. La búsqueda exacta permite a un docente autorizado probar un correo conocido y ver datos básicos de esa cuenta; esta limitación de privacidad se acepta para la inscripción manual, no equivale a un directorio libre.

La fuente de verdad es `courses/{courseId}/enrollments/{studentUid}`. El ID de documento es el UID del estudiante: la misma combinación de curso y estudiante no se duplica. No hay documento espejo ni contador. Campos exactos:

| Campo | Tipo | Uso |
| --- | --- | --- |
| `studentUid`, `ownerUid` | string | Identidad del estudiante e identidad del docente propietario. Ambas se contrastan con ruta/curso; el cliente deriva el docente de Authentication. |
| `name`, `email`, `studentCode` | string, string, string o null | Snapshot de directorio/perfil, para mostrar listas sin leer un perfil privado por fila. |
| `subject`, `group`, `period` | string | Snapshot del curso, que es inmutable en este conjunto, para listar materias sin otra lectura por fila. |
| `status` | string | Solo `active` en esta etapa; no hay retiro o reincorporación. |
| `createdAt` | timestamp | `serverTimestamp()`; momento de ingreso efectivo. No genera asistencias o faltas pasadas. |

El docente autorizado crea en su curso mediante una transacción que comprueba la entrada y si ya existe el ID. Un reintento que encuentra el mismo documento devuelve «ya inscrito» sin escribir de nuevo. Solo el docente dueño lista la subcolección. La persona con `student` y correo verificado consulta solo sus inscripciones mediante `collectionGroup('enrollments')` filtrada por `studentUid == request.auth.uid`. El orden de ambas listas es `createdAt DESC, __name__ DESC` con páginas; el índice compuesto de grupo se declara en `firestore.indexes.json`. Las cantidades proceden de los documentos reales, no de un valor simulado o un contador que pueda quedar desfasado. El estudiante puede hacer `get` del padre y `get/list` de sus `weekly_blocks` solo cuando existe su inscripción activa; no puede escribirlos. Las reglas preservan `users` privado, la creación atómica de cursos y el límite de ocho bloques. Nombre, correo y código en una matrícula son **snapshots del momento de ingreso**: si la persona cambia después su perfil, el vínculo por UID sigue vigente, pero la fila docente puede conservar esos datos antiguos hasta un futuro flujo de actualización de matrícula. La interfaz no debe presentarlos como lectura actual del perfil privado.

El estudiante reconstruye el curso y el horario guardado y reutiliza `generatePlannedMeetings` para consultar encuentros **previstos**. Si tiene también `teacher`, conserva por separado el espacio de cursos que imparte. Una sesión cerrada, un rol retirado o un cambio de cuenta impide reutilizar una respuesta antigua en la interfaz. El resultado de la transacción se devuelve sin una lectura posterior que convierta un guardado confirmado en error aparente. Un fallo de red durante la transacción puede dejar resultado incierto: la interfaz debe ofrecer consultar la lista y reintentar con el mismo ID, sin afirmar que se canceló.

El contrato, los frames vigentes, las pruebas y los límites se describen en [seguimiento_conjunto_3.md](seguimiento_conjunto_3.md). El usuario informó que desplegó las reglas y el índice y comprobó manualmente el recorrido en el TECNO; [activacion_conjunto_3.md](activacion_conjunto_3.md) conserva los pasos para reproducirlo. Codex no ejecutó esa prueba real. Excel, invitaciones, solicitudes de ingreso, edición/retiro/reincorporación, asistencia, QR, Bluetooth y reportes permanecen fuera de este conjunto.

## Conjunto funcional 4: ingreso por código temporal

El módulo `lib/features/course_entry/` genera y gestiona invitaciones de cursos propios, permite la consulta puntual de un código, crea solicitudes verificadas y consulta las solicitudes del docente y del estudiante. `presentation/` usa repositorios inyectados; no accede directamente a Firestore. La invitación no concede acceso: el ingreso efectivo requiere una decisión del docente propietario y una matrícula canónica.

### Invitaciones

La configuración privada única se guarda en `courses/{courseId}/invitation/current` con exactamente estos campos:

| Campo | Tipo | Restricción |
|---|---|---|
| `code` | string | 16 caracteres del alfabeto `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (32 símbolos; excluye `0`, `1`, `I`, `O`). El cliente lo crea con `Random.secure()`, lo normaliza antes de formar la ruta y lo muestra en cuatro grupos de cuatro. |
| `status` | string | `active`, `paused` o `inactive` (desactivación definitiva para ese código). |
| `createdAt` | timestamp | `serverTimestamp()`; reinicia la vigencia al renovar. |
| `updatedAt` | timestamp | `serverTimestamp()` en cada cambio confirmado. |
| `validForSeconds` | int | Duración total desde `createdAt`: 3600–7776000 segundos (1 hora–90 días), por defecto 1209600 (14 días). Ausente en documentos antiguos, que conservan 14 días. |

El índice de consulta exacta `course_invites/{code}` mantiene exactamente `courseId`, `subject`, `group`, `period` y `createdAt`. No contiene horario, bloques, docente, directorio, perfiles ni otra fuente de vencimiento. Solo un estudiante verificado con perfil válido puede hacer `get` de un código conocido. No permite `list`. Las reglas comparan código/creación con `current`, estado activo y `request.time < createdAt + validForSeconds` (14 días si el campo está ausente). El estudiante **no lee** `invitation/current`: esa lectura en el Dart anterior causaba `permission-denied` incluso con códigos nuevos. Solo las reglas acceden internamente al documento privado. Consulta y envío usan el índice permitido y revalidan en servidor al confirmar.

Flutter muestra al docente el vencimiento derivado de la creación confirmada más la duración, o espera si todavía no hay timestamp confirmado. El estado guardado se distingue de la vigencia efectiva y no se calcula con `DateTime.now()` para bloquear acciones. El estudiante no anuncia una fecha privada que el índice no proporciona. Pausar no detiene el tiempo; reactivar exige vigencia futura; editar conserva creación/código y exige que la vigencia anterior y propuesta sean futuras. Desactivar es definitivo para ese código. Renovar genera otro y puede reemplazar uno vencido o desactivado. No se modifican solicitudes previas, decisiones, roles ni matrículas.

El docente verificado con perfil `teacher` solo puede leer, crear, renovar o desactivar `current` en un curso propio. Crear/renovar escribe el nuevo `current` y `course_invites/{code}` en una transacción; el código anterior deja de ser consultable al cambiar el puntero y no se borran los documentos históricos. Si un identificador aleatorio colisiona, las reglas bloquean sobrescribir el documento. Como no se permite sondear códigos antiguos o ajenos, el cliente conserva `permission-denied` como tal y no lo trata como una colisión inferida.

### Solicitudes y decisiones

La ruta es `courses/{courseId}/join_requests/{studentUid}`; el UID y curso se derivan de la ruta. El esquema exacto es:

| Campo | Tipo | Restricción |
|---|---|---|
| `studentUid` | string | Debe ser igual al UID autenticado y al ID del documento. |
| `name` | string | Snapshot del perfil, de 1 a 100 caracteres. |
| `email` | string | Snapshot del correo verificado; de 3 a 254 caracteres, igual al token y perfil al solicitar. |
| `studentCode` | string o null | Snapshot del perfil; si es texto, de 1 a 40 caracteres. |
| `subject` | string | Snapshot mínimo de curso, cotejado con el documento padre, de 1 a 120 caracteres no blancos. |
| `group` | string | Snapshot de curso cotejado; de 1 a 40 caracteres no blancos. |
| `period` | string | Snapshot de curso cotejado; de 1 a 32 caracteres no blancos. |
| `invitationCode` | string | Código normalizado usado para solicitar; las reglas lo verifican contra invitación actual. Se persiste para validar el origen, pero el modelo y la UI no lo muestran ni lo registran. |
| `status` | string | `pending`, `approved` o `rejected`; al crear es `pending`. |
| `createdAt` | timestamp | `serverTimestamp()` de la solicitud; inmutable. |
| `decidedBy` | string o null | UID del docente propietario; null al crear. |
| `decidedAt` | timestamp o null | `serverTimestamp()` al decidir; null al crear. |
| `rejectionReason` | string o null | null al crear o aprobar; en rechazo, motivo recortado de 1 a 500 caracteres. |

Una cuenta con `student` y correo verificado puede crear y leer la solicitud cuyo ID sea su UID, y consultar únicamente su `collectionGroup('join_requests')` filtrado por `studentUid == request.auth.uid`. El docente verificado propietario puede leer documentos puntuales de su curso y listar solo documentos pendientes. `admin` sin permiso `teacher` no recibe acceso académico. No se puede enumerar invitaciones, estudiantes, solicitudes de otro UID ni cursos a partir de un código.

Enviar se valida de nuevo en una transacción: invitación todavía actual/activa/no vencida, perfil autenticado, matrícula existente y solicitud estable. El ID UID hace idempotente el reintento: una solicitud pending se reutiliza; un rechazo se conserva como decisión histórica y no permite reenvío en esta versión; quien ya está matriculado recibe el estado existente sin duplicado. Los campos de materia, grupo y período permiten mostrar solicitudes pendientes y decisiones después de expirar el código, sin abrir el curso o el horario antes de la matrícula.

Aprobar solo permite `pending → approved`, actualiza actor/fecha y crea o reutiliza `courses/{courseId}/enrollments/{studentUid}` en la misma transacción. El mapa de matrícula conserva exactamente el esquema del conjunto 3; los datos de identidad y curso proceden de snapshots cotejados con la solicitud. Rechazar solo permite `pending → rejected`, exige motivo y nunca crea matrícula. `getAfter()` exige que una aprobación y matrícula nueva aparezcan juntas; las decisiones finales no se pueden volver a cambiar. Si una matrícula ya existe, se conserva sin reescribirla. Si el flujo manual del conjunto 3 encuentra una solicitud pending, la inscripción y su resolución como approved ocurren en la misma transacción; una inscripción manual posterior a rejected deja intacta esa historia y aparece en Mis materias. Races de aprobación, rechazo, solicitud y matrícula se resuelven por el ID estable y el reintento transaccional; una escritura confirmada no se marca fallida por un refresco posterior.

### Consultas e índices

- Pendientes docentes: subcolección del curso, `status == 'pending'`, `createdAt DESC`, ID DESC, con páginas. Índice de grupo `join_requests`, `COLLECTION`, `status ASC`, `createdAt DESC`, `__name__ DESC`.
- Solicitudes del estudiante: `collectionGroup('join_requests')`, `studentUid == uid`, `createdAt DESC`, ID DESC, con páginas. Índice de grupo `join_requests`, `COLLECTION_GROUP`, `studentUid ASC`, `createdAt DESC`, `__name__ DESC`.
- Búsqueda del código: `get` puntual por documento, sin índice compuesto ni lista general.

Las reglas, estados, métodos Dart, frames de Figma, carreras, pruebas y limitaciones de este conjunto están en [seguimiento_conjunto_4.md](seguimiento_conjunto_4.md). La validación real informada por el propietario y los pasos para revisar la pantalla final están en [activacion_conjunto_4.md](activacion_conjunto_4.md). Codex no desplegó Firebase ni ejecutó el teléfono.
