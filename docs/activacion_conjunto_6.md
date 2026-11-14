# Demostración manual del conjunto 6

La APK compilada está en `build/app/outputs/flutter-apk/app-debug.apk`. El conjunto 6 usa las reglas e índices ya existentes; no requiere otro despliegue.

## Validación manual reportada por el propietario

El propietario informó que ejecutó en el TECNO con Firebase real el recorrido de una copia `.xls`: confirmó el alta de una cuenta de prueba con correo y código coincidentes, comprobó el curso en **Mis materias** desde esa cuenta sin solicitud adicional, observó que otra cuenta sin código para el cotejo no se vinculó y reimportó el mismo archivo para confirmar que la cuenta ya aparecía como **«Ya inscrita»**. No especificó si el código de la cuenta que no se vinculó faltaba en el Excel o en el perfil. Codex no ejecutó ni observó la prueba.

No se reportó que se probaran en el TECNO el `.xlsx`, el Excel original sin modificar ni otras filas/estados. La guía paso a paso siguiente conserva el procedimiento para repetir la prueba; esos pasos no deben interpretarse como pruebas ya ejecutadas. Usa cuentas controladas con correo verificado.

## Preparar una copia de prueba

Los fixtures ficticios de `.xls` y `.xlsx` están en `test/fixtures/excel_import/`; sus encabezados corresponden al formato del docente. Prepara **una copia fuera de Git** y conserva `CODIGOESTUDIANTE`, `MAIL_INST` y `NOMBRECOMPLETO`. Sustituye únicamente dos filas por cuentas que controles:

1. Una cuenta de estudiante con correo verificado, que ya entró al espacio Estudiante y todavía no está inscrita en el curso de prueba. Usa el correo y código exactos de su perfil.
2. Otra cuenta verificada que ya esté inscrita en ese mismo curso, también con correo y código exactos.

Conserva filas ficticias para comprobar un correo sin entrada disponible, una fila con código distinto y una repetida. No guardes la copia con correos reales dentro del repositorio ni envíes el archivo a un servicio de conversión. Puedes copiarla al almacenamiento del TECNO y elegirla con el selector del sistema.

## Recorrido corto

1. Entra como docente verificado propietario: **Mis cursos → curso de prueba → Gestionar estudiantes → Importar Excel**. Comprueba materia, grupo y período de destino antes de abrir el archivo.
2. Selecciona la copia `.xls` o `.xlsx`, elige hoja si hay varias compatibles y revisa el nombre, los encabezados reconocidos y los números originales de fila.
3. Pulsa **Revisar importación**. La cuenta nueva debe aparecer lista para matricular; la ya inscrita como **Ya inscrito**; la cuenta sin entrada como **Cuenta no disponible para vincular**. Las filas con código distinto, duplicados o datos incompletos no deben poder seleccionarse.
4. En **Seleccionar estudiantes**, marca solo el alta nueva. Revisa la pantalla **Confirmar importación** y la fecha efectiva **Al confirmar**. Volver o cancelar hasta aquí no debe crear matrículas.
5. Confirma una vez y observa el resultado por fila. Vuelve a **Estudiantes del curso** y comprueba que aumentó el conteo activo y que aparece el estudiante nuevo.
6. Entra con esa cuenta de estudiante. Abre **Mis materias**, la materia nueva y su horario. Cierra sesión antes de volver a la cuenta docente.
7. Reimporta la misma copia. La cuenta ya matriculada debe aparecer como **Ya inscrito** y no producir otra matrícula. Si pruebas una fila de matrícula retirada, debe mostrarse **Retirado** y conducir al procedimiento explícito de reincorporación del conjunto 5, sin activarla desde Excel.

La fila sin cuenta disponible no crea una reserva. Cuando esa persona se registre, verifique el correo y entre en el espacio Estudiante, importa de nuevo el archivo para repetir la revisión. El correo de verificación pendiente de Outlook es una incidencia independiente; usa cuentas de prueba que ya funcionen y no cambies la verificación para esta demostración.

## Resultados y límites de la comprobación

Las pruebas locales de lector, revisión, widgets, reglas y compilación se enumeran en [seguimiento_conjunto_6.md](seguimiento_conjunto_6.md). La compilación y el emulador no demuestran por sí solos el recorrido con Firebase real. Registra por separado lo que observes en el TECNO y no atribuyas esa ejecución a Codex.
