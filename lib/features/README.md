# Módulos del producto

Cada carpeta delimita una función. Las capas de presentación, lógica de negocio y acceso a datos se añadirán al implementar cada función, no como estructuras vacías.

- [`auth`](auth/README.md): registro, verificación, inicio, recuperación y cierre de sesión.
- [`profiles`](profiles/README.md): perfil y relación de una cuenta con sus permisos.
- [`courses`](courses/README.md): cursos oficiales por materia, grupo y período.
- [`enrollments`](enrollments/README.md): matrículas, vigencias y solicitudes de ingreso.
- [`schedule`](schedule/README.md): horarios definidos por docentes para cursos.
- [`sessions`](sessions/README.md): ocurrencias de clase, cancelaciones, reposiciones y cambios.
- [`attendance`](attendance/README.md): registros por sesión, métodos, tardanzas y correcciones.
- [`justifications`](justifications/README.md): solicitudes de justificación y adjuntos PDF.
- [`imports`](imports/README.md): importación y actualización confirmada de listas desde Excel.
- [`reports`](reports/README.md): estadísticas con la unidad de cálculo aún por definir.
- [`administration`](administration/README.md): administración autorizada, invitaciones y revisión de permisos.
- [`demo_records`](demo_records/README.md): CRUD temporal de registros de prueba por cuenta, separado del dominio oficial.
