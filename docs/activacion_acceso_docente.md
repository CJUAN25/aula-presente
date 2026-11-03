# Activación manual del acceso docente

Este documento describe la activación administrativa del conjunto 1. **Ningún comando de esta guía se ejecutó durante su implementación original**. Posteriormente el propietario informó que publicó las reglas e índices; su estado actual no se verificó desde la consola durante la preparación local de la entrega. El proyecto destino indicado es `aula-presente-movil-juan-2026`. Para evaluar el registro y el login de la app existente no es necesario repetir estos pasos; consulta el [README](../README.md). Si se adapta la guía a un proyecto independiente, una persona autorizada debe revisar y ajustar el destino de los comandos antes de ejecutarlos.

## Preparar el primer administrador

1. En la app publicada, registra una cuenta normal con datos de la persona que administrará el proyecto y verifica su correo desde el enlace recibido.
2. En Firebase Console, abre **Authentication → Users** y copia el UID exacto de esa cuenta.
3. En **Firestore Database → (default) → `users`**, abre el documento con ese UID. Comprueba el perfil actual antes de cambiarlo.
4. Edita únicamente el arreglo `roles`: conserva `student` y agrega `admin`, por ejemplo `['student', 'admin']`. Conserva también `name`, `email` y `studentCode`. No copies el UID ni el correo de una cuenta de prueba a la documentación o al código.
5. Cierra y vuelve a iniciar sesión con esa cuenta, o usa «Volver a comprobar» en su pantalla de acceso. La app consulta el perfil desde el servidor y debe mostrar el espacio **Administrador del proyecto**.

Esta acción se hace en la consola autorizada; la app cliente no contiene un botón, código secreto ni excepción por correo para crear administradores.

## Revisar y publicar reglas e índices

Primero comprueba que Firebase CLI apunta al proyecto correcto y vuelve a leer `firestore.rules`, `firestore.indexes.json` y `firebase.json`. Para publicar, una persona autorizada ejecutará desde la raíz:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project aula-presente-movil-juan-2026
```

Este comando no forma parte de las pruebas locales y **no se ejecutó durante este trabajo**. No uses `--project` distinto al proyecto destino. Confirma en la consola de Firebase que las reglas y el índice terminaron de desplegarse.

## Prueba funcional posterior

1. Registra y verifica una segunda cuenta normal; conserva el rol inicial `student`.
2. En C04, abre **Solicitar acceso docente**. La cuenta debe crear una sola solicitud pendiente y seguir sin rol docente.
3. Inicia sesión con el administrador inicial y abre **Administrador del proyecto → Solicitudes docentes**.
4. Abre la solicitud S05, compara el snapshot con el perfil actual y aprueba o rechaza. Un rechazo requiere motivo.
5. Confirma que la solicitud y el perfil cambian juntos: aprobar agrega `teacher` conservando `student`; rechazar no modifica los roles.
6. Vuelve a iniciar sesión con la segunda cuenta y comprueba que el espacio mostrado coincide con los roles autorizados.

Para validar permisos antes de publicar, ejecuta la suite local descrita en [tools/firestore_rules_tests/README.md](../tools/firestore_rules_tests/README.md). Esta usa el emulador y un ID ficticio; no valida el proyecto Firebase real.

## Límites

Las invitaciones docentes por código, la reapertura de solicitudes rechazadas y las estadísticas de asistencia no están implementadas. La creación y consulta de cursos y horarios pertenecen al conjunto 2 y se describen en [su guía](activacion_conjunto_2.md). La aprobación es una revisión manual; el correo verificado y el código estudiantil no se presentan como acreditación institucional automática.
