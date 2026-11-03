import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/domain/auth_access.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/teacher_access_repository.dart';
import '../domain/teacher_access_request.dart';
import 'administration_components.dart';
import 'teacher_access_screens.dart';

class AdminTeacherRequestsScreen extends StatefulWidget {
  const AdminTeacherRequestsScreen({
    super.key,
    required this.access,
    required this.authRepository,
    required this.requestRepository,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final TeacherAccessRepository requestRepository;

  @override
  State<AdminTeacherRequestsScreen> createState() =>
      _AdminTeacherRequestsScreenState();
}

class _AdminTeacherRequestsScreenState
    extends State<AdminTeacherRequestsScreen> {
  late Stream<List<TeacherAccessRequest>> _pendingStream;
  late Stream<AuthAccess> _accessStream;
  final Set<String> _openingUids = {};

  @override
  void initState() {
    super.initState();
    _pendingStream = _safePendingStream();
    _accessStream = _safeAccessStream();
  }

  Stream<AuthAccess> _safeAccessStream() {
    try {
      return widget.authRepository.watchAccess();
    } catch (error) {
      return Stream<AuthAccess>.error(error);
    }
  }

  Stream<List<TeacherAccessRequest>> _safePendingStream() {
    try {
      return withInitialServerResponseTimeout(
        widget.requestRepository.watchPendingRequests(),
      );
    } catch (error) {
      return Stream<List<TeacherAccessRequest>>.error(error);
    }
  }

  void _retry() => setState(() => _pendingStream = _safePendingStream());

  Future<void> _openReview(TeacherAccessRequest request) async {
    if (!_openingUids.add(request.uid)) return;
    setState(() {});
    try {
      final review = await widget.requestRepository.getReview(request.uid);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _AdminTeacherReviewScreen(
            access: widget.access,
            authRepository: widget.authRepository,
            requestRepository: widget.requestRepository,
            review: review,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(teacherAccessErrorMessage(error))),
          );
      }
    } finally {
      _openingUids.remove(request.uid);
      if (mounted) setState(() {});
    }
  }

  void _showUnavailable(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$feature todavía no está disponible.')),
      );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthAccess>(
    stream: _accessStream,
    initialData: widget.access,
    builder: (context, authSnapshot) {
      final access = authSnapshot.data ?? widget.access;
      final admin =
          !authSnapshot.hasError &&
          access.uid == widget.access.uid &&
          hasUsableAuthAccess(access) &&
          hasAuthRole(access, 'admin');
      return AdministrationPage(
        title: 'Solicitudes docentes',
        child: !admin
            ? _AccessUnavailable(
                message: authSnapshot.hasError
                    ? 'No pudimos confirmar que tu cuenta conserve el permiso de administración.'
                    : 'Esta vista requiere el rol de administración activo.',
              )
            : _adminContent(),
      );
    },
  );

  Widget _adminContent() => StreamBuilder<List<TeacherAccessRequest>>(
    stream: _pendingStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AdministrationContent(
          children: [
            const AdministrationIntro(
              title: 'Revisa solicitudes de acceso docente.',
              body: 'La lista incluye solicitudes pendientes que permite revisar tu cuenta.',
            ),
            const SizedBox(height: 20),
            AdministrationMessageCard(
              title: 'No pudimos cargar las solicitudes',
              body: teacherAccessErrorMessage(snapshot.error),
              icon: Icons.cloud_off_outlined,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            AdministrationSecondaryButton(
              label: 'Reintentar',
              icon: Icons.refresh,
              onPressed: _retry,
            ),
            const SizedBox(height: 24),
            _adminOptions(),
          ],
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const AdministrationLoading(
          message: 'Cargando solicitudes docentes…',
        );
      }

      final requests = snapshot.data ?? const <TeacherAccessRequest>[];
      return AdministrationContent(
        children: [
          const AdministrationIntro(
            title: 'Revisa solicitudes de acceso docente.',
            body: 'La lista incluye solicitudes pendientes que permite revisar tu cuenta.',
          ),
          const SizedBox(height: 20),
          AdministrationSectionTitle(
            'Solicitudes pendientes · ${requests.length}',
          ),
          const SizedBox(height: 12),
          if (requests.isEmpty)
            const AdministrationMessageCard(
              title: 'No hay solicitudes pendientes',
              body: 'Cuando alguien solicite acceso, aparecerá aquí para su revisión.',
              icon: Icons.inbox_outlined,
            )
          else
            for (final request in requests) ...[
              _RequestTile(
                key: ValueKey('teacher-request-${request.uid}'),
                request: request,
                opening: _openingUids.contains(request.uid),
                onTap: _openingUids.contains(request.uid)
                    ? null
                    : () => _openReview(request),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 18),
          _adminOptions(),
        ],
      );
    },
  );

  Widget _adminOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdministrationSectionTitle('Más herramientas'),
      const SizedBox(height: 12),
      AdministrationCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdministrationSectionTitle('Invitaciones docentes'),
            const SizedBox(height: 6),
            const Text(
              'La administración de códigos todavía no está disponible.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            AdministrationSecondaryButton(
              label: 'Aún no disponible',
              icon: Icons.key_off_outlined,
              onPressed: () => _showUnavailable('Las invitaciones docentes'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const AdministrationMessageCard(
        title: 'Estadísticas',
        body: 'No hay métricas de cursos para mostrar todavía. Esta pantalla no usa datos de ejemplo.',
        icon: Icons.bar_chart_outlined,
      ),
    ],
  );
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    super.key,
    required this.request,
    required this.opening,
    required this.onTap,
  });

  final TeacherAccessRequest request;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.outline),
      borderRadius: BorderRadius.circular(24),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.glass,
              foregroundColor: AppColors.primary,
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.name,
                    softWrap: true,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      height: 24 / 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    request.email,
                    softWrap: true,
                    style: const TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                  if (request.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Enviada ${MaterialLocalizations.of(context).formatMediumDate(request.createdAt!.toLocal())}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 18 / 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (opening)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _AdminTeacherReviewScreen extends StatefulWidget {
  const _AdminTeacherReviewScreen({
    required this.access,
    required this.authRepository,
    required this.requestRepository,
    required this.review,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final TeacherAccessRepository requestRepository;
  final TeacherAccessReview review;

  @override
  State<_AdminTeacherReviewScreen> createState() =>
      _AdminTeacherReviewScreenState();
}

class _AdminTeacherReviewScreenState extends State<_AdminTeacherReviewScreen> {
  late final StreamSubscription<AuthAccess> _accessSubscription;
  AuthAccess? _currentAccess;
  Object? _accessError;
  String? _operationError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _currentAccess = widget.access;
    try {
      _accessSubscription = widget.authRepository.watchAccess().listen(
        (access) {
          if (mounted) {
            setState(() {
              _currentAccess = access;
              _accessError = null;
            });
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _accessError = error);
        },
      );
    } catch (error) {
      _accessSubscription = const Stream<AuthAccess>.empty().listen((_) {});
      _accessError = error;
    }
  }

  @override
  void dispose() {
    _accessSubscription.cancel();
    super.dispose();
  }

  Future<void> _decide(TeacherAccessDecision decision) async {
    if (_busy) return;
    final access = _currentAccess ?? widget.access;
    if (access.uid != widget.access.uid ||
        !hasUsableAuthAccess(access) ||
        !hasAuthRole(access, 'admin')) {
      setState(
        () => _operationError =
            'Tu cuenta ya no tiene permiso de administración.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _operationError = null;
    });

    String? rejectionReason;
    if (decision == TeacherAccessDecision.approve) {
      final confirmed = await _confirmApproval();
      if (confirmed != true || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    } else {
      rejectionReason = await _askRejectionReason();
      if (rejectionReason == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }

    final latestAccess = _currentAccess ?? widget.access;
    if (latestAccess.uid != widget.access.uid ||
        !hasUsableAuthAccess(latestAccess) ||
        !hasAuthRole(latestAccess, 'admin')) {
      setState(() {
        _busy = false;
        _operationError =
            'Tu permiso de administración cambió. No se envió la decisión.';
      });
      return;
    }

    late final TeacherAccessRequest decided;
    try {
      decided = await widget.requestRepository.decideRequest(
        requesterUid: widget.review.request.uid,
        decision: decision,
        rejectionReason: rejectionReason,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _operationError = teacherAccessErrorMessage(error);
        });
      }
      return;
    }

    if (!mounted) return;
    if (decided.status == TeacherAccessStatus.approved ||
        decided.status == TeacherAccessStatus.rejected) {
      // Navigation is intentionally outside the transaction error handler:
      // once decideRequest returns, Firestore has acknowledged the write.
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => TeacherAccessDecisionResultScreen(
              access: latestAccess,
              authRepository: widget.authRepository,
              request: decided,
            ),
          ),
        ),
      );
    } else {
      setState(() {
        _busy = false;
        _operationError = 'El servidor no confirmó una decisión. La solicitud conserva su estado real.';
      });
    }
  }

  Future<bool?> _confirmApproval() => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Aprobar solicitud'),
      content: Text(
        '¿Confirmas el acceso docente para ${widget.review.request.name}? La solicitud y los permisos se actualizarán juntos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirmar aprobación'),
        ),
      ],
    ),
  );

  Future<String?> _askRejectionReason() async {
    return showDialog<String>(
      context: context,
      builder: (_) => const _TeacherRejectionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = _currentAccess ?? widget.access;
    final admin =
        _accessError == null &&
        access.uid == widget.access.uid &&
        hasUsableAuthAccess(access) &&
        hasAuthRole(access, 'admin');
    final request = widget.review.request;
    return AdministrationPage(
      title: 'Revisar solicitud',
      child: !admin
          ? _AccessUnavailable(
              message: _accessError != null
                  ? 'No pudimos confirmar que tu cuenta conserve el permiso de administración.'
                  : 'Tu sesión o el permiso de administración cambiaron. Ya no puedes revisar esta solicitud.',
            )
          : AdministrationContent(
              children: [
                const AdministrationIntro(
                  title: 'Verifica la identidad y los datos.',
                  body: 'Compara lo que se guardó al solicitar con el perfil actual.',
                ),
                const SizedBox(height: 16),
                AdministrationStatus(
                  label: teacherAccessStatusPresentation(request.status).$1,
                  color: teacherAccessStatusPresentation(request.status).$2,
                  icon: teacherAccessStatusPresentation(request.status).$3,
                ),
                const SizedBox(height: 16),
                _IdentityComparison(
                  title: 'Nombre',
                  requested: request.name,
                  current: widget.review.currentName,
                ),
                const SizedBox(height: 10),
                _IdentityComparison(
                  title: 'Correo',
                  requested: request.email,
                  current: widget.review.currentEmail,
                ),
                const SizedBox(height: 10),
                _IdentityComparison(
                  title: 'Código de estudiante',
                  requested: request.studentCode ?? 'No registrado',
                  current: widget.review.currentStudentCode ?? 'No registrado',
                ),
                const SizedBox(height: 12),
                AdministrationMessageCard(
                  title: 'El código no acredita identidad docente',
                  body: 'El código de estudiante es un dato del perfil. La decisión debe basarse en la revisión autorizada, no en ese código por sí solo.',
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 12),
                AdministrationCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AdministrationSectionTitle('Roles actuales'),
                      const SizedBox(height: 10),
                      if (widget.review.currentRoles.isEmpty)
                        const Text('El perfil no muestra roles actuales.')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.review.currentRoles
                              .map(
                                (role) => Chip(label: Text(_roleLabel(role))),
                              )
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
                if (_operationError != null) ...[
                  const SizedBox(height: 12),
                  AdministrationMessageCard(
                    title: 'No se confirmó la decisión',
                    body: _operationError!,
                    icon: Icons.error_outline,
                    color: AppColors.danger,
                  ),
                ],
                const SizedBox(height: 20),
                AdministrationPrimaryButton(
                  label: _busy ? 'Guardando…' : 'Aprobar acceso docente',
                  icon: _busy ? null : Icons.check_circle_outline,
                  onPressed:
                      _busy || request.status != TeacherAccessStatus.pending
                      ? null
                      : () => _decide(TeacherAccessDecision.approve),
                ),
                const SizedBox(height: 8),
                AdministrationSecondaryButton(
                  label: _busy ? 'Procesando…' : 'Rechazar solicitud',
                  icon: Icons.close,
                  onPressed:
                      _busy || request.status != TeacherAccessStatus.pending
                      ? null
                      : () => _decide(TeacherAccessDecision.reject),
                ),
              ],
            ),
    );
  }
}

class _TeacherRejectionDialog extends StatefulWidget {
  const _TeacherRejectionDialog();

  @override
  State<_TeacherRejectionDialog> createState() =>
      _TeacherRejectionDialogState();
}

class _TeacherRejectionDialogState extends State<_TeacherRejectionDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty || value.length > 500) {
      setState(() => _errorText = 'Escribe un motivo de 1 a 500 caracteres.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rechazar solicitud'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Indica un motivo de 1 a 500 caracteres.'),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Motivo del rechazo',
            errorText: _errorText,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _errorText = null),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Confirmar rechazo')),
    ],
  );
}

class _IdentityComparison extends StatelessWidget {
  const _IdentityComparison({
    required this.title,
    required this.requested,
    required this.current,
  });

  final String title;
  final String requested;
  final String current;

  @override
  Widget build(BuildContext context) {
    final differs = requested.trim() != current.trim();
    return AdministrationCard(
      color: differs
          ? AppColors.glass.withValues(alpha: 0.75)
          : AppColors.surface,
      borderColor: differs ? AppColors.information : AppColors.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: AdministrationSectionTitle(title)),
              if (differs)
                const AdministrationStatus(
                  label: 'Diferencia',
                  color: AppColors.information,
                  icon: Icons.compare_arrows,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ComparisonValue(label: 'Al solicitar', value: requested),
          const SizedBox(height: 8),
          _ComparisonValue(label: 'Perfil actual', value: current),
        ],
      ),
    );
  }
}

class _ComparisonValue extends StatelessWidget {
  const _ComparisonValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 18 / 12,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        softWrap: true,
        style: const TextStyle(color: AppColors.text, height: 1.45),
      ),
    ],
  );
}

class TeacherAccessDecisionResultScreen extends StatefulWidget {
  const TeacherAccessDecisionResultScreen({
    super.key,
    required this.access,
    required this.authRepository,
    required this.request,
  });

  final AuthAccess access;
  final AuthRepository authRepository;
  final TeacherAccessRequest request;

  @override
  State<TeacherAccessDecisionResultScreen> createState() =>
      _TeacherAccessDecisionResultScreenState();
}

class _TeacherAccessDecisionResultScreenState
    extends State<TeacherAccessDecisionResultScreen> {
  late final StreamSubscription<AuthAccess> _accessSubscription;
  AuthAccess? _currentAccess;
  Object? _accessError;

  @override
  void initState() {
    super.initState();
    _currentAccess = widget.access;
    try {
      _accessSubscription = widget.authRepository.watchAccess().listen(
        (access) {
          if (mounted) {
            setState(() {
              _currentAccess = access;
              _accessError = null;
            });
          }
        },
        onError: (Object error) {
          if (mounted) setState(() => _accessError = error);
        },
      );
    } catch (error) {
      _accessSubscription = const Stream<AuthAccess>.empty().listen((_) {});
      _accessError = error;
    }
  }

  @override
  void dispose() {
    _accessSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _currentAccess ?? widget.access;
    final admin =
        _accessError == null &&
        access.uid == widget.access.uid &&
        hasUsableAuthAccess(access) &&
        hasAuthRole(access, 'admin');
    final request = widget.request;
    if (!admin) {
      return AdministrationPage(
        title: 'Solicitud docente',
        child: _AccessUnavailable(
          message: _accessError != null
              ? 'No pudimos confirmar que tu cuenta conserve el permiso de administración.'
              : 'Tu sesión o el permiso de administración cambiaron. El resultado ya no está disponible en esta vista.',
        ),
      );
    }
    final approved = request.status == TeacherAccessStatus.approved;
    final rejected = request.status == TeacherAccessStatus.rejected;
    final status = teacherAccessStatusPresentation(request.status);
    return AdministrationPage(
      title: approved ? 'Acceso docente' : 'Solicitud docente',
      child: AdministrationContent(
        children: [
          const SizedBox(height: 28),
          Icon(
            approved ? Icons.check_circle_outline : Icons.info_outline,
            color: status.$2,
            size: 64,
          ),
          const SizedBox(height: 20),
          AdministrationIntro(
            title: approved
                ? 'Autorización concedida.'
                : rejected
                ? 'Solicitud rechazada.'
                : 'La solicitud sigue pendiente.',
            body: approved
                ? 'La decisión administrativa se guardó correctamente.'
                : rejected
                ? 'El estado y el motivo que aparecen aquí corresponden a la decisión registrada.'
                : 'El servidor no devolvió una decisión terminal.',
          ),
          const SizedBox(height: 20),
          AdministrationStatus(
            label: status.$1,
            color: status.$2,
            icon: status.$3,
          ),
          if (request.rejectionReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            AdministrationMessageCard(
              title: 'Motivo registrado',
              body: request.rejectionReason!.trim(),
              icon: Icons.chat_bubble_outline,
              color: AppColors.information,
            ),
          ],
          if (request.decidedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Decisión registrada ${MaterialLocalizations.of(context).formatMediumDate(request.decidedAt!.toLocal())}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 24),
          AdministrationPrimaryButton(
            label: 'Volver a solicitudes',
            icon: Icons.arrow_back,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _AccessUnavailable extends StatelessWidget {
  const _AccessUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AdministrationMessageCard(
        title: 'Acceso de administración no disponible',
        body: message,
        icon: Icons.lock_outline,
        color: AppColors.danger,
      ),
    ),
  );
}

String _roleLabel(String role) => switch (role.toLowerCase()) {
  'student' => 'Estudiante',
  'teacher' => 'Docente',
  'admin' => 'Administración',
  _ => role,
};
