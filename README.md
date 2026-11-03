# Aula Presente

**Autor:** Juan David Cerón  
**Estado:** aplicación en desarrollo. Primer entregable académico de autenticación.

Aula Presente busca facilitar el control de asistencia en el aula y la consulta de información académica para estudiantes, docentes y personas administradoras. Actualmente permite gestionar el acceso de usuarios y consultar cursos con sus horarios previstos. El registro de asistencia todavía no está implementado.

## Primer entregable

El docente evaluador puede probar con su propio correo:

- Registro de una cuenta con Firebase Authentication y creación de su perfil en Cloud Firestore.
- Verificación del correo mediante el enlace enviado por Firebase.
- Inicio de sesión con correo y contraseña.
- Recuperación de contraseña con un enlace de Firebase; la contraseña nueva se establece en su página web.
- Cierre de sesión y retorno a la pantalla de acceso.

La contraseña no se guarda en Firestore. Una cuenta nueva recibe el rol `student` (estudiante) y puede evaluar estos flujos sin solicitar aprobación docente.

### Avances adicionales

También existen un CRUD privado de **Registros de prueba**, solicitud y aprobación administrativa de acceso docente, creación y consulta de cursos propios, bloques semanales, calendario previsto y agenda. Estos avances se conservan, pero no son requisitos del primer entregable. Elegir un espacio en la interfaz no concede permisos: el acceso depende de los roles del perfil.

Quedan para entregas posteriores la edición y eliminación de cursos, matrículas, listas de estudiantes, sesiones de asistencia, QR, Bluetooth, justificaciones, importaciones, festivos, excepciones y reportes. Los encuentros del calendario son previstos; no registran asistencia automáticamente.

## Tecnologías y estructura

- **Flutter y Dart:** interfaz móvil, validaciones y navegación.
- **Firebase Authentication:** cuentas, contraseñas, verificación y recuperación de acceso.
- **Cloud Firestore:** perfiles, solicitudes, registros privados y cursos.
- **flutter_svg y Manrope:** iconos y tipografía incluidos en los recursos locales.

| Ruta | Contenido |
| --- | --- |
| [lib/main.dart](lib/main.dart) | Entrada e inicialización de Firebase antes de `runApp`. |
| [lib/app/](lib/app/) | Configuración general, tema y conexión de repositorios. |
| [lib/features/](lib/features/) | Módulos de autenticación, administración, cursos, horarios y registros de prueba. Los README de módulos futuros no indican funcionalidad implementada. |
| [assets/](assets/) | SVG, fuente Manrope y su licencia. |
| [android/](android/) | Proyecto Android, configuración Gradle y actividad principal. |
| [test/](test/) | Pruebas Dart y Flutter. |
| [tools/firestore_rules_tests/](tools/firestore_rules_tests/) | Pruebas de permisos con el emulador local y el SDK de JavaScript. |
| [docs/](docs/) | Arquitectura, estado actual, guías técnicas y seguimiento. |
| [pubspec.yaml](pubspec.yaml) y [pubspec.lock](pubspec.lock) | Dependencias y versiones resueltas. |

## Requisitos para Android

Solo **Android** tiene configuración Firebase actualmente. Las carpetas `ios/` y `web/` son parte del proyecto, pero esas plataformas no están listas para ejecutar esta integración.

Se necesita Git para obtener el repositorio, Flutter, Android Studio o las herramientas Android equivalentes, Internet y un dispositivo Android o emulador. Las versiones comprobadas en el equipo de desarrollo son:

| Elemento | Entorno comprobado y requisito del proyecto |
| --- | --- |
| Flutter | `3.47.1` stable. Es la versión de referencia; `pubspec.yaml` no declara una versión mínima de Flutter separada. |
| Dart | `3.13.1`. El proyecto exige `^3.13.1`, es decir, desde `3.13.1` hasta antes de `4.0.0`. |
| Android | Con el Flutter de referencia: dispositivo API 24 o superior, SDK de compilación/objetivo 36 y NDK `28.2.13676358`. Estos valores se heredan de Flutter. |
| Java | Se comprobó JBR `25.0.2` de Android Studio. El código Android configura compatibilidad Java 17; eso no significa que se haya probado con todos los JDK. |
| Gradle y Android Gradle Plugin | El wrapper fija Gradle `9.3.1`; el proyecto declara AGP `9.1.0`. |

Se recomienda usar el Flutter de referencia y conservar `pubspec.lock`. `flutter doctor -v` permite comprobar qué SDK y JDK está usando Flutter en cada equipo.

## Obtener y ejecutar el proyecto

1. **Obtener acceso al repositorio privado.** La cuenta GitHub del evaluador debe estar autorizada. Cuando el código esté subido, desde una terminal:

   ```powershell
   git clone https://github.com/CJUAN25/aula-presente.git
   cd aula-presente
   ```

2. **Comprobar Flutter y Android:**

   ```powershell
   flutter --version
   flutter doctor -v
   ```

   Resuelve los componentes Android que indique `doctor`. Si solicita aceptar licencias, ejecuta `flutter doctor --android-licenses`.

3. **Instalar las dependencias del proyecto:**

   ```powershell
   flutter pub get
   ```

4. **Preparar un destino Android.** Inicia un emulador desde Android Studio o conecta un dispositivo con depuración USB autorizada y ejecuta:

   ```powershell
   flutter devices
   ```

5. **Ejecutar la app:**

   ```powershell
   flutter run -d ID_ANDROID
   ```

   Sustituye `ID_ANDROID` por el identificador Android que mostró `flutter devices`; no escribas ese marcador literalmente. No selecciones Chrome o iOS para esta entrega.

6. **Opcional: generar una APK de depuración:**

   ```powershell
   flutter build apk --debug
   ```

   El resultado se guarda en `build/app/outputs/flutter-apk/app-debug.apk`.

Las herramientas Flutter generan o actualizan `android/local.properties` y otros archivos locales según el equipo. No copies rutas del SDK de otra máquina. El código fuente, los recursos, el wrapper Gradle y `pubspec.lock` se preparan para versionar; las compilaciones, cachés y dependencias descargadas se excluyen.

## Firebase

La app actual usa el proyecto **`aula-presente-movil-juan-2026`**, Firestore `(default)` y el paquete Android **`com.juanceron.aulapresente`**. Necesita Internet para usar los servicios reales y recibir los correos.

Se incluyen [lib/firebase_options.dart](lib/firebase_options.dart), usado por la inicialización en Dart, y [android/app/google-services.json](android/app/google-services.json), usado por el plugin Android de Google Services. Contienen configuración cliente e identificadores del proyecto; no son cuentas de servicio ni credenciales administrativas. La revisión local no comprobó las restricciones activas de la API key en Google Cloud. Las claves privadas, archivos de servicio, tokens y keystores permanecen excluidos. Véase la [documentación oficial sobre API keys de Firebase](https://firebase.google.com/docs/projects/api-keys).

**Para evaluar esta app existente, el docente no necesita acceder a Firebase Console, crear otro proyecto, instalar Firebase CLI ni volver a desplegar reglas.** Utiliza la configuración incluida y su propia cuenta de usuario. La disponibilidad del backend y del correo depende de los servicios Firebase. El propietario informó que habilitó correo/contraseña y publicó las reglas e índices; esta preparación local no repitió esas comprobaciones en la consola.

Una **instalación independiente con otro proyecto Firebase** requiere registrar su propia app Android, generar su configuración con FlutterFire, habilitar Authentication por correo/contraseña y Firestore, y revisar/publicar las reglas e índices para ese nuevo destino con autorización. Es un procedimiento distinto de evaluar esta entrega. Consulta la [guía oficial de FlutterFire](https://firebase.google.com/docs/flutter/setup), el [esquema y permisos](docs/arquitectura.md), la [activación de acceso docente](docs/activacion_acceso_docente.md) y la [guía de cursos](docs/activacion_conjunto_2.md). No ejecutes sus comandos de despliegue para probar la app ya configurada.

## Cómo evaluar la autenticación

Usa un correo propio al que tengas acceso. Aunque el formulario dice «correo institucional», la validación acepta cualquier dirección de correo válida. No se incluyen cuentas ni contraseñas de prueba.

1. Entra por **Entrar con mi cuenta** y elige **Crear mi cuenta**. Escribe tu nombre, correo y una contraseña de al menos ocho caracteres; confírmala. El código estudiantil es opcional.
2. Completa el registro y revisa tu buzón, incluido correo no deseado. Abre el enlace de verificación enviado por Firebase.
3. Vuelve a la app y pulsa **Ya verifiqué mi correo**. La app recarga el usuario y su token antes de comprobar la verificación y el perfil. Si el mensaje tarda, puedes reenviarlo cuando termine la espera indicada.
4. Cierra sesión y vuelve a ingresar con el mismo correo y contraseña. Puedes entrar al espacio de estudiante; no necesitas aprobación docente para evaluar la autenticación.
5. Cierra sesión y elige **Olvidé mi contraseña**. Solicita la recuperación para tu correo. La confirmación es genérica para no revelar si una cuenta existe.
6. Abre el enlace recibido, revisa correo no deseado si es necesario y define la nueva contraseña en la **página web de Firebase**. La app no incluye un formulario interno para cambiarla.
7. Regresa a la app, ingresa con la contraseña nueva y cierra sesión. Debe volver al acceso y retirar la navegación protegida.

## Verificaciones y documentación

Desde la raíz, después de instalar dependencias:

```powershell
flutter analyze
flutter test
```

Las pruebas Dart/Flutter comprueban validaciones, calendario, permisos de navegación y presentación con datos locales y dobles de repositorios o del SDK. Algunas ejecutan el repositorio Dart de cursos con respuestas controladas del SDK; eso no equivale a conectarlo a Firestore real o al emulador nativo Android.

Durante la preparación local de esta entrega, el **2 de noviembre de 2026**, se ejecutaron:

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Sin problemas. |
| `flutter test --reporter expanded` | 108 pruebas aprobadas. |
| `flutter build apk --debug` | APK generada. Avisos no bloqueantes de Java y KGP en plugins Firebase. |

En esa preparación no se ejecutó la app en el teléfono, no se enviaron correos ni se hicieron operaciones contra Firebase real. La suite del emulador no se repitió porque no cambiaron reglas ni operaciones de datos.

La suite de [Firestore Rules](tools/firestore_rules_tests/README.md) usa el SDK **JavaScript**, un emulador local y un proyecto ficticio. Comprueba reglas y operaciones, incluida la aprobación atómica y la creación de cursos. No ejecuta el repositorio Dart contra Firebase. Para esa suite adicional se necesitan Node.js, Java y Firebase CLI según su guía, e instalar primero sus dependencias con `npm ci --prefix tools/firestore_rules_tests`. No hace falta para ejecutar la app ni probar el login.

Los resultados históricos y las pruebas manuales reportadas por el usuario en Firebase real y en el TECNO CM6 se distinguen de las pruebas automáticas en [estado actual](docs/estado_actual.md), [seguimiento del conjunto 1](docs/seguimiento_conjunto_1.md) y [seguimiento del conjunto 2](docs/seguimiento_conjunto_2.md). No se debe interpretar una compilación o un test local como una prueba manual de envío de correos o de disponibilidad del servidor.

Más información: [arquitectura](docs/arquitectura.md), [módulo de autenticación](lib/features/auth/README.md), [mapa de módulos](lib/features/README.md) e [instrucciones de trabajo](AGENTS.md).

[GUIA_DOCUMENTACION.md](GUIA_DOCUMENTACION.md) describe un ZIP documental histórico. Ese ZIP se excluye de Git y no sustituye este proyecto Flutter ejecutable.
