# Pruebas locales de reglas de Firestore

Revisión del 17/11/2026: **109/109**. Se conservaron las dos regresiones del parche de corrección de la segunda hora finalizada (normal/reprogramada), y se añadieron solicitudes por encuentro/horas con decisiones idempotentes, matrícula/roles, restauración interrumpida y privacidad/inmutabilidad del historial de calendario. No se consultó ni publicó Firebase real para estas pruebas. La APK y guía del propietario están en `docs/seguimiento_conjunto_8.md`.

Estas pruebas usan exclusivamente el emulador local y el proyecto ficticio
`demo-aula-presente-firestore-rules-tests`. No autentican contra Firebase ni
publican reglas. Las reglas probadas se leen directamente de `../../firestore.rules`.
El emulador se configura en `firebase.json`; `firestore.indexes.json` contiene
los índices compuestos de solicitudes, cursos, matrículas y listas filtradas por
estado.

Desde la raíz del proyecto, con Node.js 24.12 o posterior, Java 21 o posterior y
Firebase CLI instalados, instala las dependencias y ejecuta las pruebas así:

```powershell
npm ci --prefix tools/firestore_rules_tests
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"
```

La ruta de Java se puede ajustar si el JDK está instalado en otra ubicación.

La suite contiene 75 casos de Rules Unit Testing con el SDK de JavaScript. Conserva
los permisos de perfiles, `demo_records` y solicitud/aprobación docente; también
cubre cursos padre y la subcolección `weekly_blocks`, creación atómica de hasta
ocho bloques, ocurrencias, solapes, consultas y lecturas privadas por propietario,
timestamps, inmutabilidad e idempotencia. El conjunto 3 añade publicación de un
directorio de correo exacto sin enumeración, inscripciones únicas bajo cursos,
consulta de grupo filtrada por UID, conteos, paginación y acceso del estudiante al
curso y a sus bloques; prueba identidades falsas, roles insuficientes, entradas
obsoletas y código estudiantil opcional. Los perfiles de admin/docente usados
como fixtures se crean solo con `withSecurityRulesDisabled` dentro del emulador.
El conjunto 4 cubre creación y colisión de invitaciones sin sobrescritura,
renovación, desactivación y expiración calculada con `request.time`; vista mínima
por código exacto; solicitudes propias, filtros/índices y aislamiento; validación
de identidad, snapshots y estado inicial; aprobación/rechazo atómicos e inmutables;
matrícula manual con solicitud pending y preservación de decisiones rechazadas;
y carreras entre decisiones. El conjunto 5 prueba las transiciones atómicas
`active → withdrawn` y `withdrawn → active`, eventos de historial inmutables,
preservación del snapshot y la fecha de creación, rol y propiedad del docente,
revalidación del acceso del estudiante y rechazo de solicitudes por código o
aprobaciones que intenten reactivar una inscripción retirada.

La línea base anterior reportó el máximo de 1.000 expresiones del emulador en las
pruebas de publicación/recuperación del directorio, creación/validación e
inmutabilidad de matrículas del conjunto 3, colisión de invitaciones, matrícula
aislada sin aprobación y matrícula manual que no resolvía una solicitud pending.
`firestore.rules` se simplificó y ordenó conservando propiedad, identidad,
verificación, consistencia y atomicidad. Los casos negativos que alcanzaban el
límite ahora usan `assertPermissionDenied`, que exige exactamente el código
`permission-denied`; los escenarios válidos equivalentes siguen usando
`assertSucceeds`. La prueba de colisión compara crear un código único con
intentar uno ya usado por otro curso. Aprobación e inscripción manual comparan
la escritura aislada denegada con la transacción conjunta permitida.

En la última verificación local, la suite completa pasó 70/70 en Firestore Emulator
1.22.0, con Firebase CLI 15.32.1 y el proyecto ficticio indicado arriba. La
revisión del log no encontró el diagnóstico `maximum of 1000 expressions`.
Estos resultados son solo del emulador; no se ha desplegado ni probado el cambio
contra Firebase real.

La suite valida las reglas y el patrón transaccional desde el cliente JS; no ejecuta
el repositorio Dart de Flutter contra el emulador. La serialización canónica de
dominio y el flujo de presentación Flutter tienen pruebas independientes.

La ampliación del 9 de noviembre añade el recorrido fiel del repositorio: un índice recién escrito permite lectura del estudiante, pero leer `invitation/current` directamente o en transacción sigue denegado. Esa lectura privada era un defecto en Dart; no se abrió con reglas. Se prueban además vigencia configurable finita, pausa/reactivación, desactivación definitiva, edición sin cambio de código, legacy de 14 días, ficha abierta, historial conservado y docentes ajenos. La configuración efectiva solo vive en `current.validForSeconds`; el índice no replica vencimientos. Las 70 pruebas de esa revisión incluyeron las nueve regresiones que antes agotaban expresiones; la revisión del log registró cero diagnósticos de ese límite.

En la verificación local del conjunto 5, `firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"` pasó 74/74 con Firestore Emulator 1.22.0, Firebase CLI 15.32.1, Node.js 24.14.1 y el JBR local 25.0.2. Codex solo probó reglas e índices en el emulador; el propietario informó después que los desplegó y validó el recorrido en Firebase real y el TECNO.

El conjunto 6 añade un caso que reproduce la confirmación de un alta desde un correo exacto ya publicado: antes de la transacción, el estudiante no lee el curso ni sus bloques; después accede a ambos, mientras una cuenta no seleccionada sigue sin acceso. Repetir el alta devuelve la matrícula existente, conserva `createdAt` y no crea un segundo documento. La suite pasó **75/75** el 14 de noviembre de 2026 con el proyecto ficticio anterior. Esta prueba usa el SDK JavaScript y el patrón transaccional canónico; no ejecuta FlutterFire contra el emulador. No se cambiaron reglas ni índices para el conjunto 6.

## Conjunto 7: autorizaciones pendientes de lista completa

La ampliación local añade pruebas de la transacción del docente que crea una autorización bajo `courses/{courseId}/pending_enrollments/{emailExact}`, asociada con una lista completa válida; una lectura parcial o una fila ambigua no permite retiros. También prueba acceso del estudiante con correo/código exactos, vínculo atómico a la matrícula canónica, evento inmutable, solicitudes C4 coincidentes, rechazo de identidades/estados incoherentes y compatibilidad con matrículas C5/C6 legacy sin migrarlas. Los índices nuevos son uno de alcance `COLLECTION` para la consulta docente y otro `COLLECTION_GROUP` para la consulta del estudiante; no se abren enumeraciones generales.

El 14 de noviembre de 2026 la suite completa pasó **80/80** con Firestore Emulator 1.22.0, Firebase CLI 15.32.1, Node.js 24.14.1 y el JBR local 25.0.2. El subconjunto C5 pasó 2/2 y el C7 5/5. La ejecución final no registró `maximum of 1000 expressions`; el helper rechaza explícitamente ese diagnóstico aunque el SDK lo presente como `permission-denied`. El proyecto sigue siendo `demo-aula-presente-firestore-rules-tests` y esta prueba no contacta Firebase real.

La suite de Rules usa el SDK JavaScript y prueba permisos/patrones de transacción; **no ejecuta el repositorio Dart de Flutter contra Firestore Emulator**. Los repositorios y pantallas Flutter tienen pruebas separadas. La verificación real del índice, el despliegue y el flujo en el TECNO CM6 siguen pendientes del propietario.

## Conjunto 8: asistencia manual

En la revisión del cierre atascado del 16/11/2026, la suite completa pasó **101/101**, con **0** diagnósticos de límite de 1.000 expresiones en la ejecución final. Los casos `C8 closing rescheduled minutes` parten de una sesión ya `closing/ready`, reprogramada del 05/11 al 16/11 06:00–08:00, con dos tramos, marcas existentes y 2/12 estudiantes sintéticos. Reanudan preparación de proyecciones y publicación en chunks de hasta 10, sin cambiar marcas, duplicar filas o reemplazar `publishedAt`; prueban también las marcas del propietario y los rechazos de identidad/horario/shape/permisos. La reproducción inicial falló al crear la proyección por agotar expresiones. Causa, comandos, medidas del repositorio Dart con latencia artificial y límites de esas mediciones están en [seguimiento C8](../../docs/seguimiento_conjunto_8.md). No se desplegó Firebase ni se ejecutó FlutterFire en un teléfono.

La ampliación C8 verifica acceso docente propietario a configuración, sesiones, segmentos, nómina, eventos y proyecciones; creación de sesión vinculada atómicamente a la configuración; marcas, cierre, publicación después de `finalized`, consulta por el estudiante con filtros de `rosterEntryId` propio y `visibility == 'published'`, correcciones, revisión de justificación y anulación. La consulta estudiantil es por fila, de modo que las proyecciones se vuelven disponibles de forma eventual sin listar datos ajenos. En la verificación del 15 de noviembre de 2026, la suite completa pasó **91/91** con Firestore Emulator 1.22.0, Firebase CLI 15.32.1, Node.js 24.14.1 y JBR 25.0.2. Incluye los escenarios previos de perfiles, solicitudes, invitaciones, matrículas y autorizaciones pendientes de C4/C7. La suite prueba reglas y transacciones con el SDK JS, no ejecuta el repositorio Dart ni consulta Firebase real.
