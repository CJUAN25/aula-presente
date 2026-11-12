# Cursos

En este módulo se crea, lista y consulta el agregado `courses/{courseId}` para el docente propietario. El padre guarda metadatos y `weeklyBlockIds`; `courses/{courseId}/weekly_blocks/{blockId}` contiene cada bloque en minutos enteros y orden canónico. Ambos se guardan en un solo commit. `domain/` contiene modelos, serialización canónica, contrato de repositorio y fallos tipados; `application/` valida y normaliza borradores; `data/` implementa Firestore, paginación por UID, carga de subcolección y creación transaccional idempotente; `presentation/` contiene el espacio docente, alta, vista previa y detalle de solo consulta.

El propietario se deriva de Firebase Auth. El cliente no edita ni elimina cursos guardados en esta etapa. Firestore Rules valida el padre, la presencia y orden de todos los hijos y la relación con los bloques vecinos. Campos, reglas, límites y estrategia de reintento están documentados en [docs/arquitectura.md](../../../docs/arquitectura.md) y [docs/seguimiento_conjunto_2.md](../../../docs/seguimiento_conjunto_2.md).

En modo debug, la revisión ofrece **Diagnosticar sin guardar (debug)** y el aviso ofrece **Ver diagnóstico**. Permiten copiar los valores consumidos por el comparador sin crear cursos ni exportar identificadores reales o datos de perfil. Procedimiento y estado pendiente: [diagnóstico de horarios](../../../docs/diagnostico_conflictos_horarios.md).

El conjunto 3 enlaza el detalle del curso docente con la gestión de estudiantes. La inscripción y sus consultas viven en [`enrollments`](../enrollments/README.md); el padre y los bloques del curso siguen siendo la fuente de información del calendario. El estudiante solo obtiene acceso de lectura a un curso en el que está inscrito.

El conjunto 4 añade invitaciones temporales y decisiones de acceso mediante [`course_entry`](../course_entry/README.md). El código solo permite solicitar; la matrícula sigue en `enrollments` y el horario permanece protegido hasta que exista ese documento canónico.
