import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/course_entry_failure.dart';
import '../domain/course_entry_repository.dart';
import '../domain/course_invitation.dart';
import 'course_entry_components.dart';
import 'invitation_validity_dialog.dart';
import 'teacher_join_request_screens.dart';

class CourseInvitationScreen extends StatefulWidget {
  const CourseInvitationScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final CourseEntryRepository repository;

  @override
  State<CourseInvitationScreen> createState() => _CourseInvitationScreenState();
}

class _CourseInvitationScreenState extends State<CourseInvitationScreen> {
  late final String? _sessionUid = widget.repository.currentUid;
  CourseInvitation? _invitation;
  Object? _error;
  bool _loading = false;
  bool _loaded = false;
  Duration _validity = CourseInvitation.defaultValidity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(
        () => _error = const CourseEntryFailure(
          CourseEntryFailureKind.unauthenticated,
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invitation = await widget.repository.getCurrentInvitation(
        widget.course.id,
      );
      if (!mounted) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() {
          _invitation = null;
          _error = const CourseEntryFailure(
            CourseEntryFailureKind.unauthenticated,
          );
        });
        return;
      }
      setState(() {
        _invitation = invitation;
        _loaded = true;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseValidity() async {
    if (_loading) return;
    final value = await chooseInvitationValidity(context, initial: _validity);
    if (mounted && value != null) setState(() => _validity = value);
  }

  Future<void> _generate() async {
    if (_loading || !_loaded || _invitation != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
        throw const CourseEntryFailure(CourseEntryFailureKind.unauthenticated);
      }
      final invitation = await widget.repository.createOrGetInvitation(
        widget.course.id,
        validity: _validity,
      );
      if (!mounted || widget.repository.currentUid != _sessionUid) return;
      setState(() => _invitation = invitation);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openManage() async {
    final updated = await Navigator.of(context).push<CourseInvitation?>(
      MaterialPageRoute<CourseInvitation?>(
        builder: (_) => ManageCourseInvitationScreen(
          course: widget.course,
          invitation: _invitation!,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _invitation = updated);
  }

  Future<void> _openRequests() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TeacherJoinRequestsScreen(
        course: widget.course,
        repository: widget.repository,
      ),
    ),
  );

  Future<void> _openShare() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => InvitationShareReadyScreen(
        course: widget.course,
        invitation: _invitation!,
      ),
    ),
  );

  Future<void> _copyCode() async {
    final invitation = _invitation;
    if (invitation == null ||
        invitation.state != CourseInvitationState.active) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: invitation.groupedCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado. Compártelo manualmente.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Invitar al curso',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final invitation = _invitation;
    final state = invitation?.state;
    return CoursePage(
      title: invitation == null ? 'Invitar al curso' : 'Invitación lista',
      leading: IconButton(
        tooltip: 'Volver al curso',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar invitación',
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          if (_loading && invitation == null)
            const CourseLoading(message: 'Consultando el código…'),
          if (_error != null) ...[
            CourseEntryFailureCard(
              error: _error!,
              onRetry: _loading ? null : _load,
            ),
            const SizedBox(height: 12),
          ],
          if (invitation != null && state != null) ...[
            const CoursePageHeading(title: 'Tu invitación está lista.'),
            const SizedBox(height: 16),
            _CourseSummary(course: widget.course),
            const SizedBox(height: 16),
            CourseEntryCodePanel(
              code: invitation.groupedCode,
              label: 'Código temporal',
              onCopy: state == CourseInvitationState.active ? _copyCode : null,
            ),
            const SizedBox(height: 12),
            CoursePanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vigencia',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 18 / 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    invitationStateLabel(state),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      height: 24 / 16,
                    ),
                  ),
                  if (state != CourseInvitationState.inactive) ...[
                    const SizedBox(height: 4),
                    Text(invitationExpiryLabel(invitation.expiresAt)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state == CourseInvitationState.active) ...[
              CoursePrimaryButton(
                label: 'Ver código para compartir',
                icon: Icons.ios_share_outlined,
                onPressed: _openShare,
              ),
              const SizedBox(height: 12),
            ] else ...[
              const CourseStateCard(
                title: 'Este código no acepta solicitudes nuevas',
                message: 'Puedes reactivar un código pausado o renovarlo para compartir uno nuevo.',
                color: AppColors.danger,
              ),
              const SizedBox(height: 12),
            ],
            CourseSecondaryButton(
              label: 'Gestionar invitación',
              icon: Icons.tune,
              onPressed: _openManage,
            ),
            const SizedBox(height: 12),
            CourseSecondaryButton(
              label: 'Ver solicitudes',
              icon: Icons.people_outline,
              onPressed: _openRequests,
            ),
          ],
          if (_loaded && invitation == null) ...[
            const CoursePageHeading(title: 'Comparte tu curso.'),
            const SizedBox(height: 16),
            _CourseSummary(course: widget.course),
            const SizedBox(height: 16),
            CourseSecondaryButton(
              label: 'Vigencia: ${invitationValidityLabel(_validity)}',
              icon: Icons.event_outlined,
              onPressed: _loading ? null : _chooseValidity,
            ),
            const SizedBox(height: 12),
            const Text('Elige entre 1 hora y 90 días. Por defecto, 14 días.'),
            const SizedBox(height: 16),
            CoursePrimaryButton(
              label: _loading ? 'Generando…' : 'Generar código',
              busy: _loading,
              onPressed: _loading ? null : _generate,
            ),
          ],
        ],
      ),
    );
  }
}

class InvitationShareReadyScreen extends StatefulWidget {
  const InvitationShareReadyScreen({
    super.key,
    required this.course,
    required this.invitation,
  });

  final Course course;
  final CourseInvitation invitation;

  @override
  State<InvitationShareReadyScreen> createState() =>
      _InvitationShareReadyScreenState();
}

class _InvitationShareReadyScreenState
    extends State<InvitationShareReadyScreen> {
  bool _copied = false;

  String get _shareText {
    final expiry = widget.invitation.expiresAt;
    final expiryMessage = expiry == null
        ? 'La fecha de vencimiento está pendiente de confirmación.'
        : 'Vence el ${invitationDateTime(expiry)}.';
    return 'Aula Presente · ${widget.course.subject} · grupo ${widget.course.group} · '
        '${widget.course.period}. Código: ${widget.invitation.groupedCode}. '
        'Ingresa el código en la app y solicita acceso. El docente debe aprobarlo. '
        '$expiryMessage';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Invitación copiada. Puedes compartirla desde tu teléfono.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CoursePage(
    title: 'Código listo para compartir',
    leading: IconButton(
      tooltip: 'Volver',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back),
    ),
    child: CourseContent(
      children: [
        const CoursePageHeading(title: 'Comparte este código.'),
        const SizedBox(height: 20),
        CourseEntryCodePanel(
          code: widget.invitation.groupedCode,
          label: 'Código del curso',
        ),
        const SizedBox(height: 16),
        const CourseStateCard(
          title: 'Acceso por aprobación',
          message: 'El estudiante ingresa el código en Aula Presente, verifica su correo y solicita acceso. La invitación no abre la app ni autoriza asistencia.',
        ),
        const SizedBox(height: 12),
        CourseStateCard(
          title: widget.invitation.expiresAt == null
              ? 'Confirmando la fecha de vigencia'
              : 'Vigencia',
          message: widget.invitation.expiresAt == null
              ? 'La escritura fue aceptada, pero todavía no se confirmó la fecha del servidor. No compartiremos una fecha estimada.'
              : invitationExpiryLabel(widget.invitation.expiresAt),
        ),
        const SizedBox(height: 20),
        CoursePrimaryButton(
          label: _copied ? 'Mensaje copiado' : 'Copiar invitación',
          icon: Icons.copy_outlined,
          onPressed: _copy,
        ),
        const SizedBox(height: 12),
        CourseSecondaryButton(
          label: 'Volver a invitaciones',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}

class ManageCourseInvitationScreen extends StatefulWidget {
  const ManageCourseInvitationScreen({
    super.key,
    required this.course,
    required this.invitation,
    required this.repository,
  });

  final Course course;
  final CourseInvitation invitation;
  final CourseEntryRepository repository;

  @override
  State<ManageCourseInvitationScreen> createState() =>
      _ManageCourseInvitationScreenState();
}

enum _InvitationAction { renew, edit, reactivate, deactivate }

class _ManageCourseInvitationScreenState
    extends State<ManageCourseInvitationScreen> {
  late CourseInvitation _invitation = widget.invitation;
  late final String? _sessionUid = widget.repository.currentUid;
  bool _busy = false;
  bool _writing = false;
  Object? _error;
  String? _errorAction;
  String? _success;

  Future<bool> _confirm(_InvitationAction action) async {
    final (title, message, label) = switch (action) {
      _InvitationAction.reactivate => (
        '¿Reactivar el código?',
        'El mismo código volverá a aceptar solicitudes si aún no ha vencido.',
        'Confirmar reactivación',
      ),
      _ => (
        '¿Desactivar el código?',
        'El código dejará de servir. Para invitar de nuevo, renueva el código. Las solicitudes y matrículas existentes se conservan.',
        'Confirmar desactivación',
      ),
    };
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: action == _InvitationAction.deactivate
                    ? FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: AppColors.background,
                      )
                    : null,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(label),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _change(_InvitationAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _errorAction = switch (action) {
        _InvitationAction.renew => 'No se pudo renovar el código',
        _InvitationAction.edit => 'No se pudo editar el vencimiento',
        _InvitationAction.reactivate => 'No se pudo reactivar el código',
        _InvitationAction.deactivate => 'No se pudo desactivar el código',
      };
    });
    try {
      Duration? validity;
      if (action == _InvitationAction.renew ||
          action == _InvitationAction.edit) {
        if (action == _InvitationAction.edit && _invitation.createdAt == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Actualiza la invitación para confirmar su fecha antes de editar el vencimiento.',
              ),
            ),
          );
          return;
        }
        validity = await chooseInvitationValidity(
          context,
          initial: action == _InvitationAction.renew
              ? CourseInvitation.defaultValidity
              : _invitation.validity,
          createdAt: action == _InvitationAction.edit
              ? _invitation.createdAt
              : null,
          replacingCode: action == _InvitationAction.renew,
        );
        if (validity == null) return;
      } else if (!await _confirm(action)) {
        return;
      }
      if (!mounted) return;
      if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
        throw const CourseEntryFailure(CourseEntryFailureKind.unauthenticated);
      }
      setState(() => _writing = true);
      final updated = switch (action) {
        _InvitationAction.renew => await widget.repository.renewInvitation(
          widget.course.id,
          validity: validity!,
        ),
        _InvitationAction.edit =>
          await widget.repository.updateInvitationValidity(
            widget.course.id,
            validity!,
          ),
        _InvitationAction.reactivate =>
          await widget.repository.reactivateInvitation(widget.course.id),
        _InvitationAction.deactivate => await _deactivate(),
      };
      if (!mounted || widget.repository.currentUid != _sessionUid) return;
      setState(() {
        _invitation = updated;
        _success = switch (action) {
          _InvitationAction.renew => 'Invitación renovada.',
          _InvitationAction.edit => 'Vencimiento actualizado.',
          _InvitationAction.reactivate => 'Invitación reactivada.',
          _InvitationAction.deactivate => 'Invitación desactivada.',
        };
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _writing = false;
        });
      }
    }
  }

  Future<CourseInvitation> _deactivate() async {
    await widget.repository.deactivateInvitation(widget.course.id);
    return CourseInvitation(
      courseId: _invitation.courseId,
      code: _invitation.code,
      status: 'inactive',
      createdAt: _invitation.createdAt,
      updatedAt: null,
      validity: _invitation.validity,
    );
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _errorAction = 'No se pudo actualizar la invitación';
    });
    try {
      final current = await widget.repository.getCurrentInvitation(
        widget.course.id,
      );
      if (!mounted || widget.repository.currentUid != _sessionUid) return;
      if (current == null) {
        throw const CourseEntryFailure(
          CourseEntryFailureKind.inviteUnavailable,
        );
      }
      setState(() {
        _invitation = current;
        _success = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _returnWithUpdate() => Navigator.of(context).pop(_invitation);

  Future<void> _copyCode() async {
    if (_busy || _invitation.state != CourseInvitationState.active) return;
    await Clipboard.setData(ClipboardData(text: _invitation.groupedCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Código copiado.')));
  }

  String _errorMessage(Object error) {
    if (error is CourseEntryFailure) {
      return switch (error.kind) {
        CourseEntryFailureKind.permissionDenied ||
        CourseEntryFailureKind.teacherRoleRequired => 'Tu cuenta no tiene permiso para cambiar esta invitación. Actualiza la pantalla y comprueba que sigues siendo docente de este curso.',
        CourseEntryFailureKind.invalidTransition ||
        CourseEntryFailureKind.inviteUnavailable => 'El código cambió, venció o fue desactivado. Actualiza la invitación y, si hace falta, renueva el código.',
        _ => courseEntryErrorMessage(error, uncertainWrite: true),
      };
    }
    return courseEntryErrorMessage(error, uncertainWrite: true);
  }

  Widget _statusPanel() => CoursePanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estado del código',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          invitationStateLabel(_invitation.state),
          style: const TextStyle(color: AppColors.text, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          _invitation.state == CourseInvitationState.inactive &&
                  _invitation.expiresAt != null
              ? 'Vencimiento previsto: ${invitationDateTime(_invitation.expiresAt!)}'
              : invitationExpiryLabel(_invitation.expiresAt),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Gestionar invitación',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final inactive = _invitation.state == CourseInvitationState.inactive;
    return CoursePage(
      title: 'Gestionar invitación',
      leading: IconButton(
        tooltip: 'Volver',
        onPressed: _busy ? null : _returnWithUpdate,
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar invitación',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Código del curso'),
          const SizedBox(height: 16),
          CourseEntryCodePanel(
            code: _invitation.groupedCode,
            label: 'Código temporal',
          ),
          if (!inactive &&
              _invitation.state == CourseInvitationState.active) ...[
            const SizedBox(height: 12),
            CourseSecondaryButton(
              label: 'Copiar código',
              icon: Icons.copy_outlined,
              onPressed: _busy ? null : _copyCode,
            ),
          ],
          const SizedBox(height: 12),
          _statusPanel(),
          if (_success != null) ...[
            const SizedBox(height: 12),
            CourseStateCard(title: _success!, message: 'Cambio guardado.'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            CourseStateCard(
              title: _errorAction ?? 'No se pudo completar la operación',
              message: _errorMessage(_error!),
              icon: Icons.cloud_off_outlined,
              color: AppColors.danger,
            ),
          ],
          const SizedBox(height: 20),
          CoursePrimaryButton(
            label: _writing ? 'Procesando…' : 'Renovar código',
            busy: _writing,
            onPressed: _busy ? null : () => _change(_InvitationAction.renew),
          ),
          if (!inactive) ...[
            const SizedBox(height: 12),
            CourseSecondaryButton(
              label: 'Editar vencimiento',
              icon: Icons.event_outlined,
              onPressed: _busy ? null : () => _change(_InvitationAction.edit),
            ),
            if (_invitation.state == CourseInvitationState.paused) ...[
              const SizedBox(height: 12),
              CourseSecondaryButton(
                label: 'Reactivar código',
                icon: Icons.play_arrow,
                onPressed: _busy
                    ? null
                    : () => _change(_InvitationAction.reactivate),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.background,
                ),
                icon: const Icon(Icons.block_outlined),
                label: const Text('Desactivar código'),
                onPressed: _busy
                    ? null
                    : () => _change(_InvitationAction.deactivate),
              ),
            ),
          ],
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Volver a invitaciones',
            onPressed: _busy ? null : _returnWithUpdate,
          ),
        ],
      ),
    );
  }
}

class _CourseSummary extends StatelessWidget {
  const _CourseSummary({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) => CoursePanel(
    color: AppColors.glass.withValues(alpha: 0.62),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        SvgPicture.asset('assets/figma/51a24.svg', width: 24, height: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${course.subject} · ${course.group}',
                style: const TextStyle(color: AppColors.text, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                course.period,
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
