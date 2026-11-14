# Seguimiento del conjunto 5: retiro y reincorporación

## Alcance y base

La rama `feature/conjunto-5-retiro-y-reincorporacion` parte del commit `75c3b959c644d7674f8235dc19a8b47d6577d1a7` de `feature/conjunto-4-ingreso-por-codigo`. El cierre de esta entrega conserva `main`, la release `v0.1.0-entrega-1` y el historial remoto. Codex no desplegó Firebase durante la implementación ni durante este cierre.

El conjunto 5 permite retirar y reincorporar de forma individual a un estudiante, consultar matrículas activas/retiradas y revisar historial. No incorpora retiros masivos, Excel, edición general de snapshots, cambios retroactivos o programados, sesiones, asistencia, QR, Bluetooth, métricas ni reportes.

## Recorrido visual y Figma

La referencia consultada en modo lectura fue la página vigente `01 · Aula Presente · Rediseño` (`25:57`) del archivo [NUEVA-CORRECION](https://www.figma.com/design/XP9LIZClkFzVNf17jUXjGU/NUEVA-CORRECION). Se ignoraron las páginas archivadas `90 · Archivo · Sistema anterior` y `91 · Archivo · Prototipo anterior`.

| Frame vigente | Nodo | Adaptación |
|---|---|---|
| M01 · Gestionar estudiantes | `2005:12218` | Entrada desde la gestión existente. |
| M14 · Estudiantes del curso | `2005:13829` | Lista activa, búsqueda en la página cargada y acceso a retirados. |
| M18 · Ficha del estudiante | `2005:13979` | Identidad y snapshots reales, estado, ingreso, historial y acción según estado. Omite asistencia. |
| M13 · Retirar estudiante | `2005:13714` | Confirmación, fecha efectiva «Al confirmar», aviso de conservación y botón secundario «Conservar inscripción». |
| M15 · Retirados e histórico | `2005:14115` | Lista paginada real, estados vacío/error y vuelta a activos. |
| M33 · Reincorporar estudiante | `4009:9850` | Confirmación explícita, fecha «Al confirmar» y conservación del historial. |
| M34 · Reincorporación confirmada | `4009:9922` | Resultado confirmado y acción «Ver estudiantes». |
| E02 · Mis materias | `30:18` | Solo matrículas activas. |
| E08 · Mi horario | `30:24` | Horario previsto solo con matrícula activa. |
| M25 · Historial de asistencia | `4006:8346` | Solo patrón de tarjetas; no se muestran asistencias, ausencias ni justificaciones. |

El código reutiliza Manrope, el tema oscuro y los componentes actuales. No se copiaron los nombres o datos ficticios del prototipo. Se añadieron estados de carga, vacío, error y confirmación. Las pruebas de presentación C5 recorren listas activa/retirada y confirmación en 320, 390 y 430 px lógicos con escala de texto 1.6. No se hizo comparación pixel a pixel entre un render Flutter y las capturas de Figma. Codex no ejecutó la app en TECNO CM6; el propietario reportó después la prueba real descrita al cierre de este documento.

## Esquema persistido

La fuente canónica sigue siendo `courses/{courseId}/enrollments/{studentUid}`; el UID permanece como ID. Campos existentes que no cambian: `studentUid`, `ownerUid`, `name`, `email`, `studentCode`, `subject`, `group`, `period`, `createdAt`. `status` vale `active` o `withdrawn`. Las matrículas antiguas `active` sin campos nuevos son válidas; no se requiere migración.

Después del primer cambio se añaden juntos `lastStatusEventId` (string) y `lastStatusChangedAt` (timestamp). Cada transición escribe un documento inmutable en `courses/{courseId}/enrollments/{studentUid}/status_events/{operationId}` con los campos exactos `fromStatus`, `toStatus`, `changedAt` (timestamp) y `changedBy` (UID del docente). `changedAt` y `lastStatusChangedAt` usan timestamp de servidor. El evento registra `active → withdrawn` o `withdrawn → active`; `createdAt` sigue siendo el inicio del tramo original. Los eventos se consultan por fecha descendente con páginas estables; la presentación añade el ingreso original al final, después de cargar la última página, y solo si `createdAt` tiene un timestamp real.

El cliente genera `operationId` antes de entrar en la transacción y conserva el mismo ID para reintentar un resultado de red incierto. La transacción comprueba estado, marcadores de versión e identidad del curso; actualiza solo estado y marcadores y crea el evento en el mismo commit. Si ya se confirmó ese ID y sigue siendo el último evento, responde idempotentemente; si la ficha quedó obsoleta o el ID pertenece a un ciclo anterior, rechaza sin repetir la decisión. Navegación y mensajes se ejecutan después de la confirmación, nunca dentro del callback que Firestore puede reintentar.

Las reglas permiten transiciones solo al docente verificado, con perfil válido y propietario del curso. No se concede a `admin` sin rol propietario, estudiantes, docentes ajenos o no verificados. `getAfter()` vincula el cambio de matrícula a la creación del evento correspondiente; ambos documentos validan estado, actor, fecha, ID y campos permitidos. Se prohíbe borrar matrícula o editar/eliminar eventos. El estudiante solo consulta su propia matrícula por ID y listas filtradas a `active`; no lee historial. Los cursos y bloques siguen disponibles para estudiantes solo mientras el vínculo esté activo.

## Consultas e índices

- Docente, activos: subcolección `enrollments`, `status == 'active'`, `createdAt DESC`, ID DESC. El contador solo cuenta activos.
- Docente, retirados: misma subcolección con `status == 'withdrawn'`, orden y cursor estables. Historial por `changedAt DESC`, ID descendente.
- Estudiante: `collectionGroup('enrollments')` filtrada por `studentUid == uid` y `status == 'active'`; no enumera matrículas retiradas.
- `firestore.indexes.json` declara los índices de activos/retirados (`status ASC, createdAt DESC, __name__ DESC`, alcance `COLLECTION`) y del estudiante (`studentUid ASC, status ASC, createdAt DESC, __name__ DESC`, alcance `COLLECTION_GROUP`). También conserva el índice anterior de grupo de colección `studentUid ASC, createdAt DESC, __name__ DESC` (incluido `__name__ DESC`), que ya existía en la base del conjunto 4 y no equivale al índice nuevo que filtra por `status`.

Durante la activación Firebase avisó que ese índice anterior estaba en la nube pero faltaba en el manifiesto local. El propietario respondió **No** a eliminarlo y después confirmó que los siete índices aparecían **Habilitados** en la consola. Se reincorporó aquí su declaración exacta desde el commit base para alinear el repositorio; no se borró ningún índice ni se hizo otro despliegue.

La lista no descarga todos los registros para buscar: la búsqueda de la pantalla docente actúa sobre elementos ya cargados y su interfaz lo indica. Activos y retirados se consultan separadamente con cursores propios.

## Comportamiento de los conjuntos 3 y 4

La inscripción manual de una matrícula activa sigue devolviendo «ya inscrito». Si está retirada, se devuelve el mismo documento y la ficha ofrece reincorporarla de forma explícita; no se crea una segunda inscripción ni se cambia estado desde el flujo manual. Si se introduce un código válido para un curso donde la cuenta está retirada, se informa que debe solicitar al docente la reincorporación. No se crea otra `join_request`. La aprobación histórica de una solicitud nunca reabre una matrícula retirada; la decisión previa tampoco se reescribe.

La baja no modifica curso, horario o bloques ni afecta otras materias, roles o matrículas. El estudiante vuelve a consultar su estado al regresar a una ruta y al reanudar la app; las pantallas de curso/calendario borran los datos mostrados mientras comprueban de nuevo. El detalle de un encuentro también revalida su matrícula.

## Ubicación de responsabilidades

| Módulo/ruta | Responsabilidad |
|---|---|
| `lib/features/enrollments/domain/` | Modelo `Enrollment`, estados/resultado de cambio, eventos, cursores/páginas y errores. |
| `lib/features/enrollments/data/firestore_enrollment_repository.dart` | UID Auth, transacciones de cambio, historial, filtros, conteo y lectura propia/propietario. |
| `lib/features/enrollments/presentation/teacher_enrollment_screens.dart` | Activos, retirados, detalle, confirmaciones, reincorporación, historial y resultado. |
| `lib/features/enrollments/presentation/student_enrollment_screens.dart` | Materias, horario de materias y comprobación al regresar/reanudar. |
| `lib/features/course_entry/data/` y `presentation/` | Resultados `alreadyWithdrawn` y mensaje de matrícula retirada en el ingreso por código; aprobación no reincorpora. |
| `lib/features/courses/presentation/course_detail_screen.dart` | Calendario compartido: vuelve a validar estudiante al abrir, regresar o reanudar y no muestra eventos al perder acceso. El recorrido de docente no cambia. |
| `lib/app/enrollment_route_observer.dart` y `lib/app/aula_presente_app.dart` | Observador de navegación de la app para revalidar acceso al volver de otra ruta. |
| `firestore.rules`, `firestore.indexes.json` | Autoridad de permiso y necesidades de consulta; requieren publicación manual para Firebase real. |
| `tools/firestore_rules_tests/` | Pruebas de seguridad y transacciones con datos ficticios en Firestore Emulator. |

## Revisión independiente y correcciones

Un revisor independiente comprobó reglas, transacciones, índices, consultas, inscripción manual/código/aprobación del conjunto 4, caché de estudiante y pantallas. Los hallazgos se corrigieron y se cubrieron con regresiones:

- La lectura puntual `getCourseEnrollment` requería antes rol docente para todos. Ahora una rama valida perfil `student` y `studentUid == auth.uid`; otra valida `teacher` y `ownerUid == auth.uid`. No se mezclan roles con el UID de la otra parte. Se añadieron casos permitidos y denegados.
- El historial consultaba eventos de más nuevo a más antiguo, pero colocaba el ingreso inicial encima de ellos. El ingreso original ahora aparece al final y solo cuando todas las páginas están cargadas.
- Retiro/reincorporación muestran la fecha **«Al confirmar»** y explican que se usa tiempo del servidor. La aprobación histórica se titula «Solicitud aprobada» o «Aprobación histórica», sin afirmar acceso actual si la matrícula está retirada.
- El hub docente recarga el conteo activo al volver de retirados después de reincorporar.
- Se añadieron pruebas de reglas para sesión anónima y reutilización de `operationId` tras un ciclo; de datos para dos ciclos completos con cuatro IDs; y de calendario para limpiar la vista si la lectura recibe `permission-denied`.

El revisor no encontró otro bypass ni una reactivación desde inscripción manual, código o aprobación histórica. No ejecutó Firebase real, el teléfono ni una comparación pixel a pixel.

| Comprobación | Resultado final |
|---|---|
| `flutter analyze` | Aprobado sin problemas en la ejecución local reportada por Codex antes de este cierre. |
| `flutter test --reporter expanded` | Aprobado: 195/195 en la ejecución local reportada por Codex. Incluye repositorio, presentación, dos ciclos completos, aprobación histórica y revocación del calendario. |
| Firestore Emulator, proyecto ficticio `demo-aula-presente-firestore-rules-tests` | Aprobado: 74/74 en la ejecución local reportada por Codex, con Firebase CLI 15.32.1 y Firestore Emulator 1.22.0. Incluye actor anónimo, reuso de ID tras un ciclo y cuatro transiciones con `createdAt` conservado. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` y JSON de `firestore.indexes.json` | Aprobados en la ejecución previa y el JSON se volvió a validar durante este cierre. |
| `git diff --check` | Aprobado previamente y vuelto a ejecutar durante este cierre. Git solo avisó que convertirá LF a CRLF en archivos cambiados en Windows. |
| Widgets C5 adaptables | Aprobados previamente por Codex en 320/390/430 px lógicos con escala 1.6; listas activa/retirada y confirmación sin excepciones de layout. |
| `flutter build apk --debug` | Aprobado en la ejecución local reportada por Codex. `build/app/outputs/flutter-apk/app-debug.apk`, 226,372,526 bytes. |

En este cierre se repitieron la validación del JSON de índices y `git diff --check`; no se repitieron `flutter analyze`, las pruebas Flutter, las pruebas del emulador ni la compilación porque los cambios de cierre son documentación y la declaración de un índice ya existente en la nube.

**Prueba real informada por el propietario:** después del despliegue, realizó en el TECNO con Firebase real el recorrido completo. El docente retiró y reincorporó al estudiante; se conservó el historial de la matrícula y el estudiante perdió y recuperó el acceso a la misma materia y a su horario. Codex no ejecutó ni observó esa prueba.

El emulador usó proyecto ficticio y reglas locales; Codex no publicó reglas o índices ni contactó Firestore real. La prueba en el TECNO y Firebase real es un reporte del propietario, no una ejecución de Codex. La comparación visual pixel a pixel sigue sin realizarse. Los pasos para reproducir la activación y el recorrido están en [activacion_conjunto_5.md](activacion_conjunto_5.md).
