import 'package:flutter/material.dart';

import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../application/enrollment_validator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_repository.dart';
import '../domain/enrollment_status_change.dart';
import '../domain/pending_enrollment.dart';
import '../domain/pending_enrollment_page.dart';
import 'enrollment_components.dart';

class EnrollmentHistoryScreen extends StatefulWidget {
  const EnrollmentHistoryScreen({
    super.key,
    required this.course,
    required this.enrollment,
    required this.repository,
  });

  final Course course;
  final Enrollment enrollment;
  final EnrollmentRepository repository;

  @override
  State<EnrollmentHistoryScreen> createState() =>
      _EnrollmentHistoryScreenState();
}

class _EnrollmentHistoryScreenState extends State<EnrollmentHistoryScreen> {
  late final String? _sessionUid;
  final List<EnrollmentStatusEvent> _events = [];
  final List<PendingEnrollmentStatusEvent> _authorizationEvents = [];
  EnrollmentHistoryCursor? _cursor;
  PendingEnrollmentHistoryCursor? _authorizationCursor;
  bool _hasMore = true;
  bool _authorizationHasMore = false;
  bool _authorizationChecked = false;
  bool _loading = false;
  bool _authorizationLoading = false;
  Object? _error;
  Object? _authorizationError;
  PendingEnrollment? _linkedAuthorization;
  int _epoch = 0;
  int _authorizationEpoch = 0;

  bool get _sessionIsValid =>
      _sessionUid != null &&
      _sessionUid == widget.enrollment.ownerUid &&
      _sessionUid == widget.repository.currentUid;

  @override
  void initState() {
    super.initState();
    _sessionUid = widget.repository.currentUid;
    _load(reset: true);
    _loadLinkedAuthorization(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final epoch = ++_epoch;
    if (reset) {
      _events.clear();
      _cursor = null;
      _hasMore = true;
    }
    if (!_sessionIsValid) {
      setState(() {
        _events.clear();
        _error = const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listEnrollmentHistory(
        courseId: widget.course.id,
        studentUid: widget.enrollment.studentUid,
        cursor: _cursor,
      );
      if (!mounted || epoch != _epoch) return;
      if (!_sessionIsValid) {
        setState(() {
          _events.clear();
          _error = const EnrollmentFailure(
            EnrollmentFailureKind.unauthenticated,
          );
        });
        return;
      }
      setState(() {
        _events.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _loadLinkedAuthorization({bool reset = false}) async {
    if (_authorizationLoading ||
        (!reset && _authorizationChecked && !_authorizationHasMore)) {
      return;
    }
    final epoch = ++_authorizationEpoch;
    if (reset) {
      _authorizationEvents.clear();
      _authorizationCursor = null;
      _authorizationHasMore = false;
      _authorizationChecked = false;
      _linkedAuthorization = null;
    }
    if (!_sessionIsValid) {
      setState(() {
        _authorizationEvents.clear();
        _authorizationError = const EnrollmentFailure(
          EnrollmentFailureKind.unauthenticated,
        );
        _authorizationLoading = false;
      });
      return;
    }

    final rosterEntryId = widget.enrollment.rosterEntryId;
    if (rosterEntryId == null) {
      setState(() {
        _authorizationChecked = true;
        _authorizationHasMore = false;
        _authorizationError = null;
      });
      return;
    }

    String email;
    try {
      email = EnrollmentValidator.exactEmail(rosterEntryId);
    } on EnrollmentFailure {
      setState(() {
        _authorizationChecked = true;
        _authorizationHasMore = false;
        _authorizationError = null;
      });
      return;
    }

    setState(() {
      _authorizationLoading = true;
      _authorizationError = null;
    });
    try {
      var linkedAuthorization = _linkedAuthorization;
      if (!_authorizationChecked || reset) {
        linkedAuthorization = await widget.repository
            .getCoursePendingEnrollment(
              courseId: widget.course.id,
              email: email,
            );
        if (!mounted || epoch != _authorizationEpoch) return;
        if (!_sessionIsValid) {
          setState(() {
            _authorizationEvents.clear();
            _authorizationError = const EnrollmentFailure(
              EnrollmentFailureKind.unauthenticated,
            );
          });
          return;
        }
        if (linkedAuthorization == null ||
            linkedAuthorization.status != 'linked' ||
            linkedAuthorization.studentUid != widget.enrollment.studentUid ||
            linkedAuthorization.courseId != widget.course.id ||
            linkedAuthorization.ownerUid != widget.enrollment.ownerUid ||
            linkedAuthorization.rosterEntryId != rosterEntryId) {
          setState(() {
            _linkedAuthorization = null;
            _authorizationChecked = true;
            _authorizationHasMore = false;
            _authorizationError = null;
          });
          return;
        }
        _linkedAuthorization = linkedAuthorization;
        _authorizationChecked = true;
        _authorizationHasMore = true;
      }

      final page = await widget.repository.listPendingEnrollmentHistory(
        courseId: widget.course.id,
        email: email,
        cursor: _authorizationCursor,
      );
      if (!mounted || epoch != _authorizationEpoch) return;
      if (!_sessionIsValid) {
        setState(() {
          _authorizationEvents.clear();
          _authorizationError = const EnrollmentFailure(
            EnrollmentFailureKind.unauthenticated,
          );
        });
        return;
      }
      setState(() {
        _authorizationEvents.addAll(page.items);
        _authorizationCursor = page.nextCursor;
        _authorizationHasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _authorizationEpoch) {
        setState(() => _authorizationError = error);
      }
    } finally {
      if (mounted && epoch == _authorizationEpoch) {
        setState(() => _authorizationLoading = false);
      }
    }
  }

  String _authorizationEventTitle(PendingEnrollmentStatusEvent event) =>
      switch (event.toStatus) {
        'linked' => 'Cuenta vinculada',
        'withdrawn' => 'Autorización retirada',
        'pending' => 'Autorización reabierta',
        _ => 'Cambio de autorización',
      };

  @override
  Widget build(BuildContext context) {
    if (!_sessionIsValid) {
      return CoursePage(
        title: 'Historial de matrícula',
        child: CourseContent(
          children: [
            const CourseStateCard(
              title: 'La sesión cambió',
              message: 'Cerramos el historial de la cuenta anterior. Vuelve al curso y consulta de nuevo con la cuenta docente autorizada.',
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 16),
            CourseSecondaryButton(
              label: 'Volver al historial del curso',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      );
    }

    return CoursePage(
      title: 'Historial de matrícula',
      leading: IconButton(
        tooltip: 'Volver a la ficha',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar historial',
          onPressed: _loading || _authorizationLoading
              ? null
              : () {
                  _load(reset: true);
                  _loadLinkedAuthorization(reset: true);
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          CoursePageHeading(
            title: 'Cambios de ${widget.enrollment.name}.',
            description:
                '${widget.course.subject} · Grupo ${widget.course.group} · ${widget.course.period} · ${widget.enrollment.status == 'active' ? 'Activo' : 'Retirado'}',
          ),
          const SizedBox(height: 16),
          CourseStateCard(
            title: 'Historial de solo consulta',
            message: 'Cada evento refleja una transición confirmada por el servidor. Ninguna entrada de esta lista se puede editar o eliminar.',
            icon: Icons.history,
          ),
          const SizedBox(height: 12),
          if (_loading && _events.isEmpty)
            const CourseLoading(message: 'Cargando historial…'),
          if (_error != null)
            EnrollmentFailureCard(
              error: _error,
              onRetry: () => _load(reset: _events.isEmpty),
            ),
          if (!_loading && _error == null && _events.isEmpty)
            const CourseStateCard(
              title: 'Todavía no hay cambios de estado',
              message: 'La inscripción no ha registrado retiros ni reincorporaciones.',
              icon: Icons.event_note_outlined,
            ),
          for (final event in _events)
            EnrollmentTile(
              title: event.toStatus == 'withdrawn'
                  ? 'Retiro confirmado'
                  : 'Reincorporación confirmada',
              subtitle:
                  '${event.effectiveDate == null ? '' : 'Fecha efectiva · ${event.effectiveDate!.isoDate} · '}'
                  'Confirmado ${_enrollmentDateTime(event.changedAt)} · ${event.fromStatus == 'active' ? 'Activo' : 'Retirado'} → ${event.toStatus == 'active' ? 'Activo' : 'Retirado'}',
              iconAsset: event.toStatus == 'withdrawn'
                  ? 'df818.svg'
                  : '51a24.svg',
            ),
          if (!_hasMore &&
              (widget.enrollment.effectiveStartDate != null ||
                  widget.enrollment.createdAt != null))
            EnrollmentTile(
              title: 'Ingreso confirmado',
              subtitle: widget.enrollment.effectiveStartDate == null
                  ? 'Fecha registrada · ${_enrollmentDate(widget.enrollment.createdAt!)}'
                  : 'Fecha efectiva · ${widget.enrollment.effectiveStartDate!.isoDate}',
              iconAsset: '51a24.svg',
            ),
          if (_hasMore && _events.isNotEmpty)
            CourseSecondaryButton(
              label: _loading ? 'Cargando…' : 'Cargar más historial',
              onPressed: _loading ? null : () => _load(),
            ),
          if (_linkedAuthorization != null) ...[
            const SizedBox(height: 8),
            const CourseSectionHeading(title: 'Autorización previa'),
            const SizedBox(height: 8),
            if (_authorizationLoading && _authorizationEvents.isEmpty)
              const CourseLoading(message: 'Cargando eventos de vinculación…'),
            if (_authorizationError != null)
              EnrollmentFailureCard(
                error: _authorizationError,
                onRetry: () => _loadLinkedAuthorization(reset: true),
              ),
            for (final event in _authorizationEvents)
              EnrollmentTile(
                title: _authorizationEventTitle(event),
                subtitle:
                    'Fecha efectiva · ${event.effectiveDate.isoDate} · Registrado ${_enrollmentDateTime(event.changedAt)}',
                iconAsset: event.toStatus == 'withdrawn'
                    ? 'df818.svg'
                    : '51a24.svg',
              ),
            if (_authorizationHasMore && _authorizationEvents.isNotEmpty)
              CourseSecondaryButton(
                label: _authorizationLoading
                    ? 'Cargando…'
                    : 'Cargar más eventos de autorización',
                onPressed: _authorizationLoading
                    ? null
                    : () => _loadLinkedAuthorization(),
              ),
          ],
        ],
      ),
    );
  }
}

String _enrollmentDate(DateTime value) {
  final local = _academicLocal(value);
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _enrollmentDateTime(DateTime value) {
  final local = _academicLocal(value);
  return '${_enrollmentDate(value)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Academic timestamps are displayed in Colombia's UTC-5 timezone regardless
/// of the device timezone. Colombia does not observe daylight saving time.
DateTime _academicLocal(DateTime value) =>
    value.toUtc().subtract(const Duration(hours: 5));
