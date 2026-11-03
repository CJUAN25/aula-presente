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

La suite contiene 41 casos de Rules Unit Testing con el SDK de JavaScript. Conserva
los permisos de perfiles, `demo_records` y solicitud/aprobación docente; también
cubre cursos padre y la subcolección `weekly_blocks`, creación atómica de hasta
ocho bloques, ocurrencias, solapes, consultas y lecturas privadas por propietario,
timestamps, inmutabilidad e idempotencia. Los perfiles de admin/docente usados
como fixtures se crean solo con `withSecurityRulesDisabled` dentro del emulador.

La suite valida las reglas y el patrón transaccional desde el cliente JS; no ejecuta
el repositorio Dart de Flutter contra el emulador. La serialización canónica de
dominio y el flujo de presentación Flutter tienen pruebas independientes.
