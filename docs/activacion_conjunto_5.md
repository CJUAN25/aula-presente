# Activación manual del conjunto 5

## Reglas e índices

**Estado informado por el propietario (14 de noviembre de 2026):** el despliegue a Firebase real se completó y los siete índices aparecieron **Habilitados** en Firebase Console. El propietario reportó el recorrido completo en TECNO: el docente retiró y reincorporó al estudiante, se conservó el historial y el estudiante perdió y recuperó acceso a la misma materia y horario. Codex no realizó el despliegue ni ejecutó el teléfono.

Durante la activación, Firebase avisó que un índice anterior de `enrollments` con alcance `COLLECTION_GROUP` (`studentUid ASC`, `createdAt DESC`, `__name__ DESC`) existía en la nube pero faltaba en el manifiesto. El propietario respondió **No** a eliminarlo. Su definición exacta del commit base se restauró en `firestore.indexes.json`; se mantiene junto al índice nuevo que añade `status ASC`, pues sirven a consultas distintas. No se borró el índice ni se hizo otro despliegue en este cierre.

El comando utilizado para publicar reglas e índices se conserva como referencia para una activación futura solo si hay nuevos cambios que lo requieran. **No lo vuelvas a ejecutar para este cierre**:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project aula-presente-movil-juan-2026
```

Si se utiliza por un cambio futuro autorizado, este comando actualiza Rules y la definición de índices. Abre Firebase Console → Firestore Database → Indexes y espera a que las entradas de `enrollments` indiquen **Enabled**; mientras se construyen, las consultas pueden responder con error. No interpretes ese estado temporal como una matrícula vacía. Rules se activa al terminar el despliegue, mientras los índices se habilitan en segundo plano.

No es necesario publicar otra configuración de Firebase ni recrear las matrículas antiguas: las inscripciones `active` sin marcadores de transición siguen admitidas. Después de retirar o reincorporar una matrícula, el mismo documento tendrá `lastStatusEventId` y `lastStatusChangedAt`, y cada cambio confirmado tendrá un evento append-only.

## Prueba manual con dos cuentas verificadas

Usa dos cuentas de prueba que controles: una cuenta **docente verificada** con perfil válido y `teacher` en `roles`, propietaria del curso; y una cuenta **estudiante verificada** con perfil `student`. Utiliza un curso y una materia de prueba. No compartas contraseñas, enlaces de correo, códigos de invitación ni datos personales en capturas o reportes.

1. Con la cuenta docente, abre **Mis cursos → curso propio → Gestionar estudiantes**. Inscribe manualmente al estudiante o aprueba su solicitud pendiente por código. La lista debe mostrar una sola matrícula activa.
2. En el teléfono del estudiante, abre **Mis materias** y elige el curso. Comprueba la materia y su horario previsto. Abre el calendario y, si aplica, un detalle de encuentro.
3. En la cuenta docente, desde la lista activa abre la ficha del estudiante y pulsa **Retirar del curso**. Verifica que la fecha aparezca como **Al confirmar** y que el aviso indique que se pierde acceso y se conserva el historial. Pulsa **Conservar inscripción** primero en una prueba de cancelación: no debe cambiar el estado ni agregar un evento.
4. Confirma el retiro. La transacción debe volver confirmada; la matrícula desaparece de activos y el conteo baja en uno. En **Retirados e histórico** debe aparecer el mismo estudiante.
5. En la cuenta del estudiante, actualiza Mis materias o regresa a la app después de dejar abierto el horario. El curso debe desaparecer de la lista y la pantalla abierta debe borrar el horario tras revalidar. Una lectura denegada no debe volver a mostrar lo que estaba en memoria.
6. Mientras el estudiante sigue retirado, prueba un código válido vigente del mismo curso. La app debe explicar que pida al docente la reincorporación; no debe crear una segunda matrícula ni mostrar acceso. Si había una solicitud histórica aprobada, debe mostrar la decisión histórica por separado del estado actual.
7. En la cuenta docente, abre la ficha desde retirados, consulta **Historial de matrícula** y verifica el ingreso original y el retiro con fecha de servidor en zona `America/Bogota`. Pulsa **Reincorporar estudiante** y confirma. Se conserva `createdAt` y la misma matrícula; el historial añade el nuevo ingreso.
8. Vuelve al estudiante. El curso y su horario deben aparecer de nuevo en Mis materias. Desde la ficha docente comprueba que el registro ya está activo y que conserva los eventos anteriores.
9. Para comprobar que cada ciclo se registra una sola vez, repite retiro y reincorporación. Deben agregarse dos eventos nuevos al mismo documento, sin duplicar matrícula ni curso. Repite también el caso con un segundo curso para comprobar que una retirada no afecta las demás materias.

## Comportamiento ante fallos

Si una acción devuelve un error de red y no queda claro si el servidor confirmó la transacción, no asumas que fue revertida: consulta de nuevo el estado o reintenta conservando el mismo identificador de operación. Un error real `permission-denied` debe presentarse como problema de permisos; no es un éxito. Si el docente confirma la escritura pero falla la actualización posterior de una lista, la acción confirmada debe conservar el mensaje de éxito y la pantalla debe permitir recargar.

La revisión independiente de código está completa y sus hallazgos se corrigieron con pruebas. Codex reportó previamente `flutter analyze` limpio, `flutter test --reporter expanded` 195/195, Firestore Emulator 74/74, JSON/sintaxis de reglas y `git diff --check` aprobados y APK debug compilada en `build/app/outputs/flutter-apk/app-debug.apk` (226,372,526 bytes). En este cierre solo se repitieron la validación JSON y `git diff --check`, no las pruebas Flutter, el emulador ni la compilación. La activación y recorrido real descritos arriba fueron informados por el propietario; Codex no accedió a Firebase real ni ejecutó la app en el TECNO. La comparación visual pixel a pixel sigue pendiente.
