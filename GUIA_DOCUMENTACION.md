# Guía del paquete documental histórico · Aula Presente

Este documento corresponde a `insumos_codigo_aula_presente.zip`, preparado en una etapa anterior para documentar Firebase. **No es la guía de instalación del primer entregable académico ni describe todos los avances actuales.** El proyecto ejecutable y sus instrucciones vigentes están en [README.md](README.md); el alcance actualizado se registra en [docs/estado_actual.md](docs/estado_actual.md).

## Alcance del paquete

El ZIP reúne una copia histórica del manifiesto, la entrada de Flutter, los módulos de autenticación y `demo_records`, la arquitectura y las reglas de Cloud Firestore de esa etapa. La guía describe aquella copia y sus comprobaciones; no acredita una prueba de conexión ni un despliegue de reglas en Firebase, y no incluye los avances posteriores de permisos docentes y cursos.

El `README.md` **dentro del ZIP** conserva texto de la etapa inicial que describía Firebase y el CRUD como pendientes. Esa afirmación está desactualizada: ambos están implementados en el proyecto actual y el README principal ya lo explica. No se ha reconstruido ni modificado el ZIP histórico.

Por el alcance solicitado para aquel paquete, el ZIP omite `lib/firebase_options.dart`, `android/app/google-services.json`, los recursos y el proyecto Android. No es autónomo para compilar. **Los dos archivos Firebase son configuración cliente, no credenciales administrativas**; se revisaron y están presentes en el proyecto real, preparados para versionar en la entrega académica. Las restricciones activas de la API key no se comprobaron desde el entorno local. Las claves privadas y cuentas de servicio se mantienen excluidas. Consulta la [explicación oficial de Firebase](https://firebase.google.com/docs/projects/api-keys).

## Versiones y dependencias de la copia histórica

- Versión de la app declarada en `pubspec.yaml`: `1.0.0+1`.
- Restricción de Dart del proyecto: `^3.13.1`.
- Entorno usado para verificar esta entrega: Flutter `3.47.1` (stable) y Dart `3.13.1`.
- Dependencias directas de ejecución declaradas y resueltas en `pubspec.lock`:

| Paquete | Restricción declarada | Versión resuelta |
| --- | --- | --- |
| `firebase_core` | `^4.15.0` | `4.15.0` |
| `firebase_auth` | `^6.7.0` | `6.7.0` |
| `cloud_firestore` | `^6.10.0` | `6.10.0` |
| `flutter_svg` | `^2.3.0` | `2.3.0` |

Dependencias de desarrollo: `flutter_test` del SDK de Flutter y `flutter_lints` (`^6.0.0`, resuelta a `6.0.0`). El archivo `pubspec.lock` se consultó para documentar versiones, pero no forma parte de la lista solicitada para el ZIP.

## Estructura incluida

- `lib/main.dart`: arranque de Flutter e inicialización de Firebase.
- `lib/app/`: widget raíz y tema visual.
- `lib/features/auth/`: validación de formularios, contrato y modelo de acceso, repositorio Firebase y pantallas de autenticación.
- `lib/features/demo_records/`: contrato y modelo del registro, validación, repositorio Firestore y pantallas de lista, detalle y formulario.
- `firestore.rules`: reglas de perfil y registros de demostración.
- `docs/arquitectura.md`: decisiones de producto, rutas y esquema de Firestore.

## Inicialización de Firebase

En `lib/main.dart`, `main()` llama primero a `WidgetsFlutterBinding.ensureInitialized()`, después espera `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` y finalmente ejecuta `runApp(const AulaPresenteApp())`. Las opciones están en `lib/firebase_options.dart`, que se excluyó del paquete por solicitud. El proyecto descrito en la arquitectura es `aula-presente-movil-juan-2026`.

## Flujos de autenticación

La interacción con Firebase Authentication y el perfil de Firestore se concentra en `lib/features/auth/data/firebase_auth_repository.dart`. Formularios y navegación están en presentación; `AulaPresenteApp` inicia el flujo mediante `AuthStartScreen`.

1. **Registro:** valida nombre, correo, código estudiantil y contraseña; llama a `createUserWithEmailAndPassword`, actualiza el nombre visible, crea `users/{uid}` con `name`, `email`, `studentCode` y `roles: ['student']`, y envía verificación con el idioma de Auth en español. La contraseña solo se entrega a Firebase Authentication.
2. **Verificación:** la acción de comprobar llama a `reload()` y fuerza la renovación del token antes de resolver el acceso. Mientras `emailVerified` sea falso, no abre el perfil. Se puede reenviar el correo con un intervalo de 30 segundos. Corregir correo reautentica con la contraseña actual y solicita el cambio mediante `verifyBeforeUpdateEmail`; el correo nuevo se refleja en el perfil cuando Firebase lo confirma.
3. **Inicio de sesión y autorización:** usa `signInWithEmailAndPassword`. Un correo sin verificar vuelve a la pantalla de verificación. Con correo verificado, consulta `users/{uid}` y valida que exista, que el correo coincida y que `roles` contenga `student`. Un perfil ausente, inválido, con correo inconsistente o sin ese rol no obtiene acceso de estudiante. La interfaz no otorga roles docentes o administrativos.
4. **Recuperación:** solicita `sendPasswordResetEmail` y presenta una confirmación genérica. El código no implementa una pantalla interna para cambiar contraseña; se usa el enlace y la página de acción predeterminados de Firebase.
5. **Cerrar sesión y restaurar:** cerrar sesión llama a `FirebaseAuth.signOut()` y reemplaza la navegación protegida. Al iniciar, la app espera el estado de Auth, recarga el usuario y el token y vuelve a resolver correo, perfil y rol antes de mostrar el perfil.

## CRUD de `demo_records`

La entrada **Registros de prueba** está en el perfil que solo se muestra al acceso de estudiante autorizado. `FirestoreDemoRecordsRepository` comprueba que haya usuario autenticado y correo verificado; obtiene el UID de `FirebaseAuth.currentUser` y solo accede a `users/{uid}/demo_records`. No recibe un UID desde la interfaz.

Cada documento contiene exactamente `title`, `description`, `createdAt` y `updatedAt`. La validación admite título de 1 a 120 caracteres y descripción vacía o de hasta 1000 caracteres, como indican las reglas incluidas.

- **Crear:** agrega un documento con título y descripción, y asigna `FieldValue.serverTimestamp()` a `createdAt` y `updatedAt`.
- **Listar:** escucha la subcolección con snapshots, ordenada por `updatedAt` descendente; muestra carga, lista vacía y errores.
- **Consultar:** obtiene el documento seleccionado por su ID dentro de la subcolección propia y muestra sus datos y timestamps.
- **Editar:** actualiza solo `title`, `description` y `updatedAt` con `FieldValue.serverTimestamp()`. No escribe `createdAt`, por lo que conserva el valor original.
- **Eliminar:** pide confirmación y borra el documento seleccionado de la subcolección propia.

La presentación bloquea solicitudes repetidas mientras una acción se procesa y muestra mensajes para errores de red, sesión, correo no verificado o permisos. Las reglas en el ZIP son el código fuente de reglas; la preparación del paquete no publica ni verifica su despliegue.

## Comprobaciones ejecutadas al preparar aquel paquete

En el proyecto Flutter completo, antes de generar el ZIP:

- `flutter analyze`: pasó, sin problemas reportados.
- `flutter test`: pasó; 16 pruebas.
- `flutter build apk --debug`: pasó y generó `build/app/outputs/flutter-apk/app-debug.apk`. Gradle emitió avisos de compatibilidad futura de los plugins Firebase con el soporte Kotlin de Flutter, pero la compilación terminó correctamente.

Estas comprobaciones no ejecutan la app ni crean documentos en Firebase. No incluyen una prueba manual en dispositivo ni una operación contra la base real.

## Redacción de datos de ejemplo

La copia empaquetada de `lib/features/auth/presentation/auth_screens.dart` sustituye los correos y el nombre de ejemplo visibles en formularios y vistas previas por valores neutrales. El archivo del proyecto original no se modifica. No se incluyen contraseñas, tokens, enlaces de acción, opciones Firebase, archivos de servicio, dependencias descargadas ni archivos de compilación.
