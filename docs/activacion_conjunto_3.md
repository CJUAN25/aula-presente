# Activación y prueba manual del conjunto 3

**Estado de cierre:** el usuario informó que desplegó las reglas y el índice, observó `enrollments` **Habilitado** y comprobó que el conjunto funciona en el TECNO. Codex no hizo el despliegue, no ejecutó la app en el teléfono y no creó cuentas ni inscripciones reales. Los pasos siguientes quedan como guía para repetir la prueba.

## Despliegue informado y referencia para repetirlo

El proyecto de destino es `aula-presente-movil-juan-2026`, base `(default)`. La consulta de matrículas y las lecturas de estudiante requieren las reglas de `firestore.rules` y el índice de grupo de `firestore.indexes.json`. El usuario comunicó que ya los publicó y que el índice está habilitado. Este es el comando preparado para una activación posterior o para reproducir el procedimiento; **no se ejecutó en este cierre**:

```powershell
firebase deploy --project aula-presente-movil-juan-2026 --only firestore:rules,firestore:indexes
```

Para repetir una activación se debe esperar a que el índice esté habilitado antes de probar la lista del estudiante. El APK de la release `v0.1.0-entrega-1` pertenece al primer entregable y **no incluye** el conjunto 3. Se compiló una APK debug local en `build/app/outputs/flutter-apk/app-debug.apk`. El usuario reportó una prueba satisfactoria en el TECNO, sin identificar en este registro el archivo binario exacto que instaló. Este cierre no publica una APK nueva.

## Cuentas anteriores

La cuenta estudiante debe estar registrada, con correo verificado y rol `student` en su perfil. Al entrar al espacio estudiante en la versión nueva, la app publica o actualiza `student_directory/{email}` con los datos del propio perfil. Este paso permite localizar por correo a cuentas creadas antes del conjunto 3 sin modificar los documentos `users` ni migrar cursos. Si el docente no encuentra el correo, el estudiante debe abrir de nuevo su espacio, revisar si se mostró un error de publicación y pedir un reintento; no se crea otra cuenta desde la sesión docente. El código estudiantil puede ser null en cuentas anteriores. Una entrada que ya no coincide con el perfil se deniega con `permission-denied` hasta que su titular publique la información vigente o el nuevo titular verificado recupere un correo liberado. La interfaz no confunde ese error con una cuenta inexistente ni oculta denegaciones reales.

## Recorrido manual sugerido

1. Con una cuenta estudiante verificada, abre el espacio **Estudiante**. Comprueba que **Mis materias** esté vacío si todavía no tiene matrículas. Cierra sesión.
2. Con una cuenta docente verificada y autorizada, abre **Mis cursos** y elige un curso existente de su propiedad. Entra en **Estudiantes y matrícula** y luego en **Agregar estudiante**.
3. Escribe el correo exacto de la cuenta estudiante. Si conoces su código estudiantil, introdúcelo para cotejarlo; no pierdas sus ceros iniciales. Comprueba el nombre, correo y código mostrados antes de confirmar. Confirma una sola vez.
4. Comprueba la confirmación y la fila del estudiante en **Estudiantes del curso**. Repite el intento con la misma persona: debe informar que ya estaba inscrita sin crear otra fila ni incrementar la cantidad. Cierra la app y vuelve: la fila debe persistir.
5. Inicia sesión como estudiante. **Mis materias** debe incluir solo ese curso. Ábrelo y revisa materia, grupo, período, horario semanal y calendario **previsto**. Cierra y abre la app: los datos deben persistir.
6. Usa una segunda cuenta docente con otro curso y otra cuenta estudiante. El docente no debe poder gestionar matrículas del curso ajeno; el estudiante no debe poder leer matrículas, cursos o bloques de personas ajenas. Un usuario con `student` y `teacher` debe ver ambos espacios separados. Un `admin` sin `teacher` no debe tener facultades académicas.
7. Prueba una dirección inexistente, código discordante, red interrumpida y un reintento. La app debe conservar los datos recuperables y distinguir un resultado incierto de una denegación real. Después de una escritura confirmada, un fallo al actualizar la lista no debe aparecer como fallo de la inscripción.

No se generan asistencias ni ausencias por la fecha de ingreso. Excel, invitaciones, solicitudes de ingreso, retiros e historial completo permanecen fuera del conjunto. El usuario reportó que completó la comprobación del conjunto en el TECNO con Firebase real; los pasos individuales de esta guía no tienen resultados registrados por separado. Las pruebas de emulador documentadas en [seguimiento_conjunto_3.md](seguimiento_conjunto_3.md) son evidencia local distinta.
