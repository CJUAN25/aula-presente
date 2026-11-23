# Seguimiento del conjunto 9 — maquetación y navegación

## Integración de la revisión C8 — 22/11/2026

C9 integra el commit C8 `3014c4b28c7bd0749414c8cccce8ea4f3977c61e` mediante una fusión que conserva ambos historiales. La corrección, la bandeja y la recuperación de publicación se abren en la ruta real **Mis cursos → curso → Asistencia → Gestionar**. El estudiante entra por **Mis materias → curso → Consultar asistencia**. Las rutas de curso, acceso y matrícula comparten sus repositorios existentes. El menú debug conserva **C09 · Recorridos de diseño** con sus perfiles y datos ficticios.

Para la prueba física, usa las reglas publicadas para C8 1.0.2+3 y abre una sesión por horas desde el curso real en la APK C9. Guarda una corrección, reabre la fila y consulta el resultado desde estudiante. Abre luego la galería desde el logotipo de bienvenida y verifica los filtros de estudiante y docente. Los pasos anteriores de justificación y restauración están en el [seguimiento C8](seguimiento_conjunto_8.md).

## Punto de partida y recuperación de la rama — 17/11/2026

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
| 3 | Docente: home, agenda, informes y estados | 37–58, 67, 126–128, 149 | Recorrido por módulos y prueba adaptable | Implementado; 8/8 pruebas y análisis limpios. |
| 4 | Métodos de sesión y estados de prototipo | 6, 9–10, 13, 111–125, 128, 133, 135, 143, 147, 155–156 | Interacción local, datos ficticios, carga→resultado y errores | Implementado; 12/12 pruebas y análisis limpios. |
| 5 | Revisión de pantallas conectadas e inventario final | 1–5, 7–8, 11–18, 23–26, 29, 31, 39–56, 59–66, 73–110, 129–131 | Confirmar rutas/contratos conservados, registrar cobertura por marco | Auditoría de rutas/tema completada; 158 filas; prueba integrada 371/371. Revisión nativa Android pendiente por falta de AVD. |

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

### Módulo 3 — recorrido de docente

**Resultado:** el home muestra clase próxima/registro abierto y resumen. El detalle prototipo cubre cursos y calendario, reprogramación con selector de fecha/hora/lugar y alcance futuro, motivo opcional al cancelar/corregir, método manual/Bluetooth/QR/NFC sin activar sensores, sesión activa, cierre con **Seguir registrando** o confirmación, corrección Presente/Ausente, bandeja/revisión Aprobar/Rechazar, agenda semanal, reglas de cálculo e informe de muestra. Los estados de curso archivado y cambio de horario son locales. El flujo real de asistencia, matrícula, cursos, reprogramación y justificaciones C8 permanece en sus rutas/repositorios de siempre.

| Comprobación | Resultado |
| --- | --- |
| `flutter test test/features/design_preview/design_preview_screens_test.dart --reporter expanded` | 8/8 aprobadas, incluye: aprobación/rechazo ficticios, cancelación con motivo vacío y opción **Cancelar**, cierre de asistencia reanudable (**Seguir registrando**), corrección de marca sin motivo, check-in local y viewport 320 px. |
| `flutter analyze` | Sin problemas. |
| Límite de integración | No se escribieron sesiones/resultados reales ni se abrieron Bluetooth, NFC, cámara, correo o Firebase. No hay AVD/imagen de sistema instalado; la revisión visual en Android sigue pendiente. |

**Siguiente acción exacta:** módulo 4, completar estados compartidos/admin y métodos de asistencia en los marcos 6, 9–18, 111–125, 128–133, 143–158; cubrir errores, recuperación y los restantes estados de acción ficticia. Después, módulo 5 revisará las rutas conectadas por código y cerrará el inventario.

### Módulo 4 — métodos, estados compartidos y administración

**Resultado:** los marcos QR/Bluetooth/NFC (111–125) ofrecen selección de método, duración y una acción local claramente rotulada; no activan sensores ni modifican la sesión C8. Se completaron el estado de teléfono/permisos (6, 133, 143), notificaciones/ayuda (9, 10, 13), estadísticas ficticias de administración (128), reapertura/QR vencido (147, 155), el conflicto de horario (156) y búsqueda de clase (135). La búsqueda muestra progreso mientras está activa y lo reemplaza con el resultado ficticio al terminar la acción, sin conservar un spinner indefinido. El panel de justificación mantiene la adaptación de PDF visual a texto C8.

| Comprobación | Resultado |
| --- | --- |
| `flutter test test/features/design_preview/design_preview_screens_test.dart --reporter expanded` | 12/12 aprobadas: catálogo/roles, flujos locales estudiante y docente, cancelar/cerrar/corregir sin motivo, selección de duración, estadística ficticia admin, progreso→resultado de búsqueda, estados de permiso/conflicto y viewport 320 px. |
| Fallos durante la prueba | Se corrigió el test para avanzar la transición con la búsqueda animada sin esperar que un spinner indefinido se estabilizara; el test confirma que al simular el resultado el spinner desaparece. Los mensajes de estado se verificaron como parte del texto accesible de la tarjeta. |
| `flutter analyze` | Sin problemas. |
| Firebase / dispositivo | C8 productivo y sus reglas no se modificaron. La galería no llama Firebase. No hay AVD configurado; la revisión visual nativa queda pendiente. |

**Siguiente acción exacta:** módulo 5, revisar la implementación de las rutas conectadas contra sus contratos, no sustituir repositorios ni permisos y completar en `docs/inventario_mockups_conjunto_9.md` el resultado final por página y su condición de pantalla conectada o demo local.

Cada módulo probado tendrá un commit y push propio. La compilación Android y revisión integrada quedan para el cierre C9.

### Módulo 5 — rutas productivas e inventario final

**Resultado:** se revisaron por grupo las rutas de autenticación/perfil, acceso docente, entrada a cursos, cursos y calendario, matrículas/Excel, asistencia C8 y revisión administrativa. Las pantallas productivas conservan navegación, repositorios, datos y controles de rol. Auth usa `AuthPage`/`PrimaryButton`; cursos y matrículas reutilizan `CoursePage`, `CourseContent`, `CoursePanel` y `AppColors`; el tema común define Manrope, fondo verde oscuro, superficies pino y acento menta. `AdminTeacherRequestsScreen` vuelve a comprobar el rol administrador antes de mostrar solicitudes. La galería debug permanece aislada y no altera reglas ni flujos C8.

Las rutas productivas no tienen una pantalla nueva para home/resumen completo, notificaciones/ayuda, estadísticas ni métodos de proximidad. Esas páginas se muestran como demostraciones locales. QR/Bluetooth/NFC no se integraron con sensores; el PDF de justificación no se adjunta porque C8 solo recibe texto. Esta es la adaptación explícita para no cambiar el contrato funcional ni crear permisos/configuración de Firebase no acordados. El inventario final registra las 158 páginas, con 101 rutas existentes y 57 vistas demo; no significa que existan 158 pantallas productivas distintas.

La fuente tampoco ofrece marcos propios para la recuperación `closing` de una sesión manual, la publicación pendiente por estudiante, la restauración de una asistencia anulada ni el error `permission-denied` del cierre. Se conserva para esos casos el progreso, error/reintento y recuperación ya implementados en C8; el mockup de confirmación del cierre no representa que los resultados ya estén publicados. No se creó otra pantalla de producto ni se cambió el esquema para cubrir esa falta visual.

| Verificación final | Resultado |
| --- | --- |
| `flutter test --reporter compact` | **371/371 aprobadas**, incluidas las 12 pruebas de la galería y regresiones de los conjuntos existentes. |
| `flutter analyze` | Sin problemas. |
| `flutter build apk --debug` | Compiló. APK C9 en `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256 `3FDC302D8AA1E2A1B8AFD397CCFF4BA3D541F215B452728016E49C507A198022`. C8 se conservó en `build/artifacts/app-c8-1.0.1+2-debug.apk`. |
| `git diff --check` | Sin errores de espacios; Git solo informó conversiones habituales de LF/CRLF. |
| Firestore Rules Emulator | C9 no cambió reglas. Se conserva la verificación C8 del mismo commit base: 109/109; ruleset activo ya comprobado, sin índice adicional para C9. |
| Inspección en móvil | No completada: `flutter emulators` informó que no hay AVD. El intento web previo quedó en lienzo gris y se detuvo; queda por revisar la APK en Android/TECNO y comprobar dimensiones/teclado en el dispositivo. |

**Siguiente acción para la validación visual:** instalar la APK de C9 en un emulador Android configurado o dispositivo, abrir en debug el logo de bienvenida con pulsación larga, elegir **C09 · Recorridos de diseño** y recorrer Estudiante, Docente, Compartido y Administración. Las acciones de esos recorridos son ficticias. Para datos y permisos reales, salir del catálogo e iniciar sesión por las rutas normales. No se requiere publicar reglas ni índices por C9.
