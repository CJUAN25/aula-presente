# Estado actual — 3 de noviembre de 2026

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

## Pendiente de validación externa

- Durante la entrega original no se publicaron `firestore.rules` ni índices. El usuario informó después que publicó los del conjunto 2; esta sesión no verificó su estado ni escribió en Firebase real.
- No se ejecutó la app ni se hicieron capturas en el TECNO CM6. La prueba manual descrita en la guía queda para el propietario.
- No se probó el estado del índice compuesto en Firebase real.
- No se ejecutó la app contra una instancia Firebase real durante esta entrega.
- No se comparó visualmente un render de Flutter con la captura de Figma; las pruebas de widget no sustituyen esa revisión.

La corrección del conteo no cambia reglas ni índices y no requiere despliegue de Firestore. Para probarla en el TECNO, el usuario tendrá que ejecutar la nueva compilación de la app; no se hizo durante esta sesión.

## Fuera de alcance

No se implementan matrículas, lista de estudiantes, sesiones de asistencia, QR, Bluetooth, justificaciones, reportes, festivos, excepciones, reprogramación, cancelación ni edición/borrado de cursos. El calendario es informativo y no reserva horarios entre dispositivos concurrentes. El usuario informó que publicó las reglas e índices del conjunto 2; esta sesión no consultó su estado.
