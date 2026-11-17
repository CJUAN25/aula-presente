# Asistencia manual — conjunto 8

Este módulo implementa asistencia sobre encuentros producidos por el calendario de `schedule`. Un encuentro ordinario mantiene su `PlannedMeeting.id`; las reposiciones conservan esa identidad y las clases adicionales usan una identidad independiente. No se materializa un documento por cada fecha prevista.

## Capas

- `domain/`: modalidad, configuración, encuentros, sesiones, nómina, marcas, proyecciones, eventos y `AttendanceRepository`.
- `application/`: resolución de excepciones, tramos de hasta 60 minutos, pertenencia a la fecha efectiva, validación y cálculo de unidades.
- `data/`: `FirestoreAttendanceRepository` y `AttendanceFirestoreCodec`; derivan el UID desde Auth y solo utilizan Firestore, sin servicio externo.
- `presentation/`: `TeacherAttendanceScreen`, `TeacherAttendanceSessionScreen` y `StudentAttendanceScreen`.

## Flujo

Desde **Detalle del curso → Asistencia → Gestionar**, el docente elige por curso **Por encuentro** o **Por horas**. Los cursos nuevos guardan esa elección en su creación; los anteriores sin `attendance_config/current` requieren elección explícita. El cambio se bloquea después de crear una sesión. En modalidad por horas, el horario se divide en tramos consecutivos de hasta 60 minutos y la marca se aplica al tramo elegido. La marca se escribe al seleccionarla; **Guardar y continuar después** explica que el avance queda guardado, y el docente puede volver al mismo encuentro. Al finalizar, las marcas pendientes se completan o se convierten en ausencias solo después de confirmación explícita.

La preparación usa el roster completo y sus eventos C7 para la fecha efectiva. Una nómina incompleta o un historial ambiguo bloquea la sesión. Las clases pasadas sin registro no se infieren como ocurridas o faltadas: el docente debe elegir **Registrar clase realizada** y escribir un motivo breve. Una sesión futura preparada no permite marcar antes de la hora efectiva de Bogotá. Al cerrar, primero se verifican las filas `staged` y se finaliza la sesión; después cada resultado propio se publica por lotes idempotentes. Esa publicación puede converger en momentos distintos para estudiantes distintos, pero ningún estudiante lee borradores. Si queda pendiente, el docente puede reanudarla con los mismos IDs.

Correcciones, justificaciones ya revisadas y anulaciones posteriores requieren motivo y crean historial. En la vista del estudiante, **Mis materias → materia activa → Consultar asistencia**, solo aparecen proyecciones publicadas de su identidad académica. Una sesión anulada se conserva como aviso sin motivo y se excluye del cálculo.

## Cálculo

El denominador solo suma unidades de sesiones finalizadas que aplican a la matrícula histórica del estudiante. Por encuentro, cada clase es una unidad. Por horas, son minutos realmente registrados; una hora ausente de un bloque de dos horas suma 60 minutos. La falta computable resta cobertura justificada aprobada; las unidades justificadas permanecen en el denominador. Una revisión `inReview` se incluye provisionalmente en el numerador y se muestra como tal. El umbral se evalúa exactamente con `5 × faltas >= unidades`, se redondea solo para mostrar y no calcula nota ni pérdida definitiva.

Las rutas, campos y transiciones exactos están en [arquitectura](../../../docs/arquitectura.md#conjunto-funcional-8-asistencia-manual). Los comandos y límites de pruebas, en [seguimiento C8](../../../docs/seguimiento_conjunto_8.md); la activación y prueba manual en el TECNO están en [activación C8](../../../docs/activacion_conjunto_8.md).

Bluetooth, QR, NFC, ubicación, adjuntos y una bandeja de solicitudes de justificación siguen fuera de este conjunto.

## Corrección tras prueba real

El calendario estudiantil usa una proyección `student_calendar` sin motivos, generada por transacciones del docente y protegida por matrícula activa. La anulación conserva la publicación original de cada fila y elimina sus unidades sin duplicar el evento. El propietario reportó esos flujos funcionando en TECNO. El 16/11 se reprodujo y corrigió el límite de expresiones de Rules al reconciliar una nómina parcial por horas. Una lista incompleta se recupera con **Completar lista**, sobre la misma sesión; iniciar sigue separado de preparar y usa la hora efectiva. La tarjeta abre el registro cuando la lista está lista y ya llegó la hora. Ver seguimiento C8 para evidencia, archivos, pruebas y siguiente paso manual.

La revisión posterior del 16/11 reproduce también un cierre por horas ya `closing`: el validador de proyecciones agotaba 1.000 expresiones. El único `firestore.rules` optimiza esa evaluación sin cambiar el contrato de datos o permisos. El reintento conserva marcas, sesión, una fila por identidad y fecha original de publicación. `AttendanceOperationTrace` mide etapas sin datos personales. El repositorio agrupa hasta seis lecturas independientes y mantiene paginación/revalidaciones; la UI carga colecciones en paralelo, usa páginas de hasta 100 y muestra demoras y errores. Esta corrección necesita las reglas nuevas y la APK recompilada; la prueba real corresponde al propietario.
