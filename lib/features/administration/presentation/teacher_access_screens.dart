import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/domain/auth_access.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/teacher_access_repository.dart';
import '../domain/teacher_access_request.dart';
import 'administration_components.dart';

class TeacherAccessScreen extends StatefulWidget {
  const TeacherAccessScreen({
    super.key,
    required this.access,
    required this.authRepository,
    required this.requestRepository,
    required this.onContinueAsStudent,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final TeacherAccessRepository requestRepository;
  final VoidCallback onContinueAsStudent;

  @override
  State<TeacherAccessScreen> createState() => _TeacherAccessScreenState();
}

class _TeacherAccessScreenState extends State<TeacherAccessScreen> {
  late Stream<AuthAccess> _accessStream;
  late Stream<TeacherAccessRequest?> _requestStream;
  bool _submitting = false;
  String? _operationMessage;

  @override
  void initState() {
    super.initState();
    _accessStream = _safeAccessStream();
    _requestStream = _safeRequestStream();
  }

  Stream<AuthAccess> _safeAccessStream() {
    try {
      return widget.authRepository.watchAccess();
    } catch (error) {
      return Stream<AuthAccess>.error(error);
    }
  }

  Stream<TeacherAccessRequest?> _safeRequestStream() {
    try {
      return withInitialServerResponseTimeout(
        widget.requestRepository.watchOwnRequest(),
      );
    } catch (error) {
      return Stream<TeacherAccessRequest?>.error(error);
    }
  }

  void _retryRequest() {
    setState(() {
      _operationMessage = null;
      _requestStream = _safeRequestStream();
    });
  }

  Future<void> _explainInvitation() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invitaciones docentes'),
        content: const Text(
          'El ingreso con código todavía no está disponible. Puedes solicitar acceso desde esta pantalla; administración revisará tu solicitud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRequest(AuthAccess currentAccess) async {
    if (_submitting) return;
    if (!hasUsableAuthAccess(currentAccess)) {
      _showMessage('Inicia sesión y verifica tu correo para solicitar acceso.');
      return;
    }
    if (hasAuthRole(currentAccess, 'teacher')) {
      _showMessage('Tu cuenta ya tiene acceso docente.');
      return;
    }

    setState(() {
      _submitting = true;
      _operationMessage = null;
    });
    try {
      await widget.requestRepository.createOwnRequest();
      if (!mounted) return;
      _showMessage('Solicitud enviada y confirmada.');
      await _openStatus();
    } catch (error) {
      if (!mounted) return;
      final message = teacherAccessErrorMessage(error);
      setState(() => _operationMessage = message);
      if (error is TeacherAccessFailure &&
          error.kind == TeacherAccessFailureKind.alreadyExists) {
        await _openExistingRequest();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openStatus() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TeacherRequestStatusScreen(
          access: _lastAccess,
          authRepository: widget.authRepository,
          requestRepository: widget.requestRepository,
          onContinueAsStudent: widget.onContinueAsStudent,
        ),
      ),
    );
  }

  Future<void> _openExistingRequest() async {
    try {
      final existing = await widget.requestRepository.getOwnRequest();
      if (!mounted) return;
      if (existing == null) {
        setState(() {
          _operationMessage = 'El servidor no encontró una solicitud asociada a esta cuenta. Actualiza el estado e inténtalo de nuevo.';
          _requestStream = _safeRequestStream();
        });
        return;
      }
      await _openStatus();
    } catch (error) {
      if (mounted) {
        setState(() => _operationMessage = teacherAccessErrorMessage(error));
      }
    }
  }

  AuthAccess get _lastAccess => _currentAccess ?? widget.access;
  AuthAccess? _currentAccess;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _requestState(AuthAccess access) =>
      StreamBuilder<TeacherAccessRequest?>(
        stream: _requestStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdministrationCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdministrationSectionTitle(
                    'No pudimos consultar tu solicitud',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    teacherAccessErrorMessage(snapshot.error),
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  AdministrationSecondaryButton(
                    label: 'Reintentar',
                    icon: Icons.refresh,
                    onPressed: _retryRequest,
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AdministrationCard(
              child: AdministrationLoading(
                message: 'Consultando tu solicitud…',
              ),
            );
          }

          final request = snapshot.data;
          if (request != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeacherRequestSummary(request: request),
                const SizedBox(height: 12),
                AdministrationSecondaryButton(
                  label: 'Consultar solicitud',
                  icon: Icons.refresh,
                  onPressed: _submitting ? null : _openStatus,
                ),
              ],
            );
          }
          if (hasAuthRole(access, 'teacher')) {
            return const AdministrationMessageCard(
              title: 'Acceso docente disponible',
              body: 'Tu cuenta ya tiene el rol docente autorizado.',
              icon: Icons.verified_outlined,
              color: AppColors.primary,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdministrationCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdministrationSectionTitle('Tengo una invitación'),
                    const SizedBox(height: 8),
                    const Text(
                      'El acceso con código aún no está disponible. Si necesitas acceso docente, administración puede revisar una solicitud.',
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    AdministrationSecondaryButton(
                      label: 'Aún no disponible',
                      icon: Icons.key_off_outlined,
                      onPressed: _explainInvitation,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AdministrationMessageCard(
                title: access.name?.trim().isNotEmpty == true
                    ? 'Solicitud para ${access.name!.trim()}'
                    : 'Solicitud de acceso docente',
                body: 'La administración revisará los datos de tu perfil. Enviar una solicitud no concede permisos.',
                icon: Icons.admin_panel_settings_outlined,
              ),
              const SizedBox(height: 16),
              if (_operationMessage != null) ...[
                AdministrationMessageCard(
                  title: 'No se envió la solicitud',
                  body: _operationMessage!,
                  icon: Icons.error_outline,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 12),
              ],
              AdministrationPrimaryButton(
                label: _submitting ? 'Enviando…' : 'Solicitar acceso docente',
                icon: _submitting ? null : Icons.send_outlined,
                onPressed: _submitting ? null : () => _createRequest(access),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthAccess>(
    stream: _accessStream,
    initialData: widget.access,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AdministrationPage(
          title: 'Acceso docente',
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No pudimos confirmar tu sesión. Vuelve a intentarlo.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      final access = snapshot.data ?? widget.access;
      _currentAccess = access;
      final usable = hasUsableAuthAccess(access);

      return AdministrationPage(
        title: 'Acceso docente',
        child: AdministrationContent(
          children: [
            const AdministrationIntro(
              title: 'Enseña con tu cuenta.',
              body: 'Puedes estudiar y enseñar con la misma cuenta.',
            ),
            const SizedBox(height: 20),
            if (!usable) ...[
              AdministrationMessageCard(
                title: access.status == AuthAccessStatus.verificationRequired
                    ? 'Verifica tu correo'
                    : 'Inicia sesión para continuar',
                body: access.status == AuthAccessStatus.verificationRequired
                    ? 'Finaliza el registro verificando tu dirección de correo para solicitar acceso docente.'
                    : access.uid == null
                    ? 'Aún no se envió ninguna solicitud. Finaliza el registro y verifica tu correo para continuar.'
                    : 'No pudimos confirmar un perfil válido para esta cuenta. Vuelve al registro o inicia sesión de nuevo.',
                icon: Icons.lock_outline,
                color: AppColors.information,
              ),
            ] else ...[
              _requestState(access),
            ],
            const SizedBox(height: 16),
            AdministrationMessageCard(
              title: 'Activación de permisos',
              body: 'Una persona administradora revisará la solicitud. Elegir o solicitar un espacio no modifica tus permisos.',
              icon: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 16),
            AdministrationSecondaryButton(
              label: _continueLabel(access),
              icon: Icons.school_outlined,
              onPressed: widget.onContinueAsStudent,
            ),
          ],
        ),
      );
    },
  );
}

class TeacherRequestSummary extends StatelessWidget {
  const TeacherRequestSummary({super.key, required this.request});

  final TeacherAccessRequest request;

  @override
  Widget build(BuildContext context) {
    final status = teacherAccessStatusPresentation(request.status);
    final reason = request.rejectionReason?.trim();
    return AdministrationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdministrationSectionTitle('Tu solicitud de acceso docente'),
          const SizedBox(height: 12),
          AdministrationStatus(
            label: status.$1,
            color: status.$2,
            icon: status.$3,
          ),
          const SizedBox(height: 12),
          Text(
            teacherAccessStatusSummary(request.status),
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Motivo: $reason',
              style: const TextStyle(color: AppColors.text, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class TeacherRequestStatusScreen extends StatefulWidget {
  const TeacherRequestStatusScreen({
    super.key,
    required this.access,
    required this.authRepository,
    required this.requestRepository,
    required this.onContinueAsStudent,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final TeacherAccessRepository requestRepository;
  final VoidCallback onContinueAsStudent;

  @override
  State<TeacherRequestStatusScreen> createState() =>
      _TeacherRequestStatusScreenState();
}

class _TeacherRequestStatusScreenState
    extends State<TeacherRequestStatusScreen> {
  late final StreamSubscription<AuthAccess> _accessSubscription;
  late final StreamSubscription<TeacherAccessRequest?> _requestSubscription;
  AuthAccess? _currentAccess;
  TeacherAccessRequest? _request;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _currentAccess = widget.access;
    try {
      _accessSubscription = widget.authRepository.watchAccess().listen(
        (access) {
          if (!mounted) return;
          final uidChanged = access.uid != widget.access.uid;
          final accessUnavailable = !hasUsableAuthAccess(access);
          setState(() {
            _currentAccess = access;
            if (uidChanged) _accountChanged = true;
            if (uidChanged || accessUnavailable) {
              _request = null;
              _loading = false;
              _error = null;
            }
          });
          if (uidChanged) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.popUntil((route) => route.isFirst);
              }
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _accountChanged = true;
              _request = null;
              _loading = false;
              _error = error;
            });
          }
        },
      );
    } catch (error) {
      _accessSubscription = const Stream<AuthAccess>.empty().listen((_) {});
      _error = error;
    }
    try {
      _requestSubscription = widget.requestRepository.watchOwnRequest().listen(
        (request) {
          if (!mounted ||
              _accountChanged ||
              _currentAccess?.uid != widget.access.uid ||
              !hasUsableAuthAccess(_currentAccess ?? widget.access)) {
            return;
          }
          setState(() {
            _request = request;
            _loading = false;
            _error = null;
          });
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = error;
            });
          }
        },
      );
    } catch (error) {
      _requestSubscription = const Stream<TeacherAccessRequest?>.empty().listen(
        (_) {},
      );
      _error = error;
    }
    _refreshFromServer(initial: true);
  }

  @override
  void dispose() {
    _accessSubscription.cancel();
    _requestSubscription.cancel();
    super.dispose();
  }

  Future<void> _refreshFromServer({bool initial = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = !initial;
      if (_request == null) _loading = true;
      _error = null;
    });
    try {
      final request = await widget.requestRepository.getOwnRequest();
      if (!mounted) return;
      if (_accountChanged || _currentAccess?.uid != widget.access.uid) return;
      setState(() {
        _request = request;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _currentAccess ?? widget.access;
    final sameAccount = access.uid == widget.access.uid && !_accountChanged;
    final usable = hasUsableAuthAccess(access);
    final request = _request;
    return AdministrationPage(
      title: 'Solicitud docente',
      child: AdministrationContent(
        children: [
          const AdministrationIntro(
            title: 'Consulta el estado de tu solicitud.',
            body: 'El permiso cambia solo después de una decisión administrativa confirmada.',
          ),
          const SizedBox(height: 20),
          if (!sameAccount)
            const AdministrationMessageCard(
              title: 'La sesión cambió',
              body: 'Volveremos a los espacios autorizados para la cuenta activa.',
              icon: Icons.lock_outline,
            )
          else if (!usable)
            const AdministrationMessageCard(
              title: 'Sesión no disponible',
              body: 'Inicia sesión con la cuenta que envió la solicitud para consultar su estado.',
              icon: Icons.lock_outline,
            )
          else if (_loading)
            const AdministrationCard(
              child: AdministrationLoading(message: 'Consultando solicitud…'),
            )
          else if (request == null && _error != null)
            AdministrationMessageCard(
              title: 'No se pudo confirmar el estado',
              body: teacherAccessErrorMessage(_error),
              icon: Icons.cloud_off_outlined,
              color: AppColors.danger,
            )
          else if (request == null)
            const AdministrationMessageCard(
              title: 'No encontramos una solicitud',
              body: 'Aún no hay una solicitud asociada a esta cuenta.',
              icon: Icons.inbox_outlined,
            )
          else ...[
            TeacherRequestSummary(request: request),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AdministrationMessageCard(
                title: 'No pudimos confirmar si el estado cambió',
                body: teacherAccessErrorMessage(_error),
                icon: Icons.cloud_off_outlined,
                color: AppColors.danger,
              ),
            ],
          ],
          const SizedBox(height: 16),
          AdministrationPrimaryButton(
            label: _refreshing ? 'Consultando…' : 'Consultar solicitud',
            icon: _refreshing ? null : Icons.refresh,
            onPressed: !usable || _refreshing
                ? null
                : () => _refreshFromServer(),
          ),
          const SizedBox(height: 8),
          AdministrationSecondaryButton(
            label: _continueLabel(access),
            icon: Icons.school_outlined,
            onPressed: sameAccount ? widget.onContinueAsStudent : null,
          ),
        ],
      ),
    );
  }
}

bool hasUsableAuthAccess(AuthAccess access) {
  final usableStatuses = {
    AuthAccessStatus.student,
    AuthAccessStatus.accessAvailable,
  };
  return access.uid?.isNotEmpty == true &&
      access.roles.isNotEmpty &&
      usableStatuses.contains(access.status);
}

bool hasAuthRole(AuthAccess access, String role) =>
    access.roles.map((value) => value.toLowerCase()).contains(role);

String _continueLabel(AuthAccess access) {
  if (!hasUsableAuthAccess(access)) return 'Volver al registro';
  if (hasAuthRole(access, 'student')) return 'Continuar como estudiante';
  return 'Volver a mis espacios';
}

(String, Color, IconData) teacherAccessStatusPresentation(
  TeacherAccessStatus status,
) => switch (status) {
  TeacherAccessStatus.pending => (
    'Pendiente de revisión',
    AppColors.information,
    Icons.schedule_outlined,
  ),
  TeacherAccessStatus.approved => (
    'Aprobada',
    AppColors.primary,
    Icons.check_circle_outline,
  ),
  TeacherAccessStatus.rejected => (
    'Rechazada',
    AppColors.danger,
    Icons.cancel_outlined,
  ),
};

String teacherAccessStatusSummary(
  TeacherAccessStatus status,
) => switch (status) {
  TeacherAccessStatus.pending =>
    'La administración todavía no ha registrado una decisión.',
  TeacherAccessStatus.approved => 'La aprobación fue confirmada. Tu cuenta tiene acceso docente según sus permisos actuales.',
  TeacherAccessStatus.rejected =>
    'La solicitud fue rechazada. Revisa el motivo indicado por administración.',
};

String teacherAccessErrorMessage(Object? error) {
  if (error is! TeacherAccessFailure) {
    return 'No pudimos completar la operación. Inténtalo de nuevo.';
  }
  return switch (error.kind) {
    TeacherAccessFailureKind.unauthenticated =>
      'Tu sesión terminó. Inicia sesión y vuelve a intentarlo.',
    TeacherAccessFailureKind.verificationRequired =>
      'Verifica tu correo electrónico para continuar.',
    TeacherAccessFailureKind.profileUnavailable =>
      'No pudimos consultar el perfil asociado a tu cuenta.',
    TeacherAccessFailureKind.profileInvalid =>
      'Los datos del perfil no tienen el formato requerido.',
    TeacherAccessFailureKind.alreadyExists =>
      'Ya existe una solicitud para esta cuenta. Actualiza el estado.',
    TeacherAccessFailureKind.notFound =>
      'La solicitud ya no está disponible. Actualiza la lista.',
    TeacherAccessFailureKind.notPending =>
      'Esta solicitud ya tiene una decisión y no puede cambiarse.',
    TeacherAccessFailureKind.invalidReason =>
      'Escribe un motivo de rechazo de 1 a 500 caracteres.',
    TeacherAccessFailureKind.permissionDenied =>
      'Tu cuenta no tiene permiso para completar esta operación.',
    TeacherAccessFailureKind.network =>
      'No pudimos conectar con el servicio. Revisa tu conexión.',
    TeacherAccessFailureKind.unknown =>
      'No pudimos completar la operación. Inténtalo de nuevo.',
  };
}
