# Seguimiento del conjunto 8 — asistencia manual

## Incidente de cierre — punto de partida del 16/11/2026

Verificados antes de editar: rama `feature/conjunto-8-asistencia-manual`, HEAD `bed4ac83fd1d82b53080df0af1d2dc467208d4e4`, remoto `https://github.com/CJUAN25/aula-presente.git` y `git status --short` vacío.

El propietario publicó manualmente las reglas de su VS Code en `aula-presente-movil-juan-2026`, base `(default)`. La versión exacta publicada y la APK instalada siguen por confirmar. En Lógica reprogramada al **16/11/2026 06:00–08:00**, **Por horas**, pudo entrar y alcanzar **Finalizando**, pero **Continuar finalización** devuelve `permission-denied`. También hay esperas largas en **Preparar lista**, **Completar lista** y **Ver lista**. Codex no ejecutó esos recorridos ni inspeccionó datos reales. No se presupone que sea el mismo fallo de preparación documentado abajo.

Esta revisión reprodujo y corrigió el cierre y midió las etapas antes de optimizar, como se detalla a continuación. La publicación y la prueba en TECNO quedan a cargo del propietario. Los apartados posteriores a esta revisión conservan resultados históricos.

### Causa comprobada del cierre

La prueba nueva `C8 closing rescheduled minutes` parte de una sesión **ya `closing/ready`**, reprogramada del 05/11 al **16/11/2026 06:00–08:00**, con dos tramos de 60 minutos y marcas existentes. Usa exclusivamente identidades sintéticas y Firestore Emulator con proyecto `demo-aula-presente-firestore-rules-tests`.

Con las reglas del HEAD inicial, la primera llamada equivalente a `_stageRecords` falla con `permission-denied`: el `create` de **`courses/course/attendance_records/course|block|2026-11-05|student@example.test`**, junto con el incremento de versión de **`courses/course/attendance_sessions/course|block|2026-11-05`**, supera **1.000 expresiones**. El log señala `validAttendanceRecordSegmentAt` (línea 2768 del archivo inicial) y el `allow create` de `attendance_records` (3363). No era un rechazo de la fecha reprogramada ni faltaba permiso docente en esa reproducción. El padre queda en `closing`, sin publicar resultados. Evidencia local ignorada por Git: `build/c8-closing-before.log`.

El validador de **proyecciones** seguía evaluando 24 posiciones aunque solo hubiera dos tramos; era distinto del validador de **nómina** corregido previamente. La publicación `staged → published` y el `get` propio del estudiante también necesitaban margen de evaluación. El ajuste conserva un único `firestore.rules`:

- Corta la cola al tamaño real de segmentos y valida directamente cada segmento presente.
- Reutiliza valores de unidades/horas y evita listas de claves duplicadas. Todos los campos obligatorios se acceden y validan; una clave faltante deniega, y la lista exacta de claves permitidas se conserva.
- Evita ocho comparaciones de identidad/horario ya garantizadas por `diff().affectedKeys().hasOnly(...)` en **cada** rama permitida. Publicar solo cambia visibilidad, fecha de publicación y actualización.
- Evalúa primero las condiciones que rechazan borradores, identidades ajenas o transiciones inválidas. El chequeo docente descarta primero perfiles sin `teacher`, conservando la misma validación completa de perfil/correo para quien sí tiene el rol. Esto evita que el `get` estudiantil gaste el presupuesto en una rama docente que no le corresponde.

La regresión cubre **2 y 12 estudiantes**, lotes de hasta 10, interrupción después de preparar la primera proyección, reintento sin incrementar versión cuando no faltan filas, cierre del mismo padre y publicación repetida sin duplicados ni cambio de `publishedAt`. Compara la nómina y las marcas antes/después. Un control separado en `inProgress` prueba las dos marcas del propietario verificado; el fixture de recuperación permanece ya en `closing`. Estudiante y docente ajeno no pueden registrar. El estudiante consulta y obtiene solo su fila publicada; no lee otra identidad, nómina, eventos o borradores ni escribe resultados. También se rechazan claves faltantes/extra, marcas inválidas, exceso de unidades, horario/identidad alterados y creación sin versión atómica del padre.

La prueba Dart `resumes the same closing rescheduled hours session after a denied stage` ejecuta el repositorio real sobre un adaptador controlado: fuerza el rechazo al preparar resultados, verifica el diagnóstico de etapa, reabre el repositorio, finaliza y conserva las dos marcas y un resultado por persona. No equivale a ejecutar FlutterFire en Android contra el emulador. La causa está probada localmente; su correspondencia exacta con los documentos y reglas publicados en Firebase real sigue pendiente.

### Medición de esperas y cambios del cliente

Se añadió `AttendanceOperationTrace`: cronometra etapas con `Stopwatch`, emite `[C8] operación / etapa: N ms` solo en debug y admite un observador en pruebas. Las etiquetas no contienen IDs, nombres, correos, marcas ni motivos. Se registran también las etapas que fallan. Un rechazo al cerrar identifica ahora, por ejemplo, **preparar resultados privados (permission-denied)**.

Medición reproducible del **repositorio Dart**, con 12 estudiantes sintéticos, dos tramos y **5 ms de latencia artificial por lectura**, antes/después en esta sesión:

| Acción/etapa | Antes (ms) | Después (ms) |
| --- | ---: | ---: |
| Preparar: cuenta / borrador / modalidad | 18 / 7 / 9 | 11 / 7 / 7 |
| Preparar: matrículas e historial | 268 | 65 |
| Preparar: transacción inicial | 56 | 34 |
| Preparar: tramos / nómina | 23 / 110 | 16 / 45 |
| Preparar: revalidación de fuentes / confirmar lista | 84 / 37 | 21 / 33 |
| **Preparar total** | **622** | **247** |
| Completar: matrículas e historial | 246 | 54 |
| Completar: nómina / revalidación de fuentes | 101 / 80 | 35 / 20 |
| **Completar total** | **520** | **199** |
| **Ver lista y tramos** | **43** | **23** |
| Comprobar publicación al abrir una finalizada (12 filas publicadas, por encuentro) | **300** | **102** |

Son muestras locales, no promedios, garantías de tiempo ni mediciones de Internet/Firebase real/TECNO. Las pequeñas etapas varían con el equipo; las diferencias grandes se explican por las esperas seriales eliminadas. Logs: `build/c8-latency-before.log`, `build/c8-latency-after.log`, `build/c8-finalized-latency-before.log`, `build/c8-finalized-latency-after.log` (ignorados por Git).

Los historiales y vínculos de personas distintas ahora se leen en ventanas de **hasta seis**, con todas sus páginas en orden. Las lecturas independientes dentro de una transacción se lanzan juntas, siempre antes de escribir; los chunks de escritura siguen ordenados y limitados a 10. Las verificaciones de resultados se hacen en ventanas de seis. La pantalla consulta nómina/tramos/eventos en paralelo, omite tramos en modo por encuentro y solicita hasta 100 filas por página para evitar repetir cuenta/sesión cada 25 personas.

**Se conserva** la resolución por fecha efectiva, las tres comprobaciones del snapshot por preparación, los chequeos posteriores de vínculos, la revisión completa de marcas/resultados y las barreras de versión. En el ensayo de preparar+completar permanecen **6 snapshots, 24 consultas de historial y 72 lecturas de vínculos**; no se presenta como una reducción de lecturas en ese caso. Se reutiliza un historial de autorización exacta si ya fue leído en la misma operación, sin caché entre reintentos. Un error de historial sigue bloqueando `ready`; la prueba comprueba ese bloqueo y la concurrencia máxima. No se abren consultas estudiantiles adicionales ni cambia el índice.

Preparar/Completar y la carga/guardado del detalle muestran progreso; después de ocho segundos indican que la operación tarda y cuentan el tiempo. El avance confirmado se conserva y el error al abrir queda visible en pantalla, además del diagnóstico. No se abandona una escritura por un timeout de interfaz ni se anuncia éxito por una lectura parcial.

### Verificación de esta revisión

Resultados nuevos de esta sesión:

| Comprobación | Resultado y alcance |
| --- | --- |
| `flutter analyze` | Sin problemas. |
| Pruebas Flutter dirigidas | **57/57**, incluyendo recuperación de cierre por horas, fallo de historial concurrente, demora/error visible y presentación a 320/390/430 px con texto ampliado. No se repitió toda la suite Flutter. |
| Suite completa Firestore Emulator | **101/101**; incluye los dos casos nuevos de cierre de 2/12 estudiantes, control de marcas del dueño y permisos previos. **0** diagnósticos `maximum of 1000 expressions` en `firestore-debug.log` de esta ejecución final. Los `permission-denied` de casos negativos son esperados. |
| JavaScript y diff | `node --check` y `git diff --check` aprobados; Git avisa de normalización LF/CRLF sin errores de whitespace. |
| `flutter build apk --debug` | Aprobado; APK local recompilada, sin instalar. Gradle conserva un aviso de compatibilidad futura de plugins con Built-in Kotlin; no impidió la compilación. |

La suite usa el SDK JS contra el emulador y transacciones equivalentes a Dart. Las pruebas Dart ejecutan el repositorio con adaptadores controlados; las mediciones con 5 ms artificiales no usan red ni constituyen FlutterFire en Android contra el emulador. No se contactó Firebase real ni se operó el TECNO. Evidencia local: `build/c8-rules-full.log`, `build/c8-flutter-tests.log`, `build/c8-analyze.log` y `build/c8-apk.log`.

Comandos desde la raíz:

```powershell
flutter analyze
flutter test test/features/attendance test/features/courses/presentation/student_course_access_test.dart --reporter expanded
flutter test test/features/attendance/data/firestore_attendance_repository_test.dart --plain-name 'C8 latency profile' --reporter expanded
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "npm test --prefix tools/firestore_rules_tests"
# Solo la regresión del cierre:
firebase emulators:exec --only firestore --project demo-aula-presente-firestore-rules-tests "node --test --test-concurrency=1 --test-name-pattern=C8.closing.rescheduled tools/firestore_rules_tests/firestore_rules.test.js"
node --check tools/firestore_rules_tests/firestore_rules.test.js
git diff --check
flutter build apk --debug
```

### APK, reglas y repetición exacta en el TECNO

**Hace falta publicar las reglas nuevas e instalar la APK recompilada**, porque cambiaron tanto Rules como el cliente. Esta sesión ya compiló `build/app/outputs/flutter-apk/app-debug.apk`: **218.911.055 bytes**, SHA-256 **`2605B40076B58E6BFA7BD090BC76A8204168CA9A1626C61BEC2ABA5C98F4AC62`**. El único `firestore.rules` local tiene SHA-256 **`F8C9C9E7557DA55739F5884582DA342F16B7C9D200E5538657157ACF877DF6E5`**. Son huellas de los archivos locales de esta revisión, no de los artefactos anteriores usados por el propietario. `HEAD` sigue siendo la base inicial: estos cambios están en el árbol de trabajo, sin commit/push.

1. Como propietario, publica **solo** este `firestore.rules` revisado en `aula-presente-movil-juan-2026`, base `(default)`. Registra la hora/versión de la publicación y confirma que corresponde al archivo completo de esta revisión. No se modificaron índices; conserva `attendance_records` habilitado.
2. Instala la APK indicada sobre la app existente y registra su huella/versión. No borres datos, anules ni recrees sesiones para esta recuperación.
3. Con el docente verificado dueño de Lógica: **Mis cursos → Lógica → Asistencia → Gestionar**. Selecciona la ocurrencia original **05/11**, reprogramada al **16/11/2026 06:00–08:00**, **Por horas**. No elijas la otra clase del 16/11.
4. En la tarjeta **Finalizando**, pulsa **Continuar cierre** y, dentro, **Continuar finalización**. Comprueba que las marcas de 06:00–07:00 y 07:00–08:00 se conservan y que termina en **Finalizada**. Si había pendientes, revisa la confirmación explícita antes de convertirlas en ausencias. Si la publicación queda pendiente, reinténtala en la misma sesión.
5. Sal y vuelve a **Ver asistencia**: debe seguir siendo el mismo encuentro, con las mismas marcas y una sola proyección por estudiante. Comprueba por separado que la clase normal del 16/11 sigue distinta.
6. Con una cuenta estudiante ya verificada y con matrícula activa, abre **Mis materias → Lógica → Consultar asistencia**. Debe aparecer solo su resultado publicado y coincidir con sus marcas. En el caso sintético ausente/presente serían 60 minutos ausentes de 120; en el curso real compara con las marcas que realmente tenía. Otra cuenta solo ve su propio resultado, si lo tiene.
7. Mide desde cada pulsación hasta el resultado: **Preparar lista**, **Completar lista** y **Ver asistencia/lista**; usa un encuentro de ensayo para preparación, sin alterar la nómina cerrada de Lógica. Anota tamaño de lista, modalidad, acción, segundos, resultado y versión de APK/reglas. El mensaje de demora debe mantenerse hasta terminar o mostrar el error. Si falla, comparte etapa y código de **Diagnóstico**, sin datos personales; los logs `[C8]` permiten separar las etapas en la APK debug.

La publicación y todos estos pasos manuales son del propietario y continúan pendientes. No se ejecutó `firebase deploy`, no se crearon cuentas reales ni se enviaron correos.

## Antecedente de entrega — 16 de noviembre de 2026

La rama `feature/conjunto-8-asistencia-manual`, basada en el cierre C7 `55b9336bb39ea157345a2f659e4876bfbf5f938f`, contiene el módulo de asistencia, la integración con cursos y matrícula, las reglas de C8, las pruebas y esta documentación. Está preparada para revisión de código. La corrección de reintento pasó las verificaciones locales, pero falta probar esta APK concreta en el TECNO; por eso no se declara terminada la validación real del conjunto.

El repo es `CJUAN25/aula-presente`. Para identificar el commit de esta entrega usa `git rev-parse HEAD` estando en la rama indicada. El cierre se comparte como rama de trabajo y no modifica `main` ni la release anterior.

## Hallazgos y correcciones

### Reintentar una nómina incompleta

El 16/11 el propietario reportó `permission-denied` al reintentar las sesiones del 12/11 → 15/11 10:00–12:00, 05/11 → 16/11 06:00–08:00 y una clase normal del 16/11 10:00–12:00. La etiqueta “Preparada / Reintentar preparación” indicaba un estado incompleto, pero no demostraba que las tres sesiones tuvieran una misma causa. No se inspeccionaron ni repararon sus documentos reales.

Flutter conserva el ID estable de la ocurrencia y revalida la matrícula a la fecha efectiva. Al recuperar una sesión `preparing/building`, reconcilia filas que faltan y refresca la identidad de filas existentes solo si aún no tienen marcas. No crea otra sesión, no cambia marcas previas ni fusiona dos clases del mismo día.

En el emulador, una reproducción de la transacción real con dos tramos de 60 minutos agotó el límite de 1.000 expresiones de Rules. Los validadores recorrían repetidamente 24 posiciones posibles aunque la clase solo tuviera dos tramos. La regla ahora valida una vez la fila resultante y corta la evaluación anidada al conteo real de tramos. La propiedad, el rol, la verificación, las marcas y las claves exactas siguen protegidos.

Se reprodujo además un fallo distinto: si la matrícula cambiaba durante una preparación incompleta, el conteo guardado al iniciar no coincidía con la lista revalidada y Rules no permitía confirmarla. Se permite cambiar el conteo solo al pasar de `preparing/building` a `preparing/ready`, con cero marcas y todas las filas pendientes. Después de `ready`, el conteo vuelve a ser inmutable. El repositorio verifica las fuentes y filas antes de confirmar.

El motivo tardío usa la fecha y hora efectivas en `America/Bogota`. Un borrador iniciado a tiempo puede reanudarse después sin pedir un motivo nuevo. Si una preparación antigua quedó sin motivo y empezó tarde o no conserva su fecha de creación, la app solicita el motivo; Rules permite completar ese campo una sola vez en la misma sesión incompleta.

### Acción principal de la lista docente

La tarjeta refleja el estado persistido. Una lista incompleta se muestra como **Lista incompleta → Completar lista**, nunca como “Preparada”. Al alcanzar la hora efectiva, la acción conduce al registro; una clase futura permite preparar la lista y no iniciar marcas antes de tiempo. Continuar sesión/cierre, ver asistencia o completar anulación se ofrecen según el estado. Reprogramar, cancelar y anular permanecen como opciones secundarias. Los errores técnicos se consultan en **Diagnóstico**.

### Otros fallos C8 cubiertos en el mismo conjunto

La integración mantiene el flujo de borrador/publicación/corrección y la consulta propia del estudiante. También incluye reanudación de anulación sin cambiar `publishedAt` ni duplicar el evento, y la proyección mínima `student_calendar` para mostrar Cancelada/Reprogramada sin motivos internos ni acceso a cursos ajenos. La cancelación no suma ausencia ni unidades.

## Archivos y comportamiento clave

- `lib/features/attendance/`: dominio, validación, repositorio Firestore, sesión de docente, consulta del estudiante y lista de clases.
- `lib/app/attendance_repository_scope.dart`, `lib/app/aula_presente_app.dart` y `lib/features/courses/presentation/course_detail_screen.dart`: conexión de Asistencia con el curso.
- `lib/features/courses/**`, `lib/features/enrollments/**` y `lib/features/course_entry/**`: selección de modalidad al crear curso y datos de matrícula/historial usados por la nómina en la fecha efectiva.
- `firestore.rules`: permisos y transiciones de asistencia, calendario de estudiante, preparación y recuperación.
- `firestore.indexes.json`: índice compuesto `attendance_records` con `rosterEntryId ASC`, `visibility ASC`, `effectiveDate DESC` y `__name__ DESC` para la consulta publicada del estudiante.
- `test/features/attendance/**` y `tools/firestore_rules_tests/firestore_rules.test.js`: regresiones de cálculo, repositorio, presentación y permisos.
- `docs/arquitectura.md`, `docs/activacion_conjunto_8.md` y este seguimiento: esquema, activación y recorrido retomable.

## Verificaciones locales

Resultados de la corrección C8 del 16/11, anteriores a este cambio de README y seguimiento:

| Comprobación | Resultado | Alcance |
| --- | --- | --- |
| `flutter analyze` | Aprobado, sin problemas | Análisis estático de la rama. |
| `flutter test test/features/attendance test/features/courses/presentation/student_course_access_test.dart --reporter expanded` | **53/53** | Pruebas afectadas: reintento, estados de tarjeta, publicación, corrección, consulta, calendario y anulación. No se repitió toda la suite Flutter en esa corrección. |
| Firestore Rules Emulator | **99/99** | Incluye clase normal, las dos reprogramadas, conteo al completar, publicación, permisos del estudiante y denegaciones esperadas. No accede a Firebase real. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` | Aprobado | Sintaxis del conjunto JavaScript. |
| `flutter build apk --debug` | Aprobado | APK en `build/app/outputs/flutter-apk/app-debug.apk`. No se instaló en un teléfono. |
| `git diff --check` | Aprobado en la corrección C8 | En esta publicación documental se vuelve a ejecutar. |

La suite de permisos usa el emulador local `demo-aula-presente-firestore-rules-tests`. Sus SDK JavaScript ejecutan operaciones equivalentes; las pruebas Dart usan repositorios controlados. No son una prueba de FlutterFire contra producción. La guía de comandos y dependencias está en [pruebas de reglas](../tools/firestore_rules_tests/README.md).

## Firebase real y prueba manual

El propietario reportó que en TECNO con Firebase real ya funcionan guardar borrador, publicar, consultar como estudiante, corregir Ausente → Presente, recuperar una anulación y ver cambios de calendario. Codex no ejecutó la app en el TECNO ni alteró documentos reales. Aún falta repetir con la APK final el reintento de las sesiones del 15 y 16 indicado abajo.

El proyecto es `aula-presente-movil-juan-2026`, base `(default)`. El propietario reportó que el índice `attendance_records` aparece **Habilitado**. El manifiesto C8 lo declara; la corrección de reintento no modificó índices. No despliegues índices si la entrada correspondiente sigue habilitada.

La corrección posterior del 16/11 sí cambió `firestore.rules`. La última publicación que Codex consultó en solo lectura era anterior a esta corrección; no se verificó un despliegue posterior. Para probar el ajuste contra Firebase real, una persona autorizada debe publicar el `firestore.rules` de esta rama. En este cierre no se desplegaron reglas ni índices, no se crearon cuentas y no se modificaron datos reales.

## Siguiente acción exacta en el TECNO

1. Publica únicamente el `firestore.rules` de esta rama en el proyecto indicado, cuando la persona autorizada haya revisado el diff. Conserva el índice que ya aparece habilitado; no hace falta ejecutar un despliegue de índices para esta corrección.
2. Instala `build/app/outputs/flutter-apk/app-debug.apk` compilada desde esta rama.
3. Abre el mismo curso y selecciona por fecha **efectiva** y hora: 15/11 10:00–12:00 (reprogramada desde el 12/11), 16/11 06:00–08:00 (desde el 05/11) y la clase normal 16/11 10:00–12:00.
4. En cada sesión que muestre lista incompleta, pulsa **Completar lista**. No borres, anules ni recrees sesiones. Si la app solicita motivo tardío, complétalo; el motivo guardado se reutiliza. Comprueba que las marcas previas y los estudiantes se conserven y que las dos clases del 16 sigan separadas.
5. Completa las marcas, finaliza y consulta el registro propio desde la cuenta estudiante. Anota qué encuentro se probó. Si vuelve a fallar, abre **Diagnóstico** y comparte solo la etapa y el código, sin nombres, correos ni códigos de estudiante.

La guía paso a paso para el recorrido docente/estudiante está en [activación C8](activacion_conjunto_8.md). La prueba manual de la APK corregida y la confirmación de las reglas activas son los pendientes; no se deben presentar como verificaciones realizadas por Codex.
