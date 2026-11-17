# Estado actual — 17 de noviembre de 2026

## C8 ampliado — versión local 1.0.1+2

El propietario confirmó en TECNO registro, finalización y consulta, y reportó el fallo Ausente → Presente en la segunda hora de sesiones finalizadas normales/reprogramadas. Se verificó e integró `aula-presente-c8-correccion-finalizada.patch` sin conflictos, conservando los ajustes locales de v2 y las dos regresiones. Se añadieron motivos opcionales, Cancelar anulación, restauración `voided → restoring → finalized` desde marcas conservadas y solicitudes de texto del estudiante por encuentro/tramo con decisión docente atómica e idempotente. Los eventos conservan valores, actor y hora; la aprobación mantiene el denominador y descuenta solo la cobertura de esa ausencia. El historial/publicación se cargan después de los datos necesarios para mostrar la lista, conservando validaciones y errores.

Verificación local: **359/359** Flutter completos, **80/80** dirigidos, **109/109** reglas en emulador, análisis limpio y APK debug **1.0.1+2** compilada. Repositorio y pantallas se probaron con datos sintéticos; no equivale a FlutterFire en Android ni a la prueba física. **Hay que publicar el `firestore.rules` nuevo antes de instalar/probar esta APK; no hay índices nuevos.** La guía, evidencia y huellas están al inicio del [seguimiento C8](seguimiento_conjunto_8.md). No hubo publicación en Firebase, instalación en TECNO ni nuevo commit/push. Los apartados siguientes conservan el historial anterior.

## Revisión visual local de C8

Sobre `feature/conjunto-8-asistencia-manual-v2`, base `46a8893`, se revisaron las páginas docentes relevantes de `../FIGMA/NUEVA CORRECCION.pdf`; el conector Figma requiere reconexión. Se añadieron búsqueda local y contadores por tramo, selección de ambas horas también después de finalizar, acciones de guardar/finalizar después de la lista y estado de publicación al inicio. Carga/error bloquean las acciones hasta recargar; el error de escritura permanece visible. El selector se adapta a 320 px con texto ampliado. La lógica de asistencia, repositorio y reglas del arreglo anterior se conservan.

Verificado en esta revisión: **67/67** pruebas Flutter dirigidas (pantallas reales con datos sintéticos y capturas), **2/2** regresiones de cierre en Firestore Emulator, análisis sin problemas, APK debug compilada y diff sin errores. No hay emulador Android disponible ni ejecución del APK/FlutterFire en teléfono. La tabla **pantalla o flujo | referencia original | cómo quedó | motivo** y la nueva huella de APK están al inicio del [seguimiento C8](seguimiento_conjunto_8.md). La exportación no contiene una referencia específica de registro por horas ni de cierre reanudable/publicación pendiente; esas adaptaciones están identificadas. La comparación con la página online y la validación del APK en TECNO siguen pendientes. Estos ajustes permanecen locales, sin un nuevo commit/push.

## Nuevo incidente C8 — punto de partida de esta revisión

Checkout verificado: `feature/conjunto-8-asistencia-manual`, commit `bed4ac83fd1d82b53080df0af1d2dc467208d4e4`, remoto `CJUAN25/aula-presente`, sin cambios locales al iniciar. El propietario informa que publicó manualmente en `aula-presente-movil-juan-2026`, base `(default)`, las reglas que tenía en VS Code. La versión exacta publicada y la APK usada en el TECNO siguen por confirmar; esto sustituye la afirmación anterior de que no hubo publicación posterior.

En Lógica, clase reprogramada al **16/11/2026 06:00–08:00**, modalidad **Por horas**, el docente pudo entrar y la sesión llegó a **Finalizando**. **Continuar finalización** devuelve `permission-denied` y queda atascada. También reporta demoras en **Preparar lista**, **Completar lista** y **Ver lista**. Son observaciones del propietario, no pruebas ejecutadas por Codex.

**Resultado local de esta revisión:** el cierre se reprodujo desde `closing/ready` con dos tramos y marcas existentes. La creación de `attendance_records/{sessionId}|{rosterEntryId}` agotaba 1.000 expresiones en el validador de proyecciones por horas. Se simplificó su evaluación, publicación y lectura propia conservando permisos, claves y transiciones, en un solo `firestore.rules`. La recuperación con 2 y 12 estudiantes reutiliza sesión, marcas y resultados sin duplicados. Se midieron las etapas del repositorio y se paralelizaron lecturas independientes con límites, conservando historial y revalidación a la fecha efectiva. La interfaz muestra demora y error persistente. En el ensayo controlado de 12 personas, preparar/completar/ver lista pasaron de 622/520/43 ms a 247/199/23 ms; no son tiempos medidos en TECNO ni Firebase real.

Análisis sin problemas, **57/57** pruebas Flutter dirigidas, **101/101** pruebas de reglas en emulador (cero diagnósticos de límite de expresiones), sintaxis JS/diff aprobados y APK debug recompilada. El [seguimiento C8](seguimiento_conjunto_8.md) contiene causa, límites, mediciones, huellas de reglas/APK y pasos exactos para retomar **Continuar finalización**. **El propietario debe publicar las reglas de esta revisión e instalar la APK nueva**; no se modificaron índices, publicaron reglas, crearon cuentas reales ni ejecutó la app en el teléfono. Los apartados inferiores conservan antecedentes y sus cifras no son verificaciones de esta sesión.

## Actualización del 16 de noviembre de 2026

El propietario reportó en TECNO/Firebase real que funcionan el borrador, la publicación, la consulta del estudiante, la corrección, la recuperación de una anulación y la visualización de cambios del calendario. Codex no ejecutó esos recorridos. La corrección del reintento de nóminas incompletas se reprodujo localmente: Rules agotaba el límite de 1.000 expresiones al recorrer 24 posiciones de segmentos para sesiones de dos tramos. Se acotó la evaluación sin ampliar permisos ni permitir cambios de marcas; también se corrigió el cambio de conteo al completar una lista revalidada. La tarjeta ahora indica **Lista incompleta → Completar lista** y ofrece una acción por estado. El motivo tardío se solicita solo cuando falta y corresponde.

Verificación local de la corrección: análisis sin problemas, **53/53** pruebas Flutter afectadas, **99/99** reglas en emulador y APK debug compilada. La rama de revisión es [`feature/conjunto-8-asistencia-manual`](https://github.com/CJUAN25/aula-presente/tree/feature/conjunto-8-asistencia-manual). Para probar el ajuste en Firebase real falta publicar el `firestore.rules` actualizado e instalar la APK en el TECNO. El propietario reportó el índice `attendance_records` **Habilitado**; no se solicita redesplegar índices. La causa comprobada, límites, pruebas y los encuentros del 15/16 están en [seguimiento C8](seguimiento_conjunto_8.md). Los apartados inferiores conservan antecedentes históricos.

## Conjunto funcional 8: asistencia manual por encuentro o por horas

Implementación en la rama `feature/conjunto-8-asistencia-manual`, basada en el cierre C7 `55b9336bb39ea157345a2f659e4876bfbf5f938f`. Conserva `schedule` como fuente de fechas previstas y la matrícula canónica C7 como fuente de pertenencia. El docente elige una modalidad por curso, prepara una sesión por ocurrencia, toma y guarda marcas, confirma pendientes antes de finalizarlas y puede corregir, revisar una justificación ya decidida o anular con motivo e historial. Antes de finalizar, el repositorio verifica la nómina y las proyecciones `staged`; después publica cada resultado propio por filas. La disponibilidad entre estudiantes es eventual, cada fila se muestra completa, y la pantalla docente comprueba/reanuda una publicación pendiente sin repetir la toma de asistencia. El estudiante consulta únicamente la proyección publicada de su identidad estable y ve el cálculo de sus unidades.

El roster se resuelve con fechas efectivas de ingreso, retiro y reincorporación. Un error al leer una fuente o un historial legacy ambiguo no produce una lista parcial: bloquea la preparación. El esquema C8, los campos, permisos, transiciones y fórmula se documentan en [arquitectura](arquitectura.md#conjunto-funcional-8-asistencia-manual) y el contrato previo a integración en [contrato C8](contrato_integracion_conjunto_8.md).

**Estado:** el código C8 está en la rama de revisión. El manifiesto contiene el índice compuesto de `attendance_records` y el propietario reportó que está **Habilitado**. Rules local incorpora C8 y la corrección posterior del 16/11; la lectura de Rules API del 15/11 es anterior a esa corrección, así que la versión más reciente todavía debe publicarse para probarla en producción. Codex no desplegó reglas ni índices, no creó datos reales ni ejecutó la app en el TECNO. El propietario sí reportó que ya probó borrador, publicación, consulta, corrección, recuperación de anulación y calendario; falta repetir con la APK corregida los reintentos de las sesiones del 15 y 16. Consulta [seguimiento C8](seguimiento_conjunto_8.md) y [activación C8](activacion_conjunto_8.md).

**Verificaciones locales de la integración y su corrección:** `flutter analyze` sin problemas; pruebas Flutter dirigidas **53/53**; Firestore Rules Emulator **99/99**; `node --check` aprobado y APK debug compilada en `build/app/outputs/flutter-apk/app-debug.apk`. En la corrección del 16/11 no se repitió la suite Flutter completa. Las pruebas de permisos usan el emulador local y no consultan Firebase real. El detalle y comandos están en [seguimiento C8](seguimiento_conjunto_8.md).

**Actualización tras prueba del propietario:** además de los recorridos anteriores, reportó que puede recuperar una anulación y ver cambios de calendario. El fallo al reintentar nóminas incompletas quedó reproducido en emulador y su causa local fue el límite de expresiones de Rules; se corrigió y se añadieron regresiones. No se inspeccionaron los documentos reales, por lo que la relación exacta de cada sesión reportada con las reproducciones sintéticas no está confirmada. La corrección requiere publicar reglas y probar la APK en el TECNO; no se desplegó ni se modificaron datos reales o índices. Véase [seguimiento C8](seguimiento_conjunto_8.md).

## Conjunto funcional 7: actualización de lista desde Excel

Implementación local en `feature/conjunto-7-actualizacion-lista-excel`, basada en `b6cb49ebf2923244a17b7a0d186f03c4c33b7990` (cierre del conjunto 6). Añade comparación de lista completa para docentes, selección explícita de altas y retiros, y autorizaciones pendientes que permiten vincular después a estudiantes existentes por correo y código exactos. Conserva la opción C6 **Solo agregar estudiantes**, la matrícula canónica y el historial; los retiros potenciales comienzan desmarcados y requieren lista completa válida, lectura completa y confirmación. El alumno vincula una autorización únicamente con correo verificado, perfil/código válidos y transacciones protegidas por Rules.

### Ajuste final: historial de matrícula por curso

El propietario reportó que un estudiante reincorporado ya no aparecía en **Retirados e histórico**, aunque su detalle conservaba ingreso, retiro y reincorporación. La causa comprobada en código es que esa lista consulta matrículas cuyo estado canónico actual es `withdrawn`; tras reincorporar, el mismo documento queda `active` y deja correctamente la lista operativa.

Se añadió **Gestionar estudiantes → Historial de matrícula**. Reutiliza el snapshot completo del roster y las consultas existentes, resuelve una fila por identidad estable, prioriza la matrícula canónica sobre una autorización vinculada y abre el mismo detalle que la ficha. Los eventos se leen al entrar al detalle, sin escrituras ni cambios de esquema. **Retirados** sigue mostrando solo matrículas actualmente retiradas.

**Prueba manual reportada por el propietario en TECNO con Firebase real:** en el recorrido principal comprobó las altas desde Excel, el vínculo posterior de un pendiente, la selección de retiros y la reincorporación; el historial individual se conservó. Después probó el ajuste final: el reincorporado aparece una sola vez como **Activo** en **Historial de matrícula**, conserva **Ingreso**, **Retiro confirmado** y **Reincorporación confirmada**, su ficha abre el mismo historial y ya no aparece en **Retirados**. **Historial de matrícula** permite encontrar a una persona sin importar su estado actual; **Retirados** queda para gestionar personas que siguen retiradas. Codex no ejecutó la app en el teléfono ni verificó Firebase real.

**Verificaciones locales tras el ajuste final (antes de este cierre):** `flutter analyze` sin problemas; `flutter test --reporter compact` pasó **281/281**; Firestore Rules Emulator **80/80**; `git diff --check` aprobado con avisos habituales de LF/CRLF; APK debug compilada en `build/app/outputs/flutter-apk/app-debug.apk` (218.606.974 bytes). No contactaron Firebase real.

**Comprobaciones de este cierre:** se revisaron el diff completo respecto al commit base, los fixtures Excel y el destino remoto; se validaron `firestore.indexes.json` y `git diff --check`. Como el cierre solo actualiza documentación, no se repitió la suite ni la compilación.

No se modificaron `firestore.rules` ni `firestore.indexes.json` durante el ajuste final de historial ni durante este cierre. Ambos archivos sí contienen los cambios del conjunto 7 respecto a la base C6 y forman parte de la rama. No se ejecutó `firebase deploy`. Este cierre publica únicamente la rama feature; no hace merge ni modifica `main` o `v0.1.0-entrega-1`. Los detalles están en [seguimiento_conjunto_7.md](seguimiento_conjunto_7.md) y la guía reproducible en [activacion_conjunto_7.md](activacion_conjunto_7.md).

## Conjunto funcional 6: altas por Excel

La rama local `feature/conjunto-6-importacion-excel` parte de `901ff6715f2dbf8808558e77721ed4f98c1ea8de`, cierre publicado del conjunto 5. Permite elegir un `.xls` BIFF8 o `.xlsx` en el dispositivo, revisar correo exacto y código contra el directorio, seleccionar altas elegibles y confirmarlas con transacciones individuales sobre la matrícula canónica. Una matrícula activa no se duplica y una retirada no se reactiva. El archivo no se sube a Firebase y las columnas de documento, teléfono, EPS y otras ajenas se descartan. El curso viene de la pantalla docente, no del Excel.

**Implementado y probado localmente:** lector con fixtures ficticios, revisión y resultados por fila, navegación M01→M02→M03→M04→M19→M23→M05, control de doble toque y retorno a la lista. `flutter pub get` pasó, `flutter analyze` no encontró problemas, `flutter test` pasó **222/222**, Firestore Emulator pasó **75/75** con proyecto ficticio, `git diff --check` pasó y se compiló la APK debug en `build/app/outputs/flutter-apk/app-debug.apk`. Las pruebas dirigidas incluyeron 7 del lector, 32 de coordinador/repositorio y 8 de interfaz. La revisión independiente detectó una hoja vacía sin explicación y hojas incompatibles omitidas; se corrigieron y probaron. El contrato, los límites y la evidencia están en [seguimiento_conjunto_6.md](seguimiento_conjunto_6.md); el recorrido corto para el TECNO está en [activacion_conjunto_6.md](activacion_conjunto_6.md).

**Validación manual reportada por el propietario:** en el TECNO con Firebase real, el docente importó una copia `.xls` y confirmó el alta de una cuenta de prueba cuyo correo y código coincidían. El estudiante vio el curso en **Mis materias** sin solicitud ni aceptación adicional. Otra cuenta sin código estudiantil para el cotejo no pudo vincularse; no se especifica si el dato faltaba en la fila o en el perfil. Al reimportar el mismo archivo en el mismo curso, la cuenta apareció como **«Ya inscrita»** y no se ofreció otra vez como alta. Codex no ejecutó ni observó esta prueba en el teléfono.

El propietario no reportó prueba en el TECNO del `.xlsx`, del Excel original sin modificar ni de otros estados. La lectura local sí se probó con un `.xls` BIFF8 ficticio equivalente de 35 filas y un `.xlsx` mixto. No se probó un libro auténticamente cifrado ni se hizo comparación pixel a pixel de Flutter con Figma. El flujo importa cuentas existentes con el cotejo requerido; una cuenta sin vínculo disponible puede revisarse al volver a importar después. No se crea reserva ni alta automática futura. La incidencia del correo institucional de Outlook sigue pendiente por separado, sin causa confirmada. No se cambiaron ni desplegaron reglas o índices para el conjunto 6; `main` y la release `v0.1.0-entrega-1` permanecen separados.

**Incidencia independiente de Outlook:** el propietario reportó que su cuenta institucional aparece en Firebase Authentication y la app indica verificación pendiente, pero no ha recibido el mensaje. La causa no está determinada. El conjunto 6 no cambia el correo ni relaja la verificación; la demostración utiliza cuentas controladas que ya puedan verificar y entrar al espacio Estudiante.

## Conjunto funcional 5: retiro y reincorporación con historial

Implementación local en `feature/conjunto-5-retiro-y-reincorporacion`, creada desde `75c3b959c644d7674f8235dc19a8b47d6577d1a7` de Conjunto 4. Conserva una sola matrícula en `courses/{courseId}/enrollments/{studentUid}`; las transiciones individuales escriben estado e historial en una transacción, mantienen `createdAt` y no se eliminan. La inscripción manual y el ingreso por código informan una matrícula retirada sin duplicarla ni reabrirla.

**Estado:** implementación revisada y cerrada en `feature/conjunto-5-retiro-y-reincorporacion`. Se consultaron los frames vigentes M01/M14/M18/M13/M15/M33/M34 y los espacios E02/E08 en modo lectura. No se modificó Figma. Los detalles del contrato, hallazgos y resultados están en [seguimiento_conjunto_5.md](seguimiento_conjunto_5.md); los pasos de activación y reproducción con dos cuentas están en [activacion_conjunto_5.md](activacion_conjunto_5.md).

**Comprobaciones locales reportadas por Codex antes de este cierre:** `flutter analyze` sin problemas; 195/195 pruebas Flutter; 74/74 pruebas de reglas en el emulador ficticio; sintaxis JS y JSON de índices válidos; `git diff --check` aprobado; widgets C5 a 320/390/430 px con escala 1.6 sin excepciones; APK debug compilada en `build/app/outputs/flutter-apk/app-debug.apk` (226,372,526 bytes). En el cierre se volvieron a validar el JSON de índices y `git diff --check`; no se repitieron análisis, pruebas Flutter, emulador ni APK porque solo se ajustaron documentación y el manifiesto de índices. La revisión independiente corrigió el acceso del estudiante a su matrícula, el orden del historial, fechas de confirmación, conteo al volver y título de aprobación histórica.

**Activación y prueba manual informadas por el propietario:** Firebase real permitió completar el recorrido en el TECNO: el docente retiró y reincorporó al estudiante, el historial se conservó y el estudiante perdió y recuperó el acceso a la misma materia y a su horario. En consola, el propietario confirmó los siete índices **Habilitados**. Codex no publicó las reglas/índices ni ejecutó esa prueba. Al activar, se conservó el índice histórico de `enrollments` de grupo de colección (`studentUid ASC`, `createdAt DESC`, `__name__ DESC`): el propietario rechazó eliminarlo y su declaración exacta se reincorporó al manifiesto porque no equivale al nuevo índice que filtra por `status`.

La comparación visual pixel a pixel sigue pendiente. El conjunto 5 quedó publicado en `feature/conjunto-5-retiro-y-reincorporacion`; `main` y la release `v0.1.0-entrega-1` se conservan separados.

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
