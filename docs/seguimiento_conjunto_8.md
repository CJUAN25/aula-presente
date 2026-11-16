# Seguimiento del conjunto 8 — asistencia manual

## Estado de entrega — 16 de noviembre de 2026

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
