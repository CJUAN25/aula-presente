# Guía de validación manual del conjunto 7

Esta guía conserva el procedimiento de repetición manual. El propietario reportó dos pruebas en TECNO con Firebase real: primero las altas desde Excel, el vínculo posterior, los retiros y la reincorporación; después, el ajuste del historial por curso. En la segunda confirmó que el reincorporado aparece una sola vez como **Activo**, conserva **Ingreso**, **Retiro confirmado** y **Reincorporación confirmada**, la ficha lleva al mismo historial y la persona no aparece en **Retirados**. El motivo original era que **Retirados** filtra el estado actual `withdrawn`, mientras reincorporar deja el documento canónico `active`. **Historial de matrícula** permite buscar a la persona sin importar el estado; **Retirados** muestra y gestiona solo a quienes permanecen retirados. Codex no ejecutó la app en el TECNO, no creó cuentas, no envió correos, no escribió datos en Firebase real ni desplegó reglas o índices. La APK local de depuración se genera en `build/app/outputs/flutter-apk/app-debug.apk`.

## Activación manual de Firebase

El conjunto 7 ya incluye cambios previos en `firestore.rules` y `firestore.indexes.json` respecto a la base C6. Este ajuste de historial no modificó esos archivos, no añade consultas nuevas y no requiere otro despliegue. El propietario reportó que ya probó el flujo anterior con Firebase real; Codex no verificó qué revisión exacta está publicada. Si las reglas e índices C7 aún no estuvieran activos, el flujo base conserva este paso de activación explícita para el proyecto `aula-presente-movil-juan-2026`:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project aula-presente-movil-juan-2026
```

Este comando **no se ejecutó durante la implementación**. En Firebase Console, espera que el índice de grupo de colección `pending_enrollments` aparezca como **Habilitado** antes de entrar al flujo de estudiante. Si la búsqueda informa que falta un índice o está construyéndose, no repitas importaciones ni concluyas que la identidad no coincide: espera a que termine el índice y vuelve a intentar.

No se crean índices manualmente distintos del manifiesto del repositorio, no se eliminan índices existentes y no se abren reglas generales. Revisa el diff local de ambos archivos antes del despliegue. Las pruebas locales de Rules usan solo el emulador y el proyecto ficticio `demo-aula-presente-firestore-rules-tests`.

El ajuste de historial descrito en esta guía reutiliza las consultas del repositorio, las reglas y los índices existentes; no modifica el contrato de Firestore ni requiere otro despliegue. Si las reglas e índices C7 ya están activos en el proyecto, continúa directamente con la comprobación manual del historial.

## Preparar cuentas y un curso de prueba

Usa un curso propio de un docente con correo verificado y rol docente confiable. Para probar fechas, el curso debe estar vigente; para la excepción de curso futuro, crea aparte un curso que todavía no inicia. Usa cuentas que controles:

1. **Estudiante directo:** cuenta existente, correo verificado, rol `student`, entrada propia publicada y código de perfil.
2. **Estudiante pendiente:** todavía sin una cuenta vinculable durante la primera importación; después se registrará con el correo exacto de la fila, verificará ese correo y completará en su perfil el mismo código estudiantil.
3. **Estudiantes activos adicionales:** dos cuentas ya matriculadas en el curso, para revisar la selección parcial de retiros y que las personas no seleccionadas conserven acceso.
4. Si se valida una carrera con C4, crea una solicitud pendiente desde una de esas cuentas controladas. No uses cuentas que no puedas recuperar.

Los archivos ficticios están en `test/fixtures/excel_import/`:

- `estudiantes_ficticios_35.xls`: `.xls` BIFF8 de 35 filas.
- `estudiantes_ficticios_mixtos.xlsx`: libro `.xlsx` ficticio con casos variados.

Haz copias **fuera del repositorio** y modifica únicamente esas copias para reemplazar filas de prueba por cuentas propias. No copies el Excel real del docente al proyecto, no subas correos/códigos reales y no guardes contraseñas, tokens ni enlaces de verificación en archivos o capturas compartidas.

## Recorrido principal

### 1. Alta directa y autorización pendiente

1. Instala la APK debug y entra como docente propietario verificado.
2. Abre **Mis cursos → curso → Gestionar estudiantes → Actualizar lista con Excel**. Comprueba materia, grupo y período del destino; no los toma del archivo.
3. Elige una copia de prueba, la hoja y **Solo agregar estudiantes** o **Comparar lista completa** según el contenido. La modalidad parcial no propone retiros. La modalidad completa solo habilita retiros si todas las páginas del roster se cargaron y la hoja no tiene filas inválidas, repetidas ni identidades contradictorias.
4. Incluye una fila de una cuenta verificada con correo/código exactos y otra fila sin una cuenta disponible, también con correo/código controlados. Confirma la identidad por correo y código; el nombre solo ayuda a reconocer a la persona.
5. Selecciona explícitamente ambas filas. Revisa la fecha efectiva y confirma una vez. Antes de este botón, archivo, resumen, selección y cancelación son de solo lectura.
6. Comprueba el resultado real por fila: la primera queda inscrita; la segunda queda **pendiente de vincular**. En **Gestionar estudiantes → Pendientes de vincular** se muestra la autorización y su historial. No se crea usuario ni contraseña.

### 2. Verificación y vínculo automático

1. Registra la cuenta del estudiante pendiente desde la app, usando el correo exacto autorizado.
2. Abre el correo de verificación, verifica la cuenta e inicia sesión. Completa `studentCode` del perfil con el mismo código que confirmó el docente.
3. Entra en **Mis materias** o pulsa **Actualizar materias**. La app actualiza primero su entrada de directorio, busca pendientes por correo y código autenticados y vincula la autorización en una transacción con la matrícula canónica.
4. Comprueba que el curso aparece en **Mis materias** sin solicitud ni aceptación adicional. El roster docente debe mostrar una sola matrícula activa, no una fila activa duplicada más un pendiente.
5. Repite con casos negativos controlados: correo no verificado, otro correo, código distinto, falla de red y autorización retirada. Ninguno debe conceder acceso; tras recuperar red o corregir la identidad, vuelve a entrar/actualizar para reintentar. Un pendiente retirado no se activa al registrarse; el docente debe reabrirlo explícitamente.

### 3. Comparación completa y selección parcial de retiros

1. Con al menos dos cuentas activas en el roster, prepara una copia nueva de la lista completa que incluya una de ellas y omita dos.
2. Selecciona **Comparar lista completa** y revisa que los dos faltantes figuren como **Posibles retiros**, desmarcados inicialmente.
3. Selecciona solo a una de esas personas. Confirma la fecha efectiva y lee la explicación de que el día de retiro queda fuera del tramo activo.
4. Confirma y revisa el resultado individual. Solo esa persona debe quedar retirada, perder acceso al curso/horario y conservar su documento e historial. La persona no seleccionada debe seguir activa y con acceso.
5. Abre **Retirados** y el detalle de la matrícula para comprobar fechas efectivas y eventos. Un reingreso que aparece otra vez en el Excel exige seleccionar explícitamente **Reincorporar**; conserva `createdAt` y abre otro tramo.
6. Repite el mismo archivo como **Solo agregar estudiantes** omitiendo a otra cuenta activa. No debe proponer ni aplicar retiro alguno.

### 4. Pendiente retirado antes del registro

Autoriza en el curso una cuenta todavía no registrada. Antes de registrarla, retira la autorización desde **Pendientes de vincular**. Luego crea y verifica esa cuenta con el mismo correo/código y entra a **Mis materias**. No debe activarse el curso. El docente puede consultar el registro en **Historial de pendientes** y reabrirlo solo de forma explícita, con una nueva fecha efectiva válida.

### 5. Fechas efectivas

- Para comprobar una adición retroactiva, selecciona una fecha civil dentro del calendario del curso y anterior al día en que la cuenta pendiente se registra/verifica. Al vincular, la matrícula debe conservar esa fecha de autorización, no usar el día en que se vinculó.
- En un curso que aún no empieza, las altas/reincorporaciones solo pueden usar el inicio exacto. Los retiros nunca se programan para una fecha futura. Si se cancela una autorización o una matrícula cuyo inicio todavía no ocurre, selecciona una fecha no posterior a hoy en Bogotá; no puede ser anterior a la autorización/creación ni al último cambio válido.
- No uses `FECHAMATRICULA` como fecha efectiva. La hora de confirmación siempre la genera el servidor.
- La fecha de retiro se excluye del tramo activo. Al confirmar, el cambio de acceso es inmediato; la fecha efectiva sirve para reconstruir la pertenencia, no para calcular asistencias.

### 6. C3/C4 y regresiones

En una cuenta con autorización pendiente exacta, prueba también agregarla mediante **Agregar estudiante** o aceptar una solicitud C4 coincidente. Debe reutilizar la autorización y conservar una sola matrícula canónica. Si correo/código/curso de una solicitud no coincide, el alta automática no decide la solicitud: la deja para revisión docente y no permite al estudiante aprobarla. Las matrículas C5/C6 y eventos históricos deben seguir visibles sin migración.

### 7. Historial general de matrícula: estudiante reincorporado

Usa el mismo estudiante que ya retiraste y reincorporaste en el curso de prueba; no es necesario crear registros adicionales:

1. Abre **Mis cursos → curso propio → Gestionar estudiantes → Historial de matrícula**. Comprueba la materia, grupo y período del encabezado y que la persona aparezca una sola vez como **Activo**.
2. Abre su fila. En **Historial de matrícula**, comprueba **Ingreso confirmado**, **Retiro confirmado** y **Reincorporación confirmada**, con sus fechas. Si hubo un vínculo de cuenta, se muestra aparte como **Cuenta vinculada** y no reemplaza el ingreso efectivo.
3. Vuelve a **Gestionar estudiantes → Lista de estudiantes**, abre la ficha y pulsa **Ver historial de matrícula**: debe llegar al mismo detalle. En **Retirados**, comprueba que el estudiante reincorporado no figure.

## Qué observar y qué queda pendiente

Guarda solo evidencias de estado no sensibles: modo elegido, recuentos, resultado por fila y evento/fecha sin exponer correo real, código, contraseña, token ni enlace de acción. Compara visualmente la APK final con los frames vigentes en el TECNO a escala normal y ampliada; Codex solo cubrió widgets de Flutter con tamaños lógicos 320/390/430 y escala 1.6, no comparó píxeles ni ejecutó el dispositivo.

El propietario ya reportó la validación manual del recorrido principal y del ajuste de historial descritos arriba. La guía conserva los pasos para repetirlos. La comparación visual pixel a pixel no está acreditada por ese reporte; compilar la APK y ejecutar pruebas Flutter o del emulador local no prueba por sí solo Firebase real ni fidelidad visual en el teléfono.
