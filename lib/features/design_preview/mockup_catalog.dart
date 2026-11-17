import 'mockup_frame.dart';

/// 158 PDF frames indexed in the checked C9 visual inventory.
const _mockupRows = r'''
1	shared	Aula	WelcomeScreen — features/auth/presentation/auth_screens.dart	true	Cuenta
2	shared	Iniciar sesión	LoginScreen — auth_screens.dart	true	Cuenta
3	shared	Recuperar acceso	RecoveryScreen — auth_screens.dart	true	Cuenta
4	shared	Revisa tu correo	RecoverySentScreen — auth_screens.dart	true	Cuenta
5	shared	Elige tu espacio	AccessSpaceScreen — auth_screens.dart	true	Cuenta
6	shared	Preparar tu teléfono	Sin ruta — preparación del dispositivo y permisos (demo local)	false	Cuenta
7	student	Vincular materia	StudentCourseCodeScreen — features/course_entry/presentation/student_course_entry_screens.dart	true	Cuenta
8	student	Vinculación pendiente	CourseJoinRequestStatusScreen — student_course_entry_screens.dart	true	Cuenta
9	student	Notificaciones	No notifications screen (local demo)	false	Cuenta
10	teacher	Notificaciones	No notifications screen (local demo)	false	Cuenta
11	student	Mi perfil	StudentProfileScreen — auth_screens.dart	true	Cuenta
12	teacher	Mi perfil	TeacherProfileScreen — features/administration/presentation/teacher_profile_screen.dart	true	Cuenta
13	shared	Ayuda	No help screen (local demo)	false	Cuenta
14	shared	Crear cuenta	RegistrationScreen — auth_screens.dart	true	Cuenta
15	shared	Verificar correo	VerificationScreen — auth_screens.dart	true	Cuenta
16	teacher	Acceso docente	TeacherAccessScreen — features/administration/presentation/teacher_access_screens.dart	true	Cuenta
17	teacher	Solicitud docente	TeacherRequestStatusScreen — teacher_access_screens.dart	true	Cuenta
18	student	Confirmar curso	ConfirmCourseRequestScreen — student_course_entry_screens.dart	true	Cuenta
19	student	Aula	No student home/dashboard (new C9)	false	Estudiante
20	student	Aula	No student home/dashboard (new C9)	false	Estudiante
21	student	Aula	No student home/dashboard (new C9)	false	Estudiante
22	student	Aula	No student empty-state home (new C9)	false	Estudiante
23	student	Mis materias	StudentCoursesScreen — features/enrollments/presentation/student_enrollment_screens.dart	true	Estudiante
24	student	Programación Móvil	StudentEnrolledCourseScreen — student_enrollment_screens.dart	true	Estudiante
25	student	Cálculo I	StudentEnrolledCourseScreen — features/enrollments/presentation/student_enrollment_screens.dart	true	Estudiante
26	student	Redes Informáticas	StudentEnrolledCourseScreen — features/enrollments/presentation/student_enrollment_screens.dart	true	Estudiante
27	student	Registrar asistencia	No student attendance registration/Bluetooth/QR (local demo)	false	Estudiante
28	student	Asistencia registrada	No student registration receipt (local demo)	false	Estudiante
29	student	Historial	StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart	true	Estudiante
30	student	Cómo se calcula	No visual calculation guide (new C9)	false	Estudiante
31	student	Mi horario	StudentScheduleScreen — student_enrollment_screens.dart	true	Estudiante
32	student	Enviar justificación	No PDF justification form (local demo; C8 stores text only)	false	Estudiante
33	student	Enviar justificación	No PDF justification form (local demo; C8 stores text only)	false	Estudiante
34	student	Mis justificaciones	No My Justifications list (new C9)	false	Estudiante
35	student	Escanear QR	No QR scanner (local demo)	false	Estudiante
36	student	Cursos encontrados	Course match result needs a visual state	false	Estudiante
37	teacher	Aula	No teacher home/agenda (new C9)	false	Docente
38	teacher	Aula	No teacher open-class home (new C9)	false	Docente
39	teacher	Mis cursos	TeacherCoursesScreen — features/courses/presentation/teacher_courses_screen.dart	true	Docente
40	teacher	Bases de Datos · G2	CourseDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
41	teacher	Bases de Datos · G1	TeacherCoursesScreen / CourseDetailScreen	true	Docente
42	teacher	Calendario del curso	CourseCalendarScreen — course_detail_screen.dart	true	Docente
43	teacher	Cancelar clase	CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
44	teacher	Reprogramar clase	CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
45	teacher	Preparar asistencia	TeacherAttendanceScreen — features/attendance/presentation/teacher_attendance_screens.dart	true	Docente
46	teacher	Sesión en curso	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
47	teacher	Cerrar registro	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
48	teacher	Registro manual	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
49	teacher	Registro manual	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
50	teacher	Reabrir registro	QR/Bluetooth session reopening outside C8 (local demo)	false	Docente
51	teacher	Justificaciones	C8 request widget in attendance/student results; PDF review is demo only	true	Docente
52	teacher	Justificación aprobada	C8 request widget in attendance/student results; PDF review is demo only	true	Docente
53	teacher	Justificación rechazada	C8 request widget in attendance/student results; PDF review is demo only	true	Docente
54	teacher	Revisar justificación	TeacherAttendanceSessionScreen / C8 justification requests — attendance_session_screen.dart	true	Docente
55	teacher	Estudiantes	CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
56	teacher	Estudiantes	CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
57	teacher	Informes	No course reports/downloads (local demo)	false	Docente
58	teacher	Reglas y cálculo	No visual rules and calculation guide (new C9)	false	Docente
59	teacher	Crear curso	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
60	teacher	Horario del curso	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
61	teacher	Revisar calendario	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
62	teacher	Editar curso	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
63	teacher	Día y horario	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
64	teacher	Alcance del cambio	CourseCreationFlow — features/courses/presentation/course_creation_flow.dart	true	Docente
65	teacher	Añadir clase	CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
66	teacher	Detalle de clase	PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
67	teacher	Mi agenda docente	No weekly teacher agenda (new C9)	false	Docente
68	teacher	Archivar curso	No archive-course flow in C8 (local demo)	false	Docente
69	teacher	Cursos archivados	No archived-course list (local demo)	false	Docente
70	teacher	Archivo del curso	No archived-course detail (local demo)	false	Docente
71	teacher	Cambiar horario futuro	No future-schedule editor (local demo)	false	Docente
72	teacher	Confirmar nuevo horario	No future-schedule confirmation (local demo)	false	Docente
73	teacher	Estado de asistencia	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
74	teacher	Corrección · ausente	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
75	teacher	Elegir estudiante	AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
76	teacher	Gestionar estudiantes	TeacherEnrollmentHubScreen — teacher_enrollment_screens.dart	true	Docente
77	teacher	Importar Excel	ExcelImportScreen — features/excel_import/presentation/excel_import_screen.dart	true	Docente
78	teacher	Columnas del Excel	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
79	teacher	Revisar importación	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
80	teacher	Importación completada	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
81	teacher	Comparar actualización	ExcelRosterUpdateScreen — features/excel_import/presentation/excel_roster_update_screen.dart	true	Docente
82	teacher	Seleccionar retiros	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
83	teacher	Agregar estudiante	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
84	teacher	Revisar coincidencia	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
85	teacher	Pendiente de cuenta	CoursePendingEnrollmentsScreen / PendingEnrollmentDetailScreen — features/enrollments/presentation/pending_enrollments_screen.dart	true	Docente
86	teacher	Invitar al curso	CourseInvitationScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
87	teacher	Solicitudes de ingreso	TeacherJoinRequestsScreen — features/course_entry/presentation/teacher_join_request_screens.dart	true	Docente
88	teacher	Retirar estudiante	EnrollmentStatusChangeScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
89	teacher	Estudiantes del curso	CourseStudentsScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
90	teacher	Retirados e histórico	CourseEnrollmentHistoryScreen — features/enrollments/presentation/course_enrollment_history_screen.dart	true	Docente
91	teacher	Invitación lista	InvitationShareReadyScreen — course_invitation_screens.dart	true	Docente
92	teacher	Revisar solicitud	ReviewJoinRequestScreen — features/course_entry/presentation/teacher_join_request_screens.dart	true	Docente
93	teacher	Ficha del estudiante	StudentEnrollmentDetailScreen — teacher_enrollment_screens.dart	true	Docente
94	teacher	Seleccionar altas del Excel	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
95	teacher	Seleccionar estudiantes nuevos	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
96	teacher	Confirmar actualización	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
97	teacher	Actualización aplicada	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
98	teacher	Confirmar importación	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
99	teacher	Inscripción confirmada	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
100	teacher	Historial del estudiante	StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart	true	Docente
101	teacher	Editar inscripción	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
102	teacher	Inscripción actualizada	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
103	teacher	Sin cambios seleccionados	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
104	teacher	Gestionar invitación	ManageCourseInvitationScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
105	teacher	Renovar invitación	ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
106	teacher	Desactivar invitación	ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
107	teacher	Invitación actualizada	ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
108	teacher	Reincorporar estudiante	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
109	teacher	Reincorporación confirmada	EnrollmentStatusChangeScreen / AddStudentScreen — features/enrollments/presentation/teacher_enrollment_screens.dart	true	Docente
110	teacher	Código listo para compartir	ManageCourseInvitationScreen / InvitationShareReadyScreen — features/course_entry/presentation/course_invitation_screens.dart	true	Docente
111	teacher	Método de asistencia	No active Bluetooth/QR/NFC method in C8 (local demo, no Firestore)	false	Docente
112	teacher	Preparar QR	Prepare QR (local demo)	false	Docente
113	teacher	Sesión por QR	QR session (local demo)	false	Docente
114	teacher	Agregar tiempo	Extend QR/Bluetooth time outside C8 (local demo)	false	Docente
115	teacher	Tiempo ampliado	Extended-time confirmation (local demo)	false	Docente
116	teacher	Métodos de la sesión	Change session method (local demo)	false	Docente
117	teacher	Método de reapertura	Choose method to reopen (local demo)	false	Docente
118	teacher	Reabrir por QR	Reopen QR (local demo)	false	Docente
119	teacher	QR · tiempo ampliado	Extended QR session (local demo)	false	Docente
120	teacher	Ampliar sesión QR	Extend QR session (local demo)	false	Docente
121	teacher	Bluetooth · ampliado	Extended Bluetooth session (local demo)	false	Docente
122	teacher	Bluetooth · reapertura	Bluetooth reopen (local demo)	false	Docente
123	teacher	QR · reapertura	QR reopen (local demo)	false	Docente
124	teacher	Duración del registro	Choose duration (local demo)	false	Docente
125	teacher	Elegir tiempo adicional	Choose extra time (local demo)	false	Docente
126	student	Mi resumen	StudentCoursesScreen — summary screen missing; proposed C9 route	false	Estudiante
127	teacher	Resumen de mis cursos	TeacherCoursesScreen — summary view missing; proposed C9 route	false	Docente
128	admin	Estadísticas del proyecto	AdministrationPage — features/administration/presentation/administration_components.dart; global statistics view missing	false	Administraci?n
129	admin	Accesos docentes	AdminTeacherRequestsScreen — features/administration/presentation/admin_teacher_requests_screen.dart	true	Administraci?n
130	admin	Revisar acceso docente	AdminTeacherRequestsScreen → _AdminTeacherReviewScreen	true	Administraci?n
131	admin	Acceso autorizado	TeacherAccessDecisionResultScreen — admin_teacher_requests_screen.dart	true	Administraci?n
132	shared	Iniciar sesión	LoginScreen — authentication error state	true	Estados
133	student	Permiso desactivado	Nearby/Bluetooth permission (local demo)	false	Estudiante
134	student	Mis materias	StudentCoursesScreen — empty state	true	Estudiante
135	student	Buscando tu clase	Find student session (local demo)	false	Estudiante
136	student	Registro cerrado	Partial closed-registration result needs a view	false	Estudiante
137	student	Ya estás registrado	Student attendance receipt (local demo)	false	Estudiante
138	student	Llegada tarde registrada	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Estudiante
139	student	Registro sin confirmar	Pending reconciliation/confirmation (local demo)	false	Estudiante
140	student	Revisa tu asistencia	StudentAttendanceScreen — features/attendance/presentation/student_attendance_screen.dart	true	Estudiante
141	student	Justificación enviada	C8 request widget in attendance/student results; PDF review is demo only	true	Estudiante
142	student	Revisar documento	PDF/attachment error (local demo)	false	Estudiante
143	student	Bluetooth no disponible	Bluetooth unavailable (local demo)	false	Estudiante
144	shared	Conexión interrumpida	Reconnect with pending changes	false	Estados
145	teacher	Clase cancelada	CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
146	teacher	Corrección guardada	TeacherAttendanceSessionScreen — features/attendance/presentation/attendance_session_screen.dart	true	Docente
147	teacher	Reapertura activa	QR/Bluetooth reopened registration (local demo)	false	Docente
148	student	Justificación aprobada	C8 request widget in attendance/student results; PDF review is demo only	true	Estudiante
149	teacher	Informe disponible	Report ready/download (local demo)	false	Docente
150	student	Justificación rechazada	C8 request widget in attendance/student results; PDF review is demo only	true	Estudiante
151	teacher	Clase reprogramada	CourseCalendarScreen / PlannedMeetingDetailScreen — features/courses/presentation/course_detail_screen.dart	true	Docente
152	teacher	Problemas en Excel	ExcelImportScreen / ExcelRosterUpdateScreen — features/excel_import/presentation/	true	Docente
153	student	Invitación no válida	StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth	true	Estudiante
154	student	Sin acceso a esta clase	StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth	true	Estudiante
155	student	QR vencido	Expired QR (local demo)	false	Estudiante
156	teacher	Horario en conflicto	CourseCreationFlow / CourseScheduleDiagnosticScreen	true	Docente
157	student	Revisar mis datos	StudentCourseCodeScreen / StudentProfileScreen — course_entry/auth	true	Estudiante
158	shared	Revisión del prototipo	Debug catalog of demonstration states, not a product screen	false	Estados
''';

final mockupFrames = List<MockupFrame>.unmodifiable(
  _mockupRows.trim().split('\n').map(MockupFrame.fromTsv),
);
