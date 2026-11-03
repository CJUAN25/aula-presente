# Horarios

`domain/` representa fechas académicas civiles, bloques semanales y encuentros previstos. Los bloques se persisten como documentos `courses/{courseId}/weekly_blocks/{blockId}` con `weekday`, `startMinute`, `endMinute`, `room` y `order`; el dominio conserva `HH:mm` para la presentación. `application/` valida bloques y conflictos reales entre ocurrencias. La función única `generatePlannedMeetings` alimenta la vista previa, el calendario de un curso y la agenda docente; no crea sesiones ni marca asistencia.

Las fechas se guardan como timestamp UTC a medianoche; los bloques se interpretan en `America/Bogota`. La etapa no incluye festivos, excepciones, reprogramación ni agenda de estudiantes. Véase [docs/arquitectura.md](../../../docs/arquitectura.md).

`checkScheduleConflicts` conserva las entradas y los encuentros de una única evaluación: `overlapPairs` justifica cada cruce, mientras `conflicts` contiene una sola entrada por encuentro candidato estable. El alta y el informe debug consumen esa misma evaluación; no hay un segundo cálculo del calendario para diagnosticar. La exportación se limita a días/fechas/horas y alias, sin los campos privados del curso o de la sesión.
