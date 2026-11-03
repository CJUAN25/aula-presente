# Primer entregable académico: APK y trazabilidad

**Autor:** Juan David Cerón. Producto: **Aula Presente**, en desarrollo.

El evaluador puede probar registro, verificación del correo, inicio de sesión, recuperación de contraseña y cierre de sesión. Los permisos docentes, cursos y registros privados son avances adicionales. El recorrido breve para el docente está en el [README](../README.md).

## Descarga e instalación

La [release preliminar v0.1.0-entrega-1](https://github.com/CJUAN25/aula-presente/releases/tag/v0.1.0-entrega-1) pertenece al repositorio **privado**. Es necesario entrar a GitHub con una cuenta autorizada. La invitación del docente queda a cargo del propietario cuando disponga de su usuario o correo GitHub.

Descarga **Aula-Presente-Entrega-1.apk**, abre el emulador Android Pixel y arrastra el archivo sobre su pantalla. Al terminar la instalación, abre `aula_presente` desde la lista de aplicaciones. No hace falta compilar ni mantener VS Code ejecutando la app. Este mecanismo está descrito en la [documentación oficial del emulador Android](https://developer.android.com/studio/run/emulator-install-add-files).

Se requiere Internet y acceso al buzón del correo registrado. Los enlaces de verificación y recuperación pueden abrirse en la Mac u otro dispositivo; después se vuelve a la app del emulador. La nueva contraseña se establece en la página web de Firebase. Una cuenta nueva obtiene `student` y no requiere aprobación docente para evaluar autenticación.

## APK inspeccionada

| Propiedad | Valor comprobado |
| --- | --- |
| Archivo adjunto | `Aula-Presente-Entrega-1.apk` |
| Tipo | Compilación de depuración para evaluación académica; manifiesto con `application-debuggable`. |
| Paquete | `com.juanceron.aulapresente` |
| Nombre del lanzador | `aula_presente` |
| Versión de la app | `1.0.0`, código `1` (`1.0.0+1` en pubspec). |
| Android mínimo | API `24`, Android `7.0`. |
| Android objetivo | API `36`. |
| Arquitecturas nativas | `arm64-v8a`, `x86_64`, `armeabi-v7a`; se comprobó `libflutter.so` en las tres. |
| Tamaño | `158986606` bytes, aproximadamente 159 MB (151,62 MiB). |
| SHA-256 | `ad17e700f0286ec0e1042c278fbd3f8864483938fbc418010a5f62f7027f2f01` |
| Firma | `apksigner verify --verbose` correcto; esquema APK Signature v2. No se configuró firma de producción. |

La APK incluye ARM64 y x86_64 para cubrir imágenes Android compatibles de emuladores en Mac Apple Silicon o Intel. Esa inclusión se comprobó con `aapt dump badging` y el inventario de bibliotecas del APK; no se dedujo del nombre del archivo. No se conoce el procesador de la Mac del docente ni se realizó una instalación en su emulador.

La etiqueta `v0.1.0-entrega-1` identifica la entrega académica. No cambia la versión interna de la app a `0.1.0`.

## Código que produjo la APK

La compilación procede de un clon limpio descargado de GitHub del commit:

`56c0491e59e3a52b1601d75300b711dbe454ce9f`

Desde esa copia pasaron `flutter pub get`, `flutter analyze`, `flutter test` (108 pruebas) y `flutter build apk --debug`. No se copiaron archivos del proyecto original para completar el clon. La configuración cliente Firebase, los 30 SVG, la fuente Manrope y los archivos Android estaban presentes; los recursos y la fuente se comprobaron también dentro de la APK.

Para esta publicación se reutilizó el archivo conservado: no se recompiló ni se cambió el código de la aplicación. Se comprobó su SHA-256 antes de renombrar la copia descargable. La etiqueta de la release conserva el commit compilado aunque `main` avance con cambios exclusivos de documentación.

## Publicación e integridad comprobadas

El **3 de noviembre de 2026** se publicó la release **Aula Presente — Primer entregable** como versión preliminar, con etiqueta `v0.1.0-entrega-1`, dentro del repositorio privado. Se comprobó que contiene un único adjunto llamado `Aula-Presente-Entrega-1.apk`, con el tamaño y la huella indicados arriba.

Después de publicarlo se descargó nuevamente el adjunto mediante autenticación disponible en el equipo. Su tamaño y SHA-256 coincidieron con la APK local del clon limpio. La publicación no incluyó contraseñas, tokens ni credenciales administrativas.

Esta etapa inspeccionó el binario y verificó su publicación; no repitió la compilación ni las 108 pruebas, que corresponden a la comprobación previa del clon limpio. Los cambios posteriores en `main` para esta entrega afectan solo documentación. La prueba de instalación y autenticación en la Mac/Pixel del docente sigue pendiente.

## Entorno y límites

La compilación se comprobó en Windows con Flutter `3.47.1`, Dart `3.13.1`, SDK Android `36`, NDK `28.2.13676358` y JBR `25.0.2` de Android Studio. El proyecto exige Dart `^3.13.1` y hereda los valores Android del Flutter de referencia. El wrapper fija Gradle `9.3.1` y el proyecto declara AGP `9.1.0`; la compatibilidad del código Android está fijada en Java 17. No se declara un mínimo independiente de Flutter ni se certifica cualquier JDK.

En el clon, `flutter doctor` mostró avisos locales sobre el estado desconocido de licencias Android y componentes faltantes de Visual Studio para Windows; no bloquearon la compilación Android. También hubo avisos no bloqueantes de Java/KGP y dependencias con versiones más recientes. No se cambiaron versiones para esta entrega.

Solo Android tiene configuración Firebase. La Mac puede ser el equipo anfitrión del emulador Android, pero iOS, Web y macOS no son destinos preparados de la app. La compilación en macOS y la instalación en el Pixel del docente quedan pendientes de la prueba del evaluador.

Las verificaciones locales no son una nueva prueba de registro, envío de correos o autenticación contra Firebase real. Las pruebas Dart/Flutter usan datos locales y dobles del SDK o de repositorios. Las pruebas de reglas con JavaScript descritas en [su guía](../tools/firestore_rules_tests/README.md) usan un emulador de Firestore, distinto del emulador Android; no se repitieron para publicar esta APK.

## Configuración Firebase y desarrollo

La app utiliza `aula-presente-movil-juan-2026`, Firestore `(default)` y la configuración cliente incluida en `lib/firebase_options.dart` y `android/app/google-services.json`. El evaluador no necesita Firebase Console, Firebase CLI, otro proyecto ni desplegar reglas. Los archivos cliente contienen identificadores y no credenciales administrativas. Las restricciones activas de la API key no se comprobaron en Google Cloud durante la revisión local; los secretos privados siguen excluidos. Véase la [explicación oficial de Firebase](https://firebase.google.com/docs/projects/api-keys).

Para desarrollar con un proyecto Firebase independiente hay que generar su propia configuración, habilitar Authentication y Firestore y revisar las reglas e índices para ese destino con autorización. Consulta la [guía oficial de FlutterFire](https://firebase.google.com/docs/flutter/setup), la [arquitectura](arquitectura.md), la [activación de roles docentes](activacion_acceso_docente.md) y la [guía de cursos](activacion_conjunto_2.md). Esos procedimientos no son necesarios para evaluar la app existente y esta publicación no modifica Firebase.
