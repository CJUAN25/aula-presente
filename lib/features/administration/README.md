# Acceso docente y administración

Este módulo implementa el conjunto 1: solicitud de acceso docente, consulta de estado y revisión manual de solicitudes pendientes.

## Capas

- `domain/teacher_access_request.dart`: estados, decisiones, solicitud tipada y comparación de identidad.
- `domain/teacher_access_repository.dart`: contrato y errores de dominio.
- `application/teacher_access_validator.dart`: normaliza y valida el motivo de rechazo (1–500 caracteres).
- `data/firestore_teacher_access_repository.dart`: usa Firebase Auth, el perfil del UID activo, timestamps de servidor y transacciones. La UI nunca pasa un UID propio ni cambia roles directamente.
- `presentation/teacher_access_screens.dart`: C12 y C13.
- `presentation/admin_teacher_requests_screen.dart`: S04 y S05.
- `presentation/teacher_profile_screen.dart`: C08D para una cuenta con rol docente real.
- `presentation/administration_components.dart`: componentes del lenguaje visual vigente para vistas administrativas.

## Recorrido y permisos

Una cuenta autenticada, con correo verificado y perfil válido puede crear una única solicitud en `teacher_access_requests/{uid}`. La solicitud toma del perfil `name`, `email` y `studentCode`; el cliente no concede `teacher`. Si ya existe, se consulta y abre su estado; los resultados pendiente, aprobado y rechazado son terminales para el solicitante. “Tengo una invitación” informa que los códigos todavía no están disponibles.

S04 obtiene solo pendientes y ofrece carga, vacío, error con reintento y apertura individual. S05 compara la identidad guardada con el perfil actual. Aprobar agrega únicamente `teacher`, preservando los roles y el resto del perfil, y actualiza la solicitud dentro de una misma transacción. Rechazar exige un motivo y no toca el perfil. Los controles se desactivan durante la decisión. Cambiar de cuenta o perder rol oculta la información de la vista protegida.

La transacción devuelve el resultado de la decisión solo cuando Firestore confirma el commit. Las reglas permiten al administrador leer el detalle únicamente mientras la solicitud está `pending`; por eso no se vuelve a leer el documento después de resolverlo. S05 se reemplaza por S06 al recibir la confirmación; la suscripción pendiente de S04 permanece activa debajo y elimina el elemento de la cola, mientras C13 conserva su lectura del documento propio. El resultado no muestra `decidedAt`, ya que ese valor autoritativo lo fija el servidor y el administrador no tiene permiso para leer de nuevo el documento resuelto.

Las reglas exigen correo verificado para crear y decidir, restringen el listado a consultas filtradas por `status == 'pending'`, bloquean el listado de perfiles `users`, impiden autoaprobación, falsificación del snapshot y reescritura de decisiones finales. `firestore.indexes.json` contiene el índice de estado y fecha requerido por S04.

No se reabren solicitudes rechazadas en esta etapa, no se envían invitaciones y no se muestra un panel de estadísticas o cursos. El otorgamiento inicial de `admin` queda fuera de la app. Los detalles de activación manual están en `docs/activacion_acceso_docente.md`.

## Pruebas

Las pruebas de `test/features/administration/` cubren validación, pantallas, estados, confirmaciones, cambios de cuenta, timeout recuperable sin respuesta del servidor y anchos de pantalla/texto ampliado. Las pruebas de reglas se ejecutan con el emulador local desde `tools/firestore_rules_tests/README.md`; no despliegan reglas ni crean cuentas reales.
