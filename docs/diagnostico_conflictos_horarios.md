# Diagnóstico del aviso persistente de horarios — 2 de noviembre de 2026

## Evidencia y estado

El usuario informó inicialmente que solo tenía Móvil guardado con lunes/viernes y que intentaba crear Lógica los martes/jueves 08:00–09:00. Después confirmó que el horario real de Móvil es **lunes 08:00–10:00 y martes 06:00–10:00**. Acortar el período había cambiado el conteo anunciado de 17 a 13. La captura mostraba, detrás del aviso de 13, jueves 19/11/2026 y martes 24/11/2026 a las 08:00–09:00.

Al preparar la herramienta, la causa del aviso real todavía no estaba demostrada. El informe recibido posteriormente permite explicar el aviso, como se detalla a continuación. No se ha consultado Firebase real ni ejecutado la app en el teléfono durante esta investigación.

## Resultado del informe recibido

El JSON que obtuvo el usuario en la app tiene versión `aula-schedule-2026-11-02-v1`, un curso existente y el período inclusivo 2026-11-01 a 2027-02-28 en ambos horarios. Sus entradas son:

| Origen | Bloque | Día recibido | Hora |
| --- | --- | --- | --- |
| Borrador (Lógica según el usuario) | 1 | 2 = martes | 08:00–09:00 |
| Borrador | 2 | 4 = jueves | 08:00–09:00 |
| Curso existente (Móvil según el usuario) | 1 | 1 = lunes | 08:00–10:00 |
| Curso existente | 2 | **2 = martes** | **06:00–10:00** |

**Causa inmediata demostrada:** el comparador recibe el segundo bloque del curso existente como martes, no como viernes. El informe contiene exactamente 17 parejas, todas entre el bloque 1 del borrador y el bloque 2 del curso existente en martes. No contiene comparaciones del borrador consigo mismo (`sameIdAsDraft: false`, cursos distintos en cada pareja), jueves ni duplicación de parejas para un mismo encuentro. Por ejemplo, el 03/11/2026 el candidato 08:00–09:00 cruza el existente 06:00–10:00. Los otros martes son 10/11, 17/11, 24/11, 01/12, 08/12, 15/12, 22/12, 29/12, 05/01, 12/01, 19/01, 26/01, 02/02, 09/02, 16/02 y 23/02.

El conteo de 17 es correcto **para esas entradas**. El usuario confirmó después que Móvil efectivamente tiene lunes 08:00–10:00 y martes 06:00–10:00, en concordancia con el informe. Queda explicado el caso como un solapamiento real de martes; no hay evidencia de una conversión de viernes a martes. La referencia inicial a viernes no correspondía al horario confirmado. El informe contiene valores Dart reconstruidos; el repositorio lee `value['weekday']` y lo entrega directamente a `WeeklyBlock.weekday`, sin remapeo. El documento Firestore sin procesar no se inspeccionó en esta sesión.

Se añadió una regresión con estos valores y fechas: reproduce 17 cruces; al cambiar exclusivamente el día del segundo bloque a 5 (viernes) en los datos sintéticos, devuelve cero. Otra prueba recorre el formulario actual: selecciona lunes 08:00–10:00 y viernes 06:00–10:00, vuelve a revisión y comprueba el borrador entregado al repositorio y sus documentos canónicos con días `[1, 5]` y minutos `[480, 360]` a `[600, 600]`. Pasó sin cambiar el código de la app. No se ha reproducido que el formulario actual convierta viernes en martes.

**Cierre de este caso:** el aviso funciona correctamente para los horarios confirmados. Se conservan detector, cursos, permisos y reglas. No hace falta otra extracción ni una corrección de datos por esta incidencia. El aviso es informativo: el usuario puede cancelar o elegir **Crear de todos modos** si desea conservar ambos cursos solapados. Una futura modificación de horarios guardados necesita un alcance nuevo porque la app no ofrece edición de cursos en esta entrega.

## Recorrido comprobado y cambio preparado

El formulario guarda el día ISO 1–7 y la hora en formato 24 h; el borrador conserva sus IDs. La vista previa y el comparador usan `generatePlannedMeetings`. El repositorio deriva el UID desde Auth, comprueba el perfil, consulta todos los padres propios del servidor y carga los hijos de cada padre por `order`; reconstruye `weekday`, minutos y fechas civiles UTC. El detector omite el ID del propio borrador, agrupa por fecha académica y aplica solapamiento estricto. `_saving` impide comprobaciones simultáneas y cambios del borrador durante la consulta. El repositorio comprueba que siga la misma cuenta y la presentación comprueba `mounted` antes de mostrar el resultado.

Para obtener la evidencia se añadió una herramienta debug de solo lectura. `checkScheduleConflicts` devuelve una evaluación con las entradas, los encuentros que generó, todas las parejas de solapamiento y el conteo de candidatos distintos. El diálogo de creación y su diagnóstico usan **la misma evaluación**, sin otra consulta ni otro cálculo del calendario. `findScheduleConflicts` conserva su contrato anterior como acceso al conteo deduplicado de esa evaluación. La regla de comparación y el guardado transaccional no cambiaron.

En **Revisar calendario**, el botón **Diagnosticar sin guardar (debug)** consulta la agenda y abre el informe sin llamar a `createCourse`, incluso si no hay conflictos. En un aviso abierto al crear, **Ver diagnóstico** muestra las entradas exactas de ese aviso. Ambas entradas están bajo `kDebugMode`; no aparecen en profile/release. El informe se mantiene en memoria y solo se copia al portapapeles al pulsar **Copiar diagnóstico**. No escribe archivos ni envía registros a un servicio.

## Captura del informe (procedimiento ya completado por el usuario)

1. Ejecuta de nuevo el proyecto desde VS Code con **Run/Debug en modo debug**, como en tu prueba anterior. Esta investigación no ejecutó ni instaló nada en el teléfono.
2. Abre el detalle de Móvil y comprueba los días y las horas que muestra después de actualizar cursos. No lo modifiques.
3. Prepara el borrador de Lógica y llega a **Revisar calendario**. Conserva el período y los bloques que provocan el aviso.
4. Pulsa **Diagnosticar sin guardar (debug)**. No necesitas pulsar **Crear curso** ni **Crear de todos modos**. La acción no crea ni modifica cursos.
5. Pulsa **Copiar diagnóstico** y pega aquí el texto completo. El informe contiene la marca `aula-schedule-2026-11-02-v1`, fechas, días ISO, minutos, encuentros y coincidencias. Usa alias `draft`, `course-1`, `block-1`, etc. Omite nombres de asignaturas, grupo, programa, período de texto libre, aula, correos, UID, IDs reales de documentos, tokens y credenciales. Con un único curso recuperado, `course-1` es ese curso. Los alias conservan la igualdad de IDs: un curso cuyo ID sea el del borrador aparece como `draft` y con `sameIdAsDraft: true`.
6. Si ya apareció el aviso al intentar crear, pulsa **Ver diagnóstico** dentro de ese mismo aviso y copia ese informe. Así se conserva exactamente la comprobación que originó el número, aunque los datos cambien después. Al volver, el aviso conserva sus opciones; puedes cancelar.

La herramienta usa los permisos actuales del docente y las consultas normales del repositorio. Un error de red/permisos se muestra como error recuperable; no se exporta como si fueran cero cursos. Si cambió la cuenta o se cerró el flujo mientras cargaba, se descarta ese resultado.

## Cómo leer la evidencia

- `candidate.blocks` y `candidateMeetings`: horario e instancias concretas del borrador usado al pulsar el botón.
- `existingCourseCount` y `existingCourses`: número y horarios que devolvió el repositorio; `sameIdAsDraft` y `excludedFromComparison` indican si se recibió el propio borrador y se omitió.
- `existingMeetings`: encuentros generados desde esos cursos, enlazados a sus alias de curso/bloque.
- `overlapPairs`: cada pareja concreta que el detector consideró solapada, con fecha, curso, bloque e intervalo de cada lado. `affectedCandidateMeetingCount` es el número que usa el aviso; `overlapPairCount` puede ser mayor cuando un candidato cruza varios cursos.

El informe contiene **valores Dart ya reconstruidos**, no documentos Firestore sin procesar. Si Móvil llega como días 1/5 y Lógica como 2/4, no debe haber parejas; si los horarios recuperados difieren, el informe permitirá localizar esa discrepancia antes de decidir si hace falta revisar documentos o la conversión nativa. No se cambiarán cursos ni se ampliarán permisos por una hipótesis. Si el resultado de solo lectura difiere de un aviso posterior, copia también el diagnóstico de ese aviso para comparar ambas instantáneas.

## Archivos y pruebas

- `lib/features/schedule/application/schedule_conflict_detector.dart`: evaluación única y testigos de todas las coincidencias; mantiene el conteo por candidato estable.
- `lib/features/schedule/application/schedule_conflict_diagnostic.dart`: exportación JSON mediante campos permitidos y alias locales.
- `lib/features/courses/presentation/course_creation_flow.dart` y `course_schedule_diagnostic_screen.dart`: comprobación de solo lectura, acceso debug y copia explícita del informe.
- `test/features/courses/data/firestore_course_repository_schedule_test.dart`: ejecuta el repositorio Dart real y su decodificador privado con fronteras del SDK controladas. Comprueba bloques de documentos hijos lunes/viernes → cero con martes/jueves; respuesta sintética de días coincidentes → fechas exactas; paginación; lectura fallida; cambio de cuenta. No es una prueba del SDK nativo ni de Firebase real.
- `test/features/schedule/schedule_conflict_diagnostic_test.dart`: origen de cada pareja, conteo distinto, omisión del propio ID y exclusión de datos privados.
- `test/features/courses/presentation/course_creation_conflict_test.dart`: conserva las regresiones anteriores y comprueba diagnóstico sin escritura, copia, coherencia con el aviso y descarte de lectura tardía al cerrar el flujo.
- Documentación actualizada: este archivo, `docs/seguimiento_conjunto_2.md`, `docs/estado_actual.md`, `docs/activacion_conjunto_2.md`, `docs/arquitectura.md`, `lib/features/courses/README.md` y `lib/features/schedule/README.md`.

No se modificaron reglas, índices, dependencias ni configuración Firebase. No requiere despliegue. Tras recibir el informe solo se añadieron las dos regresiones indicadas y se actualizó documentación; no hubo cambio funcional en la app ni modificación de cursos. Las pruebas locales no reemplazan la inspección del documento real o la validación del usuario en Android.

## Verificación al preparar la herramienta

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Sin problemas. |
| `flutter test --reporter expanded` | 106 pruebas aprobadas, incluidas las 11 nuevas de repositorio, informe y presentación. |
| `flutter build apk --debug` | APK generada en `build/app/outputs/flutter-apk/app-debug.apk`. Avisos no bloqueantes de Java y KGP en plugins Firebase. |
| Firebase Emulator / Firebase real / TECNO | No ejecutados. No cambiaron reglas, consultas ni escrituras; las nuevas pruebas controlan las respuestas del SDK al repositorio Dart. La reproducción nativa y el informe del teléfono quedan pendientes. |

## Verificación tras recibir el informe

`flutter analyze` terminó sin problemas y `flutter test --reporter expanded` aprobó 108 pruebas. Las dos regresiones nuevas pasaron con la implementación actual: los datos recibidos producen 17 cruces, el horario sintético con viernes produce cero y la selección lunes/viernes del formulario conserva el día y las horas hasta la carga canónica de guardado. No se recompiló la APK porque el código productivo no cambió; tampoco se ejecutaron Firebase real, el emulador ni el teléfono.

Los únicos archivos modificados en esta continuación son `test/features/schedule/schedule_conflict_detector_test.dart`, `test/features/courses/presentation/course_creation_conflict_test.dart`, `docs/diagnostico_conflictos_horarios.md`, `docs/seguimiento_conjunto_2.md`, `docs/estado_actual.md` y `docs/activacion_conjunto_2.md`.
