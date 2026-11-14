# Estado actual — 14 de noviembre de 2026

## Conjunto funcional 5: retiro y reincorporación con historial

Implementación local en `feature/conjunto-5-retiro-y-reincorporacion`, creada desde `75c3b959c644d7674f8235dc19a8b47d6577d1a7` de Conjunto 4. Conserva una sola matrícula en `courses/{courseId}/enrollments/{studentUid}`; las transiciones individuales escriben estado e historial en una transacción, mantienen `createdAt` y no se eliminan. La inscripción manual y el ingreso por código informan una matrícula retirada sin duplicarla ni reabrirla.

**Estado:** implementación revisada y cerrada en `feature/conjunto-5-retiro-y-reincorporacion`. Se consultaron los frames vigentes M01/M14/M18/M13/M15/M33/M34 y los espacios E02/E08 en modo lectura. No se modificó Figma. Los detalles del contrato, hallazgos y resultados están en [seguimiento_conjunto_5.md](seguimiento_conjunto_5.md); los pasos de activación y reproducción con dos cuentas están en [activacion_conjunto_5.md](activacion_conjunto_5.md).

**Comprobaciones locales reportadas por Codex antes de este cierre:** `flutter analyze` sin problemas; 195/195 pruebas Flutter; 74/74 pruebas de reglas en el emulador ficticio; sintaxis JS y JSON de índices válidos; `git diff --check` aprobado; widgets C5 a 320/390/430 px con escala 1.6 sin excepciones; APK debug compilada en `build/app/outputs/flutter-apk/app-debug.apk` (226,372,526 bytes). En el cierre se volvieron a validar el JSON de índices y `git diff --check`; no se repitieron análisis, pruebas Flutter, emulador ni APK porque solo se ajustaron documentación y el manifiesto de índices. La revisión independiente corrigió el acceso del estudiante a su matrícula, el orden del historial, fechas de confirmación, conteo al volver y título de aprobación histórica.

**Activación y prueba manual informadas por el propietario:** Firebase real permitió completar el recorrido en el TECNO: el docente retiró y reincorporó al estudiante, el historial se conservó y el estudiante perdió y recuperó el acceso a la misma materia y a su horario. En consola, el propietario confirmó los siete índices **Habilitados**. Codex no publicó las reglas/índices ni ejecutó esa prueba. Al activar, se conservó el índice histórico de `enrollments` de grupo de colección (`studentUid ASC`, `createdAt DESC`, `__name__ DESC`): el propietario rechazó eliminarlo y su declaración exacta se reincorporó al manifiesto porque no equivale al nuevo índice que filtra por `status`.

La comparación visual pixel a pixel sigue pendiente. El cierre local se publica en la rama del conjunto 5; `main` y la release `v0.1.0-entrega-1` se conservan separados.

## Conjunto funcional 4: ingreso por código temporal

La rama `feature/conjunto-4-ingreso-por-codigo` parte de `e4b557407a8336595a6f2ec8bbd63d06eefdf302`. El propietario informó primero dos fallos al consultar códigos nuevos en su TECNO. Codex reprodujo localmente la causa: el estudiante leía indebidamente `invitation/current`, privado del docente; esa denegación se convertía en código no disponible. Se corrigió consulta y envío para usar solo el índice autorizado, manteniendo las reglas privadas.

**Validación real informada por el propietario:** publicó reglas e índices; en el TECNO generó y renovó códigos con distinta vigencia, comprobó que desactivar impide su uso, envió una solicitud con un código nuevo, la aprobó y vio la materia y el horario en Mis materias del estudiante. Codex no ejecutó esas operaciones ni consultó Firebase real.

**Cierre de presentación:** Gestionar invitación muestra el código, Copiar, estado y vencimiento. Permite renovar, editar y desactivar; no ofrece pausar. Una invitación pausada previamente conserva Reactivar o Renovar. La operación de pausa permanece en repositorio y reglas para documentos existentes. `validForSeconds` sigue siendo la única configuración de duración, con 14 días para documentos antiguos. Las acciones conservan solicitudes, decisiones y matrículas; la vigencia y transiciones se validan en el servidor.

**Comprobaciones de Codex:** la corrección previa pasó 70/70 pruebas de reglas en emulador ficticio, sin diagnósticos del límite de 1.000 expresiones. El cierre de pantalla se verifica con Flutter, análisis y APK debug; los resultados finales están en [seguimiento](seguimiento_conjunto_4.md). **Pendiente:** revisar visualmente esta pantalla simplificada en el TECNO con la APK nueva. Esta limpieza no modifica reglas ni índices y no requiere otro despliegue de Firebase. `main` y la release privada permanecen separados de la rama. Instrucciones: [activación](activacion_conjunto_4.md).

## Cierre del conjunto 3

La rama local `feature/conjunto-3-inscripciones` implementa la inscripción manual de cuentas existentes y la consulta de materias del estudiante. Usa `student_directory/{email}` para localizar un correo exacto conocido sin listar perfiles y `courses/{courseId}/enrollments/{studentUid}` como inscripción canónica. El detalle del estudiante lee el curso y los bloques permitidos y reutiliza el generador de calendario previsto. Contratos, frames, recorridos y pruebas: [seguimiento_conjunto_3.md](seguimiento_conjunto_3.md); pasos de activación y reproducción: [activacion_conjunto_3.md](activacion_conjunto_3.md).

**Integración local verificada por Codex:** `flutter analyze` sin problemas, 120 pruebas Flutter aprobadas, 51/51 pruebas de reglas en emulador ficticio y APK debug compilada. **Validación real informada por el usuario:** publicó las reglas y el índice en `aula-presente-movil-juan-2026`, vio `enrollments` **Habilitado** en la consola y comprobó manualmente en el TECNO que el conjunto funciona. Codex no realizó esa publicación ni ejecutó la app en el teléfono. El código de esta rama aún no se ha subido a GitHub; la release privada `v0.1.0-entrega-1` conserva el primer entregable y no contiene el conjunto 3.

## Entrega implementada

El primer entregable académico dispone de una [release preliminar privada](https://github.com/CJUAN25/aula-presente/releases/tag/v0.1.0-entrega-1) con `Aula-Presente-Entrega-1.apk`. La APK se reutilizó del clon limpio del commit `56c0491e59e3a52b1601d75300b711dbe454ce9f`; el 3 de noviembre se comprobaron paquete, modo debug, mínimo API 24, arquitecturas ARM64/x86_64/ARM de 32 bits, firma e integridad tras descargar el adjunto publicado. La etiqueta conserva el commit compilado; la documentación puede avanzar en `main`. No se ejecutó la app en la Mac del docente ni se probaron otra vez los servicios Firebase reales. Detalles y huella en [entrega_1.md](entrega_1.md).

La aplicación integra Firebase Authentication y Cloud Firestore para autenticación/perfiles, solicitud y aprobación manual del acceso docente, CRUD privado `demo_records`, y el conjunto 2 de creación y consulta de cursos con horario y calendario previsto.

- C04 muestra espacios según los roles reales de `users/{uid}`. El cliente no concede `teacher` ni `admin`.
- C12/C13 y S04/S05/S06 gestionan la solicitud docente; la aprobación agrega solo `teacher` y es atómica. El resultado de la decisión no depende de una lectura posterior que pueda perder permiso.
- La entrada docente enlaza al espacio docente, cursos y agenda. D01, D02, D03/D03G1, D04, D15, D16, D17, D19, D22, D24 y X26 se alimentan del estado real de la sesión y de cursos propios; los cursos de Figma no son datos simulados.
- D15→D16→D19→D17 conserva el borrador, permite volver y corregirlo y confirma la creación antes de abrir el detalle. Los conflictos se comprueban con todos los cursos propios paginados.
- El curso y entre uno y ocho bloques semanales se escriben juntos en una transacción. `courses/{courseId}` conserva metadatos e IDs ordenados; `weekly_blocks/{blockId}` guarda cada bloque. Rules valida pertenencia al padre, rango, ocurrencia y solapamiento. El calendario se calcula; no se guardan documentos por encuentro.
- D01, D24, D04 y D22 muestran encuentros **previstos**. El paso del tiempo no los convierte en sesiones ni registra asistencia. Las listas se consultan del servidor y se pueden actualizar.
- La retirada de sesión o del rol docente cierra las rutas protegidas. Crear y consultar cursos requiere correo verificado, perfil válido, `teacher` y coincidencia del propietario.

El 29 de octubre el usuario reportó que, durante la prueba real del conjunto 2, Lógica (martes/jueves) recibió una advertencia de 17 encuentros frente a Móvil (lunes/viernes). La reproducción local con esos días no generó cruces; no se inspeccionaron los documentos reales ni se confirmó la causa de ese aviso. Se corrigió por separado un defecto demostrado del conteo: un encuentro propuesto ya no se cuenta varias veces por coincidir con varios cursos. Véase [seguimiento_conjunto_2.md](seguimiento_conjunto_2.md).

El 2 de noviembre el usuario informó que el aviso persistía (13 al acortar el período), con solo Móvil guardado. El diagnóstico recibido muestra **Móvil con lunes 08:00–10:00 y martes 06:00–10:00**, y Lógica con martes/jueves 08:00–09:00. Sus 17 coincidencias son los 17 martes compartidos del 01/11/2026 al 28/02/2027. El usuario confirmó posteriormente ese horario de Móvil y quedó explicada la advertencia. El formulario actual conserva viernes como día 5 en la prueba añadida. No se modificaron cursos reales ni el detector. Evidencia: [diagnostico_conflictos_horarios.md](diagnostico_conflictos_horarios.md#resultado-del-informe-recibido).

**Cierre del aviso de horarios:** el usuario confirmó después que Móvil tiene realmente lunes 08:00–10:00 y martes 06:00–10:00. El diagnóstico coincide con ese horario y la advertencia es correcta al cruzarlo con los martes de Lógica. Este caso queda explicado y cerrado; no hay corrección funcional o de datos pendiente por esta incidencia. No se modificó el código de la app en este cierre documental.

El usuario informó que había comprobado manualmente el conjunto 1 en Firebase real y en el TECNO CM6 (solicitud, aprobación, rechazo, acceso docente y cierre de sesión). Esa comprobación se registra como reporte del usuario; no se repitió durante esta sesión.

El esquema, permisos, límites y decisiones se describen en [arquitectura.md](arquitectura.md). La prueba manual del conjunto 2 está en [activacion_conjunto_2.md](activacion_conjunto_2.md).

## Diseño consultado

La referencia fue la página `01 · Aula Presente · Rediseño` (`25:57`) del archivo vigente. Se revisaron los frames D01 (`30:34`), D02 (`30:35`), D03 (`30:36`), D03G1 (`30:49`), D04 (`30:37`), D15 (`2005:10871`), D16 (`2005:10975`), D17 (`2005:11106`), D19 (`2005:11378`), D22 (`2005:11715`), D24 (`2005:11871`) y X26 (`2005:16175`). No se usaron las páginas archivadas ni se modificó Figma.

La implementación reutiliza Manrope, tema y componentes existentes. Se adaptaron carga, vacío, error, confirmación y accesibilidad al estado real. Los tests de widgets comprueban tamaños y texto ampliado, pero no se hizo una comparación pixel a pixel entre un render de Flutter y Figma.

## Verificación local y en emulador

Tras recibir el informe: `flutter analyze` sin problemas y `flutter test --reporter expanded` con 108 pruebas aprobadas. Se añadieron dos regresiones para las 17 coincidencias explicadas por los datos recibidos y para la selección lunes/viernes hasta el borrador canónico. No cambió código productivo ni se recompiló la APK en esta continuación.

Continuación del 2 de noviembre: `flutter analyze` sin problemas, `flutter test --reporter expanded` con 106 pruebas aprobadas y APK debug compilada. Se ejecutó el repositorio Dart real con respuestas del SDK controladas; no se ejecutó el SDK nativo contra el emulador ni Firebase real. El informe debug y los pasos pendientes se describen en [diagnostico_conflictos_horarios.md](diagnostico_conflictos_horarios.md).

Resultados del cierre del conjunto 2:

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Aprobado; sin problemas. |
| `flutter test` | Aprobado; 85 pruebas. Incluye dominio/calendario, presentación, navegación y roles. |
| Firestore Emulator, proyecto ficticio `demo-aula-presente-firestore-rules-tests` | Aprobado; 41/41 casos de Rules Unit Testing con SDK JS. Sin errores del límite de 1000 expresiones. Incluye regresiones del conjunto 1 y cursos, máximo de ocho bloques, solapes, calendario de un día, privacidad, timestamps e idempotencia. |
| `node --check tools/firestore_rules_tests/firestore_rules.test.js` | Aprobado. |
| `flutter build apk --debug` | Aprobado; `build/app/outputs/flutter-apk/app-debug.apk`. Gradle mostró avisos no bloqueantes de acceso nativo restringido en Java y del Kotlin Gradle Plugin de `firebase_auth`/`firebase_core`. |

La suite del emulador prueba las reglas y transacciones con el SDK de JavaScript; no ejecuta el repositorio Dart contra el emulador. El dominio prueba por separado los mapas canónicos y Flutter prueba la lógica/presentación con repositorios controlados.

## Registro histórico de validación externa del conjunto 2

- Durante la entrega original no se publicaron `firestore.rules` ni índices. El usuario informó después que publicó los del conjunto 2; esta sesión no verificó su estado ni escribió en Firebase real.
- Durante ese cierre, Codex no ejecutó la app ni hizo capturas en el TECNO CM6. El usuario reportó después la prueba manual del conjunto 3, registrada al inicio de este documento.
- No se probó el estado del índice compuesto en Firebase real.
- No se ejecutó la app contra una instancia Firebase real durante esta entrega.
- No se comparó visualmente un render de Flutter con la captura de Figma; las pruebas de widget no sustituyen esa revisión.

La corrección del conteo no cambia reglas ni índices y no requiere despliegue de Firestore. Para probarla en el TECNO, el usuario tendrá que ejecutar la nueva compilación de la app; no se hizo durante esta sesión.

## Fuera de alcance del conjunto 2

Al cerrar el conjunto 2 no se habían implementado matrículas ni lista de estudiantes; el conjunto 3 implementó ambas funciones sin alterar los cursos existentes. Siguen fuera de alcance sesiones de asistencia, QR, Bluetooth, justificaciones, reportes, festivos, excepciones, reprogramación, cancelación y edición/borrado de cursos. El calendario es informativo y no reserva horarios entre dispositivos concurrentes. El usuario informó que publicó las reglas e índices del conjunto 2; esa sesión no consultó su estado.
