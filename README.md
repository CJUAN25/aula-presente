# Aula Presente

**Desarrollado por Juan David Cerón, estudiante de la Universidad de la Amazonia.**

Hice Aula Presente para facilitar el registro de asistencia y la consulta de información académica. En muchos grupos la asistencia se lleva en listas separadas y luego cuesta saber qué ocurrió en cada clase. La app reúne los cursos, sus horarios, las matrículas y el registro de cada encuentro.

La revisión **1.0.3+4** de C8 corrige la consulta de justificaciones por horas, muestra todos los tramos en cada tarjeta docente y adelanta la carga de **Mis materias**. **C8 está cerrado** tras la validación del propietario en el TECNO. La siguiente etapa es validar C9 en el TECNO. [Seguimiento C8](docs/seguimiento_conjunto_8.md)

## Qué se puede hacer

### Docente

- Crear y organizar cursos con horario y modalidad de asistencia por encuentro o por horas.
- Inscribir estudiantes manualmente, mediante solicitud de ingreso o con una lista de Excel.
- Preparar la lista de una clase, marcar **Presente** o **Ausente** y finalizar el registro.
- Continuar una asistencia incompleta, corregir una marca con historial y anular o restaurar una sesión.
- Encontrar **Justificaciones pendientes** en la asistencia del curso y aprobar o rechazar cada solicitud.
- Reprogramar o cancelar clases antes de iniciar su asistencia.

### Estudiante

- Crear una cuenta, verificar el correo, ingresar, recuperar la contraseña y cerrar sesión.
- Solicitar ingreso a un curso y consultar sus materias activas y su calendario previsto.
- Consultar sus propios registros publicados y solicitar justificación de una ausencia por encuentro/tramo. Pendiente o rechazada sigue contando; aprobada conserva el total y resta solo la falta cubierta.

Cada cuenta nueva empieza con el rol de estudiante. La app no permite que una persona se asigne permisos docentes o administrativos desde el cliente.

## Cuentas para probar

Usa dos cuentas distintas cuyos correos puedas consultar. No hay cuentas de demostración ni contraseñas publicadas en este repositorio.

- **Estudiante:** regístrate desde la app y verifica el correo. Para que el curso aparezca en **Mis materias**, el docente debe inscribir esta cuenta o aprobar su solicitud de ingreso.
- **Docente:** regístrate, verifica el correo y envía la solicitud de acceso docente desde la app. Una cuenta administradora ya autorizada debe aprobarla. También puedes usar una cuenta docente verificada que ya tenga ese permiso.

Los roles no se asignan desde el formulario. La [guía de acceso docente](docs/activacion_acceso_docente.md) explica el otorgamiento confiable; las [guías de ingreso y matrícula](docs/activacion_conjunto_4.md) describen cómo vincular al estudiante.

## Probar el flujo principal

Para la prueba usa un curso de ensayo con un docente propietario y un estudiante con matrícula activa. Si la clase aún no llega a su fecha y hora efectiva, se puede preparar la lista, pero no iniciar el registro.

1. Ingresa como docente y abre **Mis cursos → curso → Asistencia → Gestionar**.
2. Elige una clase cuya hora efectiva ya haya comenzado. Pulsa **Registrar asistencia**; si la lista está incompleta, pulsa **Completar lista**.
3. Marca al estudiante como **Presente** o **Ausente** y pulsa **Finalizar**. Confirma las pendientes si la app lo solicita.
4. Cierra sesión e ingresa con la cuenta del estudiante.
5. Abre **Mis materias → curso → Consultar asistencia**. El estudiante solo puede consultar su propio registro una vez publicado. Si todavía no aparece, vuelve a abrir o actualizar la consulta mientras termina la publicación por filas.

La [guía de activación C8](docs/activacion_conjunto_8.md) conserva recorridos por encuentro y por horas, y el [seguimiento C8](docs/seguimiento_conjunto_8.md) indica cómo retomar las tres sesiones incompletas del 15 y 16 de noviembre.

## Clonar y ejecutar en Android

Se necesita Git, Flutter con Dart, Android Studio con el SDK y las herramientas de Android, y un emulador o dispositivo Android. La versión usada para las verificaciones de esta rama fue Flutter **3.47.1** y Dart **3.13.1**. Android es la plataforma configurada en este proyecto.

```bash
git clone --branch feature/conjunto-8-asistencia-manual-v2 https://github.com/CJUAN25/aula-presente.git
cd aula-presente
flutter doctor -v
flutter pub get
flutter devices
flutter run -d ID_DEL_DISPOSITIVO
```

Reemplaza `ID_DEL_DISPOSITIVO` por uno de los identificadores que muestre `flutter devices`. Si Android solicita aceptar licencias, ejecuta `flutter doctor --android-licenses`. El proyecto requiere Android SDK 36, NDK 28.2.13676358 y es compatible desde Android 7.0 (API 24). Android Studio genera `android/local.properties` para cada equipo; no copies rutas del SDK de otra computadora.

Para revisar o compilar localmente:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

La APK de depuración queda en `build/app/outputs/flutter-apk/app-debug.apk`. Compilar no equivale a probar la app en el teléfono ni a comprobar las reglas publicadas.

## Firebase

La configuración cliente incluida apunta al proyecto `aula-presente-movil-juan-2026`: `lib/firebase_options.dart` y `android/app/google-services.json`. Es configuración de cliente para Firebase; no son credenciales administrativas. Para iniciar sesión se necesita Internet, una cuenta propia y acceso al correo de verificación.

Para el cierre de C8, el propietario publicó `firestore.rules` en `aula-presente-movil-juan-2026`, base `(default)`, y verificó que la fuente activa coincide con el archivo local. La revisión conserva el índice automático por `status` de la bandeja y el compuesto de `attendance_records`. [Seguimiento C8](docs/seguimiento_conjunto_8.md)

## Documentación

- [Arquitectura y esquema](docs/arquitectura.md)
- [Estado actual del proyecto](docs/estado_actual.md)
- [Seguimiento, diagnóstico y pruebas de C8](docs/seguimiento_conjunto_8.md)
- [Activación y recorrido manual de C8](docs/activacion_conjunto_8.md)
- [Guías de acceso docente](docs/activacion_acceso_docente.md), [cursos](docs/activacion_conjunto_2.md), [matrícula por código](docs/activacion_conjunto_4.md), [retiro y reincorporación](docs/activacion_conjunto_5.md) e [importación de Excel](docs/activacion_conjunto_6.md)
- [Pruebas de reglas con el emulador](tools/firestore_rules_tests/README.md)

El [seguimiento](docs/seguimiento_conjunto_8.md) registra las verificaciones locales, mediciones y pasos de validación en el TECNO.
