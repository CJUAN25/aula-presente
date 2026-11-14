import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/course_entry_failure.dart';
import '../domain/course_entry_repository.dart';
import '../domain/join_request.dart';
import '../domain/join_request_page.dart';
import 'course_entry_components.dart';

class TeacherJoinRequestsScreen extends StatefulWidget {
  const TeacherJoinRequestsScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final CourseEntryRepository repository;

  @override
  State<TeacherJoinRequestsScreen> createState() =>
      _TeacherJoinRequestsScreenState();
}

class _TeacherJoinRequestsScreenState extends State<TeacherJoinRequestsScreen> {
  final List<JoinRequest> _items = [];
  late final String? _sessionUid = widget.repository.currentUid;
  JoinRequestCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(() {
        _items.clear();
        _error = const CourseEntryFailure(
          CourseEntryFailureKind.unauthenticated,
        );
      });
      return;
    }
    final epoch = ++_epoch;
    if (reset) {
      _items.clear();
      _cursor = null;
      _hasMore = true;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listCourseRequests(
        widget.course.id,
        cursor: _cursor,
      );
      if (!mounted || epoch != _epoch) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() {
          _items.clear();
          _error = const CourseEntryFailure(
            CourseEntryFailureKind.unauthenticated,
          );
        });
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _review(JoinRequest request) async {
    final decided = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewJoinRequestScreen(
          course: widget.course,
          request: request,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted && decided == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Solicitudes de ingreso',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    return CoursePage(
      title: 'Solicitudes de ingreso',
      leading: IconButton(
        tooltip: 'Volver al grupo',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar solicitudes',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          const CoursePageHeading(title: '¿Quién se une al grupo?'),
          const SizedBox(height: 8),
          Text(
            '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          if (_loading && _items.isEmpty)
            const CourseLoading(message: 'Cargando solicitudes…'),
          if (_error != null) ...[
            CourseEntryFailureCard(
              error: _error!,
              onRetry: _loading ? null : () => _load(reset: _items.isEmpty),
            ),
            const SizedBox(height: 12),
          ],
          if (!_loading && _error == null && _items.isEmpty)
            const CourseStateCard(
              title: 'No hay solicitudes pendientes',
              message: 'Cuando un estudiante solicite acceso con un código vigente, aparecerá aquí.',
              icon: Icons.people_outline,
            ),
          for (final request in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _JoinRequestTile(
                request: request,
                onTap: () => _review(request),
              ),
            ),
          if (_hasMore && _items.isNotEmpty) ...[
            const SizedBox(height: 4),
            CourseSecondaryButton(
              label: _loading ? 'Cargando…' : 'Cargar más solicitudes',
              onPressed: _loading ? null : () => _load(),
            ),
          ],
          const SizedBox(height: 12),
          const CourseStateCard(
            title: 'Datos del curso',
            message: 'Solo quien imparte este curso puede aprobar o rechazar ingresos.',
          ),
        ],
      ),
    );
  }
}

class ReviewJoinRequestScreen extends StatefulWidget {
  const ReviewJoinRequestScreen({
    super.key,
    required this.course,
    required this.request,
    required this.repository,
  });

  final Course course;
  final JoinRequest request;
  final CourseEntryRepository repository;

  @override
  State<ReviewJoinRequestScreen> createState() =>
      _ReviewJoinRequestScreenState();
}

class _ReviewJoinRequestScreenState extends State<ReviewJoinRequestScreen> {
  late final String? _sessionUid = widget.repository.currentUid;
  bool _busy = false;
  Object? _error;
  JoinDecisionResult? _result;

  Future<void> _approve() => _decide(JoinRequestDecision.approve);

  Future<String?> _askReason() async {
    var reason = '';
    var invalid = false;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Motivo del rechazo'),
          content: TextField(
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            onChanged: (value) => reason = value,
            decoration: InputDecoration(
              hintText: 'Escribe un motivo breve para la solicitud',
              errorText: invalid
                  ? 'Escribe un motivo de hasta 500 caracteres.'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = reason.trim();
                if (value.isNotEmpty && value.length <= 500) {
                  Navigator.of(dialogContext).pop(value);
                } else {
                  setDialogState(() => invalid = true);
                }
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await _askReason();
    if (reason == null || !mounted) return;
    await _decide(JoinRequestDecision.reject, reason: reason);
  }

  Future<void> _decide(JoinRequestDecision decision, {String? reason}) async {
    if (_busy) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(
        () => _error = const CourseEntryFailure(
          CourseEntryFailureKind.unauthenticated,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.decideJoinRequest(
        courseId: widget.course.id,
        studentUid: widget.request.studentUid,
        decision: decision,
        rejectionReason: reason,
      );
      if (!mounted) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() {
          _result = null;
          _error = const CourseEntryFailure(
            CourseEntryFailureKind.unauthenticated,
          );
        });
        return;
      }
      // The transaction result is the confirmation. Do not make a list/detail
      // read a prerequisite for showing the committed decision.
      setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Revisar solicitud',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final result = _result;
    final request = result?.request ?? widget.request;
    final status = request.status;
    final withdrawnEnrollment =
        _error is CourseEntryFailure &&
        (_error as CourseEntryFailure).kind ==
            CourseEntryFailureKind.enrollmentWithdrawn;
    return CoursePage(
      title: 'Revisar solicitud',
      leading: IconButton(
        tooltip: 'Volver a solicitudes',
        onPressed: () => Navigator.of(context).maybePop(result != null),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          if (result != null) ...[
            CoursePageHeading(
              title: switch (result.status) {
                JoinDecisionResultStatus.approved => 'Ingreso aprobado.',
                JoinDecisionResultStatus.rejected => 'Solicitud rechazada.',
                JoinDecisionResultStatus.alreadyApproved =>
                  'La solicitud ya estaba aprobada.',
                JoinDecisionResultStatus.alreadyRejected =>
                  'La solicitud ya estaba rechazada.',
              },
            ),
            const SizedBox(height: 16),
            CoursePanel(
              child: Text(
                '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
                style: const TextStyle(color: AppColors.text),
              ),
            ),
            const SizedBox(height: 12),
            if (result.status == JoinDecisionResultStatus.approved ||
                result.status == JoinDecisionResultStatus.alreadyApproved)
              const CourseStateCard(
                title: 'Matrícula confirmada',
                message: 'El estudiante ya puede encontrar esta materia en Mis materias. La decisión se guardó una sola vez.',
              )
            else
              CourseStateCard(
                title: 'Decisión guardada',
                message:
                    request.rejectionReason ??
                    'La solicitud fue rechazada. No se creó una matrícula.',
                color: AppColors.information,
              ),
            const SizedBox(height: 20),
            CoursePrimaryButton(
              label: 'Volver a solicitudes',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ] else ...[
            CoursePageHeading(title: request.name),
            const SizedBox(height: 16),
            _StudentIdentityPanel(request: request),
            const SizedBox(height: 12),
            CoursePanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fecha de solicitud',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shortDate(request.createdAt),
                    style: const TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CourseStateCard(
              title: status == JoinRequestStatus.pending
                  ? 'Antes de aprobar'
                  : 'Decisión existente',
              message: status == JoinRequestStatus.pending
                  ? 'Confirma que esta cuenta pertenece al grupo. Al aprobar, se vincula la matrícula a este curso y período.'
                  : status == JoinRequestStatus.approved
                  ? 'Esta solicitud ya fue aprobada y no se puede decidir otra vez.'
                  : request.rejectionReason ?? 'Esta solicitud ya fue rechazada y no se puede reabrir.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              if (withdrawnEnrollment)
                const CourseStateCard(
                  title: 'La matrícula está retirada',
                  message: 'La aprobación no cambió la solicitud ni el estado del estudiante. Abre Gestión de estudiantes → Retirados e histórico y reincorpora esta matrícula; después vuelve aquí si la solicitud sigue pendiente.',
                  color: AppColors.danger,
                  icon: Icons.history,
                )
              else
                CourseEntryFailureCard(
                  error: _error!,
                  uncertainWrite: true,
                  onRetry: null,
                ),
            ],
            if (status == JoinRequestStatus.pending) ...[
              const SizedBox(height: 20),
              CoursePrimaryButton(
                label: _busy ? 'Aprobando…' : 'Aprobar ingreso',
                icon: Icons.check,
                busy: _busy,
                onPressed: _busy || withdrawnEnrollment ? null : _approve,
              ),
              const SizedBox(height: 12),
              CourseSecondaryButton(
                label: _busy ? 'Procesando…' : 'Rechazar solicitud',
                icon: Icons.close,
                onPressed: _busy ? null : _reject,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StudentIdentityPanel extends StatelessWidget {
  const _StudentIdentityPanel({required this.request});

  final JoinRequest request;

  @override
  Widget build(BuildContext context) => CoursePanel(
    color: AppColors.glass.withValues(alpha: 0.62),
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset('assets/figma/df818.svg', width: 24, height: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Estudiante verificado',
                style: TextStyle(color: AppColors.text, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  request.email,
                  if (request.studentCode?.isNotEmpty == true)
                    'Código ${request.studentCode}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({required this.request, required this.onTap});

  final JoinRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: CoursePanel(
        color: AppColors.glass.withValues(alpha: 0.62),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SvgPicture.asset(
                'assets/figma/df818.svg',
                width: 24,
                height: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.name,
                    style: const TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Correo verificado · ${request.studentCode == null ? 'solicitud pendiente' : 'código ${request.studentCode}'}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Solicitó el ${shortDate(request.createdAt)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}
