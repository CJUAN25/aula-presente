import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/course_repository_scope.dart';
import '../../../app/enrollment_repository_scope.dart';
import '../../../app/teacher_access_repository_scope.dart';
import '../../administration/domain/teacher_access_repository.dart';
import '../../administration/presentation/admin_teacher_requests_screen.dart'
    as teacher_access;
import '../../administration/presentation/teacher_access_screens.dart'
    as teacher_access;
import '../../administration/presentation/teacher_profile_screen.dart'
    as teacher_profile;
import '../../demo_records/presentation/demo_records_screen.dart';
import '../../courses/presentation/teacher_courses_screen.dart'
    as teacher_courses;
import '../../enrollments/presentation/student_enrollment_screens.dart';
import '../application/auth_form_validator.dart';
import '../domain/auth_access.dart';
import '../domain/auth_repository.dart';

const _pageWidth = 390.0;
const _pagePadding = 20.0;

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _failureMessage(AuthFailure failure) => switch (failure.kind) {
  AuthFailureKind.invalidCredentials =>
    'No pudimos iniciar sesión. Revisa el correo y la contraseña.',
  AuthFailureKind.emailAlreadyInUse =>
    'Este correo ya tiene una cuenta. Inicia sesión o recupera el acceso.',
  AuthFailureKind.weakPassword => 'Elige una contraseña más segura.',
  AuthFailureKind.network =>
    'No pudimos conectar. Revisa tu conexión e inténtalo de nuevo.',
  AuthFailureKind.tooManyRequests =>
    'Hubo demasiados intentos. Espera un momento y vuelve a probar.',
  AuthFailureKind.recentLoginRequired =>
    'Vuelve a iniciar sesión para confirmar este cambio.',
  AuthFailureKind.profileUnavailable => 'No pudimos consultar tu perfil. Comprueba la conexión e inténtalo otra vez.',
  AuthFailureKind.unknown =>
    'No pudimos completar la solicitud. Inténtalo otra vez.',
};

Widget _destinationForAccess(
  BuildContext context,
  AuthRepository repository,
  AuthAccess access,
) {
  final requestRepository = TeacherAccessRepositoryScope.read(context);
  return switch (access.status) {
    AuthAccessStatus.signedOut => WelcomeScreen(repository: repository),
    AuthAccessStatus.verificationRequired => VerificationScreen(
      repository: repository,
      email: access.email ?? '',
      name: access.name,
    ),
    AuthAccessStatus.checking => const _AuthLoadingScreen(
      message: 'Comprobando el acceso de esta cuenta…',
    ),
    AuthAccessStatus.student ||
    AuthAccessStatus.accessAvailable => AccessSpaceScreen(
      repository: repository,
      access: access,
      requestRepository: requestRepository,
    ),
    AuthAccessStatus.profileMissing ||
    AuthAccessStatus.profileInvalid ||
    AuthAccessStatus.profileEmailMismatch ||
    AuthAccessStatus.roleNotGranted ||
    AuthAccessStatus.profileUnavailable ||
    AuthAccessStatus.pendingEmailChange => AuthAccessStatusScreen(
      repository: repository,
      access: access,
    ),
  };
}

void _replaceWithAccess(
  BuildContext context,
  AuthRepository repository,
  AuthAccess access,
) {
  Navigator.of(context).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(
      builder: (routeContext) =>
          _destinationForAccess(routeContext, repository, access),
    ),
    (_) => false,
  );
}

class AuthStartScreen extends StatefulWidget {
  const AuthStartScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AuthStartScreen> createState() => _AuthStartScreenState();
}

class _AuthStartScreenState extends State<AuthStartScreen> {
  late Future<AuthAccess> _restore;

  @override
  void initState() {
    super.initState();
    _restore = widget.repository.restoreSession();
  }

  void _retry() =>
      setState(() => _restore = widget.repository.restoreSession());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthAccess>(
      future: _restore,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AuthLoadingScreen(message: 'Comprobando tu sesión…');
        }
        if (snapshot.hasError) {
          final failure = snapshot.error is AuthFailure
              ? snapshot.error! as AuthFailure
              : const AuthFailure(AuthFailureKind.unknown);
          return AuthPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageIntro(title: 'No pudimos comprobar tu sesión.'),
                const SizedBox(height: 16),
                NoticeCard(
                  title: 'Inténtalo de nuevo',
                  body: _failureMessage(failure),
                  icon: 'fcc39.svg',
                  isError: true,
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Reintentar', onPressed: _retry),
              ],
            ),
          );
        }
        return _destinationForAccess(
          context,
          widget.repository,
          snapshot.data ?? const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => AuthPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: AuthTextStyles.body),
      ],
    ),
  );
}

class _AuthRoleGuard extends StatefulWidget {
  const _AuthRoleGuard({
    required this.repository,
    required this.initialAccess,
    required this.builder,
    this.requiredRole,
  });

  final AuthRepository repository;
  final AuthAccess initialAccess;
  final String? requiredRole;
  final Widget Function(BuildContext context, AuthAccess access) builder;

  @override
  State<_AuthRoleGuard> createState() => _AuthRoleGuardState();
}

class _AuthRoleGuardState extends State<_AuthRoleGuard> {
  late final Stream<AuthAccess> _accessStream;
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    try {
      _accessStream = widget.repository.watchAccess();
    } catch (error) {
      _accessStream = Stream<AuthAccess>.error(error);
    }
  }

  bool _hasRequiredAccess(AuthAccess access) {
    final hasProfile =
        access.uid?.isNotEmpty == true && access.roles.isNotEmpty;
    final isAuthorized =
        access.status == AuthAccessStatus.accessAvailable ||
        access.status == AuthAccessStatus.student;
    return hasProfile &&
        isAuthorized &&
        (widget.requiredRole == null ||
            access.roles.contains(widget.requiredRole));
  }

  void _redirect(BuildContext context, AuthAccess access) {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _replaceWithAccess(context, widget.repository, access);
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthAccess>(
    stream: _accessStream,
    initialData: widget.initialAccess,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final unavailable = AuthAccess(
          status: AuthAccessStatus.profileUnavailable,
          uid: widget.initialAccess.uid,
          email: widget.initialAccess.email,
          failure: AuthFailureKind.network,
        );
        _redirect(context, unavailable);
        return const _AuthLoadingScreen(
          message: 'Volviendo a comprobar tus permisos…',
        );
      }

      final currentAccess = snapshot.data ?? widget.initialAccess;
      if (currentAccess.status == AuthAccessStatus.checking) {
        return const _AuthLoadingScreen(
          message: 'Cambiando a la cuenta activa…',
        );
      }
      if (!_hasRequiredAccess(currentAccess) ||
          currentAccess.uid != widget.initialAccess.uid) {
        _redirect(context, currentAccess);
        return const _AuthLoadingScreen(
          message: 'Actualizando el acceso de tu cuenta…',
        );
      }

      return widget.builder(context, currentAccess);
    },
  );
}

class AuthAccessStatusScreen extends StatefulWidget {
  const AuthAccessStatusScreen({
    super.key,
    required this.repository,
    required this.access,
  });

  final AuthRepository repository;
  final AuthAccess access;

  @override
  State<AuthAccessStatusScreen> createState() => _AuthAccessStatusScreenState();
}

class _AuthAccessStatusScreenState extends State<AuthAccessStatusScreen> {
  bool _busy = false;
  String? _error;

  (String, String) get _copy => switch (widget.access.status) {
    AuthAccessStatus.profileMissing => (
      'No encontramos tu perfil.',
      'Tu cuenta existe, pero falta el perfil de Aula Presente. No asignamos permisos automáticamente. Intenta consultar otra vez o cierra sesión y contacta al equipo de soporte.',
    ),
    AuthAccessStatus.profileInvalid => (
      'Tu perfil requiere revisión.',
      'El perfil no tiene el formato esperado. No habilitamos un espacio hasta que se corrija mediante un proceso confiable.',
    ),
    AuthAccessStatus.profileEmailMismatch => (
      'Tu correo no coincide con el perfil.',
      'No habilitamos el acceso hasta que el correo verificado y tu perfil coincidan. Comprueba el correo de la cuenta o contacta al equipo de soporte.',
    ),
    AuthAccessStatus.roleNotGranted => (
      'Aún no tienes un espacio autorizado.',
      'El acceso de estudiante requiere un perfil autorizado. Los permisos docentes y de administración solo pueden concederse mediante un proceso confiable.',
    ),
    AuthAccessStatus.profileUnavailable => (
      'No pudimos cargar tu perfil.',
      'Comprueba tu conexión e inténtalo de nuevo. No se abrió ningún espacio protegido.',
    ),
    AuthAccessStatus.pendingEmailChange => (
      'Confirma el correo nuevo.',
      'Abre el enlace que enviamos a la dirección nueva y vuelve aquí para comprobarla.',
    ),
    _ => (
      'No pudimos habilitar el acceso.',
      'Vuelve a intentarlo o cierra sesión.',
    ),
  };

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = await widget.repository.refreshAccess();
      if (mounted) _replaceWithAccess(context, widget.repository, access);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos conectar. Inténtalo otra vez.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.signOut();
      if (mounted) {
        _replaceWithAccess(
          context,
          widget.repository,
          const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cerrar la sesión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return AuthPage(
      appBar: const AuthAppBar(title: 'Acceso a Aula Presente'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageIntro(title: copy.$1),
          const SizedBox(height: 16),
          NoticeCard(
            title: 'Tu cuenta está protegida',
            body: copy.$2,
            icon: 'fcc39.svg',
            isError:
                widget.access.status == AuthAccessStatus.profileUnavailable,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoticeCard(
              title: 'No se completó la acción',
              body: _error!,
              icon: 'fcc39.svg',
              isError: true,
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Volver a comprobar',
            isLoading: _busy,
            onPressed: _busy ? null : _retry,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Cerrar sesión',
            onPressed: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({
    super.key,
    required this.repository,
    required this.access,
  });

  final AuthRepository repository;
  final AuthAccess access;

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  bool _busy = false;
  String? _error;
  bool _directoryStarted = false;
  bool _directoryBusy = false;
  Object? _directoryError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_directoryStarted) {
      _directoryStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_publishDirectory());
      });
    }
  }

  Future<void> _publishDirectory() async {
    if (_directoryBusy) return;
    setState(() {
      _directoryBusy = true;
      _directoryError = null;
    });
    try {
      await EnrollmentRepositoryScope.read(context)
          .ensureStudentDirectoryEntry();
    } catch (error) {
      if (mounted) setState(() => _directoryError = error);
    } finally {
      if (mounted) setState(() => _directoryBusy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.signOut();
      if (mounted) {
        _replaceWithAccess(
          context,
          widget.repository,
          const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cerrar la sesión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthRoleGuard(
    repository: widget.repository,
    initialAccess: widget.access,
    requiredRole: 'student',
    builder: _buildProfile,
  );

  Widget _buildProfile(BuildContext context, AuthAccess access) {
    return AuthPage(
      appBar: const AuthAppBar(title: 'Perfil estudiante'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.outline),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.glass,
                  child: const FigmaIcon('c2efa.svg', size: 32),
                ),
                const SizedBox(height: 12),
                Text(
                  access.name ?? 'Estudiante',
                  style: AuthTextStyles.cardTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  access.email ?? '',
                  style: AuthTextStyles.body,
                  textAlign: TextAlign.center,
                ),
                if (access.studentCode?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(access.studentCode!, style: AuthTextStyles.small),
                ],
                const SizedBox(height: 12),
                const StatusPill(label: 'Estudiante'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_directoryError != null) ...[
            NoticeCard(
              title: 'Tu cuenta aún no aparece para agregados manuales',
              body: 'No pudimos actualizar tus datos de búsqueda. Revisa la conexión y vuelve a intentarlo. Tus cursos inscritos se consultan por separado.',
              icon: 'fcc39.svg',
              isError: true,
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Reintentar actualización',
              onPressed: _directoryBusy ? null : _publishDirectory,
            ),
            const SizedBox(height: 12),
          ],
          ActionCard(
            title: 'Mis materias',
            body: 'Cursos en los que estás inscrito y horario previsto',
            leading: '49279.svg',
            trailing: '8aca9.svg',
            onTap: () => _push(
              context,
              StudentCoursesScreen(
                repository: EnrollmentRepositoryScope.read(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const ActionCard(
            title: 'Permisos del teléfono',
            body: 'Configuración del dispositivo',
            leading: 'f6ef6.svg',
          ),
          const SizedBox(height: 10),
          const ActionCard(
            title: 'Ayuda',
            body: 'Información de Aula Presente',
            leading: '1e78f.svg',
          ),
          const SizedBox(height: 10),
          ActionCard(
            title: 'Registros de prueba',
            body: 'Consulta y administra tus registros',
            leading: '727c8.svg',
            trailing: '8aca9.svg',
            onTap: () => _push(context, const DemoRecordsScreen()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoticeCard(
              title: 'No se completó el cierre',
              body: _error!,
              icon: 'fcc39.svg',
              isError: true,
            ),
          ],
          const SizedBox(height: 16),
          SecondaryButton(
            label: _busy ? 'Cerrando sesión…' : 'Cerrar sesión',
            icon: '13650.svg',
            onPressed: _busy ? null : _signOut,
          ),
          const SizedBox(height: 20),
          const _PreviewBottomNavigation(teacher: false),
        ],
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onLongPress: kDebugMode
                ? () => _showPreviewMenu(context, repository)
                : null,
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FigmaIcon('727c8.svg', size: 24),
                SizedBox(width: 16),
                Text('Aula\nPresente', style: AuthTextStyles.brand),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: const FigmaImage('b26fd.svg', width: 350, height: 244),
          ),
          const SizedBox(height: 20),
          const Text('Tu clase empieza aquí.', style: AuthTextStyles.hero),
          const SizedBox(height: 8),
          const Text(
            'Tu asistencia, clara y a tiempo.',
            style: AuthTextStyles.body,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Entrar con mi cuenta',
            icon: '18fe3.svg',
            onPressed: () =>
                _push(context, LoginScreen(repository: repository)),
          ),
          const SizedBox(height: 16),
          ActionCard(
            title: '¿Primera vez?',
            body: 'Usa tu correo institucional',
            leading: '0beda.svg',
            trailing: '8aca9.svg',
            onTap: () =>
                _push(context, RegistrationScreen(repository: repository)),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    this.showError = false,
  });

  final AuthRepository repository;
  final bool showError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.showError) {
      _message(context, 'Vista previa: no se intentó iniciar sesión.');
      return;
    }
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final access = await widget.repository.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) _replaceWithAccess(context, widget.repository, access);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _errorMessage = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'No pudimos iniciar sesión. Inténtalo otra vez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showError && !kDebugMode) {
      return const _PreviewUnavailableScreen();
    }
    final error = widget.showError || _errorMessage != null;
    return AuthPage(
      appBar: AuthAppBar(title: 'Iniciar sesión'),
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageIntro(
              title: error ? 'Intentémoslo otra vez.' : 'Qué bueno verte.',
            ),
            const SizedBox(height: 8),
            AuthTextField(
              label: 'Correo institucional',
              controller: _emailController,
              hint: 'estudiante@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: AuthFormValidator.email,
              forceErrorBorder: error,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Contraseña',
              controller: _passwordController,
              hint: '••••••••  ·  mostrar / ocultar',
              isPassword: true,
              textInputAction: TextInputAction.done,
              validator: AuthFormValidator.password,
              forceErrorBorder: error,
              onSubmitted: (_) => _submit(),
            ),
            if (widget.showError) ...[
              const SizedBox(height: 12),
              const NoticeCard(
                title: 'No pudimos entrar',
                body: 'Revisa el correo y la contraseña.',
                icon: 'fcc39.svg',
                isError: true,
              ),
              const SizedBox(height: 8),
              const PreviewNotice(
                message: 'Vista previa de error. No se intentó autenticar.',
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              NoticeCard(
                title: 'No pudimos entrar',
                body: _errorMessage!,
                icon: 'fcc39.svg',
                isError: true,
              ),
            ],
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Olvidé mi contraseña',
              icon: '999a7.svg',
              onPressed: _busy
                  ? null
                  : () => _push(
                      context,
                      RecoveryScreen(repository: widget.repository),
                    ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: _busy ? 'Entrando…' : 'Entrar',
              icon: _busy ? null : 'e265d.svg',
              isLoading: _busy,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Crear mi cuenta',
              icon: '777ff.svg',
              onPressed: _busy
                  ? null
                  : () => _push(
                      context,
                      RegistrationScreen(repository: widget.repository),
                    ),
            ),
            const SizedBox(height: 16),
            const NoticeCard(
              title: 'Una cuenta, varios espacios',
              body: 'Puedes estudiar y enseñar con permisos habilitados.',
            ),
          ],
        ),
      ),
    );
  }
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.sendPasswordReset(_emailController.text.trim());
      if (mounted) {
        _push(
          context,
          RecoverySentScreen(
            repository: widget.repository,
            email: _emailController.text.trim(),
          ),
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'No pudimos enviar la solicitud. Comprueba tu conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      appBar: const AuthAppBar(title: 'Recuperar acceso'),
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageIntro(
              title: 'Volvamos a entrar.',
              body: 'Te enviaremos un enlace para crear otra contraseña.',
            ),
            const SizedBox(height: 24),
            AuthTextField(
              label: 'Correo institucional',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: AuthFormValidator.email,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoticeCard(
                title: 'No se completó la solicitud',
                body: _error!,
                icon: 'fcc39.svg',
                isError: true,
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: _busy ? 'Enviando…' : 'Enviar enlace',
              isLoading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class RecoverySentScreen extends StatefulWidget {
  const RecoverySentScreen({
    super.key,
    required this.repository,
    required this.email,
    this.previewOnly = false,
  });

  final AuthRepository repository;
  final String email;
  final bool previewOnly;

  @override
  State<RecoverySentScreen> createState() => _RecoverySentScreenState();
}

class _RecoverySentScreenState extends State<RecoverySentScreen> {
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _resend() async {
    if (widget.previewOnly) {
      _message(context, 'Vista previa: no se envió ningún correo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.repository.sendPasswordReset(widget.email);
      if (mounted) {
        setState(
          () => _notice = 'Si el correo corresponde a una cuenta, recibirás un enlace de recuperación.',
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'No pudimos enviar la solicitud. Comprueba tu conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.previewOnly && !kDebugMode) {
      return const _PreviewUnavailableScreen();
    }
    return AuthPage(
      appBar: const AuthAppBar(title: 'Revisa tu correo'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageIntro(
            title: 'Revisa tu bandeja.',
            body: 'Si el correo está registrado, recibirás un enlace de recuperación.',
          ),
          const SizedBox(height: 24),
          if (_notice != null) ...[
            NoticeCard(title: 'Solicitud enviada', body: _notice!),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            NoticeCard(
              title: 'No se completó la solicitud',
              body: _error!,
              icon: 'fcc39.svg',
              isError: true,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.previewOnly) ...[
            PreviewNotice(
              message:
                  'Vista previa local para ${widget.email}. No se envió ningún correo.',
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Volver al inicio de sesión',
            onPressed: () {
              final navigator = Navigator.of(context);
              if (widget.previewOnly) {
                navigator.popUntil((route) => route.isFirst);
              } else {
                navigator.pushAndRemoveUntil<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => LoginScreen(repository: widget.repository),
                  ),
                  (route) => route.isFirst,
                );
              }
            },
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: _busy ? 'Enviando…' : 'Enviar otra vez',
            onPressed: _busy ? null : _resend,
          ),
        ],
      ),
    );
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _studentCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _studentCodeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      final studentCode = _studentCodeController.text.trim();
      final result = await widget.repository.register(
        name: name,
        email: _emailController.text.trim(),
        studentCode: studentCode,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          builder: (_) => VerificationScreen(
            repository: widget.repository,
            email: result.email,
            name: name,
            studentCode: studentCode,
            profileReady: result.profileCreated && result.displayNameUpdated,
            verificationEmailSent: result.verificationEmailSent,
            setupFailure: result.setupFailure,
          ),
        ),
        (_) => false,
      );
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No pudimos crear la cuenta. Inténtalo otra vez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      appBar: const AuthAppBar(title: 'Crear cuenta'),
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageIntro(title: 'Tu cuenta empieza aquí.'),
            const SizedBox(height: 20),
            AuthTextField(
              label: 'Nombre completo',
              hint: 'Nombre Apellido',
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: AuthFormValidator.fullName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Correo institucional',
              hint: 'estudiante@example.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: AuthFormValidator.email,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Código estudiantil',
              hint: 'Tu código, si eres estudiante',
              controller: _studentCodeController,
              textInputAction: TextInputAction.next,
              validator: AuthFormValidator.studentCode,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Contraseña',
              hint: 'Mínimo 8 caracteres',
              controller: _passwordController,
              isPassword: true,
              validator: AuthFormValidator.password,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Confirmar contraseña',
              controller: _confirmController,
              isPassword: true,
              validator: (value) => AuthFormValidator.confirmation(
                _passwordController.text,
                value,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoticeCard(
                title: 'No se creó la cuenta',
                body: _error!,
                icon: 'fcc39.svg',
                isError: true,
              ),
            ],
            const SizedBox(height: 16),
            ActionCard(
              title: 'Cómo participarás',
              body: 'Estudiante · solicitar acceso docente',
              leading: '727c8.svg',
              trailing: '8aca9.svg',
              onTap: () => _push(
                context,
                teacher_access.TeacherAccessScreen(
                  access: const AuthAccess(status: AuthAccessStatus.signedOut),
                  authRepository: widget.repository,
                  requestRepository: TeacherAccessRepositoryScope.read(context),
                  onContinueAsStudent: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: _busy ? 'Creando cuenta…' : 'Crear cuenta y verificar',
              isLoading: _busy,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 12),
            const Text(
              'Acepto el uso de mis datos para gestionar asistencia.',
              textAlign: TextAlign.center,
              style: AuthTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.repository,
    required this.email,
    this.name,
    this.studentCode = '',
    this.profileReady = true,
    this.verificationEmailSent = true,
    this.setupFailure,
    this.previewOnly = false,
  });

  final AuthRepository repository;
  final String email;
  final String? name;
  final String studentCode;
  final bool profileReady;
  final bool verificationEmailSent;
  final AuthFailureKind? setupFailure;
  final bool previewOnly;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _busy = false;
  late bool _profileReady;
  late bool _verificationEmailSent;
  String? _pendingEmail;
  String? _notice;
  String? _error;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _profileReady = widget.profileReady;
    _verificationEmailSent = widget.verificationEmailSent;
    if (widget.verificationEmailSent) _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verify() async {
    if (widget.previewOnly) {
      _message(context, 'Vista previa: no se comprobó ninguna cuenta.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
    });
    try {
      final access = await widget.repository.refreshAccess(
        expectedEmail: _pendingEmail,
      );
      if (!mounted) return;
      if (access.status == AuthAccessStatus.verificationRequired) {
        setState(
          () => _notice = _pendingEmail == null
              ? 'Todavía no aparece la verificación. Abre el enlace del correo y vuelve a comprobar.'
              : 'El correo nuevo todavía no está confirmado. Abre el enlace enviado a $_pendingEmail.',
        );
        return;
      }
      if (access.status == AuthAccessStatus.pendingEmailChange) {
        setState(
          () => _notice =
              'Aún esperamos la confirmación enviada a ${_pendingEmail ?? widget.email}.',
        );
        return;
      }
      if (access.status == AuthAccessStatus.profileMissing &&
          !_profileReady &&
          widget.name != null) {
        setState(
          () => _error = 'La cuenta ya existe, pero falta completar su perfil. Reintenta la preparación antes de entrar.',
        );
        return;
      }
      _replaceWithAccess(context, widget.repository, access);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No pudimos comprobar el correo. Inténtalo otra vez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (widget.previewOnly) {
      _message(context, 'Vista previa: no se envió ningún correo.');
      return;
    }
    if (_busy || _resendSeconds > 0) return;
    if (_pendingEmail != null) {
      await _correctEmail(resendPendingChange: true);
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
    });
    try {
      await widget.repository.resendEmailVerification();
      if (mounted) {
        setState(() {
          _verificationEmailSent = true;
          _notice = 'Enviamos otro enlace de verificación a ${widget.email}.';
        });
        _startResendCooldown();
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos reenviar el enlace.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correctEmail({bool resendPendingChange = false}) async {
    if (widget.previewOnly) {
      _message(context, 'Vista previa: no se cambió ningún correo.');
      return;
    }
    final details = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) => _EmailCorrectionDialog(
        initialEmail: _pendingEmail ?? widget.email,
        resendPendingChange: resendPendingChange,
      ),
    );
    if (details == null || !mounted) return;

    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
    });
    try {
      await widget.repository.requestEmailCorrection(
        newEmail: details.email,
        currentPassword: details.password,
      );
      if (!mounted) return;
      setState(() {
        _pendingEmail = details.email.trim();
        _verificationEmailSent = true;
        _notice =
            'Enviamos un enlace de confirmación a ${details.email.trim()}. El cambio se aplicará cuando lo confirmes.';
      });
      _startResendCooldown();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos solicitar el cambio de correo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryProfile() async {
    final name = widget.name;
    if (widget.previewOnly || name == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.repository.retryRegistrationSetup(
        name: name,
        studentCode: widget.studentCode,
      );
      if (mounted) {
        setState(() {
          _profileReady = true;
          _notice =
              'Perfil de estudiante preparado. Ya puedes comprobar el correo.';
        });
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No pudimos completar el perfil. Inténtalo otra vez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (widget.previewOnly || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.signOut();
      if (mounted) {
        _replaceWithAccess(
          context,
          widget.repository,
          const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cerrar la sesión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.previewOnly && !kDebugMode) {
      return const _PreviewUnavailableScreen();
    }
    final displayedEmail = _pendingEmail ?? widget.email;
    final setupError = widget.setupFailure == null
        ? null
        : _failureMessage(AuthFailure(widget.setupFailure!));
    return AuthPage(
      appBar: AuthAppBar(
        title: 'Verificar correo',
        onBack: widget.previewOnly ? null : _signOut,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageIntro(title: 'Revisa tu correo.'),
          const SizedBox(height: 20),
          NoticeCard(
            title: _pendingEmail == null
                ? 'Correo pendiente'
                : 'Correo nuevo pendiente',
            body: displayedEmail,
            icon: '0beda.svg',
          ),
          const SizedBox(height: 12),
          const NoticeCard(
            title: 'Confirma que eres tú',
            body: 'Abre el enlace de verificación. Después podremos buscar tus cursos.',
            icon: 'e265d.svg',
          ),
          if (!_profileReady || !_verificationEmailSent) ...[
            const SizedBox(height: 12),
            NoticeCard(
              title: 'Preparación pendiente',
              body: !_profileReady
                  ? 'La cuenta se creó, pero no pudimos guardar el perfil de estudiante.'
                  : setupError ??
                        'No pudimos enviar el correo de verificación.',
              icon: 'fcc39.svg',
              isError: true,
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            NoticeCard(title: 'Estado de verificación', body: _notice!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoticeCard(
              title: 'No se completó la acción',
              body: _error!,
              icon: 'fcc39.svg',
              isError: true,
            ),
          ],
          if (widget.previewOnly) ...[
            const SizedBox(height: 16),
            const PreviewNotice(
              message: 'Vista previa aislada. No se consultó ni modificó una cuenta.',
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: _busy ? 'Comprobando…' : 'Ya verifiqué mi correo',
            isLoading: _busy,
            onPressed: _busy ? null : _verify,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: _busy
                ? 'Procesando…'
                : _resendSeconds > 0
                ? 'Reenviar enlace · ${_resendSeconds}s'
                : 'Reenviar enlace',
            onPressed: _busy || _resendSeconds > 0 ? null : _resend,
          ),
          if (!_profileReady && widget.name != null && !widget.previewOnly) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: _busy
                  ? 'Preparando…'
                  : 'Reintentar preparación del perfil',
              onPressed: _busy ? null : _retryProfile,
            ),
          ],
          TextButton(
            onPressed: _busy ? null : () => _correctEmail(),
            child: const Text('Corregir correo'),
          ),
          if (!widget.previewOnly)
            TextButton(
              onPressed: _busy ? null : _signOut,
              child: const Text('Salir de esta cuenta'),
            ),
        ],
      ),
    );
  }
}

class _EmailCorrectionDialog extends StatefulWidget {
  const _EmailCorrectionDialog({
    required this.initialEmail,
    required this.resendPendingChange,
  });

  final String initialEmail;
  final bool resendPendingChange;

  @override
  State<_EmailCorrectionDialog> createState() => _EmailCorrectionDialogState();
}

class _EmailCorrectionDialogState extends State<_EmailCorrectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    title: Text(
      widget.resendPendingChange
          ? 'Reenviar cambio de correo'
          : 'Corregir correo',
      style: AuthTextStyles.cardTitle,
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Confirma tu contraseña actual. Enviaremos un enlace a la dirección nueva y no cambiaremos la cuenta hasta que lo confirmes.',
            style: AuthTextStyles.small,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo nuevo'),
            validator: AuthFormValidator.email,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Contraseña actual'),
            validator: (value) => (value == null || value.isEmpty)
                ? 'Escribe tu contraseña actual.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.of(context).pop((
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ));
        },
        child: const Text('Enviar confirmación'),
      ),
    ],
  );
}

class TeacherAccessPreviewScreen extends StatefulWidget {
  const TeacherAccessPreviewScreen({super.key});

  @override
  State<TeacherAccessPreviewScreen> createState() =>
      _TeacherAccessPreviewScreenState();
}

class _TeacherAccessPreviewScreenState
    extends State<TeacherAccessPreviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteController = TextEditingController();

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  void _requestAccess() {
    if (!_formKey.currentState!.validate()) return;
    if (kDebugMode) {
      _push(context, const TeacherRequestPreviewScreen());
    } else {
      _message(context, 'No se envió una solicitud ni se activaron permisos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      appBar: const AuthAppBar(title: 'Acceso docente'),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageIntro(
              title: 'Enseña con tu cuenta.',
              body: 'Puedes estudiar y enseñar con la misma cuenta.',
            ),
            const SizedBox(height: 20),
            const NoticeCard(
              title: 'Tengo una invitación',
              body: 'Introduce el código del administrador.',
              icon: '9c45e.svg',
            ),
            const SizedBox(height: 12),
            AuthTextField(
              label: 'Invitación docente',
              hint: 'DOC-2026-XXXX',
              controller: _inviteController,
              textCapitalization: TextCapitalization.characters,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Escribe el código de invitación.'
                  : null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _requestAccess(),
            ),
            const SizedBox(height: 12),
            const NoticeCard(
              title: 'Activación de permisos',
              body: 'El administrador del proyecto valida la invitación o tu solicitud.',
              icon: 'e265d.svg',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Solicitar acceso docente',
              onPressed: _requestAccess,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Continuar como estudiante',
              onPressed: () => _message(
                context,
                'Vista previa: no hay una sesión de estudiante.',
              ),
            ),
            const SizedBox(height: 12),
            const PreviewNotice(
              message:
                  'Vista previa: la invitación no se validará ni guardará.',
            ),
          ],
        ),
      ),
    );
  }
}

class TeacherRequestPreviewScreen extends StatelessWidget {
  const TeacherRequestPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const _PreviewUnavailableScreen();
    return AuthPage(
      appBar: const AuthAppBar(title: 'Solicitud docente'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageIntro(title: 'Tu solicitud está en revisión.'),
          const SizedBox(height: 20),
          const StatusPill(label: 'Pendiente'),
          const SizedBox(height: 16),
          const NoticeCard(
            title: 'Te avisaremos al resolverla',
            body:
                'Podrás crear cursos cuando tu acceso docente esté habilitado.',
            icon: 'ce7e6.svg',
          ),
          const SizedBox(height: 16),
          const PreviewNotice(
            message: 'Vista previa: no se envió ni guardó una solicitud.',
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Ir a mi espacio estudiante',
            onPressed: () => _message(
              context,
              'No hay una sesión ni un espacio estudiante activo.',
            ),
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Consultar solicitud',
            onPressed: () => _message(
              context,
              'Vista previa: no existe una solicitud para consultar.',
            ),
          ),
        ],
      ),
    );
  }
}

class AccessSpaceScreen extends StatelessWidget {
  const AccessSpaceScreen({
    super.key,
    required this.repository,
    required this.requestRepository,
    required this.access,
  });

  final AuthRepository repository;
  final TeacherAccessRepository requestRepository;
  final AuthAccess access;

  void _openStudent(BuildContext context, AuthAccess currentAccess) {
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudentProfileScreen(repository: repository, access: currentAccess),
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await repository.signOut();
      if (context.mounted) {
        _replaceWithAccess(
          context,
          repository,
          const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _message(context, 'No pudimos cerrar la sesión. Inténtalo de nuevo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AuthRoleGuard(
    repository: repository,
    initialAccess: access,
    builder: (context, currentAccess) =>
        _buildSpacePicker(context, currentAccess),
  );

  Widget _buildSpacePicker(BuildContext context, AuthAccess currentAccess) {
    final roles = currentAccess.roles.toSet();
    return AuthPage(
      appBar: const AuthAppBar(title: 'Elige tu espacio'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageIntro(title: '¿En qué espacio entrarás?'),
          const SizedBox(height: 20),
          if (roles.contains('student')) ...[
            ActionCard(
              title: 'Estudiante',
              body: 'Mis materias, horario y asistencia',
              leading: '727c8.svg',
              onTap: () => _openStudent(context, currentAccess),
            ),
            const SizedBox(height: 10),
          ],
          if (roles.contains('teacher')) ...[
            ActionCard(
              title: 'Docente',
              body: 'Mis cursos, horario y agenda docente',
              leading: '777ff.svg',
              onTap: () {
                final courses = CourseRepositoryScope.read(context);
                _push(
                  context,
                  _AuthRoleGuard(
                    repository: repository,
                    initialAccess: currentAccess,
                    requiredRole: 'teacher',
                    builder: (workspaceContext, liveAccess) =>
                        teacher_courses.TeacherCoursesScreen(
                          repository: courses,
                          access: liveAccess,
                          onOpenProfile: () => _push(
                            workspaceContext,
                            teacher_profile.TeacherProfileScreen(
                              access: liveAccess,
                              authRepository: repository,
                              onChangeSpace: () =>
                                  _openStudent(workspaceContext, liveAccess),
                              onSignOut: () => _signOut(workspaceContext),
                            ),
                          ),
                          onSignOut: () => _signOut(workspaceContext),
                        ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          if (roles.contains('admin')) ...[
            ActionCard(
              title: 'Administrador del proyecto',
              body: 'Solicitudes de acceso docente',
              leading: 'f6ef6.svg',
              onTap: () => _push(
                context,
                teacher_access.AdminTeacherRequestsScreen(
                  access: currentAccess,
                  authRepository: repository,
                  requestRepository: requestRepository,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const NoticeCard(
            title: 'Según tus permisos',
            body: 'Solo aparecen los espacios autorizados para tu cuenta.',
            icon: '999a7.svg',
          ),
          if (!roles.contains('teacher')) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Solicitar acceso docente',
              onPressed: () => _push(
                context,
                teacher_access.TeacherAccessScreen(
                  access: currentAccess,
                  authRepository: repository,
                  requestRepository: requestRepository,
                  onContinueAsStudent: () =>
                      _openStudent(context, currentAccess),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Cerrar sesión',
            icon: '13650.svg',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}

class AccessSpacePreviewScreen extends StatelessWidget {
  const AccessSpacePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const _PreviewUnavailableScreen();
    return AuthPage(
      appBar: const AuthAppBar(title: 'Elige tu espacio'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageIntro(title: '¿En qué espacio entrarás?'),
          const SizedBox(height: 20),
          ActionCard(
            title: 'Estudiante',
            body: 'Mis materias, horario y asistencia',
            leading: '727c8.svg',
            onTap: () =>
                _message(context, 'Vista previa: el rol no concede permisos.'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            title: 'Docente',
            body: 'Mis cursos, grupos y registros',
            leading: '777ff.svg',
            onTap: () =>
                _message(context, 'Vista previa: el rol no concede permisos.'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            title: 'Administrador del proyecto',
            body: 'Estadísticas y accesos',
            leading: 'f6ef6.svg',
            onTap: () =>
                _message(context, 'Vista previa: el rol no concede permisos.'),
          ),
          const SizedBox(height: 16),
          const NoticeCard(
            title: 'Según tus permisos',
            body: 'Solo aparecen los espacios autorizados para tu cuenta.',
            icon: '999a7.svg',
          ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Solicitar acceso docente',
            onPressed: () => _push(context, const TeacherAccessPreviewScreen()),
          ),
          const SizedBox(height: 12),
          const PreviewNotice(
            message:
                'Vista previa: no hay cuenta autenticada ni roles autorizados.',
          ),
        ],
      ),
    );
  }
}

class ProfilePreviewScreen extends StatelessWidget {
  const ProfilePreviewScreen({super.key, required this.teacher});

  final bool teacher;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const _PreviewUnavailableScreen();
    final next = !teacher;
    return AuthPage(
      appBar: AuthAppBar(
        title: teacher ? 'Perfil docente' : 'Perfil estudiante',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PreviewNotice(
            message: 'Vista previa de diseño. Esta cuenta no inició sesión.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.outline),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.glass,
                  child: const FigmaIcon('c2efa.svg', size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Estudiante de ejemplo',
                  style: AuthTextStyles.cardTitle,
                ),
                const SizedBox(height: 4),
                const Text(
                  'estudiante@example.com',
                  style: AuthTextStyles.body,
                ),
                const SizedBox(height: 12),
                StatusPill(
                  label: teacher
                      ? 'Docente · vista previa'
                      : 'Estudiante · vista previa',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ActionCard(
            title: 'Cambiar espacio',
            body: teacher ? 'Vista de estudiante' : 'Vista de docente',
            leading: 'b6488.svg',
            trailing: '8aca9.svg',
            onTap: () => _push(context, ProfilePreviewScreen(teacher: next)),
          ),
          const SizedBox(height: 10),
          const ActionCard(
            title: 'Permisos del teléfono',
            body: 'Configuración del dispositivo',
            leading: 'f6ef6.svg',
          ),
          const SizedBox(height: 10),
          const ActionCard(
            title: 'Ayuda',
            body: 'Información de Aula Presente',
            leading: '1e78f.svg',
          ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Cerrar sesión',
            icon: '13650.svg',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              _message(
                context,
                'Vista previa cerrada; no había una sesión iniciada.',
              );
            },
          ),
          const SizedBox(height: 20),
          _PreviewBottomNavigation(teacher: teacher),
        ],
      ),
    );
  }
}

class _PreviewBottomNavigation extends StatelessWidget {
  const _PreviewBottomNavigation({required this.teacher});

  final bool teacher;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _NavItem(icon: '3dfb1.svg', label: 'Inicio'),
          _NavItem(icon: '49279.svg', label: teacher ? 'Cursos' : 'Materias'),
          const _NavItem(icon: 'c2efa.svg', label: 'Perfil', selected: true),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final String icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FigmaIcon(icon, size: 20),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.muted,
          fontSize: 11,
        ),
      ),
    ],
  );
}

class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.child, this.appBar});

  final Widget child;
  final AuthAppBar? appBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF071B17),
              AppColors.background,
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _pageWidth),
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      _pagePadding,
                      24,
                      _pagePadding,
                      28,
                    ),
                    sliver: SliverList.list(
                      children: [
                        if (appBar != null) ...[
                          appBar!,
                          const SizedBox(height: 24),
                        ],
                        child,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthAppBar extends StatelessWidget {
  const AuthAppBar({super.key, required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Center(child: FigmaIcon('55742.svg')),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: AuthTextStyles.cardTitle)),
      ],
    );
  }
}

class PageIntro extends StatelessWidget {
  const PageIntro({super.key, required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AuthTextStyles.heading),
      if (body != null) ...[
        const SizedBox(height: 8),
        Text(body!, style: AuthTextStyles.body),
      ],
    ],
  );
}

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.isPassword = false,
    this.forceErrorBorder = false,
    this.onSubmitted,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool isPassword;
  final bool forceErrorBorder;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      obscureText: widget.isPassword && _obscure,
      onFieldSubmitted: widget.onSubmitted,
      style: AuthTextStyles.field,
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        filled: true,
        fillColor: AppColors.glass.withValues(alpha: 0.66),
        labelStyle: AuthTextStyles.fieldLabel,
        hintStyle: AuthTextStyles.field.copyWith(color: AppColors.muted),
        errorStyle: const TextStyle(
          color: AppColors.danger,
          fontSize: 12,
          height: 1.2,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: _border(
          widget.forceErrorBorder ? AppColors.danger : AppColors.outline,
        ),
        enabledBorder: _border(
          widget.forceErrorBorder ? AppColors.danger : AppColors.outline,
        ),
        focusedBorder: _border(AppColors.primary, width: 1.5),
        errorBorder: _border(AppColors.danger),
        focusedErrorBorder: _border(AppColors.danger, width: 1.5),
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.muted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.primaryInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: AuthTextStyles.button,
      ),
      onPressed: onPressed,
      child: isLoading
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryInk,
              ),
            )
          : _buttonChild(),
    ),
  );

  Widget _buttonChild() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (icon != null) ...[
        FigmaIcon(icon!, size: 20),
        const SizedBox(width: 8),
      ],
      Flexible(child: Text(label, textAlign: TextAlign.center)),
    ],
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: AuthTextStyles.button,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            FigmaIcon(icon!, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.isError = false,
  });

  final String title;
  final String body;
  final String? icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? AppColors.danger : AppColors.information;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glass,
        border: Border.all(
          color: isError ? AppColors.danger : AppColors.outline,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            FigmaIcon(icon!, size: 22),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AuthTextStyles.noticeTitle.copyWith(color: accent),
                ),
                const SizedBox(height: 6),
                Text(body, style: AuthTextStyles.small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewNotice extends StatelessWidget {
  const PreviewNotice({
    super.key,
    this.message = 'Vista previa local: no se conectó autenticación.',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF332A15),
      border: Border.all(color: const Color(0xFF8C7133)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.visibility_outlined,
          size: 18,
          color: Color(0xFFFFD879),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AuthTextStyles.caption.copyWith(color: AppColors.text),
          ),
        ),
      ],
    ),
  );
}

class _PreviewUnavailableScreen extends StatelessWidget {
  const _PreviewUnavailableScreen();

  @override
  Widget build(BuildContext context) => AuthPage(
    child: const NoticeCard(
      title: 'Vista previa no disponible',
      body: 'Este estado de diseño solo está habilitado en modo depuración.',
      icon: 'fcc39.svg',
      isError: true,
    ),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String body;
  final String? leading;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (leading != null) ...[
              FigmaIcon(leading!, size: 24),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AuthTextStyles.cardTitle),
                  const SizedBox(height: 4),
                  Text(body, style: AuthTextStyles.small),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              FigmaIcon(trailing!, size: 20),
            ],
          ],
        ),
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.information,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AuthTextStyles.caption.copyWith(color: AppColors.text),
          ),
        ],
      ),
    ),
  );
}

class FigmaIcon extends StatelessWidget {
  const FigmaIcon(this.asset, {super.key, this.size = 24});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/figma/$asset',
    width: size,
    height: size,
    fit: BoxFit.contain,
    placeholderBuilder: (_) => SizedBox(width: size, height: size),
  );
}

class FigmaImage extends StatelessWidget {
  const FigmaImage(
    this.asset, {
    super.key,
    required this.width,
    required this.height,
  });

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/figma/$asset',
    width: width,
    height: height,
    fit: BoxFit.cover,
    placeholderBuilder: (_) => SizedBox(width: width, height: height),
  );
}

abstract final class AuthTextStyles {
  static const brand = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const hero = TextStyle(
    fontSize: 34,
    height: 42 / 34,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const heading = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const cardTitle = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );
  static const small = TextStyle(
    fontSize: 14,
    height: 21 / 14,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );
  static const field = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
  );
  static const fieldLabel = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
  );
  static const noticeTitle = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );
  static const button = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w700,
  );
}

Future<void> _showPreviewMenu(
  BuildContext context,
  AuthRepository repository,
) async {
  if (!kDebugMode) return;
  final page = await showModalBottomSheet<Widget>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Estados de diseño · solo depuración',
                style: AuthTextStyles.cardTitle,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in <(String, Widget)>[
                    (
                      'X01 · Error de inicio de sesión',
                      LoginScreen(repository: repository, showError: true),
                    ),
                    (
                      'C03S · Recuperación enviada',
                      RecoverySentScreen(
                        repository: repository,
                        email: 'estudiante@example.com',
                        previewOnly: true,
                      ),
                    ),
                    (
                      'C11 · Verificación pendiente',
                      VerificationScreen(
                        repository: repository,
                        email: 'estudiante@example.com',
                        previewOnly: true,
                      ),
                    ),
                    (
                      'C04 · Selección de espacio · preview',
                      const AccessSpacePreviewScreen(),
                    ),
                    (
                      'C12 · Acceso docente · preview',
                      const TeacherAccessPreviewScreen(),
                    ),
                    (
                      'C13 · Solicitud pendiente · preview',
                      const TeacherRequestPreviewScreen(),
                    ),
                    (
                      'C08 · Perfil estudiante',
                      const ProfilePreviewScreen(teacher: false),
                    ),
                    (
                      'C08D · Perfil docente',
                      const ProfilePreviewScreen(teacher: true),
                    ),
                  ])
                    ListTile(
                      title: Text(
                        entry.$1,
                        style: AuthTextStyles.small.copyWith(
                          color: AppColors.text,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(entry.$2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (page != null && context.mounted) _push(context, page);
}
