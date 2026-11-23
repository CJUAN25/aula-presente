import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_justification_request.dart';
import '../data/attendance_operation_trace.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_repository.dart';
import '../domain/attendance_segment.dart';
import '../domain/attendance_session.dart';
import '../domain/attendance_session_event.dart';
import 'attendance_presentation_components.dart';

class TeacherAttendanceSessionScreen extends StatefulWidget {
  const TeacherAttendanceSessionScreen({
    super.key,
    required this.course,
    required this.session,
    required this.repository,
    this.openingTrace,
  });

  final Course course;
  final AttendanceSession session;
  final AttendanceRepository repository;
  final AttendanceOperationTrace? openingTrace;

  @override
  State<TeacherAttendanceSessionScreen> createState() =>
      _TeacherAttendanceSessionScreenState();
}

class _TeacherAttendanceSessionScreenState
    extends State<TeacherAttendanceSessionScreen> {
  AttendanceSession? _session;
  List<AttendanceRosterEntry> _roster = const [];
  List<AttendanceSegment> _segments = const [];
  List<AttendanceSessionEvent> _events = const [];
  String? _selectedSegmentId;
  final _searchController = TextEditingController();
  String _studentQuery = '';
  Object? _error;
  Object? _historyError;
  Object? _requestsError;
  int _historyEpoch = 0;
  int _requestsEpoch = 0;
  List<AttendanceJustificationRequest> _requests = [];
  bool _historyLoading = false;
  bool _requestsLoading = false;
  bool _publicationChecking = false;
  AttendanceFailureKind? _publicationFailureKind;
  bool _loading = true;
  bool _processing = false;
  bool _correctionOpen = false;
  bool _publicationPending = false;
  int _epoch = 0;

  AttendanceSession get _current => _session ?? widget.session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  @override
  void didUpdateWidget(covariant TeacherAttendanceSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.id != widget.course.id ||
        oldWidget.session.occurrenceId != widget.session.occurrenceId ||
        oldWidget.repository != widget.repository) {
      _session = widget.session;
      _selectedSegmentId = null;
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({AttendanceFinalizeResult? knownPublication}) async {
    final epoch = ++_epoch;
    final trace = AttendanceOperationTrace('abrir pantalla');
    final opening = widget.openingTrace ?? trace;
    trace.start('leer datos necesarios para la lista');
    setState(() {
      _loading = true;
      _historyLoading = false;
      _requestsLoading = false;
      _publicationChecking = false;
      _error = null;
      _historyError = null;
      _requestsError = null;
      _events = [];
      _requests = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _epoch) {
        opening.milestone('primera respuesta visible');
      }
    });
    try {
      final view = await widget.repository.loadSessionView(
        courseId: widget.course.id,
        occurrenceId: widget.session.occurrenceId,
      );
      if (!mounted || epoch != _epoch) return;
      final session = view.session;
      final segments = [...view.segments]
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      final publication = knownPublication?.session?.version == session.version
          ? knownPublication
          : null;
      final checkPublication =
          session.status == AttendanceSessionStatus.finalized &&
          publication == null;
      setState(() {
        _session = session;
        _roster = view.roster;
        _segments = segments;
        _selectedSegmentId = segments.any((s) => s.id == _selectedSegmentId)
            ? _selectedSegmentId
            : segments.firstOrNull?.id;
        _loading = false;
        _publicationPending = publication?.publicationPending ?? false;
        _publicationFailureKind = publication?.failureKind;
        _publicationChecking = checkPublication;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _epoch) opening.milestone('lista utilizable');
      });
      trace.finish();
      _loadExtras(session, epoch, opening, checkPublication: checkPublication);
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } finally {
      trace.finish();
    }
  }

  Future<void> _loadExtras(
    AttendanceSession session,
    int epoch,
    AttendanceOperationTrace trace, {
    required bool checkPublication,
  }) async {
    await Future.wait([
      _loadHistory(session),
      _loadRequests(session),
      if (checkPublication) _checkPublication(session),
    ]);
    if (mounted && epoch == _epoch) {
      trace.milestone('consultas secundarias terminadas');
    }
  }

  Future<void> _loadHistory(AttendanceSession session) async {
    if (![
      AttendanceSessionStatus.finalized,
      AttendanceSessionStatus.voided,
      AttendanceSessionStatus.voiding,
      AttendanceSessionStatus.restoring,
    ].contains(session.status)) {
      return;
    }
    final epoch = _epoch;
    final attempt = ++_historyEpoch;
    bool current() => mounted && epoch == _epoch && attempt == _historyEpoch;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    final trace = AttendanceOperationTrace('abrir pantalla')
      ..start('historial secundario');
    try {
      final events = <AttendanceSessionEvent>[];
      AttendanceSessionEventCursor? cursor;
      do {
        final page = await widget.repository.listSessionEvents(
          session: session,
          cursor: cursor,
        );
        if (!current()) return;
        events.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      if (current()) setState(() => _events = events);
    } catch (error) {
      if (current()) setState(() => _historyError = error);
    } finally {
      if (current()) setState(() => _historyLoading = false);
      trace.finish();
    }
  }

  Future<void> _loadRequests(AttendanceSession session) async {
    // Only finalized attendance can receive new requests. Historical requests
    // can still be read while a finalized session is voided or being restored.
    if (session.status != AttendanceSessionStatus.finalized &&
        session.finalizedAt == null) {
      return;
    }
    final epoch = _epoch;
    final attempt = ++_requestsEpoch;
    bool current() => mounted && epoch == _epoch && attempt == _requestsEpoch;
    setState(() {
      _requestsLoading = true;
      _requestsError = null;
    });
    final trace = AttendanceOperationTrace('abrir pantalla')
      ..start('solicitudes secundarias');
    try {
      final data = await widget.repository.listJustificationRequests(
        courseId: session.courseId,
        occurrenceId: session.occurrenceId,
      );
      if (current()) setState(() => _requests = data);
    } catch (error) {
      if (current()) setState(() => _requestsError = error);
    } finally {
      if (current()) setState(() => _requestsLoading = false);
      trace.finish();
    }
  }

  Future<void> _checkPublication(
    AttendanceSession session, {
    bool notify = false,
  }) async {
    final epoch = _epoch;
    bool current() => mounted && epoch == _epoch;
    setState(() => _publicationChecking = true);
    final trace = AttendanceOperationTrace('abrir pantalla')
      ..start('comprobar publicación secundaria');
    try {
      final result = await widget.repository.finalizeSession(
        courseId: session.courseId,
        occurrenceId: session.occurrenceId,
        confirmUnmarked: false,
      );
      if (!current()) return;
      final checkedSession = result.session;
      final pending =
          result.publicationPending ||
          result.status != AttendanceFinalizeStatus.confirmed;
      if (!pending &&
          checkedSession != null &&
          checkedSession.version != session.version) {
        if (_processing) {
          setState(() {
            _publicationPending = true;
            _publicationFailureKind = AttendanceFailureKind.staleSession;
          });
        } else {
          await _load();
        }
        return;
      }
      setState(() {
        _publicationPending = pending;
        _publicationFailureKind = result.failureKind;
      });
      if (notify && !pending) _showMessage('Publicación confirmada.');
    } catch (error) {
      if (current()) {
        setState(() {
          _publicationPending = true;
          _publicationFailureKind = error is AttendanceFailure
              ? error.kind
              : AttendanceFailureKind.unavailable;
        });
      }
    } finally {
      if (current()) setState(() => _publicationChecking = false);
      trace.finish();
    }
  }

  Future<void> _restore() => _run(() async {
    final result = await widget.repository.restoreSession(
      courseId: widget.course.id,
      occurrenceId: _current.occurrenceId,
    );
    if (mounted) setState(() => _session = result);
    await _load();
  });

  String _requestTimeLabel(AttendanceJustificationRequest request) {
    final segment = _segments
        .where((s) => s.id == request.segmentId)
        .firstOrNull;
    return segment == null
        ? 'Hora de la clase'
        : '${attendanceTimeLabel(segment.startMinute)}–${attendanceTimeLabel(segment.endMinute)}';
  }

  Future<void> _decide(AttendanceJustificationRequest request, bool approve) =>
      _run(() async {
        await widget.repository.decideJustificationRequest(
          courseId: widget.course.id,
          request: request,
          approve: approve,
        );
        await _load();
      });

  bool get _startIsDue {
    final bogota = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final date = _current.effectiveDate;
    final today = DateTime.utc(bogota.year, bogota.month, bogota.day);
    final effective = date.toUtcTimestamp();
    if (effective.isBefore(today)) return true;
    if (effective.isAfter(today)) return false;
    return bogota.hour * 60 + bogota.minute >= _current.startMinute;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_processing || _loading || _error != null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _showMessage(attendanceErrorMessage(error));
      await _loadAfterFailure();
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _loadAfterFailure() async {
    if (!mounted) return;
    _processing = false;
    await _load();
  }

  Future<void> _start() => _run(() async {
    final session = await widget.repository.startSession(
      courseId: widget.course.id,
      occurrenceId: _current.occurrenceId,
    );
    if (!mounted) return;
    setState(() => _session = session);
    _showMessage(
      session.status == AttendanceSessionStatus.inProgress
          ? 'Registro abierto. Las marcas se guardan al seleccionarlas.'
          : 'La sesión continúa preparada y se abrirá cuando llegue la hora efectiva.',
    );
    await _load();
  });

  Future<void> _markEntry(
    AttendanceRosterEntry entry,
    AttendanceMark mark, {
    AttendanceSegment? segment,
  }) async {
    final epoch = _epoch;
    final session = _current;
    await _run(() async {
      final result = segment == null
          ? await widget.repository.setMeetingMark(
              courseId: session.courseId,
              occurrenceId: session.occurrenceId,
              rosterEntryId: entry.rosterEntryId,
              mark: mark,
            )
          : await widget.repository.setSegmentMark(
              courseId: session.courseId,
              occurrenceId: session.occurrenceId,
              rosterEntryId: entry.rosterEntryId,
              segmentId: segment.id,
              mark: mark,
              absentUnits: mark == AttendanceMark.absent
                  ? segment.durationMinutes
                  : 0,
            );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = result.session;
        _replaceEntry(result.entry);
      });
    });
  }

  AttendanceSegment get _selectedSegment =>
      _segments.firstWhere((segment) => segment.id == _selectedSegmentId);

  AttendanceRosterMark _markFor(AttendanceRosterEntry entry) =>
      _current.mode == AttendanceMode.meeting
      ? entry.meetingMark!
      : entry.segmentMarks[_selectedSegmentId]!;

  void _replaceEntry(AttendanceRosterEntry entry) {
    final index = _roster.indexWhere(
      (current) => current.rosterEntryId == entry.rosterEntryId,
    );
    if (index < 0) return;
    final updated = [..._roster];
    updated[index] = entry;
    _roster = updated;
  }

  Future<void> _applyToAll(AttendanceMark mark) async {
    final count = _roster.length;
    final epoch = _epoch;
    final segment = _current.mode == AttendanceMode.minutes
        ? _selectedSegment
        : null;
    final unitDescription = segment == null
        ? '$count estudiantes'
        : '$count estudiantes en el tramo ${_segmentTime(segment)}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aplicar a toda la clase'),
        content: Text(
          'La acción marcará $unitDescription como ${mark == AttendanceMark.present ? 'presentes' : 'ausentes'}. Puedes cambiar marcas individuales después. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Aplicar marcas'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || epoch != _epoch) return;
    final repository = widget.repository;
    final courseId = widget.course.id;
    final occurrenceId = _current.occurrenceId;
    await _run(() async {
      for (final entry in List<AttendanceRosterEntry>.of(_roster)) {
        final result = segment == null
            ? await repository.setMeetingMark(
                courseId: courseId,
                occurrenceId: occurrenceId,
                rosterEntryId: entry.rosterEntryId,
                mark: mark,
              )
            : await repository.setSegmentMark(
                courseId: courseId,
                occurrenceId: occurrenceId,
                rosterEntryId: entry.rosterEntryId,
                segmentId: segment.id,
                mark: mark,
                absentUnits: mark == AttendanceMark.absent
                    ? segment.durationMinutes
                    : 0,
              );
        if (!mounted || epoch != _epoch) return;
        setState(() {
          _session = result.session;
          _replaceEntry(result.entry);
        });
      }
      _showMessage('Acción aplicada a $unitDescription.');
    });
  }

  Future<void> _finalize() async {
    await _run(() async {
      var result = await widget.repository.finalizeSession(
        courseId: widget.course.id,
        occurrenceId: _current.occurrenceId,
        confirmUnmarked: false,
      );
      if (result.publicationPending) {
        await _showPendingPublication(result);
        return;
      }
      if (result.status == AttendanceFinalizeStatus.reviewRequired) {
        if (!mounted) return;
        setState(() => _processing = false);
        final pendingCountLabel = _current.mode == AttendanceMode.meeting
            ? '${result.unmarkedCount} ${result.unmarkedCount == 1 ? 'estudiante sin marcar' : 'estudiantes sin marcar'}'
            : '${result.unmarkedCount} ${result.unmarkedCount == 1 ? 'estudiante con tramos pendientes' : 'estudiantes con tramos pendientes'}';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Quedan decisiones pendientes'),
            content: Text(
              'Hay $pendingCountLabel. Si confirmas, ${_current.mode == AttendanceMode.meeting ? 'se registrarán como ausentes' : 'los tramos restantes de esas personas se registrarán como ausentes'}. La decisión queda guardada en el historial.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Volver a completar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Confirmar ausencias'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          _showMessage(
            'El registro sigue abierto. No se marcó a nadie como ausente.',
          );
          return;
        }
        if (!mounted) return;
        setState(() => _processing = true);
        result = await widget.repository.finalizeSession(
          courseId: widget.course.id,
          occurrenceId: _current.occurrenceId,
          confirmUnmarked: true,
        );
        if (result.publicationPending) {
          await _showPendingPublication(result);
          return;
        }
      }
      if (!mounted) return;
      if (result.status != AttendanceFinalizeStatus.confirmed ||
          result.session == null) {
        _showMessage(
          'La sesión requiere una nueva revisión antes de finalizar.',
        );
        await _load();
        return;
      }
      setState(() {
        _session = result.session;
        _publicationPending = false;
        _publicationFailureKind = null;
      });
      _showMessage('Asistencia finalizada y publicada para sus estudiantes.');
      await _load(knownPublication: result);
    });
  }

  Future<void> _showPendingPublication(AttendanceFinalizeResult result) async {
    if (!mounted) return;
    _showMessage(_publicationPendingMessage(result.failureKind));
    await _load(knownPublication: result);
  }

  Future<void> _voidSession() async {
    final reason = _current.status == AttendanceSessionStatus.voiding
        ? _current.reason
        : await _reasonDialog(
            title: 'Anular sesión',
            description: 'La anulación conserva el historial, deja una notificación para cada estudiante y excluye la clase del cálculo.',
          );
    if (reason == null || !mounted) return;
    await _run(() async {
      final session = await widget.repository.voidSession(
        courseId: widget.course.id,
        occurrenceId: _current.occurrenceId,
        operationId: _current.status == AttendanceSessionStatus.voiding
            ? _current.lastEventId ?? newAttendanceOperationId()
            : newAttendanceOperationId(),
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _session = session);
      _showMessage(
        session.status == AttendanceSessionStatus.voided
            ? 'La sesión quedó anulada con motivo.'
            : 'La anulación sigue en curso. Puedes completar el proceso desde esta pantalla.',
      );
      await _load();
    });
  }

  Future<void> _editMark(
    AttendanceRosterEntry entry, {
    AttendanceSegment? segment,
  }) async {
    if (_correctionOpen || _processing || _publicationPending) return;
    final epoch = _epoch;
    final session = _current;
    final finalized = session.status == AttendanceSessionStatus.finalized;
    final current = segment == null
        ? entry.meetingMark!
        : entry.segmentMarks[segment.id]!;
    _correctionOpen = true;
    AttendanceMark? selected;
    try {
      selected = await showDialog<AttendanceMark>(
        context: context,
        builder: (_) => _CorrectionDialog(
          studentName: entry.displayName,
          current: current,
          startMinute: segment?.startMinute ?? session.startMinute,
          endMinute: segment?.endMinute ?? session.endMinute,
          dateLabel: attendanceDateLabel(session.effectiveDate),
          finalized: finalized,
        ),
      );
    } finally {
      _correctionOpen = false;
    }
    if (selected == null || !mounted || epoch != _epoch) return;
    if (selected == current.mark) {
      _showMessage('No hay cambios que guardar.');
      return;
    }
    if (!finalized) {
      await _markEntry(entry, selected, segment: segment);
      return;
    }
    final replacement = _replacementForCorrection(entry, selected, segment);
    await _run(() async {
      final result = await widget.repository.correctRosterEntry(
        courseId: session.courseId,
        occurrenceId: session.occurrenceId,
        operationId: newAttendanceOperationId(),
        replacement: replacement,
        reason: '',
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = result.session;
        _replaceEntry(result.entry);
      });
      _showMessage(
        result.alreadyApplied
            ? 'La marca ya tenía ese valor.'
            : 'Cambios guardados en el registro de asistencia.',
      );
      if (!result.alreadyApplied) _loadHistory(result.session);
    });
  }

  AttendanceRosterEntry _replacementForCorrection(
    AttendanceRosterEntry entry,
    AttendanceMark mark,
    AttendanceSegment? segment,
  ) {
    final replacement = AttendanceRosterMark(
      mark: mark,
      absentUnits: mark == AttendanceMark.absent
          ? segment?.durationMinutes ?? 1
          : 0,
      justificationStatus: AttendanceJustificationStatus.none,
      justifiedUnits: 0,
    );
    return AttendanceRosterEntry(
      rosterEntryId: entry.rosterEntryId,
      displayName: entry.displayName,
      studentUid: entry.studentUid,
      meetingMark: segment == null ? replacement : entry.meetingMark,
      segmentMarks: segment == null
          ? entry.segmentMarks
          : {...entry.segmentMarks, segment.id: replacement},
      version: entry.version,
      updatedAt: entry.updatedAt,
      updatedBy: entry.updatedBy,
    );
  }

  Future<void> _reviewJustification(
    AttendanceRosterEntry entry, {
    AttendanceSegment? segment,
  }) async {
    final epoch = _epoch;
    final session = _current;
    final current = segment == null
        ? entry.meetingMark!
        : entry.segmentMarks[segment.id]!;
    if (current.mark != AttendanceMark.absent || current.absentUnits == 0) {
      _showMessage('Solo se puede revisar una ausencia registrada.');
      return;
    }
    final result =
        await showDialog<
          ({AttendanceJustificationStatus status, int units, String reason})
        >(
          context: context,
          builder: (dialogContext) => _JustificationDialog(
            mode: session.mode,
            entry: entry,
            current: current,
            segment: segment,
          ),
        );
    if (result == null || !mounted || epoch != _epoch) return;
    await _run(() async {
      final mutation = await widget.repository.decideJustification(
        courseId: session.courseId,
        occurrenceId: session.occurrenceId,
        rosterEntryId: entry.rosterEntryId,
        segmentId: segment?.id,
        operationId: newAttendanceOperationId(),
        status: result.status,
        justifiedUnits: result.units,
        reason: result.reason,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = mutation.session;
        _replaceEntry(mutation.entry);
      });
      _showMessage('Revisión de justificación guardada.');
      await _load();
    });
  }

  Future<String?> _reasonDialog({
    required String title,
    required String description,
  }) => showDialog<String>(
    context: context,
    builder: (_) => AttendanceReasonDialog(
      title: title,
      description: description,
      fieldLabel: 'Motivo (opcional)',
      confirmLabel: 'Confirmar',
    ),
  );

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final session = _current;
    final active = session.status == AttendanceSessionStatus.inProgress;
    final finalized = session.status == AttendanceSessionStatus.finalized;
    final voided = session.status == AttendanceSessionStatus.voided;
    final ready = !_loading && _error == null;
    final visibleRoster = _roster
        .where(
          (entry) =>
              entry.displayName.toLowerCase().contains(_studentQuery) ||
              entry.rosterEntryId.toLowerCase().contains(_studentQuery),
        )
        .toList();
    final canMark =
        active &&
        ready &&
        (session.mode == AttendanceMode.meeting ||
            (_segments.isNotEmpty && _selectedSegmentId != null));
    return CoursePage(
      title: session.mode == AttendanceMode.minutes
          ? 'Asistencia por horas'
          : 'Registrar asistencia',
      leading: IconButton(
        tooltip: 'Volver al calendario',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar lista',
          onPressed: _loading || _processing ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        if (active ||
            session.status == AttendanceSessionStatus.preparing ||
            finalized ||
            session.status == AttendanceSessionStatus.closing)
          IconButton(
            tooltip: 'Anular sesión',
            onPressed: _processing || !ready || voided ? null : _voidSession,
            icon: const Icon(Icons.block_outlined),
          ),
      ],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          CoursePageHeading(
            eyebrow:
                '${widget.course.group} · ${attendanceModeLabel(session.mode)}',
            title: widget.course.subject,
            description:
                '${attendanceDateLabel(session.effectiveDate)} · ${attendanceTimeLabel(session.startMinute)}–${attendanceTimeLabel(session.endMinute)} · ${_statusLabel(session.status)}',
          ),
          const SizedBox(height: 16),
          if (_loading)
            const AttendanceWaitStatus(message: 'Cargando la nómina completa…'),
          if (_processing && !_loading)
            const AttendanceWaitStatus(
              message: 'Guardando los cambios de asistencia…',
            ),
          if (_error != null) ...[
            AttendanceErrorCard(error: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          if (session.scheduledDate != session.effectiveDate) ...[
            Text(
              'Reprogramada · fecha original: ${attendanceDateLabel(session.scheduledDate)}',
              style: const TextStyle(color: AppColors.information),
            ),
            const SizedBox(height: 12),
          ],
          if (session.lateRegistrationReason != null)
            CourseStateCard(
              title: 'Registro posterior',
              message:
                  'La sesión se preparó después de la hora de inicio. Motivo: ${session.lateRegistrationReason}',
              icon: Icons.history_outlined,
            ),
          if (ready && session.status == AttendanceSessionStatus.preparing) ...[
            CourseStateCard(
              title: session.rosterState == AttendanceRosterState.ready
                  ? 'Nómina preparada'
                  : 'Preparando nómina',
              message: _startIsDue
                  ? 'La hora efectiva llegó. Abre el registro para comenzar a marcar.'
                  : 'Borrador guardado. Podrás iniciar el ${attendanceDateLabel(session.effectiveDate)} a las ${attendanceTimeLabel(session.startMinute)} (America/Bogota). Hasta entonces puedes revisar la nómina.',
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 12),
            CoursePrimaryButton(
              label: _startIsDue
                  ? 'Abrir registro'
                  : 'La clase aún no comienza',
              icon: Icons.play_arrow,
              busy: _processing,
              onPressed: !_startIsDue || _processing ? null : _start,
            ),
          ],
          if (ready && session.status == AttendanceSessionStatus.closing)
            CourseStateCard(
              title: 'Cierre en curso',
              message: 'Puedes reanudar la finalización. El estudiante todavía no puede ver un resultado parcial.',
              icon: Icons.sync,
              action: CoursePrimaryButton(
                label: 'Continuar finalización',
                icon: Icons.task_alt,
                busy: _processing,
                onPressed: _processing || _publicationChecking
                    ? null
                    : _finalize,
              ),
            ),
          if (ready && session.status == AttendanceSessionStatus.voiding)
            CourseStateCard(
              title: 'Anulación en curso',
              message: 'El proceso se puede reanudar; los resultados se actualizan por estudiante hasta completar el proceso.',
              icon: Icons.sync,
              action: CoursePrimaryButton(
                label: 'Completar anulación',
                icon: Icons.block_outlined,
                busy: _processing,
                onPressed: _processing ? null : _voidSession,
              ),
            ),
          if (ready &&
              (voided || session.status == AttendanceSessionStatus.restoring))
            CourseStateCard(
              title: 'Sesión anulada',
              message:
                  'Motivo interno: ${session.reason ?? 'sin detalle disponible'}. El registro del estudiante se conserva como aviso y no suma unidades.',
              color: AppColors.information,
              icon: Icons.block_outlined,
              action: session.finalizedAt == null
                  ? null
                  : CoursePrimaryButton(
                      label: session.status == AttendanceSessionStatus.restoring
                          ? 'Continuar restauración'
                          : 'Restaurar asistencia',
                      icon: Icons.restore,
                      busy: _processing,
                      onPressed: _processing ? null : _restore,
                    ),
            ),
          if (ready && finalized && !voided) ...[
            const SizedBox(height: 8),
            CourseStateCard(
              title: _publicationChecking
                  ? 'Comprobando publicación'
                  : _publicationPending
                  ? 'Publicación pendiente'
                  : 'Registro finalizado',
              message: _publicationChecking
                  ? 'La lista ya está disponible. Comprobando que cada estudiante pueda consultar su resultado.'
                  : _publicationPending
                  ? _publicationPendingMessage(_publicationFailureKind)
                  : 'La publicación se comprobó. Cada estudiante consulta únicamente su propio resultado; las correcciones y revisiones quedan auditadas.',
              icon: _publicationPending
                  ? Icons.sync_problem_outlined
                  : Icons.verified_outlined,
              action: CoursePrimaryButton(
                label: _publicationPending
                    ? 'Reintentar publicación'
                    : 'Verificar publicación',
                icon: Icons.sync,
                busy: _processing,
                onPressed: _processing || _publicationChecking
                    ? null
                    : () => _checkPublication(session, notify: true),
              ),
            ),
          ],
          if (ready && _roster.isNotEmpty) ...[
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.mode == AttendanceMode.minutes
                        ? 'Resumen del tramo seleccionado'
                        : 'Resumen de la lista',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      for (final item in [
                        (
                          AttendanceMark.present,
                          'Presentes',
                          AppColors.primary,
                        ),
                        (AttendanceMark.absent, 'Ausentes', AppColors.danger),
                        (
                          AttendanceMark.unmarked,
                          'Pendientes',
                          AppColors.muted,
                        ),
                      ])
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_roster.where((e) => _markFor(e).mark == item.$1).length}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: item.$3,
                              ),
                            ),
                            Text(
                              item.$2,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (session.unmarkedConfirmed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Las decisiones que seguían pendientes se confirmaron como ausencias.',
                        style: const TextStyle(color: AppColors.information),
                      ),
                    ),
                  if (session.mode == AttendanceMode.minutes &&
                      _segments.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedSegmentId,
                      decoration: InputDecoration(
                        labelText: active
                            ? 'Tramo para acciones masivas'
                            : 'Tramo del resumen',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final segment in _segments)
                          DropdownMenuItem(
                            value: segment.id,
                            child: Text(
                              '${attendanceTimeLabel(segment.startMinute)}–${attendanceTimeLabel(segment.endMinute)} · ${segment.durationMinutes} min',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _processing
                          ? null
                          : (value) =>
                                setState(() => _selectedSegmentId = value),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  if (active)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _processing || _roster.isEmpty || !canMark
                              ? null
                              : () => _applyToAll(AttendanceMark.present),
                          icon: const Icon(Icons.done_all),
                          label: const Text('Todos presentes'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _processing || _roster.isEmpty || !canMark
                              ? null
                              : () => _applyToAll(AttendanceMark.absent),
                          icon: const Icon(Icons.group_off_outlined),
                          label: const Text('Todos ausentes'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 16),
          if (!_loading && _error == null && _roster.isEmpty)
            const CourseStateCard(
              title: 'Nómina vacía',
              message: 'No hay estudiantes que pertenecieran al curso en la fecha efectiva de esta clase. Si esperabas estudiantes, revisa el historial de matrícula.',
              icon: Icons.groups_outlined,
            ),
          if (ready && _roster.isNotEmpty) ...[
            CourseSectionHeading(
              title: 'Estudiantes',
              trailing: Text('${_roster.length}'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _studentQuery = value.trim().toLowerCase()),
              decoration: InputDecoration(
                labelText: 'Buscar estudiante',
                hintText: 'Nombre o correo',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (visibleRoster.isEmpty)
              const CourseStateCard(
                title: 'Sin coincidencias',
                message: 'Prueba con otro nombre o correo. La lista y sus marcas se conservan.',
                icon: Icons.search_off,
              ),
            for (final entry in visibleRoster)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _RosterTile(
                  entry: entry,
                  segments: _segments,
                  canMark: canMark && !_processing,
                  canReview:
                      finalized &&
                      ready &&
                      !_processing &&
                      !_publicationChecking &&
                      !_publicationPending,
                  onPresent: () => _markEntry(entry, AttendanceMark.present),
                  onAbsent: () => _markEntry(entry, AttendanceMark.absent),
                  onEdit: (segment) => _editMark(entry, segment: segment),
                  onJustification: (segment) =>
                      _reviewJustification(entry, segment: segment),
                ),
              ),
          ],
          if (active && ready) ...[
            const SizedBox(height: 14),
            CoursePrimaryButton(
              label: _processing ? 'Guardando…' : 'Guardar y continuar después',
              icon: Icons.save_outlined,
              busy: _processing,
              expandForText: true,
              onPressed: _processing
                  ? null
                  : () {
                      _showMessage(
                        'Las marcas seleccionadas ya están guardadas. Puedes salir y volver a esta sesión.',
                      );
                    },
            ),
            const SizedBox(height: 10),
            CourseSecondaryButton(
              label: 'Finalizar registro',
              icon: Icons.task_alt,
              onPressed: _processing || _publicationChecking ? null : _finalize,
            ),
          ],
          if (_historyLoading || _requestsLoading)
            const AttendanceWaitStatus(
              message: 'Cargando historial y solicitudes…',
            ),
          if (_historyError != null)
            CourseStateCard(
              title: 'No pudimos cargar el historial de cambios',
              message: attendanceErrorMessage(_historyError!),
              action: TextButton(
                onPressed: () => _loadHistory(session),
                child: const Text('Reintentar historial'),
              ),
            ),
          if (_requestsError != null)
            CourseStateCard(
              title: 'No pudimos cargar las solicitudes',
              message: attendanceErrorMessage(_requestsError!),
              action: TextButton(
                onPressed: () => _loadRequests(session),
                child: const Text('Reintentar solicitudes'),
              ),
            ),
          if (_requests.isNotEmpty)
            const CourseSectionHeading(
              title: 'Solicitudes de justificaci\u00f3n',
            ),
          for (final request in _requests)
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _roster
                            .where(
                              (e) => e.rosterEntryId == request.rosterEntryId,
                            )
                            .firstOrNull
                            ?.displayName ??
                        'Estudiante del curso',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    request.segmentId == null
                        ? 'Justificación del encuentro'
                        : 'Tramo: ${_requestTimeLabel(request)}',
                  ),
                  Text(request.text),
                  Text(switch (request.status) {
                    AttendanceRequestStatus.pending => 'Pendiente',
                    AttendanceRequestStatus.approved => 'Aprobada',
                    AttendanceRequestStatus.rejected => 'Rechazada',
                  }),
                  if (request.status == AttendanceRequestStatus.pending &&
                      finalized)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _processing || _publicationChecking
                              ? null
                              : () => _decide(request, true),
                          child: const Text('Aprobar'),
                        ),
                        TextButton(
                          onPressed: _processing || _publicationChecking
                              ? null
                              : () => _decide(request, false),
                          child: const Text('Rechazar'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (ready && _events.isNotEmpty) ...[
            const SizedBox(height: 12),
            const CourseSectionHeading(title: 'Historial de cambios'),
            const SizedBox(height: 8),
            for (final event in _events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EventTile(event: event, roster: _roster),
              ),
          ],
        ],
      ),
    );
  }
}

String _publicationPendingMessage(AttendanceFailureKind? kind) {
  final cause = switch (kind) {
    AttendanceFailureKind.permissionDenied => 'Firestore rechazó la publicación por permisos. Revisa las reglas activas y el acceso docente del curso.',
    AttendanceFailureKind.unavailable => 'La conexión no permitió confirmar todas las filas. La sesión ya quedó finalizada; vuelve a intentar la publicación.',
    AttendanceFailureKind.unauthenticated => 'La sesión de docente terminó antes de completar la publicación. Inicia sesión de nuevo y reintenta.',
    _ => 'La sesión quedó finalizada, pero hay filas que aún no se confirmaron publicadas. Puedes reintentar con los mismos identificadores.',
  };
  return '$cause El resultado de cada estudiante se habilita por separado cuando su fila completa queda publicada.';
}

String _statusLabel(AttendanceSessionStatus status) => switch (status) {
  AttendanceSessionStatus.preparing => 'Preparada',
  AttendanceSessionStatus.inProgress => 'En curso',
  AttendanceSessionStatus.closing => 'Finalizando',
  AttendanceSessionStatus.finalized => 'Finalizada',
  AttendanceSessionStatus.voiding => 'Anulación en curso',
  AttendanceSessionStatus.voided => 'Anulada',
  AttendanceSessionStatus.restoring => 'Restaurando',
};

String _segmentTime(AttendanceSegment segment) =>
    '${attendanceTimeLabel(segment.startMinute)}–${attendanceTimeLabel(segment.endMinute)}';

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.entry,
    required this.segments,
    required this.canMark,
    required this.canReview,
    required this.onPresent,
    required this.onAbsent,
    required this.onEdit,
    required this.onJustification,
  });

  final AttendanceRosterEntry entry;
  final List<AttendanceSegment> segments;
  final bool canMark;
  final bool canReview;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final ValueChanged<AttendanceSegment?> onEdit;
  final ValueChanged<AttendanceSegment?> onJustification;

  String _markLabel(AttendanceRosterMark mark, [AttendanceSegment? segment]) =>
      switch (mark.mark) {
        AttendanceMark.unmarked => 'Sin marcar',
        AttendanceMark.present => 'Presente',
        AttendanceMark.absent when segment == null => 'Ausente',
        AttendanceMark.absent
            when segment != null &&
                mark.absentUnits < segment.durationMinutes =>
          'Ausencia parcial · ${mark.absentUnits} min',
        AttendanceMark.absent => 'Ausente · ${mark.absentUnits} min',
      };

  String? _justificationLabel(
    AttendanceRosterMark mark,
  ) => switch (mark.justificationStatus) {
    AttendanceJustificationStatus.none => null,
    AttendanceJustificationStatus.inReview => 'En revisión',
    AttendanceJustificationStatus.justified =>
      'Justificada · ${mark.justifiedUnits} ${entry.meetingMark == null ? 'min' : 'encuentro'}',
    AttendanceJustificationStatus.notAccepted => 'No aceptada',
  };

  String _summary() {
    final marks = segments.map((segment) => entry.segmentMarks[segment.id]!);
    if (marks.every((mark) => mark.mark == AttendanceMark.present)) {
      return 'Presente';
    }
    if (marks.every((mark) => mark.mark == AttendanceMark.unmarked)) {
      return 'Sin marcar';
    }
    if (marks.any((mark) => mark.mark == AttendanceMark.unmarked)) {
      return 'Hay tramos sin marcar';
    }
    final allAbsent = segments.every(
      (segment) =>
          entry.segmentMarks[segment.id]!.absentUnits ==
          segment.durationMinutes,
    );
    return allAbsent ? 'Ausente' : 'Ausencia parcial';
  }

  @override
  Widget build(BuildContext context) {
    final meeting = entry.meetingMark;
    return CoursePanel(
      color: AppColors.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.glass,
                child: Icon(
                  Icons.person_outline,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      meeting == null ? _summary() : _markLabel(meeting),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (meeting == null)
            for (final segment in segments) ...[
              const Divider(height: 14),
              _segmentRow(segment),
            ]
          else ...[
            if (_justificationLabel(meeting) case final label?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.information),
                ),
              ),
            if (canMark || canReview)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (canMark) ...[
                      OutlinedButton.icon(
                        onPressed: onPresent,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Presente'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onAbsent,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Ausente'),
                      ),
                    ],
                    if (canReview) ...[
                      TextButton.icon(
                        onPressed: () => onEdit(null),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Corregir registro'),
                      ),
                      if (meeting.mark == AttendanceMark.absent)
                        TextButton.icon(
                          onPressed: () => onJustification(null),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Revisar justificación'),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _segmentRow(AttendanceSegment segment) {
    final mark = entry.segmentMarks[segment.id]!;
    final editable = canMark || canReview;
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey((
                'attendance-segment',
                entry.rosterEntryId,
                segment.id,
              )),
              onTap: editable ? () => onEdit(segment) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _segmentTime(segment),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _markLabel(mark, segment),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          if (_justificationLabel(mark) case final label?)
                            Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.information,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (editable)
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (canReview && mark.mark == AttendanceMark.absent)
            IconButton(
              tooltip: 'Revisar justificación de ${_segmentTime(segment)}',
              onPressed: () => onJustification(segment),
              icon: const Icon(Icons.fact_check_outlined),
            ),
        ],
      ),
    );
  }
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({
    required this.studentName,
    required this.current,
    required this.startMinute,
    required this.endMinute,
    required this.dateLabel,
    required this.finalized,
  });

  final String studentName;
  final AttendanceRosterMark current;
  final int startMinute;
  final int endMinute;
  final String dateLabel;
  final bool finalized;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late AttendanceMark _mark = widget.current.mark;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.finalized ? 'Corregir registro' : 'Marcar asistencia'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.studentName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.dateLabel} · ${attendanceTimeLabel(widget.startMinute)}–${attendanceTimeLabel(widget.endMinute)}',
          ),
          const SizedBox(height: 16),
          SegmentedButton<AttendanceMark>(
            segments: const [
              ButtonSegment(
                value: AttendanceMark.present,
                label: Text('Presente'),
              ),
              ButtonSegment(
                value: AttendanceMark.absent,
                label: Text('Ausente'),
              ),
            ],
            emptySelectionAllowed: _mark == AttendanceMark.unmarked,
            selected: _mark == AttendanceMark.unmarked ? {} : {_mark},
            onSelectionChanged: (values) =>
                setState(() => _mark = values.first),
          ),
          if (widget.current.justificationStatus !=
              AttendanceJustificationStatus.none)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Si cambias la marca, se recalculará la ausencia. La decisión anterior quedará en el historial.',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _mark == AttendanceMark.unmarked
            ? null
            : () => Navigator.pop(context, _mark),
        child: const Text('Guardar cambios'),
      ),
    ],
  );
}

class _JustificationDialog extends StatefulWidget {
  const _JustificationDialog({
    required this.mode,
    required this.entry,
    required this.current,
    required this.segment,
  });

  final AttendanceMode mode;
  final AttendanceRosterEntry entry;
  final AttendanceRosterMark current;
  final AttendanceSegment? segment;

  @override
  State<_JustificationDialog> createState() => _JustificationDialogState();
}

class _JustificationDialogState extends State<_JustificationDialog> {
  final _reason = TextEditingController();
  final _units = TextEditingController();
  AttendanceJustificationStatus _status =
      AttendanceJustificationStatus.inReview;

  @override
  void initState() {
    super.initState();
    _units.text = widget.current.absentUnits.toString();
  }

  @override
  void dispose() {
    _reason.dispose();
    _units.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();

    final units = _status == AttendanceJustificationStatus.justified
        ? widget.mode == AttendanceMode.meeting
              ? 1
              : int.tryParse(_units.text.trim())
        : 0;
    if (units == null ||
        (_status == AttendanceJustificationStatus.justified && units <= 0) ||
        units > widget.current.absentUnits) {
      return;
    }
    Navigator.of(context).pop((status: _status, units: units, reason: reason));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revisar justificación'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registra el resultado de la revisión realizada. No adjuntes diagnósticos ni documentos sensibles. Ausencia: ${widget.current.absentUnits} ${widget.mode == AttendanceMode.minutes ? 'min' : 'encuentro'}. ${widget.entry.displayName}.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AttendanceJustificationStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Resultado'),
            items: const [
              DropdownMenuItem(
                value: AttendanceJustificationStatus.inReview,
                child: Text('En revisión'),
              ),
              DropdownMenuItem(
                value: AttendanceJustificationStatus.justified,
                child: Text('Justificada'),
              ),
              DropdownMenuItem(
                value: AttendanceJustificationStatus.notAccepted,
                child: Text('No aceptada'),
              ),
            ],
            onChanged: (value) => setState(() => _status = value ?? _status),
          ),
          if (_status == AttendanceJustificationStatus.justified &&
              widget.mode == AttendanceMode.minutes) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _units,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    'Minutos aprobados (máx. ${widget.current.absentUnits})',
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nota breve de revisión',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar resultado')),
    ],
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.roster});

  final AttendanceSessionEvent event;
  final List<AttendanceRosterEntry> roster;

  String _valueLabel(Map<String, Object?> value) {
    if (value['status'] != null) {
      return switch (value['status']) {
        'finalized' => 'Finalizada',
        'voided' => 'Anulada',
        'closing' => 'Finalizando',
        _ => 'Registro abierto',
      };
    }
    final mark = value['mark'];
    if (mark is! Map) return 'Registro';
    final state = switch (mark['justificationStatus']) {
      'justified' => 'Justificada',
      'notAccepted' => 'No aceptada',
      'inReview' => 'En revisión',
      _ => switch (mark['mark']) {
        'present' => 'Presente',
        'absent' => 'Ausente',
        _ => 'Sin marcar',
      },
    };
    return '$state · ${mark['absentUnits'] ?? 0} unidades ausentes · ${mark['justifiedUnits'] ?? 0} justificadas';
  }

  @override
  Widget build(BuildContext context) {
    final time = event.changedAt?.toUtc().subtract(const Duration(hours: 5));
    String? name;
    for (final entry in roster) {
      if (entry.rosterEntryId == event.rosterEntryId) {
        name = entry.displayName;
        break;
      }
    }
    return CoursePanel(
      color: AppColors.glass.withValues(alpha: 0.42),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_eventLabel(event.kind)}${name == null ? '' : ' · $name'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${_valueLabel(event.oldValue)} → ${_valueLabel(event.newValue)}',
          ),
          Text(
            time == null
                ? 'Docente del curso'
                : 'Docente del curso · ${time.day}/${time.month}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} (Colombia)',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (event.reason.trim().isNotEmpty)
            Text(event.reason, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

String _eventLabel(AttendanceEventKind kind) => switch (kind) {
  AttendanceEventKind.restore => 'Restauración',
  AttendanceEventKind.correction => 'Corrección',
  AttendanceEventKind.justification => 'Revisión de justificación',
  AttendanceEventKind.rosterCorrection => 'Corrección de nómina',
  AttendanceEventKind.voidSession => 'Anulación',
};
