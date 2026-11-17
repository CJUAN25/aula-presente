# Seguimiento del conjunto 9 — maquetación y navegación

## Punto de recuperación — inventario inicial — 17/11/2026

Rama feature/conjunto-9-maquetacion-completa, creada desde el commit C8 exacto 605ac9f3b8017f7c212c99ae53df65fdff34267e. No existía rama local ni remota C9. Este documento y el inventario visual inicial son el primer punto de recuperación; todavía no hay cambios de interfaz C9.

La página Figma no pudo leerse porque el conector pide reautenticación. Fuente de respaldo: ../FIGMA/NUEVA CORRECCION.pdf, SHA-256 5F9AD8A69E6AD6EA958D0370EAAEE2977E9DA8AAFD6562C208D75FD2A0D03FD3. Se inspeccionaron visualmente las 158 páginas de 390×844 en diez hojas de contacto y se cruzaron títulos y rutas. No se revisaron las páginas archivadas ni se atribuyen node IDs a números del PDF.

C8, base de esta rama: commit final 605ac9f3b8017f7c212c99ae53df65fdff34267e, remoto sincronizado; 359 Flutter, analysis limpio, 109 Rules Emulator, APK Android y reglas activas verificadas. Ruleset 7f545ef7-bcf8-4fb8-ab62-63f1134a7042, activado 01:55:52 Colombia. La validación real en TECNO le corresponde al propietario.

### Rutas y diseño de la base

AuthStartScreen resuelve a StudentProfileScreen/StudentCoursesScreen, TeacherCoursesScreen/CourseDetailScreen o AdminTeacherRequestsScreen conforme a roles verificados. Reutilizar scopes, repositorios y rutas de Auth, cursos/calendario, asistencia manual, consulta propia, matrícula, invitaciones, importación Excel y acceso docente; no crear un router de producción paralelo.

Los marcos nuevos incluyen home/resúmenes, agenda, ayuda/notificaciones, informes, permisos, métodos QR/Bluetooth/NFC, check-in, formularios PDF y estados. Los que no están conectados se presentarán como demostración con datos ficticios, claramente marcada, sin persistencia, Firebase, correo, cámara, Bluetooth ni adjuntos. QR/BT/NFC no cambian el contrato C8 ni requieren configuración Firebase en C9.

### Trabajo modular previsto

| Orden | Módulo | Páginas | Pruebas por módulo | Estado |
| --- | --- | --- | --- | --- |
| 1 | Catálogo y selector de recorrido debug | 1–18, 158 | Estudiante/docente/compartido, navegación adelante/atrás, sin Firebase | Pendiente |
| 2 | Estudiante: inicio, agenda, resúmenes y ayuda | 19–36, 126, 134–143, 148, 150, 153–155, 157 | Contenido, empty/loading/error y acciones locales | Pendiente |
| 3 | Docente: home, agenda, informes y estados | 37–58, 67, 126–128, 149 | Recorrido por módulos y prueba visual adaptable | Pendiente |
| 4 | Métodos de sesión y estados de prototipo | 6, 111–125, 133, 135, 143, 147, 155 | Acciones solo locales; C8 sin modificaciones | Pendiente |
| 5 | Revisión de pantallas conectadas | 1–5, 7–8, 11–18, 23–26, 29, 31, 39–56, 59–66, 73–110, 129–131 | Reusar pruebas de cada módulo, corregir diffs visibles | Pendiente |

### Siguiente acción

Antes de editar cada módulo, revisar su README y componentes. Implementar y probar el catálogo debug como primer módulo; luego actualizar aquí rutas, marcos, cambios, capturas de prueba, y primer pendiente exacto. Cada módulo probado tendrá un commit y push propio. La compilación/revisión integrada se reserva para el cierre C9.
