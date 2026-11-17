# Activación y prueba manual — conjunto 8

## Versión vigente para la próxima prueba: 1.0.1+2 (17/11)

Publica **el `firestore.rules` completo nuevo** en `aula-presente-movil-juan-2026`, base `(default)`, e instala la APK recompilada `build/app/outputs/flutter-apk/app-debug.apk`, versión **1.0.1+2**. No hay índices nuevos. Esta revisión corrige la segunda hora finalizada, permite motivos opcionales, restaura asistencias finalizadas anuladas y añade solicitudes estudiantiles de texto. La publicación y prueba física las hace el propietario. Los pasos exactos para cada flujo y las huellas están en el [inicio del seguimiento C8](seguimiento_conjunto_8.md#ampliación-y-corrección-de-c8--17112026--apk-1012).

Los recorridos inferiores son antecedentes: donde indiquen motivo obligatorio para asistencia/calendario, ahora puede dejarse vacío. **Cancelar** no aplica cambios. La justificación puede iniciarla el estudiante desde su propia ausencia; el docente propietario decide Aprobar/Rechazar. Para una sesión ya finalizada y anulada, usa **Restaurar asistencia**, o **Continuar restauración** después de una interrupción; nunca recrees la sesión.

Esta guía es para el propietario. El índice `attendance_records` está **Habilitado** según su reporte y ya comprobó flujos C8 en TECNO con Firebase real. También reportó una publicación manual de reglas desde VS Code; la versión exacta y la APK anterior siguen por confirmar. El cierre por horas de Lógica reprogramada al 16/11 06:00–08:00 falló en **Continuar finalización**. El nuevo ajuste se probó localmente con una sesión ya `closing`, y necesita publicar **solo las reglas revisadas** e instalar la **APK recompilada**. Codex no desplegó reglas ni índices ni operó el teléfono. No se deben usar datos sensibles de excusas.

## Recuperar primero Lógica en Finalizando

Las huellas SHA-256 de los archivos nuevos y los pasos completos están en [seguimiento C8: APK, reglas y TECNO](seguimiento_conjunto_8.md#apk-reglas-y-repetición-exacta-en-el-tecno). Tras publicar el único `firestore.rules` e instalar `build/app/outputs/flutter-apk/app-debug.apk`, abre **Lógica → Asistencia → Gestionar → 05/11 reprogramada al 16/11/2026 06:00–08:00 → Continuar cierre → Continuar finalización**. Conserva la misma sesión. Comprueba ambos tramos, marcas previas, estado Finalizada y consulta propia publicada del estudiante. Reabrir/reintentar no debe duplicar resultados ni cambiar las marcas. Si queda publicación pendiente, reanúdala ahí mismo.

Mide también Preparar lista, Completar lista y Ver asistencia en un encuentro de ensayo. La interfaz avisa si tarda más de ocho segundos y conserva el error de apertura; Diagnóstico muestra etapa/código. En debug, `[C8]` registra duración por etapa sin datos personales. Registra APK, reglas, acción, cantidad de estudiantes, segundos y resultado. Los tiempos del seguimiento son ensayos locales con demora artificial, no tiempos prometidos para el TECNO. Los apartados siguientes conservan los recorridos generales y antecedentes.

## Corrección tras prueba real

El propietario ya probó borrador, publicación, consulta y corrección Ausente → Presente. Esta APK corrige la anulación y añade calendario estudiantil seguro; requiere publicar únicamente las reglas revisadas, conservando el índice habilitado. Codex no desplegó ni reparó datos reales.

Para recuperar la sesión en **Anulación en curso**, instala la APK corregida después de publicar reglas, abre el mismo curso y encuentro y pulsa **Completar anulación**. Reutiliza el evento/motivo existente. Comprueba **Registro anulado** en el estudiante y que desaparezcan tanto la falta como las unidades del cálculo.

Para excepciones de calendario anteriores, abre primero **Asistencia → Gestionar** como docente: sincroniza las proyecciones de horario sin publicar motivos. Actualiza después **Calendario previsto** con el estudiante activo.

El reintento de nómina parcial por horas se reprodujo el 16/11 en el emulador y agotaba 1.000 expresiones. Tras corregirlo, retoma los encuentros existentes **15/11 10:00–12:00** (original 12/11), **16/11 06:00–08:00** (original 05/11) y la normal **16/11 10:00–12:00**. No los borres ni vuelvas a crearlos. Pulsa **Completar lista** en cada tarjeta incompleta: debe conservar el mismo encuentro y abrir el registro cuando corresponda por hora efectiva en Bogotá. Si falta motivo de una preparación tardía antigua, lo pedirá; un borrador preparado a tiempo no necesita otro. Completa marcas y finaliza; después comprueba el registro propio del estudiante y que las dos clases del 16 sigan separadas. Si hay otro rechazo, usa **Diagnóstico** para registrar etapa/código sin datos personales. Los detalles y resultados locales están en el cierre del 16/11 de [seguimiento C8](seguimiento_conjunto_8.md).

## Antes de probar

1. Usa el proyecto Firebase correcto: `aula-presente-movil-juan-2026` y confirma que la app Android sigue registrada como `com.juanceron.aulapresente`.
2. Revisa la rama `feature/conjunto-8-asistencia-manual`, el diff completo de `firestore.rules` y `firestore.indexes.json`, y la guía de esquema en [arquitectura](arquitectura.md#conjunto-funcional-8-asistencia-manual). Esta rama conserva las reglas e índices de C7 y añade asistencia; no reemplaces la configuración de Firebase por la de otro proyecto.
3. Verifica que las cuentas de prueba tengan correo verificado y perfil válido. El docente debe tener el rol `teacher` otorgado por el flujo confiable existente y ser propietario del curso. El estudiante debe tener rol `student` y matrícula canónica activa o pertenencia histórica correspondiente. No escribas roles manualmente desde el cliente.
4. Después de revisar las reglas, cuando decidas activar, publica únicamente las reglas. El índice se conserva y no debe redesplegarse para este paso:

   ```powershell
   firebase deploy --only firestore:rules --project aula-presente-movil-juan-2026
   ```

   El intento previo del propietario devolvió `503` en la API de reglas. Codex no repitió el despliegue. Después de una publicación exitosa, confirma que `cloud.firestore` contiene el ruleset esperado; el propietario reporta el índice `attendance_records` **Habilitado** y no hace falta volver a desplegar índices para esta revisión.

5. Compila/instala la APK debug de esta rama en el TECNO. La ruta local será `build/app/outputs/flutter-apk/app-debug.apk`. La compilación no crea cuentas, envía correos ni despliega Firebase.

## Recorrido 1: curso por encuentro

1. En una cuenta docente verificada, crea un curso de prueba y selecciona **Por encuentro** en **Forma de contar las faltas**. Si usas un curso anterior sin configuración, entra a **Detalle del curso → Asistencia → Gestionar** y elige la modalidad explícitamente.
2. En un horario cuya hora efectiva ya haya comenzado, abre **Preparar asistencia**. Si la clase ya pasó, selecciona **Registrar clase realizada** y escribe el motivo breve solicitado.
3. Comprueba que aparece la nómina completa del día y marca estudiantes **Presente** o **Ausente**. Sal de la pantalla y vuelve a abrir la misma sesión: debe conservar sus marcas, sin crear otro encuentro.
4. Finaliza. Si hay marcas sin decidir, verifica que primero aparezca el número y que **Volver a completar** mantenga la sesión abierta; solo **Confirmar ausencias** puede convertir esas pendientes en ausencias.
5. Desde la cuenta estudiante inscrita, abre **Mis materias → materia → Consultar asistencia**. Confirma que solo aparece su registro propio publicado y que el resumen muestra unidades, porcentaje y explicación del umbral. La publicación final ocurre por filas: puede tardar en aparecer para cada estudiante y no es simultánea para todo el curso. Al reabrir el detalle docente de una sesión finalizada, Aula Presente comprueba/reanuda automáticamente las filas pendientes; también deja disponible **Reintentar publicación** si sigue pendiente. Solo una comprobación completa muestra publicación confirmada.

## Recorrido 2: curso por horas, 08:00–10:00

1. Usa un curso de prueba con horario **08:00–10:00** y modalidad **Por horas**. La sesión debe crear dos tramos consecutivos de 60 minutos.
2. En la primera hora, marca al estudiante **Ausente** en el tramo 08:00–09:00. En el segundo, selecciona 09:00–10:00 y marca **Presente**. Finaliza la sesión.
3. Confirma desde la cuenta del estudiante que, cuando su fila esté publicada, el historial muestra 60 minutos ausentes de 120 registrados, es decir 50 %, y que cada tramo conserva su marca. No se debe convertir la primera marca en dos horas por el horario completo. La disponibilidad converge por estudiante; no se promete que toda la clase vea el resultado al mismo instante.
4. Después de finalizar, prueba una corrección con motivo o registra **En revisión**, **Justificada** o **No aceptada** para una ausencia ya revisada. Comprueba que el estado y el resumen se actualicen, el historial docente conserve motivo y valor anterior/nuevo, y el estudiante no vea notas internas.

## Calendario, historial y privacidad

1. Antes de crear una sesión, reprograma una clase con motivo; el ID de ocurrencia original debe conservarse y no duplicarse en el cálculo.
2. Cancela una clase sin sesión: debe quedar razón en la vista docente y no debe generar ausencia. Agrega, si aplica, una clase adicional sin solape y verifica que tenga identidad independiente.
3. Prepara otra sesión con una cuenta que pertenezca al curso en esa fecha pero aún no esté vinculada. Toma asistencia y finaliza. Después verifica el correo de esa cuenta, completa el flujo C7 de vinculación en **Mis materias** y consulta su asistencia. Debe recuperar la misma identidad/registro previo sin crear una segunda fila.
4. Anula una sesión finalizada con motivo. El docente conserva el evento privado; el estudiante ve **Registro anulado** sin el motivo y esa sesión ya no suma al numerador ni al denominador.
5. Comprueba con otra cuenta que no puede leer la asistencia del estudiante, nómina, eventos ni borradores ajenos.

## Resultado

Registra por separado fecha/dispositivo, modalidad, casos probados y errores observados. No compartas correos, códigos estudiantiles, tokens ni motivos personales. El resultado manual y la versión exacta de APK deben añadirse a `docs/estado_actual.md` solo después de que el propietario realice la prueba.

La suite del emulador local no consulta Firebase real. Compilar desde esta rama tampoco demuestra permisos publicados, disponibilidad del índice, recepción de correos ni comportamiento en el TECNO.
