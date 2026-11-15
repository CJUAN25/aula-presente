# Ingreso a cursos por código temporal

El módulo separa dominio, validación, repositorio Firestore y presentación. La invitación privada actual es `courses/{courseId}/invitation/current`; guarda `code`, `status` (`active|paused|inactive`), `createdAt`, `updatedAt` y `validForSeconds`. El vencimiento deriva de `createdAt + validForSeconds`: 1 hora a 90 días, 14 días por defecto. Los documentos antiguos sin duración conservan sus 14 días; no hay migración destructiva.

El índice `course_invites/{code}` mantiene solo `courseId`, `subject`, `group`, `period` y `createdAt`. El estudiante hace `get` puntual del índice y vuelve a leerlo al enviar. No lee `invitation/current`: esa lectura estaba en Dart y causaba `permission-denied` aunque el código fuera nuevo. Las reglas leen internamente la configuración y validan estado, código y vigencia con hora de servidor. El código no abre curso, horario ni estudiantes.

El docente genera o reemplaza con duración elegida, edita el vencimiento sin cambiar código/creación y desactiva definitivamente. La gestión habitual muestra código, Copiar, estado, vencimiento, Renovar, Editar y Desactivar. No ofrece Pausar. Si encuentra una invitación pausada previamente, puede reactivarla antes de vencer o renovarla. El repositorio y las reglas conservan la transición a `paused` para compatibilidad; pausar no detiene el tiempo. Un código vencido o desactivado requiere uno nuevo. Se confirma la escritura antes del resultado y un refresco fallido no revierte la confirmación. El reloj del teléfono no autoriza acciones.

Las solicitudes estables usan `courses/{courseId}/join_requests/{studentUid}`. La aprobación y matrícula canónica siguen atómicas e inmutables. Gestionar invitaciones no modifica roles, solicitudes previas ni matrículas. El diagnóstico debug solo muestra paso y categoría/código del error, sin identificadores.

Contrato, evidencia y pruebas: [seguimiento](../../../docs/seguimiento_conjunto_4.md). Despliegue manual y prueba en el TECNO: [activación](../../../docs/activacion_conjunto_4.md).

Cuando existe una autorización C7 para el mismo curso, correo y código, aprobar la solicitud C4 reutiliza la matrícula canónica y enlaza el pendiente con su evento en la misma transacción. La identidad se coteja por curso, UID, correo y código; el nombre se conserva como dato descriptivo y no se reescribe al enlazar. Una solicitud que no coincida conserva su estado para revisión docente; el estudiante no obtiene permiso general para resolver solicitudes.
