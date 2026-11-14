# Importación de altas por Excel

`data/` abre el archivo elegido con el selector del sistema y decodifica `.xls` BIFF8 o `.xlsx` en memoria. Solo entrega código estudiantil, correo, nombre y número original de fila. No conserva columnas de documento, teléfono, EPS ni el libro completo después de la lectura.

`domain/` define las filas, hojas, advertencias, estados de revisión y resultados. `application/` compara el correo exacto y el código con `student_directory/{email}`, comprueba matrícula y propietario, bloquea duplicados y confirma solamente las filas seleccionadas. Reutiliza `EnrollmentRepository.enrollStudent` y procesa hasta tres altas simultáneas, cada una con su transacción canónica. `presentation/` implementa M02/M03/M04/M19/M23/M05 y vuelve a la lista del curso al terminar.

La revisión y la selección no escriben. Una matrícula activa existente se informa sin duplicarla; una retirada conserva su historial y requiere la reincorporación individual del conjunto 5. Las pruebas y los fixtures ficticios están en `test/features/excel_import/` y `test/fixtures/excel_import/`. Contrato completo y resultados: [seguimiento del conjunto 6](../../../docs/seguimiento_conjunto_6.md).
