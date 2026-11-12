# Pruebas locales de reglas de Firestore

Estas pruebas usan exclusivamente el emulador local y el proyecto ficticio
`demo-aula-presente-firestore-rules-tests`. No autentican contra Firebase ni
publican reglas. Las reglas probadas se leen directamente de `../../firestore.rules`.
El emulador se configura en `firebase.json`; `firestore.indexes.json` contiene
el índice para filtrar solicitudes por estado y ordenarlas por fecha.

Desde la raíz del proyecto, con Node.js 24.12 o posterior, Java 21 o posterior y
Firebase CLI instalados, instala las dependencias y ejecuta las pruebas así:

```powershell
npm ci --prefix tools/firestore_rules_tests
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"
```

La ruta de Java se puede ajustar si el JDK está instalado en otra ubicación.

La suite contiene 70 casos de Rules Unit Testing con el SDK de JavaScript. Conserva
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
y carreras entre decisiones.

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

La ampliación del 9 de noviembre añade el recorrido fiel del repositorio: un índice recién escrito permite lectura del estudiante, pero leer `invitation/current` directamente o en transacción sigue denegado. Esa lectura privada era un defecto en Dart; no se abrió con reglas. Se prueban además vigencia configurable finita, pausa/reactivación, desactivación definitiva, edición sin cambio de código, legacy de 14 días, ficha abierta, historial conservado y docentes ajenos. La configuración efectiva solo vive en `current.validForSeconds`; el índice no replica vencimientos. Las 70 pruebas incluyen las nueve regresiones que antes agotaban expresiones; la última revisión del log registró cero diagnósticos de ese límite.
