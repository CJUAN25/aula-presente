# Inventario visual inicial — Conjunto 9

## Fuente vigente y alcance

Referencia solicitada: Figma Aula Presente · Rediseño, página 01 · Aula Presente · Rediseño, URL https://www.figma.com/design/XP9LIZClkFzVNf17jUXjGU/NUEVA-CORRECCION?node-id=25-57. El conector pidió reautenticación y no devolvió el diseño. Se usó el respaldo local C:\Users\juand\OneDrive\Documentos\UNIVERSIDAD\TRABAJOS U\8. SEMESTRE\MOVIL\FIGMA\NUEVA CORRECCION.pdf, SHA-256 5F9AD8A69E6AD6EA958D0370EAAEE2977E9DA8AAFD6562C208D75FD2A0D03FD3. Tiene 158 páginas, cada una exportada como pantalla de 390 × 844. Se inspeccionaron visualmente todas las páginas en diez hojas de contacto y se consultaron los títulos/rutas Flutter. La tabla identifica la página PDF, no un node ID de Figma.

El PDF exportado no dejó un inventario separado de las páginas Figma. Por eso no se atribuyen sus números PDF a las páginas archivadas 90 · Archivo · Sistema anterior o 91 · Archivo · Prototipo anterior. Las páginas PDF 90 y 91 son aquí los marcos Retirados e histórico e Invitación lista; no se confunden con esos nombres de página.

## Recorridos, datos y prioridades

**Estado de cobertura C9:** `DesignPreviewCatalogScreen` incorpora los 158 números de página en un catálogo navegable por rol y búsqueda. Al abrirlos, los marcos conectados se etiquetan como previsualización y conservan su ruta real en el flujo normal; los que no están integrados son demostraciones locales con datos ficticios. El estudiante recorre inicio, materias, métricas, check-in, recibos, historial, cálculo, horario, justificaciones y errores; el docente recorre home, cursos/calendario, sesión, cierre/corrección, justificaciones, agenda e informes. La vista PDF del mockup de justificación se adapta al texto que soporta C8. Falta cubrir estados compartidos/admin y completar la revisión del código de las rutas conectadas. No equivale a 158 pantallas funcionales distintas ni a integración Firebase de funciones nuevas.

- Entrada real: AulaPresenteApp → AuthStartScreen → _destinationForAccess. StudentProfileScreen/StudentCoursesScreen abre el espacio estudiante; TeacherCoursesScreen/CourseDetailScreen el docente; AdminTeacherRequestsScreen la administración. Las cuentas duales conservan el cambio de espacio por perfiles reales y la interfaz nunca concede roles.
- Funcionalidad conectada existente: Auth, cursos/calendario, C8 manual, consulta propia, solicitudes de texto C8, matrícula C3–C7, códigos/invitaciones, importación Excel y aprobación de acceso docente.
- No hay rutas para home/agenda dashboard, notificaciones, ayuda, informes, estadísticas, métodos Bluetooth/QR/NFC ni adjuntos PDF. En C9 serán maquetas de demostración explícitas y sin llamadas remotas, permisos de sensores, envío de correo ni archivos.
- Las rutas conectadas siguen usando Firebase y sus permisos. El catálogo debug se separa de los recorridos reales para que ambos roles puedan revisar el diseño sin tocar cuentas/datos reales.
- Fidelidad observada: fondo verde muy oscuro; superficies verde pino, bordes redondeados, acento menta; tipografía Manrope; textos secundarios verde grisáceo; errores coral, avisos azul/ámbar. App bar compacta, titular, tarjetas, CTA menta, botones secundarios y navegación inferior. Ajustar desplazamiento para la altura móvil.

## Módulos del inventario

| Módulo | Páginas PDF | Ruta conectada | Falta en C9 |
| --- | --- | --- | --- |
| Acceso/cuenta/perfil | 1–18 | auth_screens, teacher_access, course_entry | Catálogo debug; ayuda/avisos/permisos y pantallas de perfil faltantes. |
| Estudiante | 19–36,126,134–143,148,150,153–155,157 | enrollments, attendance, course_entry, auth | Inicio/resumen, bandeja/ayuda, agenda y check-in visual; justificaciones PDF solo demo. |
| Docente | 37–58,73–74,138,145–147,149,151,152,156 | courses, attendance, enrollments, course_entry, excel_import | Inicio/agenda, informes y estadísticas; selector QR/Bluetooth demo. |
| Curso/calendario | 39–44,59–72,145,151,156 | courses/course_detail/course_creation_flow | Archivo/edición de horarios futuros donde falta integración; fidelidad visual. |
| Matrícula/Excel | 75–110,152 | enrollments, course_entry, excel_import | Revisar todos los pasos de navegación y correspondencia visual; mantener datos canónicos. |
| Métodos | 111–125,133,135,143,147,155 | Sin implementación de sensor | Demostración local, sin permisos Bluetooth/cámara, sin persistencia. |
| Administración/estados | 128–131,132,144,158 | administration/auth | Estadísticas/estado catálogo; completar estados de error y volver a intentar. |

## Inventario pantalla por pantalla

| Página PDF y marco | Rol | Ruta Flutter actual o propuesta | Trabajo que falta |
| --- | --- | --- | --- |
| PDF p. 001 · Aula | Compartida | WelcomeScreen — features/auth/presentation/auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 002 · Iniciar sesión | Compartida | LoginScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 003 · Recuperar acceso | Compartida | RecoveryScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 004 · Revisa tu correo | Compartida | RecoverySentScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 005 · Elige tu espacio | Compartida | AccessSpaceScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 006 · Preparar tu teléfono | Compartida | Sin ruta — preparación del dispositivo y permisos (demo local) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 007 · Vincular materia | Estudiante | StudentCourseCodeScreen — features/course_entry/presentation/student_course_entry_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 008 · Vinculación pendiente | Estudiante | CourseJoinRequestStatusScreen — student_course_entry_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 009 · Notificaciones | Estudiante | No notifications screen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 010 · Notificaciones | Docente | No notifications screen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 011 · Mi perfil | Estudiante | StudentProfileScreen — auth_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 012 · Mi perfil | Docente | TeacherProfileScreen — features/administration/presentation/teacher_profile_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 013 · Ayuda | Compartida | No help screen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 014 · Crear cuenta | Compartida | RegistrationScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 015 · Verificar correo | Compartida | VerificationScreen — auth_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 016 · Acceso docente | Docente | TeacherAccessScreen — features/administration/presentation/teacher_access_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 017 · Solicitud docente | Docente | TeacherRequestStatusScreen — teacher_access_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 018 · Confirmar curso | Estudiante | ConfirmCourseRequestScreen — student_course_entry_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 019 · Aula | Estudiante | No student home/dashboard (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 020 · Aula | Estudiante | No student home/dashboard (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 021 · Aula | Estudiante | No student home/dashboard (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 022 · Aula | Estudiante | No student empty-state home (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 023 · Mis materias | Estudiante | StudentCoursesScreen — features/enrollments/presentation/student_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 024 · Programación Móvil | Estudiante | StudentEnrolledCourseScreen — student_enrollment_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 025 · Cálculo I | Estudiante | StudentEnrolledCourseScreen — features/enrollments/presentation/student_enrollment_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 026 · Redes Informáticas | Estudiante | StudentEnrolledCourseScreen — features/enrollments/presentation/student_enrollment_screens.dart | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 027 · Registrar asistencia | Estudiante | No student attendance registration/Bluetooth/QR (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 028 · Asistencia registrada | Estudiante | No student registration receipt (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 029 · Historial | Estudiante | StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 030 · Cómo se calcula | Estudiante | No visual calculation guide (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 031 · Mi horario | Estudiante | StudentScheduleScreen — student_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 032 · Enviar justificación | Estudiante | No PDF justification form (local demo; C8 stores text only) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 033 · Enviar justificación | Estudiante | No PDF justification form (local demo; C8 stores text only) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 034 · Mis justificaciones | Estudiante | No My Justifications list (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 035 · Escanear QR | Estudiante | No QR scanner (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 036 · Cursos encontrados | Estudiante | Course match result needs a visual state | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 037 · Aula | Docente | No teacher home/agenda (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 038 · Aula | Docente | No teacher open-class home (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 039 · Mis cursos | Docente | TeacherCoursesScreen — features/courses/presentation/teacher_courses_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 040 · Bases de Datos · G2 | Docente | CourseDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 041 · Bases de Datos · G1 | Docente | TeacherCoursesScreen / CourseDetailScreen | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 042 · Calendario del curso | Docente | CourseCalendarScreen — course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 043 · Cancelar clase | Docente | CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 044 · Reprogramar clase | Docente | CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 045 · Preparar asistencia | Docente | TeacherAttendanceScreen — features/attendance/presentation/teacher_attendance_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 046 · Sesión en curso | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 047 · Cerrar registro | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 048 · Registro manual | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 049 · Registro manual | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 050 · Reabrir registro | Docente | QR/Bluetooth session reopening outside C8 (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 051 · Justificaciones | Docente | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 052 · Justificación aprobada | Docente | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 053 · Justificación rechazada | Docente | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 054 · Revisar justificación | Docente | TeacherAttendanceSessionScreen / C8 justification requests — attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 055 · Estudiantes | Docente | CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 056 · Estudiantes | Docente | CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 057 · Informes | Docente | No course reports/downloads (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 058 · Reglas y cálculo | Docente | No visual rules and calculation guide (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 059 · Crear curso | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 060 · Horario del curso | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 061 · Revisar calendario | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 062 · Editar curso | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 063 · Día y horario | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 064 · Alcance del cambio | Docente | CourseCreationFlow — features/courses/presentation/course_creation_flow.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 065 · Añadir clase | Docente | CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 066 · Detalle de clase | Docente | PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 067 · Mi agenda docente | Docente | No weekly teacher agenda (new C9) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 068 · Archivar curso | Docente | No archive-course flow in C8 (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 069 · Cursos archivados | Docente | No archived-course list (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 070 · Archivo del curso | Docente | No archived-course detail (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 071 · Cambiar horario futuro | Docente | No future-schedule editor (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 072 · Confirmar nuevo horario | Docente | No future-schedule confirmation (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 073 · Estado de asistencia | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 074 · Corrección · ausente | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 075 · Elegir estudiante | Docente | AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 076 · Gestionar estudiantes | Docente | TeacherEnrollmentHubScreen — teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 077 · Importar Excel | Docente | ExcelImportScreen — features/excel_import/presentation/excel_import_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 078 · Columnas del Excel | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 079 · Revisar importación | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 080 · Importación completada | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 081 · Comparar actualización | Docente | ExcelRosterUpdateScreen — features/excel_import/presentation/excel_roster_update_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 082 · Seleccionar retiros | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 083 · Agregar estudiante | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 084 · Revisar coincidencia | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 085 · Pendiente de cuenta | Docente | CoursePendingEnrollmentsScreen / PendingEnrollmentDetailScreen — features/enrollments/presentation/pending_enrollments_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 086 · Invitar al curso | Docente | CourseInvitationScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 087 · Solicitudes de ingreso | Docente | TeacherJoinRequestsScreen — features/course_entry/presentation/teacher_join_request_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 088 · Retirar estudiante | Docente | EnrollmentStatusChangeScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 089 · Estudiantes del curso | Docente | CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 090 · Retirados e histórico | Docente | CourseEnrollmentHistoryScreen — features/enrollments/presentation/course_enrollment_history_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 091 · Invitación lista | Docente | InvitationShareReadyScreen — course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 092 · Revisar solicitud | Docente | ReviewJoinRequestScreen — features/course_entry/presentation/teacher_join_request_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 093 · Ficha del estudiante | Docente | StudentEnrollmentDetailScreen — teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 094 · Seleccionar altas del Excel | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 095 · Seleccionar estudiantes nuevos | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 096 · Confirmar actualización | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 097 · Actualización aplicada | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 098 · Confirmar importación | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 099 · Inscripción confirmada | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 100 · Historial del estudiante | Docente | StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 101 · Editar inscripción | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 102 · Inscripción actualizada | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 103 · Sin cambios seleccionados | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 104 · Gestionar invitación | Docente | ManageCourseInvitationScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 105 · Renovar invitación | Docente | ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 106 · Desactivar invitación | Docente | ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 107 · Invitación actualizada | Docente | ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 108 · Reincorporar estudiante | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 109 · Reincorporación confirmada | Docente | EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 110 · Código listo para compartir | Docente | ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 111 · Método de asistencia | Docente | No active Bluetooth/QR/NFC method in C8 (local demo, no Firestore) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 112 · Preparar QR | Docente | Prepare QR (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 113 · Sesión por QR | Docente | QR session (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 114 · Agregar tiempo | Docente | Extend QR/Bluetooth time outside C8 (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 115 · Tiempo ampliado | Docente | Extended-time confirmation (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 116 · Métodos de la sesión | Docente | Change session method (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 117 · Método de reapertura | Docente | Choose method to reopen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 118 · Reabrir por QR | Docente | Reopen QR (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 119 · QR · tiempo ampliado | Docente | Extended QR session (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 120 · Ampliar sesión QR | Docente | Extend QR session (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 121 · Bluetooth · ampliado | Docente | Extended Bluetooth session (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 122 · Bluetooth · reapertura | Docente | Bluetooth reopen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 123 · QR · reapertura | Docente | QR reopen (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 124 · Duración del registro | Docente | Choose duration (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 125 · Elegir tiempo adicional | Docente | Choose extra time (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 126 · Mi resumen | Estudiante | StudentCoursesScreen — summary screen missing; proposed C9 route | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 127 · Resumen de mis cursos | Docente | TeacherCoursesScreen — summary view missing; proposed C9 route | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 128 · Estadísticas del proyecto | Administrador | AdministrationPage — features/administration/presentation/administration_components.dart; global statistics view missing | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 129 · Accesos docentes | Administrador | AdminTeacherRequestsScreen — features/administration/presentation/admin_teacher_requests_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 130 · Revisar acceso docente | Administrador | AdminTeacherRequestsScreen → _AdminTeacherReviewScreen | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 131 · Acceso autorizado | Administrador | TeacherAccessDecisionResultScreen — admin_teacher_requests_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 132 · Iniciar sesión | Compartida | LoginScreen — authentication error state | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 133 · Permiso desactivado | Estudiante | Nearby/Bluetooth permission (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 134 · Mis materias | Estudiante | StudentCoursesScreen — empty state | Enlazar a ruta existente y completar estado visual/interacción. |
| PDF p. 135 · Buscando tu clase | Estudiante | Find student session (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 136 · Registro cerrado | Estudiante | Partial closed-registration result needs a view | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 137 · Ya estás registrado | Estudiante | Student attendance receipt (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 138 · Llegada tarde registrada | Estudiante | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 139 · Registro sin confirmar | Estudiante | Pending reconciliation/confirmation (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 140 · Revisa tu asistencia | Estudiante | StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 141 · Justificación enviada | Estudiante | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 142 · Revisar documento | Estudiante | PDF/attachment error (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 143 · Bluetooth no disponible | Estudiante | Bluetooth unavailable (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 144 · Conexión interrumpida | Compartida | Reconnect with pending changes | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 145 · Clase cancelada | Docente | CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 146 · Corrección guardada | Docente | TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 147 · Reapertura activa | Docente | QR/Bluetooth reopened registration (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 148 · Justificación aprobada | Estudiante | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 149 · Informe disponible | Docente | Report ready/download (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 150 · Justificación rechazada | Estudiante | C8 request widget in attendance/student results; PDF review is demo only | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 151 · Clase reprogramada | Docente | CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 152 · Problemas en Excel | Docente | ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/ | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 153 · Invitación no válida | Estudiante | StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 154 · Sin acceso a esta clase | Estudiante | StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 155 · QR vencido | Estudiante | Expired QR (local demo) | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
| PDF p. 156 · Horario en conflicto | Docente | CourseCreationFlow / CourseScheduleDiagnosticScreen | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 157 · Revisar mis datos | Estudiante | StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth | Conectada/parcial: preservar lógica y datos; revisar fidelidad, interacción y acceso desde la navegación. |
| PDF p. 158 · Revisión del prototipo | Compartida | Debug catalog of demonstration states, not a product screen | Pendiente: maquetar/navegar en demo con datos ficticios; sin escritura Firebase. |
