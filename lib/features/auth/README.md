# Autenticación

## Responsabilidades

- `domain/`: estado de acceso y contrato de `AuthRepository`.
- `data/firebase_auth_repository.dart`: Firebase Authentication, lectura/escritura del perfil `users/{uid}`, actualización de sesión y suscripción a cambios de permisos.
- `application/`: validación de formularios.
- `presentation/auth_screens.dart`: registro, inicio, verificación, recuperación, selección de espacios y perfiles; resuelve la navegación según estados tipados.

`AulaPresenteApp` conecta Firebase Auth y Firestore con `administration` y `enrollments` mediante sus respectivos repositorios y scopes. Las vistas no realizan llamadas Firestore directas. La implementación de solicitud docente vive en `lib/features/administration/`; la inscripción manual y la consulta de materias, en `lib/features/enrollments/`.

## Perfiles y acceso

El registro crea `users/{uid}` con `name`, `email`, `studentCode` y `roles: ['student']`, actualiza el nombre de Firebase Auth y envía verificación en español. La creación del perfil puede ocurrir antes de que el correo esté verificado. Un reintento crea el perfil solo si aún no existe, por lo que nunca sustituye los roles de un perfil preparado por administración.

Después de verificar, la app lee el perfil desde el servidor y compara el correo. `watchAccess()` sigue cambios de Authentication y del perfil del UID activo; al cambiar la cuenta o retirarse permisos, las rutas protegidas se vuelven a resolver. Solo los roles guardados en Firestore habilitan espacios. `student` abre el CRUD de demostración y «Mis materias»; al entrar en el espacio estudiante publica su ficha de búsqueda por correo exacto si está autorizado. `teacher` abre cursos propios y su gestión de matrículas; `admin` abre la revisión de solicitudes.

La solicitud docente no modifica roles. `teacher` se agrega únicamente junto con la aprobación administrativa en una transacción que las reglas validan. El primer rol `admin` se habilita por un administrador fuera de la app; no existe condición por correo ni acción cliente para concederlo.

## Autenticación

El inicio y la restauración de sesión exigen correo verificado y perfil autorizado. Para recuperar acceso se envía el enlace predeterminado de Firebase; el cambio de contraseña ocurre en la página alojada por Firebase. La corrección de correo requiere reautenticación con la contraseña actual y confirmación de Firebase antes de sincronizar el perfil. Las contraseñas no se guardan.

Las vistas de preview del menú oculto solo se compilan para debug (`kDebugMode`) y sus botones no autentican ni conceden roles. Las pruebas Flutter utilizan repositorios falsos; no son una prueba contra Firebase.
