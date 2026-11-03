# Seguimiento del conjunto 1: acceso docente

## Contrato antes de implementar

- La app no concede permisos por una selección del usuario. `users/{uid}.roles` sigue siendo la fuente de autorización; el administrador inicial se prepara manualmente fuera del cliente.
- La solicitud única vive en `teacher_access_requests/{uid}` y conserva la identidad de `users/{uid}` al momento de crearla. Campos exactos: `uid`, `name`, `email`, `studentCode`, `status`, `createdAt`, `decidedBy`, `decidedAt`, `rejectionReason`.
- Alta: `status: pending`, `createdAt: serverTimestamp()`, y campos de decisión nulos. Decisión: solo `pending → approved|rejected`; `decidedBy` y `decidedAt` los fija el administrador autenticado y el servidor. El rechazo exige motivo de 1–500 caracteres. Los documentos decididos son terminales para clientes.
- La aprobación es una escritura atómica de la solicitud y `users/{uid}`. Solo agrega `teacher`, conserva `student` y cualquier otro rol existente, y conserva los demás campos del perfil. Las reglas contrastan el estado final de ambos documentos con `getAfter()`. Un administrador no puede decidir su propia solicitud ni concederse `admin`.
- Contrato Dart acordado para `TeacherAccessRepository`: `getOwnRequest() → Future<TeacherAccessRequest?>`, `watchOwnRequest() → Stream<TeacherAccessRequest?>`, `createOwnRequest() → Future<TeacherAccessRequest>`, `watchPendingRequests() → Stream<List<TeacherAccessRequest>>`, `getReview(requesterUid) → Future<TeacherAccessReview>` y `decideRequest(requesterUid, decision, rejectionReason?) → Future<TeacherAccessRequest>`. El UID propio sale de Firebase Auth; el UID de detalle es solo una solicitud individual. `TeacherAccessDecision` tiene `approve` y `reject`. La presentación no accede a Firebase ni elige roles.
- `TeacherAccessStatus` es `pending|approved|rejected`; `TeacherAccessRequest` contiene los nueve campos del esquema; `TeacherAccessReview` añade `currentName`, `currentEmail`, `currentStudentCode` y `currentRoles`. `TeacherAccessFailureKind` distingue sesión, verificación, perfil, duplicado, no encontrado, resuelto, validación, permisos, red e inesperado.
- Contrato de sesión: `AuthRepository.watchAccess() → Stream<AuthAccess>` refleja cambios de Authentication y del perfil del UID actual; la coordinación cancela/cambia la suscripción al cerrar sesión o cambiar de cuenta y saca de espacios protegidos cuando deja de haber permiso.
- La lista administrativa ordenará por `createdAt` y filtrará por `status`; se prepara el índice compuesto requerido. `firebase.json` conserva toda la configuración FlutterFire y apunta a reglas, índices y emulador local.
- C04 abre únicamente espacios presentes en los roles reales. Un estudiante conserva su perfil y CRUD; un docente autorizado ve su perfil C08D, pero no cursos ficticios; un administrador entra a S04, no a estadísticas de muestra. C12 crea/consulta la solicitud; C13 representa estado real; S04 lista solicitudes pendientes; S05 revisa; S06 confirma aprobación. “Tengo una invitación” explica que ese mecanismo aún no está disponible y ofrece la solicitud.
- Si un usuario no inició sesión o no verificó su correo, la navegación vuelve al paso real de autenticación/verificación y permite retomar después. No se confirman operaciones offline antes de recibir respuesta del servidor. Las suscripciones se limitan al UID o consulta administrativa y se cancelan al cerrar sesión o cambiar de cuenta.

## Propiedad de archivos

| Responsable | Archivos exclusivos de trabajo |
| --- | --- |
| Coordinación e integración | `lib/features/auth/**`, `lib/app/**`, `test/widget_test.dart`, documentación general y `docs/seguimiento_conjunto_1.md` |
| Subagente A: datos y lógica de solicitudes | `lib/features/administration/domain/**`, `application/**`, `data/**`, y pruebas unitarias Dart bajo `test/features/administration/domain/**` y `test/features/administration/application/**` |
| Subagente B: reglas, índices y emulador | `firestore.rules`, `firebase.json`, `firestore.indexes.json`, `tools/firestore_rules_tests/**` (excepto dependencias descargadas) |
| Subagente C: presentación basada en Figma | `lib/features/administration/presentation/**`, y `test/features/administration/presentation/**` |
| Revisor independiente, posterior a integración | Solo lectura; entrega hallazgos antes de que coordinación modifique archivos |

Los subagentes no editarán los archivos de los demás. La coordinación integrará usando el contrato anterior y resolverá conflictos sin reescribir módulos fuera del alcance.

## Línea base observada — 28 de octubre de 2026

- No existe `.git` en la raíz; no es posible producir un `git status` ni un diff confiable. Se inspeccionaron los documentos, reglas, Auth, pruebas, módulo de administración y configuración antes de editar.
- `flutter analyze`: sin problemas (86,9 s).
- `flutter test`: 16 aprobadas.
- `flutter build apk --debug`: compilación correcta (125,1 s); Flutter advierte que Firebase Auth/Core aún usan Kotlin Gradle Plugin y que futuras versiones de Flutter exigirán migración.
- Emulador local de Firestore con el ID ficticio `demo-aula-presente-firestore-rules-tests`: 14 pruebas de reglas aprobadas. No se autenticó ni escribió en Firebase real.
- Herramientas disponibles: Flutter 3.47.1/Dart 3.13.1, Node 24.14.1, Firebase CLI 15.32.1 y JDK 25 de Android Studio.
- Figma leído en la página vigente `01 · Aula Presente · Rediseño` (`25:57`): C04 `30:6`, C08D `30:13`, C12 `2005:10143`, C13 `2005:10231`, S04 `2005:15463`, S05 `2005:15585`, S06 `2006:7339`. Capturas, propiedades visuales y componentes actuales consultados en la sesión de solo lectura; no se editó Figma.

## Bitácora de ejecución

- Coordinación (`/root`): leyó el alcance, el estado real, los documentos, el esquema anterior, el historial de Figma disponible y los siete frames de esta etapa; definió los contratos y esta propiedad de archivos antes de iniciar el trabajo paralelo. Sin `.git`, no se pudo consultar ni generar un diff.
- Subagente A (`/root/teacher_access_data`): terminó modelos, contrato, validación y repositorio Firestore; añadió cuatro pruebas de validación (4/4 aprobadas). Integración revisada por coordinación.
- Subagente B (`/root/teacher_access_rules`): terminó reglas, configuración del emulador, índice compuesto y ampliación de la suite. Primera ejecución ampliada 27/27; tras integrar acceso puntual de admin al perfil vinculado a solicitud pendiente, suite actual 28/28. No desplegó.
- Subagente C (`/root/teacher_access_presentation`): terminó C12/C13/S04/S05/S06 y C08D con estados de carga, vacío, error, confirmación, acceso perdido y repositorios inyectados. Informó 24 pruebas iniciales; la suite creció durante la integración.
- Coordinación: conectó el repositorio al módulo Auth, añadió `watchAccess()` y el guard de roles, corrigió el reintento de perfil para conservar roles, completó pruebas de integración y documentos generales. Corrigió además imports detectados por el primer análisis, ocultamiento de C13 en cambio de cuenta, consulta administrativa restringida a pendientes y espera offline recuperable en C12/S04.
- Revisor independiente (`/root/teacher_access_reviewer`): inspección de solo lectura después de integrar. Encontró la fuga potencial de estado C13, el listado de solicitudes resueltas por admin, la espera indefinida inicial sin conexión y documentación pendiente. Coordinación corrigió los tres primeros hallazgos y actualizó documentación. Revisión adicional señaló avisos de evaluación en escrituras negativas; coordinación eliminó validaciones redundantes y reutilizó lecturas de perfil en variables `let`. La reejecución de 28 pruebas pasó, sin aviso del límite de 1000 expresiones; el emulador aún registra detalles de errores al rechazar las mutaciones inválidas esperadas.

## Cierre — 29 de octubre de 2026

- `flutter analyze`: sin problemas.
- `flutter test`: 48/48 aprobadas, incluidos cambios de cuenta, espera recuperable sin confirmación y vistas en 320/390/430 con texto aumentado.
- Suite de reglas en emulador local con proyecto ficticio: 28/28 aprobadas tras restringir lista y detalle de admin a solicitudes pendientes y simplificar evaluaciones redundantes. No hubo contacto ni despliegue a Firebase real.
- `flutter build apk --debug`: compilación correcta (14,6 s). Se mantiene el aviso de migración a built-in Kotlin para plugins Firebase Auth/Core.
- Sin `.git`, el proyecto no permite producir un diff o `git status` comprobable. No se modificó Figma, no se crearon usuarios y no se ejecutó la app en dispositivo.
- Los pasos de primer administrador y publicación se prepararon en `docs/activacion_acceso_docente.md`; requieren intervención manual autorizada y siguen pendientes.

## Corrección de confirmación de decisiones — 29 de octubre de 2026

### Causa comprobada

`decideRequest()` completaba su transacción atómica y, después, hacía una lectura `Source.server` de `teacher_access_requests/{uid}` para construir la respuesta. Las reglas permiten el `get` administrativo solo mientras `status == 'pending'`; al confirmar la transacción, el estado pasa a `approved` o `rejected` y esa lectura posterior queda denegada. El `permission-denied` de lectura se propagaba como si la decisión hubiera fallado, aunque el cambio ya estaba guardado. A la vez, la consulta S04 filtrada por `pending` elimina la solicitud y C13 del solicitante conserva permiso para observar su propio estado terminal.

Los casos del emulador reproducen ambas mitades de la secuencia: una transacción válida confirma la decisión, la consulta administrativa deja de incluir la solicitud y el `get` individual administrativo posterior falla por las reglas; el usuario solicitante sí puede leer el resultado. Una transacción de un usuario sin rol admin se deniega y conserva `pending`.

### Solución

- El repositorio ahora devuelve una representación del estado terminal desde el callback de la transacción; el `Future` de `runTransaction` solo entrega ese resultado cuando Firestore confirma el commit. Ya no hay lectura administrativa después del cambio de estado.
- La interfaz atrapa únicamente errores de `decideRequest()`. Tras su éxito reemplaza S05 por S06 sin esperar a que la ruta termine; S05 se descarta, la suscripción pendiente de S04 sigue activa y C13 del solicitante mantiene su listener propio.
- Un `permission-denied` de la transacción sigue apareciendo como error de permisos en S05. No se oculta ni se convierte en éxito. La decisión final y el otorgamiento atómico de `teacher` no cambiaron. S06 omite la fecha, porque el timestamp lo fija el servidor y la lectura posterior necesaria para obtenerlo no está autorizada.
- No se modificó `firestore.rules` ni se ampliaron lecturas administrativas; no requiere despliegue de reglas.

### Regresión verificada

| Comprobación | Resultado |
| --- | --- |
| Firestore Emulator: transacción de aprobación, desaparición de S04, lectura admin posterior denegada y resultado propio con `teacher` | Aprobada |
| Firestore Emulator: transacción de rechazo, desaparición de S04, lectura admin posterior denegada y motivo propio | Aprobada |
| Firestore Emulator: decisión por usuario sin rol admin denegada y solicitud aún `pending` | Aprobada |
| Suite total Firestore Emulator | 31/31 aprobadas |
| `flutter analyze` | Aprobado, sin problemas |
| `flutter test` | Aprobado, 49/49 pruebas |
| `flutter build apk --debug` | Aprobado; generó `build/app/outputs/flutter-apk/app-debug.apk` |

Solo se usó el emulador local con el proyecto de prueba ficticio. No se contactó Firebase real, no se crearon solicitudes reales y no se publicaron reglas. La prueba manual en dispositivo y la confirmación de la incidencia en la instancia Firebase real siguen pendientes.
