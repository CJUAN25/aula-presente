# Instrucciones para Codex

- Trabaja únicamente dentro de este proyecto y conserva el trabajo existente.
- Antes de cambiar un módulo, lee este archivo, `README.md`, `docs/arquitectura.md`, `docs/estado_actual.md` y la documentación del módulo afectado.
- La entrega actual incluye Firebase Authentication, Cloud Firestore, el CRUD privado `demo_records`, el conjunto 1 de solicitud/aprobación de acceso docente y el conjunto 2 de creación/consulta de cursos con horario y calendario previsto. No implementes módulos académicos posteriores sin una nueva solicitud.
- El conjunto 2 mantiene `courses` separado de matrícula/asistencia y `schedule` como fuente única del calendario. No añadas edición/borrado de cursos, estudiantes, sesiones, asistencia, QR, Bluetooth, justificaciones, reportes ni excepciones.
- Un curso usa `courses/{courseId}` para metadatos e IDs ordenados; los bloques viven en `courses/{courseId}/weekly_blocks/{blockId}` y se crean en la misma transacción. No vuelvas a incrustar una lista de bloques ni dupliques su fuente de verdad; conserva el máximo validado de ocho.
- No publiques reglas o índices, no crees cuentas reales ni envíes correos para pruebas. Usa el emulador local para las reglas y documenta qué quedó sin comprobar contra Firebase real.
- No ejecutes la app en el TECNO CM6 salvo que el usuario lo solicite. Compilar y ejecutar pruebas locales sí está permitido.
- La referencia visual vigente es [Aula Presente · Rediseño](https://www.figma.com/design/XP9LIZClkFzVNf17jUXjGU/NUEVA-CORRECION), página `01 · Aula Presente · Rediseño`. Ignora `90 · Archivo · Sistema anterior` y `91 · Archivo · Prototipo anterior` al implementar.
- Mantén `main.dart` como entrada y `app/` para configuración. Organiza funciones de producto en `lib/features/`; añade capas solo cuando tengan responsabilidades reales.
- Reserva `lib/core/` para elementos verdaderamente compartidos. Mantén `demo_records` separado de cursos, matrículas y asistencia.
- `users/{uid}.roles` es la fuente de acceso. La interfaz nunca concede roles; `teacher` se concede solo al aprobar una solicitud pendiente en una transacción y `admin` se prepara fuera del cliente.
- Los cursos se consultan bajo `ownerUid == request.auth.uid`. El cliente deriva el UID desde Auth y no envía propietario desde formulario. Roles docentes requieren verificación del perfil y correo; `admin` por sí solo no concede permisos académicos.
- No permitas enumerar perfiles `users`; las reglas deben proteger también cada operación de cliente.
- No guardes secretos, credenciales, archivos de servicio, datos personales reales ni capturas sensibles en el repositorio. Revisa `.gitignore` antes de añadir configuración local.
- No afirmes que un servicio, emulador, flujo o dispositivo fue probado si no lo verificaste en esta sesión.
