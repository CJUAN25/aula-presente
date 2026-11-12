# Activación y revisión del conjunto 4 — 11 de noviembre de 2026

## Validación real informada por el propietario

El propietario informó que publicó las reglas e índices del conjunto 4 y comprobó en su TECNO, con Firebase real, que puede generar y renovar códigos con distinta vigencia, que desactivar impide usarlos, que el estudiante puede enviar una solicitud con un código nuevo, que el docente puede aprobarla y que después aparecen la materia y el horario en **Mis materias**. Codex no ejecutó estas pruebas, no inspeccionó la base real ni desplegó Firebase.

El cierre actual simplifica la presentación. **No cambia `firestore.rules` ni `firestore.indexes.json` respecto a la versión de reglas e índices que el propietario informó haber publicado. No requiere otro despliegue de Firebase.** La revisión visual de esta pantalla final en el teléfono queda pendiente.

## APK para revisar la pantalla final

Compilación local: `build/app/outputs/flutter-apk/app-debug.apk`. Instala esta APK debug actualizada en el TECNO para ver la interfaz final. La APK de la release `v0.1.0-entrega-1` es el primer entregable académico y no contiene el conjunto 4.

Abre **Mis cursos → curso propio → Gestionar estudiantes → Invitar a mi curso → Gestionar invitación**. Verifica que se leen el código, el estado y la fecha/hora de vencimiento; **Copiar código** está disponible para el código con estado activo. El estado «Activo» muestra el valor guardado, no garantiza que la fecha aún sea futura: la consulta y la solicitud se validan en Firestore. Si la fecha ya pasó, usa **Renovar código**.

En una invitación habitual deben verse **Renovar código**, **Editar vencimiento** y **Desactivar código**. Ya no aparece **Pausar código**. Renovar elige la vigencia y sustituye el código compartido; desactivar pide confirmación y deja ese código sin uso. Si una invitación había quedado pausada, muestra **Reactivar código** además de Renovar; reactivar conserva el mismo código solo si aún no venció. Una invitación desactivada solo se reemplaza mediante Renovar. Actualizar invitación vuelve a consultar el estado antes de repetir una acción si hubo un error de conexión.

Revisa la pantalla con el ancho y tamaño de texto que utilizas normalmente. Las pruebas Flutter comprobaron el diseño a 320, 390 y 430 px lógicos con texto ampliado 1.6 y el diálogo de renovación con teclado; no sustituyen la observación final en el TECNO. No compartas códigos, correos ni capturas con datos reales al informar un problema.

## Contrato conservado

La vigencia elegida va de **1 hora a 90 días** y parte de la creación original del código. Los documentos anteriores sin `validForSeconds` mantienen 14 días. Editar conserva el código y su fecha de creación. Renovar crea otro código y el anterior deja de servir. Las solicitudes previas y matrículas no se borran. La aprobación sigue creando o reutilizando la matrícula canónica en una transacción.

La operación de pausa, sus reglas y pruebas permanecen para la compatibilidad de invitaciones ya pausadas, pero la pantalla no permite iniciar pausas nuevas. El diagnóstico seguro de consulta/envío de estudiante permanece solo en modo debug y aparece tras un error; no muestra códigos, correos ni UID.

Resultados locales completos y evidencia histórica: [seguimiento del conjunto 4](seguimiento_conjunto_4.md).
