# Registros de demostración

CRUD temporal en Cloud Firestore bajo `users/{uid}/demo_records/{recordId}`. La interfaz se ofrece desde el perfil de estudiante, que solo se abre para una cuenta con correo verificado y rol `student`; el repositorio vuelve a comprobar la sesión y obtiene el UID desde Firebase Auth.

Cada documento contiene únicamente `title`, `description`, `createdAt` y `updatedAt`. La creación y actualización usan `FieldValue.serverTimestamp()`; editar conserva `createdAt`. Las reglas de Firestore son la autoridad final para permitir las operaciones.

`domain/` define el registro y el contrato del repositorio, `application/` valida los campos y `data/` implementa el acceso real a Firestore. `presentation/` contiene lista, detalle y formulario. Estos registros son temporales y no representan cursos oficiales, matrículas ni asistencia.
