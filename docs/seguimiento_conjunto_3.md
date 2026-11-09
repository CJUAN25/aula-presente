# Seguimiento del conjunto 3: inscripción manual

## Contrato compartido fijado antes del trabajo paralelo

**Estado de cierre:** implementación y verificaciones locales completas. El usuario informó que publicó las reglas y el índice en `aula-presente-movil-juan-2026`, vio el índice `enrollments` **Habilitado** y comprobó manualmente en el TECNO que el recorrido del conjunto 3 funciona. Codex no ejecutó ese despliegue ni la app en el teléfono.

### Recorrido y Figma

La página vigente de Figma es `01 · Aula Presente · Rediseño` (`25:57`). El recorrido docente usa D03 (`30:36`) → M01 (`2005:12218`) → M14 (`2005:13829`) → M08 (`2005:13023`) → revisión de identidad → M24 (`4006:8274`) → M14. M09 (`2005:13141`) es el estado de **datos en conflicto** (código y correo diferentes), no una confirmación positiva; la confirmación positiva se adapta con los componentes de M08/M24. E02 (`30:18`) lista materias del estudiante, E03 (`30:19`) muestra detalle y E08 (`30:24`) horario; reutilizan el calendario previsto de D04 (`30:37`). M14 contiene ejemplos de personas pendientes y funciones de retiro todavía fuera de alcance: solo se muestran inscritos reales y acciones disponibles.

| Frame vigente, nombre exacto | ID | Uso en la app |
| --- | --- | --- |
| D03 · Bases de Datos · Grupo 2 | `30:36` | Punto de entrada desde el curso docente. |
| M01 · Gestionar estudiantes | `2005:12218` | Gestión del grupo y cantidad real. |
| M14 · Estudiantes del curso | `2005:13829` | Lista paginada real y estado vacío. |
| M08 · Agregar estudiante | `2005:13023` | Formulario y revisión adaptada a la cuenta encontrada. |
| M09 · Revisar coincidencia | `2005:13141` | Variante de conflicto entre código y correo. |
| M24 · Inscripción confirmada | `4006:8274` | Resultado tras confirmar la transacción. |
| E02 · Mis materias | `30:18` | Lista real de inscripciones del estudiante. |
| E03 · Programación Móvil | `30:19` | Patrón de detalle; el nombre se sustituye por el curso real. |
| E08 · Mi horario | `30:24` | Horario y encuentros previstos de cursos inscritos. |
| D04 · Calendario del curso | `30:37` | Calendario previsto reutilizado para el detalle autorizado. |

Los frames tienen referencia de 390×844, tipografía Manrope, fondo `#031310`, superficie `#0B2420`, cristal `#214039`, primario `#65F4C8`, texto `#F4FAF7`, secundario `#B7CCC4`, borde `#55736A` e información `#83C6FA`. Se reutilizan `AppTheme` y componentes existentes; los iconos SVG visibles se toman de los recursos locales o de sus exportaciones exactas de la página vigente. M08 muestra código, correo, nombre y fecha de ingreso: como el código es opcional en los perfiles previos, el correo exacto identifica la cuenta, el código escrito se coteja si existe y el nombre procede de la búsqueda; la fecha efectiva se fija mediante timestamp de servidor al confirmar. Las secciones de Excel, invitación, retiro, asistencia y métricas de los mockups se etiquetan como futuras o se omiten para no simular resultados.

### Datos y permisos

- `student_directory/{email}` es un índice auxiliar de búsqueda **exacta** por correo de Authentication. No admite `list`. El documento contiene exactamente `uid`, `name`, `email`, `studentCode` (string o null) y `updatedAt` (servidor). Lo publica/actualiza su propia cuenta con `student` y correo verificado, copiando el perfil `users/{uid}`. Un docente autorizado puede hacer `get` de un correo conocido. Las reglas cotejan la entrada con el perfil actual para impedir lecturas de entradas desactualizadas. La app no descarga ni enumera perfiles. La fecha de actualización de la entrada no acredita identidad institucional; nombre y código son datos declarados por la cuenta.
- Las cuentas anteriores se incorporan al directorio al entrar de nuevo en el espacio estudiante con la versión nueva. Si una entrada falta, el docente informa que el estudiante debe abrir ese espacio con su cuenta verificada. Una cuenta sin `studentCode` sigue siendo localizable por correo; si el docente proporciona código, debe coincidir exactamente, conservando ceros. El correo se usa con la misma forma exacta del token y del perfil; no se publica una variante normalizada adicional. Una entrada antigua tras cambio de correo no es legible por un docente porque ya no coincide con el perfil. El nuevo titular verificado puede recuperar ese ID al publicar su perfil vigente, pero no puede sustituir la entrada de un titular todavía vigente. Este índice revela a un docente autorizado la existencia y los datos básicos de un correo que conoce; no se usa para búsqueda amplia.
- La **fuente de verdad** es `courses/{courseId}/enrollments/{studentUid}`. ID estable: UID del estudiante dentro del curso; una combinación curso–estudiante solo tiene un documento. Campos exactos: `studentUid`, `ownerUid`, `name`, `email`, `studentCode` (string o null), `subject`, `group`, `period`, `status` (`active`) y `createdAt` (`serverTimestamp()`). Los datos personales y del curso son snapshots cotejados por reglas con el directorio/perfil y el curso inmutable. No se actualizan ni se retiran en este conjunto. El ingreso efectivo es la fecha de servidor de creación; no se generan faltas de asistencia.
- Solo un docente con correo verificado, perfil válido y rol `teacher` puede crear en un curso cuyo `ownerUid` sea suyo. El estudiante no puede crear ni modificar matrículas. `admin` por sí solo no otorga gestión académica. El estudiante con rol `student` y correo verificado lee únicamente sus matrículas; esto se aplica también a la consulta `collectionGroup('enrollments').where('studentUid', isEqualTo: uid)`. El docente lista la subcolección de un curso propio. El estudiante puede leer el curso y sus `weekly_blocks` si existe su inscripción activa; ninguna escritura del curso o los bloques se habilita por ello. El perfil privado `users` sigue sin permitir `list`.
- La creación usa una transacción: valida sesión y perfil docente, lee curso e inscripción por ID; si ya existe la inscripción devuelve `alreadyEnrolled` sin escribir ni incrementar contadores. Para una inscripción nueva lee también la entrada del directorio y comprueba que la identidad revisada sigue vigente; crea el único documento con timestamp de servidor. El resultado confirmado de la transacción se devuelve sin lectura posterior. Un timeout tiene resultado incierto y la UI ofrece consultar la lista/reintentar con el mismo ID, sin asumir reversión. No hay contador materializado: las cantidades se calculan a partir de documentos reales.
- La lista docente se pagina por `createdAt DESC, __name__ DESC` dentro del curso. La lista estudiante usa `collectionGroup` filtrado por `studentUid` y el mismo orden; requiere índice compuesto de grupo para UID, fecha e ID. Los curso(s) previos siguen con esquema intacto. El detalle lee padre y bloques y usa `generatePlannedMeetings`, sin materializar sesiones.

### Contrato Dart de integración

`StudentCandidate(uid, name, email, studentCode)` identifica la cuenta revisada; `Enrollment(courseId, studentUid, ownerUid, name, email, studentCode, subject, group, period, status, createdAt)` representa el documento persistido. `EnrollmentCursor(createdAt, documentPath)`, `EnrollmentPage(items, nextCursor/hasMore)` y `EnrollmentResult(enrollment, alreadyEnrolled)` cubren paginación e idempotencia. `EnrollmentRepository` ofrece `ensureStudentDirectoryEntry()`, `findStudentByEmail(email)`, `enrollStudent(courseId, candidate)`, `listCourseStudents(courseId, cursor, pageSize)`, `listMyCourses(cursor, pageSize)`, `getMyEnrolledCourse(courseId)` y `countCourseStudents(courseId)`. El repositorio deriva siempre el UID de Firebase Auth; una selección de interfaz nunca autoriza por sí sola la escritura. El `get` de detalle reconstruye el curso con sus hijos bajo el permiso de matrícula.

### Responsables de implementación

| Tarea | Archivos asignados | Estado |
| --- | --- | --- |
| Dominio/datos | `lib/features/enrollments/{domain,application,data}/**`, pruebas asociadas; lectura de curso en `lib/features/courses/data/firestore_course_repository.dart` | Implementado y probado con respuestas controladas del SDK Dart. |
| Reglas/índices | `firestore.rules`, `firestore.indexes.json`, `tools/firestore_rules_tests/**` | Implementados; 51/51 casos aprobados con emulador y proyecto ficticio. El usuario reportó su despliegue y el índice habilitado. |
| Presentación | `lib/features/enrollments/presentation/**`, integración en `lib/app/**`, `lib/features/auth/presentation/auth_screens.dart`, `lib/features/courses/presentation/course_detail_screen.dart`, pruebas de interfaz | Implementada; ocho pruebas nuevas de recorrido, sesión, fallo posterior al guardado y tamaños de pantalla. |
| Coordinación | Contratos, `README.md`, `AGENTS.md`, `docs/**`, README de módulos, integración y verificación | Integrado y verificado localmente. |
| Revisión | Código, reglas, consultas, flujos y regresiones integrados | Revisados durante la integración; no se hizo ejecución en Firebase real ni en dispositivo. |

### Resultado de la integración

El docente llega desde el detalle de un curso propio a «Gestionar» → «Lista de estudiantes» → «Agregar estudiante». Escribe un correo exacto y, opcionalmente, un código; revisa la identidad recuperada antes de confirmar. La escritura confirmada abre el estado positivo y la lista se vuelve a consultar por separado. El formulario distingue datos no encontrados, código discordante, falta de permiso y red. Un cambio de sesión tras confirmar no vuelve a ejecutar la transacción ni expone la lista de la cuenta anterior. La vista del estudiante ofrece «Mis materias», detalle de curso, horario semanal y calendario previsto calculado con el generador existente. Las entradas futuras de Excel, invitación, retiro y vinculación con código quedan señaladas como posteriores.

| Comprobación | Resultado local |
| --- | --- |
| `flutter analyze` | Aprobado; sin problemas. |
| `flutter test --reporter expanded` | Aprobado; 120 pruebas, incluidas ocho nuevas de presentación y las de datos y dominio. |
| Firestore Emulator (`demo-aula-presente-firestore-rules-tests`) | Aprobado; 51/51 pruebas de reglas y transacciones JS. Incluye privacidad, rol, duplicados, índice de búsqueda exacta y recuperación de un correo liberado. |
| `flutter build apk --debug` | Aprobado; `build/app/outputs/flutter-apk/app-debug.apk`. Avisos no bloqueantes de acceso nativo Java y Kotlin Gradle Plugin de Firebase. |

El emulador ejecutó Rules Unit Testing con el SDK JavaScript; las pruebas Flutter usaron respuestas controladas del SDK y repositorios de presentación. La regresión de Flutter comprueba que una escritura confirmada conserva el éxito aunque falle la lectura posterior de la lista; esa lectura muestra su propio error y permite reintentar sin escribir de nuevo. No se ejecutó el repositorio FlutterFire Dart contra el emulador Android: ese entorno no ofrecía un emulador Android disponible. Estas son comprobaciones locales de Codex, anteriores al cierre.

### Validación real informada por el usuario

El usuario comunicó que el despliegue de reglas e índice del conjunto 3 terminó correctamente en el proyecto `aula-presente-movil-juan-2026`, que la consola mostró el índice `enrollments` **Habilitado**, y que siguió la guía en el TECNO y comprobó que el conjunto funciona correctamente. Es una **prueba manual reportada por el usuario** contra Firebase real. No se registraron resultados individuales por escenario, capturas ni trazas para atribuirlos a una ejecución de Codex. La guía queda como referencia para repetir el recorrido: [activacion_conjunto_3.md](activacion_conjunto_3.md).
