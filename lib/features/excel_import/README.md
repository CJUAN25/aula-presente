# Importación y actualización de listas por Excel

`data/` abre el archivo elegido con el selector del sistema y decodifica `.xls` BIFF8 o `.xlsx` en memoria. Solo entrega código estudiantil, correo, nombre y número original de fila. No conserva columnas de documento, teléfono, EPS ni el libro completo después de la lectura.

`domain/` define las filas, hojas, advertencias, estados de revisión y resultados. `application/` compara el correo exacto y el código con `student_directory/{email}`, comprueba matrícula y propietario, bloquea duplicados y confirma solamente las filas seleccionadas. Reutiliza `EnrollmentRepository.enrollStudent` y procesa hasta tres altas simultáneas, cada una con su transacción canónica. `presentation/` implementa M02/M03/M04/M19/M23/M05 y vuelve a la lista del curso al terminar.

La revisión y la selección no escriben. Una matrícula activa existente se informa sin duplicarla; una retirada conserva su historial y requiere la reincorporación individual del conjunto 5. Las pruebas y los fixtures ficticios están en `test/features/excel_import/` y `test/fixtures/excel_import/`. Contrato completo y resultados: [seguimiento del conjunto 6](../../../docs/seguimiento_conjunto_6.md).

## Conjunto 7: actualizar una lista del curso

`application/excel_roster_comparator.dart` clasifica filas validadas frente al snapshot paginado del roster. `presentation/excel_roster_update_screen.dart` reutiliza el lector C6 y ofrece dos modos: **Solo agregar estudiantes** acepta filas parciales y conserva a quienes no aparecen; **Comparar lista completa** propone retiros únicamente después de cargar todas las páginas y comprobar que el archivo permita una comparación fiable.

Las altas directas, autorizaciones pendientes, reincorporaciones, retiros y reaperturas se seleccionan explícitamente y se aplican por persona con transacciones independientes. Las propuestas de retiro empiezan desmarcadas; seleccionar, revisar y cancelar no escribe. El resultado distingue filas guardadas, sin cambios, por revisar y fallidas. El Excel se procesa en el dispositivo y no se almacena en Firebase.

Las listas activa, **Pendientes de vincular**, **Retirados** y **Historial de matrícula** viven en `features/enrollments`. El estudiante verificado vincula una autorización cotejada al actualizar **Mis materias**. El historial general reúne un snapshot completo del curso y conserva una sola fila para una autorización ya vinculada y su matrícula canónica. Esquema, fechas, reglas, índice y resultados: [seguimiento del conjunto 7](../../../docs/seguimiento_conjunto_7.md); activación manual: [guía](../../../docs/activacion_conjunto_7.md).
