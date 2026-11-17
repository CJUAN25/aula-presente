# Seguimiento del conjunto 9 — maquetación y navegación

## Punto de recuperación — catálogo de recorridos — 17/11/2026

Rama feature/conjunto-9-maquetacion-completa, creada desde el commit C8 exacto 605ac9f3b8017f7c212c99ae53df65fdff34267e. No existía rama local ni remota C9. Este commit agrega el primer módulo visual y conserva C8 como padre.

La página Figma no pudo leerse porque el conector pide reautenticación. Fuente de respaldo: ../FIGMA/NUEVA CORRECCION.pdf, SHA-256 5F9AD8A69E6AD6EA958D0370EAAEE2977E9DA8AAFD6562C208D75FD2A0D03FD3. Se inspeccionaron visualmente las 158 páginas de 390×844 en diez hojas de contacto y se cruzaron títulos y rutas. No se revisaron las páginas archivadas ni se atribuyen node IDs a números del PDF.

C8, base de esta rama: commit final 605ac9f3b8017f7c212c99ae53df65fdff34267e, remoto sincronizado; 359 Flutter, analysis limpio, 109 Rules Emulator, APK Android y reglas activas verificadas. Ruleset 7f545ef7-bcf8-4fb8-ab62-63f1134a7042, activado 01:55:52 Colombia. La validación real en TECNO le corresponde al propietario.

### Rutas y diseño de la base

AuthStartScreen resuelve a StudentProfileScreen/StudentCoursesScreen, TeacherCoursesScreen/CourseDetailScreen o AdminTeacherRequestsScreen conforme a roles verificados. Reutilizar scopes, repositorios y rutas de Auth, cursos/calendario, asistencia manual, consulta propia, matrícula, invitaciones, importación Excel y acceso docente; no crear un router de producción paralelo.

Los marcos nuevos incluyen home/resúmenes, agenda, ayuda/notificaciones, informes, permisos, métodos QR/Bluetooth/NFC, check-in, formularios PDF y estados. Los que no están conectados se presentarán como demostración con datos ficticios, claramente marcada, sin persistencia, Firebase, correo, cámara, Bluetooth ni adjuntos. QR/BT/NFC no cambian el contrato C8 ni requieren configuración Firebase en C9.

### Trabajo modular previsto

| Orden | Módulo | Páginas | Pruebas por módulo | Estado |
| --- | --- | --- | --- | --- |
| 1 | Catálogo y selector de recorrido debug | 1–18, 158 | Estudiante/docente/compartido, navegación adelante/atrás, sin Firebase | Implementado; 4/4 pruebas y análisis limpios. |
| 2 | Estudiante: inicio, agenda, resúmenes y ayuda | 19–36, 126, 134–143, 148, 150, 153–155, 157 | Contenido, vacío/error y acciones locales | Implementado; 5/5 pruebas y análisis limpios. |
| 3 | Docente: home, agenda, informes y estados | 37–58, 67, 126–128, 149 | Recorrido por módulos y prueba visual adaptable | Pendiente |
| 4 | Métodos de sesión y estados de prototipo | 6, 111–125, 133, 135, 143, 147, 155 | Acciones solo locales; C8 sin modificaciones | Pendiente |
| 5 | Revisión de pantallas conectadas | 1–5, 7–8, 11–18, 23–26, 29, 31, 39–56, 59–66, 73–110, 129–131 | Reusar pruebas de cada módulo, corregir diffs visibles | Pendiente |

### Siguiente acción

### Módulo 1 — catálogo y navegación de diseño

**Resultado:** `lib/features/design_preview/` agrega el modelo de marco, catálogo de 158 páginas derivado del inventario, filtro por rol y texto, vista de marco con siguiente/anterior de la secuencia de rol, estados de acción local para justificación, corrección, reprogramación, cancelación, método e informe, y aviso persistente de datos ficticios. La entrada `C09 · Recorridos de diseño` aparece en el menú que se abre manteniendo pulsado el logotipo de bienvenida en debug. Las rutas productivas existentes no se sustituyen ni cambian sus repositorios/permisos.

| Comprobación | Resultado |
| --- | --- |
| `flutter test test/features/design_preview/design_preview_screens_test.dart --reporter expanded` | 4/4 aprobadas: inventario y roles, recorrido/acción estudiante, decisión docente local, viewport estrecho de 320 px. |
| `flutter analyze` | Sin problemas. |
| Revisión de referencia | Se compararon visualmente las hojas del PDF 017–048 con jerarquía y tokens del prototipo. No se hizo comparación pixel a pixel ni se pudo inspeccionar Figma online. |
| AVD / ejecución móvil | No hay AVD configurado (`flutter emulators`: ninguno). La prueba de render web local quedó en lienzo gris y se detuvo; la captura de widget de test usa la fuente sustituta Ahem, no válida para evaluar texto. Revisión visual en emulador/TECNO pendiente. |
| Firebase | El catálogo no contiene repositorios ni inicializa Firebase; todas las acciones de la preview son locales. |

Archivos: `lib/features/design_preview/mockup_frame.dart`, `mockup_catalog.dart`, `presentation/design_preview_screens.dart`, `README.md`, `test/features/design_preview/design_preview_screens_test.dart` y la entrada debug de `lib/features/auth/presentation/auth_screens.dart`.

**Siguiente acción exacta:** módulo 2, dar forma específica a los marcos y recorridos de estudiante (inicio, materias, registro local, asistencia/justificaciones, horario, ayuda y estados) y actualizar su estado pantalla por pantalla en el inventario.

### Módulo 2 — recorrido de estudiante

**Resultado:** el catálogo diferencia inicio estudiantil (19–22), lista y detalle de materias (23–26), registro/check-in y comprobante (27–28, 35–36, 135–139), historial/cálculo/horario (29–31), formulario y estados de justificación (32–34, 141–142, 148, 150), resumen y estados de invitación (126, 134, 153–155, 157). P134 tiene estado sin materias; P136–144 cubren registro cerrado, comprobante, llegada tarde, cambios pendientes y fallos de documento/Bluetooth. P23 tiene búsqueda visual, P30 explica el cálculo, P31/67 presentan horarios semanales y P35 muestra un QR no válido para escanear. P148/150 explican el efecto de la decisión en la falta.

Se mantienen los datos completamente ficticios. En P27 y P35 los métodos no activan sensores. En P32–33, el mockup pide un PDF, pero C8 acepta solicitudes de texto breve y no admite adjuntos; por eso el campo permite texto y la fila PDF se muestra solo como referencia visual, con la adaptación explicada en pantalla. Las rutas reales de materias, horario, historial y justificaciones siguen siendo las actuales y conectadas al abrir el recorrido normal; la galería no las sustituye.

| Comprobación | Resultado |
| --- | --- |
| `flutter test test/features/design_preview/design_preview_screens_test.dart --reporter expanded` | 5/5 aprobadas: 158 marcos/roles, enviar texto solo después de escribir, navegar al siguiente marco, decidir una solicitud ficticia, check-in local → comprobante y viewport 320 px. |
| `flutter analyze` | Sin problemas. |
| Revisiones externas | No se abrió Firebase ni se usó cámara, Bluetooth, almacenamiento o correo. No hay AVD configurado; queda pendiente la visualización en Android real/emulado. |

**Siguiente acción exacta:** módulo 3, completar la presentación docente (home, cursos, agenda, sesión, correcciones, justificaciones, informes) y cubrir sus transiciones/estados en pruebas.

Cada módulo probado tendrá un commit y push propio. La compilación Android y revisión integrada quedan para el cierre C9.
