# Activación y prueba manual del conjunto 2

## Estado de publicación

Las reglas y el índice de cursos se prepararon localmente y se validaron con el emulador durante la entrega original. El usuario informó el 29 de octubre de 2026 que ya los publicó en Firebase real; esta sesión no consultó el proyecto para verificarlo ni realizó un despliegue. El comando documentado para una publicación autorizada es:

El flujo Flutter crea `courses/{courseId}` y de uno a ocho documentos `weekly_blocks/{blockId}` en una sola transacción. No pruebes creando el padre aislado en la consola: Rules requiere que estén presentes todos los hijos enumerados en el mismo commit.

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project aula-presente-movil-juan-2026
```

Este despliegue actualiza reglas e índices de Firestore del proyecto indicado. No lo ejecutes mientras solo se esté revisando el código. Comprueba que el índice compuesto de `courses` figure como listo antes de probar la lista; conserva el índice de solicitudes del conjunto 1.

## Recorrido en TECNO CM6

Con reglas e índice publicados y el índice listo, según la comprobación del propietario:

1. Abre Aula Presente con una cuenta docente autorizada, activa y con correo verificado. Entra por **Docente**. Una cuenta estudiante o un admin sin `teacher` no debe mostrar ese espacio.
2. Ve a **Cursos** → **Crear un curso**. Completa asignatura, grupo, período y programa.
3. Define un rango que incluya fechas futuras y agrega dos bloques semanales en días distintos. Revisa que el fin sea posterior al inicio y que las fechas sean inclusivas.
4. En **Revisar calendario**, comprueba encuentros previstos. Vuelve al horario, cambia el aula o la hora y confirma que la vista previa se actualiza; luego vuelve a revisar y crea el curso.
5. Abre el detalle y su calendario. Confirma que el título, período, programa, fechas, aula y ambos días coincidan. Los encuentros se indican como previstos; no hay registro de asistencia.
6. Cierra la app por completo y vuelve a abrirla con la misma cuenta. En **Cursos**, actualiza y confirma que el curso y el calendario se recuperan del servidor.
7. Inicia sesión con una cuenta distinta sin rol docente. No debe aparecer **Docente** ni poder listar o crear cursos. Si se prueba con otra cuenta docente, tampoco debe poder leer el documento de la primera cuenta.
8. Para comprobar un error posterior de consulta, tras una creación ya confirmada desactiva temporalmente la red y fuerza una actualización de la lista. La app debe mostrar una opción de reintento y no presentar un fallo retroactivo de creación. Restablece la red y actualiza: debe aparecer una sola copia del curso. La idempotencia de repetir la misma operación con el mismo ID se comprueba aparte en los tests del emulador.
9. Para revisar el aviso de conflictos sin alterar cursos existentes, abre el detalle de **Móvil** y comprueba días, horas en formato 24 h y rango de fechas. Antes de crear **Lógica**, verifica esos mismos valores en **Revisar calendario**. Si Móvil sigue solo en lunes/viernes y Lógica solo en martes/jueves, la nueva compilación no debe abrir **Horario en conflicto**. Si aparece, conserva las fechas y los bloques visibles de ambas vistas como evidencia no sensible para investigar; no confirmes la creación solo para probar el aviso.

El usuario confirmó que Móvil tiene lunes 08:00–10:00 y **martes 06:00–10:00**. Coincide con el diagnóstico y explica las 17 coincidencias con los martes de Lógica: el aviso es correcto y este caso queda cerrado. No se necesita otra captura para esta incidencia. **Crear de todos modos** conserva el comportamiento informativo si el usuario acepta el solapamiento. La herramienta debug sigue disponible para investigar otros casos: [diagnostico_conflictos_horarios.md](diagnostico_conflictos_horarios.md#resultado-del-informe-recibido).

No se necesitan cuentas de demostración, escritura administrativa ni pruebas que concedan roles. La batería automática usa un proyecto ficticio y Auth/Firestore locales.

## Límites

Esta investigación no verificó en Firebase real el estado del despliegue o del índice, los permisos de las cuentas, los cursos guardados ni la recuperación tras cambio de red. El usuario reportó una prueba en el TECNO CM6, pero la nueva compilación y el caso de conflicto quedan pendientes de su comprobación manual. Festivos, excepciones, matrículas, asistencia, QR, Bluetooth y edición/borrado de cursos pertenecen a entregas posteriores.
