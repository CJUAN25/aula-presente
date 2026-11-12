import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/presentation/student_enrollment_screens.dart';
import '../domain/course_entry_failure.dart';
import '../domain/course_entry_repository.dart';
import '../domain/course_preview.dart';
import '../domain/join_request.dart';
import '../domain/join_request_page.dart';
import 'course_entry_components.dart';

class StudentCourseCodeScreen extends StatefulWidget {
  const StudentCourseCodeScreen({
    super.key,
    required this.repository,
    required this.enrollmentRepository,
  });

  final CourseEntryRepository repository;
  final EnrollmentRepository enrollmentRepository;

  @override
  State<StudentCourseCodeScreen> createState() =>
      _StudentCourseCodeScreenState();
}

class _StudentCourseCodeScreenState extends State<StudentCourseCodeScreen> {
  final _code = TextEditingController();
  late final String? _sessionUid = widget.repository.currentUid;
  bool _busy = false;
  Object? _error;
  bool _codeUnavailable = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    if (_busy) return;
    if (_code.text.trim().isEmpty) {
      setState(() {
        _error = const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
        _codeUnavailable = false;
      });
      return;
    }
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
      _codeUnavailable = false;
    });
    try {
      final preview = await widget.repository.findCourseByCode(_code.text);
      if (!mounted) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(
          () => _error = const CourseEntryFailure(
            CourseEntryFailureKind.unauthenticated,
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ConfirmCourseRequestScreen(
            preview: preview,
            repository: widget.repository,
            enrollmentRepository: widget.enrollmentRepository,
          ),
        ),
      );
    } on CourseEntryFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _codeUnavailable =
            error.kind == CourseEntryFailureKind.inviteUnavailable;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _codeUnavailable = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Vincular materias',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    return CoursePage(
      title: 'Vincular materias',
      leading: IconButton(
        tooltip: 'Volver a mis materias',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Encuentra tu grupo.'),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(24)],
            onSubmitted: (_) => _lookup(),
            decoration: InputDecoration(
              labelText: 'Código de invitación',
              hintText: 'XXXX-XXXX-XXXX-XXXX',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: AppColors.glass.withValues(alpha: 0.66),
              contentPadding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(minHeight: 84),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.outline),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const CourseStateCard(
            title: 'Acceso por aprobación',
            message: 'El código permite solicitar ingreso. El docente debe aprobarlo para que la materia aparezca en Mis materias.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            if (_codeUnavailable) ...[
              const CourseStateCard(
                title: 'Revisa tu código.',
                message: 'El código no es válido o ya no está disponible.',
                color: AppColors.danger,
                icon: Icons.warning_amber_outlined,
              ),
              CourseEntryDiagnostic(error: _error!),
            ] else
              CourseEntryFailureCard(error: _error!),
          ],
          const SizedBox(height: 20),
          CoursePrimaryButton(
            label: _busy ? 'Consultando…' : 'Consultar curso',
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : _lookup,
          ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Consultar mis solicitudes',
            onPressed: _busy ? null : _openRequests,
            icon: Icons.assignment_outlined,
          ),
        ],
      ),
    );
  }

  void _openRequests() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MyJoinRequestsScreen(
        repository: widget.repository,
        enrollmentRepository: widget.enrollmentRepository,
      ),
    ),
  );
}

class ConfirmCourseRequestScreen extends StatefulWidget {
  const ConfirmCourseRequestScreen({
    super.key,
    required this.preview,
    required this.repository,
    required this.enrollmentRepository,
  });

  final CoursePreview preview;
  final CourseEntryRepository repository;
  final EnrollmentRepository enrollmentRepository;

  @override
  State<ConfirmCourseRequestScreen> createState() =>
      _ConfirmCourseRequestScreenState();
}

class _ConfirmCourseRequestScreenState
    extends State<ConfirmCourseRequestScreen> {
  late final String? _sessionUid = widget.repository.currentUid;
  bool _busy = false;
  Object? _error;
  JoinRequestResult? _result;

  Future<void> _submit() async {
    if (_busy || _result != null) return;
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
      final result = await widget.repository.requestJoin(widget.preview.code);
      if (!mounted) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(
          () => _error = const CourseEntryFailure(
            CourseEntryFailureKind.unauthenticated,
          ),
        );
        return;
      }
      // Keep the transaction result distinct from any later list refresh.
      setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMyCourses() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          StudentCoursesScreen(repository: widget.enrollmentRepository),
    ),
  );

  void _openMyRequests() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MyJoinRequestsScreen(
        repository: widget.repository,
        enrollmentRepository: widget.enrollmentRepository,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Confirmar curso',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final result = _result;
    if (result != null) {
      if (result.kind == JoinRequestResultKind.alreadyEnrolled) {
        return CoursePage(
          title: 'Cursos encontrados',
          leading: IconButton(
            tooltip: 'Volver a mis materias',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          child: CourseContent(
            children: [
              const CoursePageHeading(title: 'Ya perteneces al curso.'),
              const SizedBox(height: 16),
              _CoursePreviewCard(preview: widget.preview),
              const SizedBox(height: 16),
              const CourseStateCard(
                title: 'Matrícula existente',
                message: 'No se creó una solicitud ni una matrícula duplicada.',
              ),
              const SizedBox(height: 20),
              CoursePrimaryButton(
                label: 'Ver mis materias',
                onPressed: _openMyCourses,
              ),
            ],
          ),
        );
      }
      final request = result.request;
      final status = request?.status ?? JoinRequestStatus.pending;
      return CourseJoinRequestStatusScreen(
        preview: widget.preview,
        status: status,
        request: request,
        repository: widget.repository,
        enrollmentRepository: widget.enrollmentRepository,
      );
    }
    return CoursePage(
      title: 'Confirmar curso',
      leading: IconButton(
        tooltip: 'Ingresar otro código',
        onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Este es el curso.'),
          const SizedBox(height: 16),
          _CoursePreviewCard(preview: widget.preview),
          const SizedBox(height: 16),
          CourseStateCard(
            title: 'Solicitud de ingreso',
            message: 'El docente debe aprobarla. Un código de invitación no autoriza asistencia. El horario y el contenido académico se mostrarán después de la aprobación.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            CourseEntryFailureCard(error: _error!, uncertainWrite: true),
            if (_error is CourseEntryFailure &&
                (_error as CourseEntryFailure).kind ==
                    CourseEntryFailureKind.inviteUnavailable)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: CourseStateCard(
                  title: 'El código ya no está disponible',
                  message: 'Pide al docente un código vigente. No se creó ninguna solicitud.',
                  color: AppColors.danger,
                ),
              ),
          ],
          const SizedBox(height: 20),
          CoursePrimaryButton(
            label: _busy ? 'Enviando…' : 'Solicitar unirme',
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Consultar mis solicitudes',
            icon: Icons.assignment_outlined,
            onPressed: _busy ? null : _openMyRequests,
          ),
        ],
      ),
    );
  }
}

class CourseJoinRequestStatusScreen extends StatelessWidget {
  const CourseJoinRequestStatusScreen({
    super.key,
    required this.preview,
    required this.status,
    required this.request,
    required this.repository,
    required this.enrollmentRepository,
  });

  final CoursePreview preview;
  final JoinRequestStatus status;
  final JoinRequest? request;
  final CourseEntryRepository repository;
  final EnrollmentRepository enrollmentRepository;

  @override
  Widget build(BuildContext context) {
    final heading = switch (status) {
      JoinRequestStatus.pending => 'Tu solicitud fue enviada.',
      JoinRequestStatus.approved => 'Tu ingreso fue aprobado.',
      JoinRequestStatus.rejected => 'La solicitud fue rechazada.',
    };
    final message = switch (status) {
      JoinRequestStatus.pending => 'El docente decide el ingreso. Puedes volver para consultar la respuesta después.',
      JoinRequestStatus.approved => 'La materia ya está en tu matrícula. Abre Mis materias para consultar el curso y su horario.',
      JoinRequestStatus.rejected =>
        request?.rejectionReason ??
            'El docente decidió no aprobar este ingreso.',
    };
    return CoursePage(
      title: switch (status) {
        JoinRequestStatus.pending => 'Vinculación pendiente',
        JoinRequestStatus.approved => 'Ingreso aprobado',
        JoinRequestStatus.rejected => 'Solicitud rechazada',
      },
      leading: IconButton(
        tooltip: 'Volver a mis materias',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          CoursePageHeading(title: heading),
          const SizedBox(height: 16),
          _CoursePreviewCard(
            preview: preview,
            status: joinRequestStatusLabel(status),
          ),
          const SizedBox(height: 16),
          CourseStateCard(
            title: status == JoinRequestStatus.rejected
                ? 'Motivo de la decisión'
                : status == JoinRequestStatus.approved
                ? 'Acceso confirmado'
                : 'El docente decide el ingreso',
            message: message,
            icon: status == JoinRequestStatus.rejected
                ? Icons.info_outline
                : Icons.check_circle_outline,
          ),
          const SizedBox(height: 20),
          if (status == JoinRequestStatus.approved)
            CoursePrimaryButton(
              label: 'Ver mis materias',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      StudentCoursesScreen(repository: enrollmentRepository),
                ),
              ),
            )
          else
            CoursePrimaryButton(
              label: 'Volver a mis materias',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Consultar mis solicitudes',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MyJoinRequestsScreen(
                  repository: repository,
                  enrollmentRepository: enrollmentRepository,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyJoinRequestsScreen extends StatefulWidget {
  const MyJoinRequestsScreen({
    super.key,
    required this.repository,
    required this.enrollmentRepository,
  });

  final CourseEntryRepository repository;
  final EnrollmentRepository enrollmentRepository;

  @override
  State<MyJoinRequestsScreen> createState() => _MyJoinRequestsScreenState();
}

class _MyJoinRequestsScreenState extends State<MyJoinRequestsScreen> {
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
      final page = await widget.repository.listMyRequests(cursor: _cursor);
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

  void _openMyCourses() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          StudentCoursesScreen(repository: widget.enrollmentRepository),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Mis solicitudes',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    return CoursePage(
      title: 'Mis solicitudes',
      leading: IconButton(
        tooltip: 'Volver a mis materias',
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
          const CoursePageHeading(title: 'Tus solicitudes de ingreso.'),
          const SizedBox(height: 20),
          if (_loading && _items.isEmpty)
            const CourseLoading(message: 'Cargando tus solicitudes…'),
          if (_error != null) ...[
            CourseEntryFailureCard(
              error: _error!,
              onRetry: _loading ? null : () => _load(reset: true),
            ),
            const SizedBox(height: 12),
          ],
          if (!_loading && _error == null && _items.isEmpty)
            const CourseStateCard(
              title: 'Todavía no has solicitado ingreso',
              message: 'Cuando envíes una solicitud con un código vigente, su estado aparecerá aquí.',
              icon: Icons.assignment_outlined,
            ),
          for (final request in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MyJoinRequestTile(
                request: request,
                onOpenCourses: _openMyCourses,
              ),
            ),
          if (_hasMore && _items.isNotEmpty)
            CourseSecondaryButton(
              label: _loading ? 'Cargando…' : 'Cargar más solicitudes',
              onPressed: _loading ? null : () => _load(),
            ),
          const SizedBox(height: 16),
          CourseSecondaryButton(
            label: 'Vincular otra materia',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StudentCourseCodeScreen(
                  repository: widget.repository,
                  enrollmentRepository: widget.enrollmentRepository,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursePreviewCard extends StatelessWidget {
  const _CoursePreviewCard({required this.preview, this.status});

  final CoursePreview preview;
  final String? status;

  @override
  Widget build(BuildContext context) => CoursePanel(
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
            'assets/figma/51a24.svg',
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
                '${preview.subject} · ${preview.group}',
                style: const TextStyle(color: AppColors.text, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                status == null ? preview.period : '${preview.period} · $status',
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MyJoinRequestTile extends StatelessWidget {
  const _MyJoinRequestTile({
    required this.request,
    required this.onOpenCourses,
  });

  final JoinRequest request;
  final VoidCallback onOpenCourses;

  @override
  Widget build(BuildContext context) => CoursePanel(
    color: AppColors.glass.withValues(alpha: 0.62),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${request.subject} · ${request.group}',
          style: const TextStyle(color: AppColors.text, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          '${request.period} · ${joinRequestStatusLabel(request.status)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'Solicitud del ${shortDate(request.createdAt)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        if (request.rejectionReason?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(
            request.rejectionReason!,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
        ],
        if (request.status == JoinRequestStatus.approved) ...[
          const SizedBox(height: 12),
          CoursePrimaryButton(
            label: 'Ver mis materias',
            onPressed: onOpenCourses,
          ),
        ],
      ],
    ),
  );
}
