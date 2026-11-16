# Módulos del producto

Cada carpeta delimita una función. Las capas de presentación, lógica de negocio y acceso a datos se añadirán al implementar cada función, no como estructuras vacías.

- [`auth`](auth/README.md): registro, verificación, inicio, recuperación y cierre de sesión.
- [`profiles`](profiles/README.md): perfil y relación de una cuenta con sus permisos.
- [`courses`](courses/README.md): cursos oficiales por materia, grupo y período.
- [`enrollments`](enrollments/README.md): matrícula canónica, inscripción manual y consulta de materias.
- [`course_entry`](course_entry/README.md): invitaciones temporales por código y solicitudes de ingreso.
- [`schedule`](schedule/README.md): horarios definidos por docentes para cursos.
- [`sessions`](sessions/README.md): ocurrencias de clase, cancelaciones, reposiciones y cambios.
- [`attendance`](attendance/README.md): registro manual por encuentro o por horas, excepciones de calendario, correcciones, justificaciones revisadas y consulta privada del estudiante.
- [`justifications`](justifications/README.md): solicitudes y adjuntos quedan para una entrega posterior; C8 solo registra la decisión manual de una revisión existente.
- [`imports`](imports/README.md): importación y actualización confirmada de listas desde Excel.
- [`reports`](reports/README.md): estadísticas con la unidad de cálculo aún por definir.
- [`administration`](administration/README.md): administración autorizada, invitaciones y revisión de permisos.
- [`demo_records`](demo_records/README.md): CRUD temporal de registros de prueba por cuenta, separado del dominio oficial.
