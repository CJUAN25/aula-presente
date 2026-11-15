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
- El conjunto 3 inicia la matrícula con un vínculo activo y fecha de ingreso del servidor; el conjunto 5 añade estados active/withdrawn e historial de retiros/reincorporaciones sobre el mismo documento. El ingreso tardío o reincorporación no genera asistencias o faltas anteriores.
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

El contrato, los frames vigentes, las pruebas y los límites se describen en [seguimiento_conjunto_3.md](seguimiento_conjunto_3.md). El usuario informó que desplegó las reglas y el índice y comprobó manualmente el recorrido en el TECNO; [activacion_conjunto_3.md](activacion_conjunto_3.md) conserva los pasos para reproducirlo. Codex no ejecutó esa prueba real. Excel, invitaciones, solicitudes de ingreso, edición general de matrícula, retiros y reincorporaciones permanecían fuera del conjunto 3; el retiro individual con historial se incorpora en el conjunto 5. Asistencia, QR, Bluetooth y reportes siguen fuera de estos conjuntos.

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

## Conjunto funcional 5: retiro y reincorporación con historial

El conjunto 5 conserva `courses/{courseId}/enrollments/{studentUid}` como la única matrícula vigente por curso y estudiante. El documento mantiene su ID, propietario, identidad, snapshots de curso y `createdAt`; estos campos no cambian al retirar o reincorporar. Los valores válidos de `status` son `active` y `withdrawn`. Las matrículas anteriores con `status: 'active'` continúan siendo válidas aunque no tengan metadatos de transición; no requieren migración.

La primera inscripción crea el tramo inicial activo con `createdAt` de servidor. Cada transición confirmada añade un evento en `courses/{courseId}/enrollments/{studentUid}/status_events/{operationId}`. La estructura exacta es:

| Campo | Tipo | Significado |
|---|---|---|
| `fromStatus` | string | Estado previo (`active` o `withdrawn`). |
| `toStatus` | string | Estado nuevo, obligatoriamente distinto y válido. |
| `changedAt` | timestamp | `serverTimestamp()`; las reglas lo cotejan con `request.time`. |
| `changedBy` | string | UID del docente verificado propietario que confirma la transición. |

El documento canónico incluye, después del primer cambio, `lastStatusEventId` (string con el ID del evento) y `lastStatusChangedAt` (timestamp de servidor). Ambos campos son opcionales en inscripciones legacy sin transiciones y aparecen juntos después de cambiar estado. El ID se genera antes de iniciar la transacción y se conserva ante un reintento incierto. Solo se permiten `active → withdrawn` y `withdrawn → active`; cada cambio del estado y su evento se escriben en una sola transacción. Reintentar el último `operationId` no duplica el evento. Reutilizar un ID histórico, confirmar desde una ficha obsoleta o intentar saltarse el estado actual se rechaza. No se borran matrículas ni eventos y los eventos no se editan.

Solo el docente verificado, con perfil válido y propietario del curso puede cambiar estado o consultar la subcolección de historial. Un administrador sin rol docente propietario, un docente de otro curso, una cuenta no verificada y el estudiante no pueden ejecutar transiciones. El estudiante autenticado puede leer puntualmente su matrícula para conocer su estado, pero solo enumera sus matrículas activas mediante una consulta con `studentUid == uid` y `status == 'active'`; no puede leer `status_events`. Las lecturas del curso, sus bloques y horarios requieren matrícula activa. La interfaz quita de memoria el horario del estudiante al actualizar la app, regresar de una ruta o recibir una denegación.

La inscripción manual del conjunto 3 y la solicitud por código del conjunto 4 nunca duplican ni reactivan una matrícula retirada. La inscripción manual devuelve el estado retirado para abrir la ficha existente; un código válido de ese curso informa que el estudiante debe pedir reincorporación al docente. Una aprobación histórica de solicitud no es un camino alternativo para volver a activar la matrícula. La reincorporación docente vuelve a usar el UID de la ruta y conserva las decisiones e historial anteriores.

Las listas del docente filtran `status` antes de paginar: activas y retiradas son vistas separadas; el contador solo cuenta activas. Las materias del estudiante usan la consulta `collectionGroup('enrollments')` con `studentUid` y `status == 'active'`. `firestore.indexes.json` conserva los índices existentes y declara índices para `status ASC, createdAt DESC, __name__ DESC` (alcance `COLLECTION`) y para `studentUid ASC, status ASC, createdAt DESC, __name__ DESC` (alcance `COLLECTION_GROUP`). El historial se ordena por `changedAt DESC` e ID descendente con cursor estable.

El contrato, nodos visuales, cambios de reglas/índices, pruebas y APK están en [seguimiento_conjunto_5.md](seguimiento_conjunto_5.md). El propietario informó que publicó reglas e índices y completó con Firebase real el recorrido de retiro y reincorporación en el TECNO; Codex no hizo ese despliegue ni ejecutó esa prueba. Los pasos para reproducirla y el comando de activación como referencia futura están en [activacion_conjunto_5.md](activacion_conjunto_5.md). El manifiesto conserva el índice previo `COLLECTION_GROUP` de `studentUid ASC, createdAt DESC, __name__ DESC` que ya estaba en la base del conjunto 4 y que no equivale al índice nuevo con `status`; el propietario reportó los siete índices habilitados. Al cerrar el conjunto 5, sesiones, asistencia, retiros masivos y actualizaciones Excel estaban fuera de alcance; los conjuntos 6 y 7 descritos a continuación incorporan la importación y comparación de listas, sin implementar asistencia, métricas o reportes.

## Conjunto funcional 6: altas por archivo Excel

El lector local de `.xls` BIFF8 y `.xlsx` convierte solo `CODIGOESTUDIANTE`, `MAIL_INST` y `NOMBRECOMPLETO` en filas de revisión con su número original. Los demás campos del archivo no entran en los modelos de importación ni en Firestore. El curso de destino siempre es el `Course` abierto por el docente; `FECHAMATRICULA` no altera `createdAt`, que continúa siendo un timestamp del servidor al crear la matrícula.

La revisión consulta el directorio `student_directory/{email}` por correo exacto, coteja el código estudiantil y verifica la matrícula canónica `courses/{courseId}/enrollments/{studentUid}`. La ausencia de entrada se presenta como cuenta no disponible para vincular, sin afirmar que Authentication no tenga esa cuenta. Una fila con datos incompletos, código distinto, identidad repetida, matrícula activa o retirada no se selecciona como alta. No se crean reservas ni vinculaciones futuras; una fila no disponible se puede reevaluar al importar de nuevo después de que la cuenta verificada publique su entrada de directorio.

La confirmación procesa únicamente filas elegibles seleccionadas. Cada alta se escribe mediante `EnrollmentRepository.enrollStudent`, que vuelve a comprobar curso propio, directorio, identidad y matrícula dentro de una transacción individual. La transacción conserva el ID `studentUid` y resuelve una solicitud pendiente junto al alta nueva. Si una matrícula ya existía al confirmar, la importación informa ese estado sin modificarla ni reactivar retirados. No se crea otra fuente de matrícula y el estudiante obtiene lectura del curso y los bloques solo al estar activo. Los resultados por fila permiten éxito parcial y reintentos sin duplicar.

La aplicación usa los permisos e índices existentes del conjunto 5. La separación entre lector, revisión y presentación está documentada en [seguimiento_conjunto_6.md](seguimiento_conjunto_6.md); [activacion_conjunto_6.md](activacion_conjunto_6.md) describe la prueba manual con cuentas controladas. No se añaden sesiones de asistencia, comparación para retiros masivos ni cambios de rol.

## Conjunto funcional 7: actualización de lista e inscripción pendiente

El conjunto 7 reutiliza el parser local `.xls`/`.xlsx` del conjunto 6 y añade la comparación del roster completo, la selección explícita de altas y retiros y una autorización por curso para una persona que todavía no puede vincularse a una cuenta verificada. La pantalla de gestión separa **Actualizar lista con Excel** (recorrido C7) de **Solo agregar estudiantes** (flujo parcial C6). El libro se procesa en el dispositivo; solo se escriben las personas seleccionadas y los campos mínimos de identidad.

### Inscripción sin UID

La ruta es `courses/{courseId}/pending_enrollments/{emailExact}`. `emailExact` es el correo validado y sin espacios exteriores; el ID del documento y `rosterEntryId` usan el mismo correo exacto. Por curso solo puede existir un documento para ese correo. El nombre es un snapshot informativo; el cotejo usa correo y código estudiantil, nunca similitud de nombre. Reimportar la misma identidad devuelve el pendiente sin duplicarlo. Si el correo coincide pero el código difiere, o si una búsqueda limitada encuentra una colisión de código, la interfaz bloquea el alta y pide revisión; no reemplaza el documento.

El documento de autorización usa estos campos:

| Campo | Tipo | Uso |
|---|---|---|
| `courseId`, `ownerUid` | string | Curso y docente propietario que aprobó la fila. |
| `subject`, `group`, `period` | string | Snapshot del curso de destino. |
| `email`, `studentCode`, `name` | string | Identidad mínima cotejada; el nombre es para mostrar. |
| `status` | string | `pending`, `linked` o `withdrawn`. |
| `effectiveStartDate` | timestamp UTC a medianoche | Fecha civil desde la que empieza el tramo del curso. |
| `rosterEntryId` | string | Identidad académica estable; en entradas C7 es el correo exacto, aunque posteriormente cambie el correo de Auth. |
| `studentUid` | string o null | UID asignado solo al vincular. |
| `authorizedAt`, `createdAt`, `updatedAt` | timestamp | Autorización del propietario y creación/última escritura con hora del servidor. |
| `linkedAt` | timestamp o null | Hora de servidor en que se creó el vínculo con el UID. |
| `lastEventId`, `lastStatusChangedAt` | string o timestamp, ambos null inicialmente | Última transición posterior; aparecen juntos. |

La autorización inicial se crea al confirmar el docente y no genera un evento de cambio. Las transiciones posteriores guardan de manera inmutable `courses/{courseId}/pending_enrollments/{emailExact}/status_events/{operationId}` con `fromStatus`, `toStatus`, `effectiveDate`, `changedAt` (server timestamp) y `changedBy`. Solo se permiten `pending → linked`, `pending → withdrawn` y `withdrawn → pending`. El estudiante solo puede causar la primera mediante la vinculación de su propia cuenta; las otras son acciones explícitas del propietario. `linked` es terminal en esta colección: retiros y reincorporaciones después del vínculo usan la matrícula canónica y su historial, nunca crean una segunda fila pendiente.

### Matrícula canónica e historial

`courses/{courseId}/enrollments/{studentUid}` continúa siendo la fuente única de acceso. Las nuevas altas directas y vinculaciones conservan `studentUid` como ID y añaden `rosterEntryId` y `effectiveStartDate`. La fecha efectiva pertenece al tramo académico y se copia desde la autorización; `createdAt` y `updatedAt` siguen siendo auditoría del servidor. Si ya existe una matrícula activa del mismo UID/curso con correo y código coincidentes, el vínculo reutiliza ese documento sin volver a escribirlo. Cuando es un documento C5/C6 legacy sin `rosterEntryId` ni `effectiveStartDate`, Rules y Dart aceptan la pareja ausente y conservan `createdAt`, fecha derivada y snapshot; nunca rellenan metadatos retroactivamente. Una pareja moderna presente debe coincidir con la autorización. Una matrícula `withdrawn` no se reactiva por el vínculo: requiere reincorporación docente explícita.

Los eventos C5 de `status_events/{operationId}` añaden `effectiveDate` al esquema previo (`fromStatus`, `toStatus`, `changedAt`, `changedBy`). Los documentos legacy y eventos antiguos sin `effectiveDate` siguen leyéndose sin migración; la identidad de lectura usa `legacy:{studentUid}` y la fecha civil se deriva del timestamp histórico menos cinco horas (Bogotá UTC−5). No se sobrescribe historial.

Las fechas efectivas son `AcademicDate` civil y se serializan como timestamp UTC a las 00:00; no representan una hora local. Para validar el día actual se convierte la hora del servidor a `America/Bogota` (sin horario de verano). Altas y reincorporaciones deben estar dentro del calendario del curso; para un curso que aún no comienza solo se permite la fecha exacta de inicio, no una fecha futura arbitraria. Un retiro nunca se programa en el futuro. Un cupo o matrícula cuyo inicio todavía es futuro se puede cancelar con fecha efectiva de Bogotá igual o anterior a hoy, dentro del período permitido por las reglas. Una fecha histórica que preceda a la autorización o al último evento válido se rechaza. En el tramo activo, la fecha de ingreso/reincorporación se incluye y la fecha de retiro se excluye. El cambio de acceso ocurre al confirmarse la transacción; no se calculan asistencias ni faltas.

### Comparación, selección y consultas

`features/excel_import/data/` decodifica el archivo; `application/` coteja las filas, compara estados y coordina transacciones individuales; `presentation/` mantiene los pasos de archivo, hoja/columnas, resumen, selección, confirmación y resultados. **Solo agregar** acepta un archivo parcial y no recorre el roster completo. **Comparar lista completa** necesita leer desde servidor todas las páginas de matrículas activas/retiradas y autorizaciones pendientes/retiradas; si una página falla, hay duplicados, filas inválidas o conflicto de identidad, no se ofrecen retiros. Las personas fuera de la hoja se presentan desmarcadas. La selección y la vista previa no escriben. Al confirmar se procesa cada persona en una transacción pequeña y el resultado diferencia guardado, sin cambios, revisión requerida y fallo/sin confirmación; el lote no es atómico.

El docente consulta `courses/{courseId}/pending_enrollments` filtrando `status`, en orden `createdAt DESC, __name__ DESC`, con cursor estable. La consulta del estudiante es de grupo de colección y exige filtros exactos `email == Auth.email`, `studentCode == users/{uid}.studentCode` y `status == 'pending'`, orden `createdAt DESC, __name__ DESC`; procesa páginas reintentables y no enumera perfiles, directorios, códigos ni pendientes ajenos. Los índices añadidos están en `firestore.indexes.json`: `pending_enrollments`, alcance `COLLECTION`, `status ASC, createdAt DESC, __name__ DESC`; y `pending_enrollments`, alcance `COLLECTION_GROUP`, `email ASC, studentCode ASC, status ASC, createdAt DESC, __name__ DESC`. Se conservan los índices previos de `enrollments`, `join_requests` y cursos.

Al entrar a **Mis materias**, la app publica primero el directorio del propio estudiante verificado, busca después pendientes con correo y código exactos y vincula cada autorización elegible en la misma transacción que crea la matrícula canónica. Si el perfil aún no tiene código, el correo no está verificado, una identidad no coincide o hay un fallo de red/permisos, no se crea acceso; el alumno conserva cursos ya cargados y puede volver a intentar. Una vinculación nueva conserva `rosterEntryId`, fecha efectiva y nombre que el docente autorizó. El correo exacto, el código, el UID, el curso y la autorización validan la identidad; el nombre es informativo y nunca bloquea el vínculo ni se usa para sobrescribir un snapshot canónico. Si había solicitud C4 pendiente del mismo UID, se resuelve atómicamente cuando curso y correo/código coinciden con esa autorización, incluso si el nombre descriptivo difiere. No se aprueba una solicitud general en nombre del estudiante.

Las reglas e índices C7 están preparados localmente para activación manual y **no se publican desde esta implementación**. Si el índice de grupo aún está construyéndose, la consulta puede devolver `failed-precondition`; la guía indica esperar a que figure habilitado antes de probar en Firebase real. La implementación no añade Cloud Functions, Storage, servidor ni credenciales administrativas. Aún no genera sesiones o cálculos de asistencia. El contrato y límites están en [seguimiento_conjunto_7.md](seguimiento_conjunto_7.md); la activación manual y el recorrido de verificación en dispositivo están en [activacion_conjunto_7.md](activacion_conjunto_7.md).

La consulta general **Historial de matrícula** se deriva en modo solo lectura del `CourseRosterSnapshot` completo del curso: matrículas canónicas active/withdrawn y autorizaciones pending/withdrawn, cada fuente ya paginada por el repositorio. Una fila usa `rosterEntryId`; los documentos legacy que exponen `legacy:{uid}` usan el UID. Un pendiente `linked` queda representado por su matrícula canónica y no crea otra fila. La vista no lee eventos por cada fila; al abrir el detalle carga el historial canónico y, para una vinculación confirmada cuya relación exacta coincide por curso, UID y `rosterEntryId`, muestra aparte los eventos de autorización previos. El ingreso conserva la fecha efectiva de la matrícula; `createdAt`, `linkedAt` y `changedAt` se mantienen como tiempos de auditoría. No se añade colección, regla ni índice para esta vista.
