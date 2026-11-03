# Aula Presente

**Autor:** Juan David Cerón

Aula Presente busca facilitar el control de asistencia y la consulta de información académica para estudiantes, docentes y administradores. La aplicación continúa **en desarrollo**; el registro de asistencia todavía está pendiente.

## Alcance de esta entrega

El primer entregable permite evaluar:

- Registro de una cuenta.
- Verificación del correo.
- Inicio de sesión.
- Recuperación de contraseña mediante un enlace enviado por Firebase.
- Cierre de sesión.

También existen avances de permisos docentes, cursos con horarios y calendario previsto, y registros privados de prueba. No son requisitos de esta evaluación. Las matrículas, sesiones de asistencia, QR, Bluetooth, justificaciones y reportes quedan para entregas posteriores.

## Opción rápida: probar la APK

Abre la [release del primer entregable](https://github.com/CJUAN25/aula-presente/releases/tag/v0.1.0-entrega-1).

1. Inicia sesión en GitHub con una cuenta autorizada para este **repositorio privado**.
2. Descarga **`Aula-Presente-Entrega-1.apk`** desde los archivos adjuntos de la release.
3. Abre el emulador Android Pixel con Android **7.0 / API 24 o superior**.
4. Arrastra la APK sobre la pantalla del emulador y espera la instalación.
5. Abre Aula Presente desde la lista de aplicaciones; el nombre del lanzador es **`aula_presente`**.

La APK es de **depuración para evaluación académica**, ocupa aproximadamente **159 MB** e incluye **ARM64 y x86_64**, además de ARM de 32 bits. No requiere compilar el proyecto ni mantener VS Code ejecutándolo. Sí necesita el emulador abierto e Internet. La instalación en la Mac del docente queda pendiente de su comprobación.

## Probar la autenticación

Usa tu propio correo y asegúrate de poder consultar su buzón. Puedes abrir los mensajes en la Mac o en otro dispositivo y después volver a la app del emulador.

1. Pulsa **Entrar con mi cuenta** → **Crear mi cuenta**. Completa nombre, correo y contraseña de al menos ocho caracteres; confírmala y pulsa **Crear cuenta y verificar**. El código estudiantil es opcional.
2. Abre el enlace de verificación recibido por correo. Revisa correo no deseado si no aparece.
3. Vuelve a la app y pulsa **Ya verifiqué mi correo**. Si necesitas otro mensaje, usa **Reenviar enlace** cuando termine la espera indicada.
4. Pulsa **Cerrar sesión** y vuelve a iniciar sesión mediante **Entrar**.
5. Cierra sesión, selecciona **Olvidé mi contraseña**, escribe tu correo y pulsa **Enviar enlace**.
6. Abre el enlace recibido y establece la contraseña nueva en la **página web de Firebase**. Regresa a la app, pulsa **Volver al inicio de sesión** e ingresa con la nueva contraseña mediante **Entrar**.
7. Pulsa **Cerrar sesión** para terminar.

Una cuenta nueva obtiene el rol **estudiante** (`student`). No necesita aprobación docente ni acceso a Firebase Console para evaluar estos flujos. Aunque el campo dice «correo institucional», acepta cualquier correo válido. La confirmación de recuperación es genérica y no revela si una cuenta existe. No se incluyen credenciales de usuarios.

## Revisar y ejecutar el código

El proyecto utiliza **Flutter y Dart**, **Firebase Authentication** para las cuentas y **Cloud Firestore** para los perfiles y datos. Solo **Android** tiene configuración lista en esta entrega; iOS, Web y macOS no son destinos preparados.

Para compilar se necesita acceso autorizado al repositorio privado, Git, Flutter y las herramientas Android. El entorno comprobado usa Flutter **3.47.1** y Dart **3.13.1**. El proyecto exige Dart `^3.13.1` (desde 3.13.1 hasta antes de 4.0.0), sin un mínimo de Flutter declarado por separado. Con el Flutter de referencia utiliza SDK Android **36**, NDK **28.2.13676358** y dispositivo API **24 o superior**. El equipo de desarrollo usó el JBR **25.0.2** de Android Studio; el código Android configura compatibilidad Java 17. Más detalles en la [guía técnica de la entrega](docs/entrega_1.md).

Desde una terminal de la Mac:

```bash
git clone https://github.com/CJUAN25/aula-presente.git
cd aula-presente
flutter doctor -v
flutter pub get
flutter devices
flutter run -d ID_DEL_EMULADOR
```

Sustituye `ID_DEL_EMULADOR` por el identificador Android que muestre `flutter devices`. Resuelve los avisos Android de `flutter doctor`; si solicita licencias, ejecuta `flutter doctor --android-licenses`. Las herramientas generan `android/local.properties` para cada equipo: no copies rutas del SDK de otra máquina. La compilación documentada se comprobó en Windows; no se ha compilado en la Mac del docente.

La configuración cliente Firebase está incluida en [lib/firebase_options.dart](lib/firebase_options.dart) y [android/app/google-services.json](android/app/google-services.json). La app usa el proyecto existente **`aula-presente-movil-juan-2026`**. Para evaluar esta entrega no necesitas crear otro proyecto Firebase, entrar a su consola ni desplegar reglas. Necesitas Internet y acceso a tu correo.

## Estructura y documentación

- [lib/main.dart](lib/main.dart): entrada e inicialización de Firebase.
- [lib/app/](lib/app/): configuración general y tema.
- [lib/features/](lib/features/): autenticación y módulos del producto.
- [assets/](assets/): iconos, fuente Manrope y licencia.
- [android/](android/): proyecto Android y wrapper Gradle.
- [test/](test/): pruebas Dart y Flutter.
- [docs/](docs/): documentación y seguimiento.

Guías: [entrega y trazabilidad de la APK](docs/entrega_1.md), [arquitectura](docs/arquitectura.md), [estado actual](docs/estado_actual.md), [autenticación](lib/features/auth/README.md) y [desarrollo](AGENTS.md).

El **emulador Android Pixel** ejecuta la app. El [emulador local de Firebase](tools/firestore_rules_tests/README.md) sirve para pruebas de permisos durante el desarrollo y no es necesario para evaluar la autenticación con el servicio existente. [GUIA_DOCUMENTACION.md](GUIA_DOCUMENTACION.md) corresponde a un ZIP histórico y no sustituye el proyecto ejecutable.

## Verificaciones

Desde un clon limpio del commit [`56c0491`](https://github.com/CJUAN25/aula-presente/commit/56c0491e59e3a52b1601d75300b711dbe454ce9f), sin copiar archivos del proyecto original:

| Comando | Resultado |
| --- | --- |
| `flutter pub get` | Dependencias resueltas. |
| `flutter analyze` | Sin problemas. |
| `flutter test` | 108 pruebas aprobadas. |
| `flutter build apk --debug` | APK generada. |

La APK adjunta se reutilizó de ese clon y se inspeccionaron paquete, Android mínimo, arquitecturas y firma. La etiqueta `v0.1.0-entrega-1` apunta al código compilado; `main` puede contener documentación posterior.

Las pruebas Dart/Flutter usan datos locales y dobles de repositorios o del SDK. La suite de permisos de Firebase usa JavaScript contra un emulador; no ejecuta el repositorio Dart contra Firebase real. La compilación y estas pruebas **no equivalen a una nueva prueba de autenticación real**, envío de correos o instalación en el Pixel del docente. Los reportes manuales del usuario se registran por separado en [el estado del proyecto](docs/estado_actual.md).
