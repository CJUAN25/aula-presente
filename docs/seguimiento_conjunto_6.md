# Seguimiento del conjunto 6: importación de altas por Excel

## Base y alcance

La rama local `feature/conjunto-6-importacion-excel` parte de `901ff6715f2dbf8808558e77721ed4f98c1ea8de` (cierre del conjunto 5). Este conjunto toma filas de un archivo elegido en el dispositivo, revisa las coincidencias contra el directorio de correo exacto y crea solamente las matrículas seleccionadas y confirmadas. El curso de destino procede de **Gestionar estudiantes**; la hoja no puede reemplazarlo.

El archivo y sus columnas ajenas a la matrícula no se suben a Firebase. No se crean cuentas, reservas, roles, retiros ni reincorporaciones automáticas. Una cuenta todavía no disponible se puede revisar de nuevo mediante otra importación después de que su titular se registre, verifique el correo y abra el espacio Estudiante. El problema pendiente de recepción del correo de verificación en Outlook se documenta por separado; el conjunto 6 no cambia Auth ni relaja la verificación.

## Contrato de lectura y revisión

El lector usa `excel_plus` 2.29.3 para decodificar y `file_picker` 13.3.2 para elegir únicamente un archivo del dispositivo. Acepta archivos Excel `.xls` BIFF8 y `.xlsx` auténticos, comprobando también su firma binaria. Reconoce encabezados por nombre, con espacios exteriores y variantes inequívocas de acentos y mayúsculas. Las columnas obligatorias son `CODIGOESTUDIANTE`, `MAIL_INST` y `NOMBRECOMPLETO`; las demás columnas del formato recibido se descartan. Una fila conserva su número físico original y solo tras validar correo y código puede convertirse en candidata. `FECHAMATRICULA` no determina `createdAt`: Firestore registra la hora de servidor en el momento del alta.

Los límites del lector son **5 MB**, **10 hojas**, **60 columnas** y **1000 filas de datos por hoja**. Un libro sin hoja compatible, vacío, corrupto o cuya extensión no corresponda a su formato muestra un error de archivo. El selector cancelado no crea estado ni matrícula. El parser nunca ejecuta macros, fórmulas ni vínculos; toma únicamente valores de las tres celdas necesarias. Un libro cifrado auténtico no se probó: si la decodificación falla, se presenta un aviso de libro dañado o protegido.

Los fixtures binarios ficticios están en `test/fixtures/excel_import/`: `estudiantes_ficticios_35.xls` contiene 35 filas y los nueve encabezados del docente; `estudiantes_ficticios_mixtos.xlsx` contiene dos hojas, columnas reordenadas, un código textual con ceros, otro numérico con formato de relleno y una fila incompleta. Los valores ficticios en `DOCUMENTO`, `PENG_IDENTITARIO`, `TELEFONO` y `EPS` sirven para comprobar que esos campos no salen del lector. El Excel original `Lista Movil.xls` no se abrió ni copió porque está fuera del proyecto; se probó un archivo equivalente ficticio.

La revisión consulta `student_directory/{email}` por ID exacto, sin enumerar directorios ni perfiles. El nombre de la hoja ayuda a comparar, pero el snapshot persistido procede del candidato válido devuelto por el repositorio. El correo solo pierde espacios exteriores; no se sustituye dominio ni se vinculan identidades por similitud. Los duplicados de correo, código y UID se detectan antes de permitir selección. Una matrícula activa se muestra como **Ya inscrito** y una retirada como **Retirado** para el flujo explícito del conjunto 5.

| Estado | Seleccionable | Comportamiento |
|---|---|---|
| Lista para matricular | Sí | Directorio exacto, código coincidente y sin matrícula. |
| Cuenta no disponible para vincular | No | No hay entrada consultable; no se afirma que la cuenta no exista. |
| Revisar código estudiantil | No | Falta el código en el candidato o no coincide. |
| Fila repetida o contradictoria | No | Se muestran los números implicados y se evita decidir por orden. |
| Ya inscrito | No | La matrícula activa conserva su fecha de ingreso. |
| Retirado | No | Conserva historial; requiere reincorporación explícita. |
| Fila inválida o error de conexión/permiso/sesión | No | Muestra la causa concreta y permite revisar o reintentar según corresponda. |

## Confirmación y permisos

La selección y la revisión son lecturas. Confirmar procesa cada fila seleccionada con concurrencia acotada y usa `EnrollmentRepository.enrollStudent` para la transacción canónica `courses/{courseId}/enrollments/{studentUid}`. La revisión y el guardado comprueban al docente verificado y propietario. Antes de crear se vuelve a comprobar la identidad del directorio, el código y la sesión. Una matrícula creada entretanto se reporta como existente; una retirada no se reactiva. La operación mantiene la resolución atómica de una solicitud `pending` solo cuando corresponde al alta nueva.

Cada fila tiene resultado propio: matriculada ahora, ya inscrita, retirada, pendiente de revisión o fallida/sin confirmación. Una escritura confirmada no se convierte en error por una lectura o navegación posterior. Un reintento usa el mismo documento canónico, por lo que no duplica el alta; un resultado de red incierto se explica como tal.

## Referencia visual

El agente de interfaz consultó en modo lectura los nodos y capturas de la página vigente `01 · Aula Presente · Rediseño` del archivo Figma `NUEVA-CORRECION`:

| Frame | Nodo | Uso |
|---|---|---|
| M01 · Gestionar estudiantes | `2005:12218` | Entrada desde curso propio. |
| M02 · Importar Excel | `2005:12383` | Destino y archivo. |
| M03 · Columnas del Excel | `2005:12503` | Encabezados y fecha efectiva. |
| M04 · Revisar importación | `30:73` | Totales y coincidencias. |
| M19 · Seleccionar altas del Excel | `4006:7914` | Selección explícita. |
| M23 · Confirmar importación | `4006:7986` | Confirmación antes de escribir. |
| M05 · Importación completada | `2005:12622` | Resultado real y retorno. |

M10 inspira el estado de cuenta no disponible sin prometer reserva. M06 y M07 pertenecen a retiros por comparación y quedan fuera. Se conservan tema oscuro, Manrope y componentes del proyecto; el icono de carga de M02 se añadió como `assets/figma/18f6c.svg`. Los datos ficticios del diseño no se usan como resultados. No se hizo una comparación pixel a pixel de un render Flutter con Figma.

## Revisión independiente y correcciones

La revisión independiente detectó dos estados incompletos en la lectura: una hoja válida sin filas dejaba el avance deshabilitado sin explicación, y una hoja incompatible se omitía en silencio cuando otra hoja del libro sí era válida. M03 ahora explica la hoja vacía y muestra los motivos de las hojas no vacías descartadas; se añadieron pruebas dirigidas. El revisor también comprobó que una alta nueva resuelve una solicitud `pending` atómicamente, mientras una matrícula ya existente encontrada durante la confirmación no modifica esa solicitud. Revisó revalidación de candidato y sesión, totales del resultado y el acceso posterior del estudiante. El cierre integrado se completó con las pruebas globales y la revisión final del agente principal.

## Comprobaciones y límites

- `flutter pub get` pasó y resolvió las versiones fijadas de `excel_plus` y `file_picker`.
- Pruebas dirigidas del parser: **7/7**; incluyen BIFF8 de 35 filas, OOXML, orden de columnas, ceros, alias, hoja vacía, encabezados ausentes o duplicados, libro con hojas válidas e incompatibles, firma falsa y bytes corruptos.
- Pruebas dirigidas del coordinador y repositorio de matrícula: **32/32**; incluyen revisión sin escritura, identidad y código, duplicados, sesión, carreras, resultados parciales y solicitud pendiente.
- Pruebas dirigidas de presentación: **8/8**; incluyen cancelación, ausencia de elegibles, desmarcar, error de archivo, hoja vacía y advertencias, resultado parcial y recorrido en 320/390/430 px lógicos con escala de texto 1.6.
- Firestore Emulator con el proyecto ficticio `demo-aula-presente-firestore-rules-tests`: **75/75**. El nuevo caso comprueba que un estudiante obtiene acceso a curso y bloques tras un alta confirmada y que repetirla no duplica ni cambia `createdAt`. Usa el SDK JavaScript y la transacción canónica; no ejecuta FlutterFire en el emulador.
- `flutter analyze`: sin problemas. `flutter test`: **222/222**. `flutter build apk --debug`: aprobó y generó `build/app/outputs/flutter-apk/app-debug.apk`. `git diff --check`: sin errores de formato.

## Validación manual reportada por el propietario

El propietario informó que probó en el TECNO con Firebase real una copia `.xls` y cuentas de prueba. Codex no ejecutó la app en el teléfono ni observó la sesión.

| Caso reportado | Resultado observado |
|---|---|
| Importación de una copia `.xls` con una cuenta cuyo correo y código estudiantil coincidían | El docente confirmó el alta desde Excel. |
| Consulta desde la cuenta recién matriculada | El curso apareció en **Mis materias**, sin solicitud ni aceptación adicional. |
| Otra cuenta de prueba sin código estudiantil para el cotejo | La importación no permitió vincularla. No se atribuye si faltaba el código en el archivo o en el perfil. |
| Reimportación del mismo archivo en el mismo curso | Apareció **«Ya inscrita»** y no se volvió a ofrecer como alta. |

Este reporte cubre únicamente los casos de la tabla. No afirma que se probaran en el TECNO el `.xlsx`, el Excel original sin modificar, una fila retirada u otros estados. El flujo actual permite altas de cuentas existentes con el cotejo correcto. Una cuenta sin vinculación disponible puede revisarse al importar de nuevo después; no se guarda una reserva que se active sola tras el registro. La futura vinculación automática y la incidencia de entrega del correo institucional en Outlook siguen separadas y pendientes.

**Mejora opcional:** el estado `Revisar código estudiantil` usa un mensaje común cuando el código del candidato no coincide o no está disponible. En una iteración posterior se podría distinguir de forma segura si falta en la fila o en el perfil; no se cambió el flujo durante este cierre ni se infiere cuál fue el caso observado por el propietario.

## Evidencia local de implementación

- `flutter pub get`: aprobado.
- `flutter analyze`: sin problemas.
- `flutter test`: **222/222**.
- Firestore Emulator, proyecto ficticio `demo-aula-presente-firestore-rules-tests`: **75/75**.
- `git diff --check`: sin errores.
- `flutter build apk --debug`: aprobada; `build/app/outputs/flutter-apk/app-debug.apk`.
- Las pruebas locales cubren `.xls` BIFF8 auténtico ficticio de 35 filas y `.xlsx` ficticio mixto. No se probó el Excel original ni un libro auténticamente cifrado.

Las pruebas del emulador usan el SDK JavaScript para verificar las reglas y el patrón transaccional; no ejecutan FlutterFire en el emulador. `firestore.rules` y `firestore.indexes.json` no se modificaron para esta importación, así que este cierre no requiere un despliegue de reglas o índices. La guía [activacion_conjunto_6.md](activacion_conjunto_6.md) conserva los pasos para repetir el recorrido.
