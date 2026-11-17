import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/attendance_failure.dart';
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
  });

  final Course course;
  final AttendanceSession session;
  final AttendanceRepository repository;

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
  Object? _error;
  AttendanceFailureKind? _publicationFailureKind;
  bool _loading = true;
  bool _processing = false;
  bool _publicationPending = false;
  int _epoch = 0;

  AttendanceSession get _current => _session ?? widget.session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.repository.getSession(
        courseId: widget.course.id,
        occurrenceId: widget.session.occurrenceId,
      );
      if (!mounted || epoch != _epoch) return;
      if (session == null) throw StateError('La sesión ya no está disponible.');
      var loadedSession = session;
      var publicationPending = false;
      AttendanceFailureKind? publicationFailureKind;
      if (session.status == AttendanceSessionStatus.finalized) {
        try {
          final publication = await widget.repository.finalizeSession(
            courseId: widget.course.id,
            occurrenceId: session.occurrenceId,
            confirmUnmarked: false,
          );
          loadedSession = publication.session ?? session;
          publicationPending =
              publication.publicationPending ||
              publication.status != AttendanceFinalizeStatus.confirmed;
          publicationFailureKind = publication.failureKind;
        } on AttendanceFailure catch (error) {
          publicationPending = true;
          publicationFailureKind = error.kind;
        } catch (_) {
          publicationPending = true;
          publicationFailureKind = AttendanceFailureKind.unavailable;
        }
      }
      final roster = <AttendanceRosterEntry>[];
      final segments = <AttendanceSegment>[];
      final events = <AttendanceSessionEvent>[];
      Future<void> loadRoster() async {
        AttendanceRosterCursor? cursor;
        do {
          final page = await widget.repository.listRoster(
            session: loadedSession,
            cursor: cursor,
            pageSize: 100,
          );
          roster.addAll(page.items);
          cursor = page.nextCursor;
        } while (cursor != null);
      }

      Future<void> loadSegments() async {
        if (loadedSession.mode == AttendanceMode.meeting) return;
        AttendanceSegmentCursor? cursor;
        do {
          final page = await widget.repository.listSegments(
            session: loadedSession,
            cursor: cursor,
            pageSize: 100,
          );
          segments.addAll(page.items);
          cursor = page.nextCursor;
        } while (cursor != null);
      }

      Future<void> loadEvents() async {
        if (loadedSession.status == AttendanceSessionStatus.finalized ||
            loadedSession.status == AttendanceSessionStatus.voided ||
            loadedSession.status == AttendanceSessionStatus.voiding) {
          AttendanceSessionEventCursor? eventCursor;
          do {
            final page = await widget.repository.listSessionEvents(
              session: loadedSession,
              cursor: eventCursor,
            );
            events.addAll(page.items);
            eventCursor = page.nextCursor;
          } while (eventCursor != null);
        }
      }

      // The collections are independent; each collection still pages in order.
      await Future.wait([loadRoster(), loadSegments(), loadEvents()]);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = loadedSession;
        _roster = roster;
        _segments = segments;
        _events = events;
        _publicationPending = publicationPending;
        _publicationFailureKind = publicationFailureKind;
        _selectedSegmentId ??= segments.isEmpty ? null : segments.first.id;
        if (_selectedSegmentId != null &&
            segments.every((segment) => segment.id != _selectedSegmentId)) {
          _selectedSegmentId = segments.isEmpty ? null : segments.first.id;
        }
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

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
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) _showMessage(attendanceErrorMessage(error));
      await _loadAfterFailure();
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

  Future<void> _markEntry(AttendanceRosterEntry entry, AttendanceMark mark) =>
      _run(() async {
        final result = _current.mode == AttendanceMode.meeting
            ? await widget.repository.setMeetingMark(
                courseId: widget.course.id,
                occurrenceId: _current.occurrenceId,
                rosterEntryId: entry.rosterEntryId,
                mark: mark,
              )
            : await widget.repository.setSegmentMark(
                courseId: widget.course.id,
                occurrenceId: _current.occurrenceId,
                rosterEntryId: entry.rosterEntryId,
                segmentId: _selectedSegmentId!,
                mark: mark,
                absentUnits: mark == AttendanceMark.absent
                    ? _selectedSegment.durationMinutes
                    : 0,
              );
        if (!mounted) return;
        setState(() {
          _session = result.session;
          _replaceEntry(result.entry);
        });
      });

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
    final count = _current.mode == AttendanceMode.meeting
        ? _roster.length
        : _roster.length;
    final unitDescription = _current.mode == AttendanceMode.meeting
        ? '$count estudiantes'
        : '$count estudiantes en el tramo ${attendanceTimeLabel(_selectedSegment.startMinute)}–${attendanceTimeLabel(_selectedSegment.endMinute)}';
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
    if (confirm != true || !mounted) return;
    await _run(() async {
      for (final entry in List<AttendanceRosterEntry>.of(_roster)) {
        if (_current.mode == AttendanceMode.meeting) {
          final result = await widget.repository.setMeetingMark(
            courseId: widget.course.id,
            occurrenceId: _current.occurrenceId,
            rosterEntryId: entry.rosterEntryId,
            mark: mark,
          );
          _session = result.session;
          _replaceEntry(result.entry);
        } else {
          final result = await widget.repository.setSegmentMark(
            courseId: widget.course.id,
            occurrenceId: _current.occurrenceId,
            rosterEntryId: entry.rosterEntryId,
            segmentId: _selectedSegmentId!,
            mark: mark,
            absentUnits: mark == AttendanceMark.absent
                ? _selectedSegment.durationMinutes
                : 0,
          );
          _session = result.session;
          _replaceEntry(result.entry);
        }
        if (!mounted) return;
        setState(() {});
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
        if (!mounted) return;
        setState(() {
          _session = result.session ?? _current;
          _publicationPending = true;
          _publicationFailureKind = result.failureKind;
        });
        _showMessage(_publicationPendingMessage(result.failureKind));
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
          if (!mounted) return;
          setState(() {
            _session = result.session ?? _current;
            _publicationPending = true;
            _publicationFailureKind = result.failureKind;
          });
          _showMessage(_publicationPendingMessage(result.failureKind));
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
      await _load();
    });
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

  Future<void> _correct(AttendanceRosterEntry entry) async {
    final selected =
        await showDialog<
          ({AttendanceMark mark, int? absentUnits, String reason})
        >(
          context: context,
          builder: (dialogContext) => _CorrectionDialog(
            mode: _current.mode,
            entry: entry,
            segment: _current.mode == AttendanceMode.minutes
                ? _selectedSegment
                : null,
          ),
        );
    if (selected == null || !mounted) return;
    await _run(() async {
      final replacement = _replacementForCorrection(
        entry,
        selected.mark,
        selected.absentUnits,
      );
      final result = await widget.repository.correctRosterEntry(
        courseId: widget.course.id,
        occurrenceId: _current.occurrenceId,
        operationId: newAttendanceOperationId(),
        replacement: replacement,
        reason: selected.reason,
      );
      if (!mounted) return;
      setState(() {
        _session = result.session;
        _replaceEntry(result.entry);
      });
      _showMessage('Corrección guardada con motivo e historial.');
      await _load();
    });
  }

  AttendanceRosterEntry _replacementForCorrection(
    AttendanceRosterEntry entry,
    AttendanceMark mark,
    int? absentUnits,
  ) {
    if (_current.mode == AttendanceMode.meeting) {
      return AttendanceRosterEntry(
        rosterEntryId: entry.rosterEntryId,
        displayName: entry.displayName,
        studentUid: entry.studentUid,
        meetingMark: AttendanceRosterMark(
          mark: mark,
          absentUnits: mark == AttendanceMark.absent ? 1 : 0,
          justificationStatus: AttendanceJustificationStatus.none,
          justifiedUnits: 0,
        ),
        segmentMarks: entry.segmentMarks,
        version: entry.version,
        updatedAt: entry.updatedAt,
        updatedBy: entry.updatedBy,
      );
    }
    final existing = entry.segmentMarks[_selectedSegmentId]!;
    final marks = Map<String, AttendanceRosterMark>.of(entry.segmentMarks);
    marks[_selectedSegmentId!] = AttendanceRosterMark(
      mark: mark,
      absentUnits: mark == AttendanceMark.absent
          ? absentUnits ?? _selectedSegment.durationMinutes
          : 0,
      justificationStatus: AttendanceJustificationStatus.none,
      justifiedUnits: 0,
    );
    if (existing.justifiedUnits > 0 && mark == AttendanceMark.present) {
      // A corrected present mark cannot retain previous excuse coverage.
      marks[_selectedSegmentId!] = AttendanceRosterMark(
        mark: AttendanceMark.present,
        absentUnits: 0,
        justificationStatus: AttendanceJustificationStatus.none,
        justifiedUnits: 0,
      );
    }
    return AttendanceRosterEntry(
      rosterEntryId: entry.rosterEntryId,
      displayName: entry.displayName,
      studentUid: entry.studentUid,
      meetingMark: null,
      segmentMarks: marks,
      version: entry.version,
      updatedAt: entry.updatedAt,
      updatedBy: entry.updatedBy,
    );
  }

  Future<void> _reviewJustification(AttendanceRosterEntry entry) async {
    final current = _markFor(entry);
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
            mode: _current.mode,
            entry: entry,
            current: current,
            segment: _current.mode == AttendanceMode.minutes
                ? _selectedSegment
                : null,
          ),
        );
    if (result == null || !mounted) return;
    await _run(() async {
      final mutation = await widget.repository.decideJustification(
        courseId: widget.course.id,
        occurrenceId: _current.occurrenceId,
        rosterEntryId: entry.rosterEntryId,
        segmentId: _current.mode == AttendanceMode.minutes
            ? _selectedSegmentId
            : null,
        operationId: newAttendanceOperationId(),
        status: result.status,
        justifiedUnits: result.units,
        reason: result.reason,
      );
      if (!mounted) return;
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
      fieldLabel: 'Motivo',
      confirmLabel: 'Confirmar',
    ),
  );

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final session = _current;
    final active = session.status == AttendanceSessionStatus.inProgress;
    final finalized = session.status == AttendanceSessionStatus.finalized;
    final voided = session.status == AttendanceSessionStatus.voided;
    final canMark =
        active &&
        (session.mode == AttendanceMode.meeting ||
            (_segments.isNotEmpty && _selectedSegmentId != null));
    return CoursePage(
      title: 'Registrar asistencia',
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
            onPressed: _processing || voided ? null : _voidSession,
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
          if (session.lateRegistrationReason != null)
            CourseStateCard(
              title: 'Registro posterior',
              message:
                  'La sesión se preparó después de la hora de inicio. Motivo: ${session.lateRegistrationReason}',
              icon: Icons.history_outlined,
            ),
          if (session.status == AttendanceSessionStatus.preparing) ...[
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
          if (session.status == AttendanceSessionStatus.closing)
            CourseStateCard(
              title: 'Cierre en curso',
              message: 'Puedes reanudar la finalización. El estudiante todavía no puede ver un resultado parcial.',
              icon: Icons.sync,
              action: CoursePrimaryButton(
                label: 'Continuar finalización',
                icon: Icons.task_alt,
                busy: _processing,
                onPressed: _processing ? null : _finalize,
              ),
            ),
          if (session.status == AttendanceSessionStatus.voiding)
            CourseStateCard(
              title: 'Anulación en curso',
              message: 'El proceso se puede reanudar; durante este estado el resultado no se muestra al estudiante.',
              icon: Icons.sync,
              action: CoursePrimaryButton(
                label: 'Completar anulación',
                icon: Icons.block_outlined,
                busy: _processing,
                onPressed: _processing ? null : _voidSession,
              ),
            ),
          if (voided)
            CourseStateCard(
              title: 'Sesión anulada',
              message:
                  'Motivo interno: ${session.reason ?? 'sin detalle disponible'}. El registro del estudiante se conserva como aviso y no suma unidades.',
              color: AppColors.information,
              icon: Icons.block_outlined,
            ),
          if (active) ...[
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Marcados: ${session.markedCount} de ${session.rosterCount}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                      initialValue: _selectedSegmentId,
                      decoration: const InputDecoration(
                        labelText: 'Tramo de la clase',
                        border: OutlineInputBorder(),
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
                    Text(
                      'La marca afecta únicamente el tramo seleccionado. Puedes revisar los demás por separado.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 12),
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
            CoursePrimaryButton(
              label: _processing ? 'Guardando…' : 'Guardar y continuar después',
              icon: Icons.save_outlined,
              busy: _processing,
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
              onPressed: _processing ? null : _finalize,
            ),
          ],
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
          if (!_loading && _error == null && _roster.isEmpty)
            const CourseStateCard(
              title: 'Nómina vacía',
              message: 'No hay estudiantes que pertenecieran al curso en la fecha efectiva de esta clase. Si esperabas estudiantes, revisa el historial de matrícula.',
              icon: Icons.groups_outlined,
            ),
          if (_roster.isNotEmpty) ...[
            CourseSectionHeading(
              title: 'Estudiantes',
              trailing: Text('${_roster.length}'),
            ),
            const SizedBox(height: 8),
            for (final entry in _roster)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _RosterTile(
                  entry: entry,
                  mark: _markFor(entry),
                  mode: session.mode,
                  segment:
                      session.mode == AttendanceMode.minutes &&
                          _segments.isNotEmpty
                      ? _selectedSegment
                      : null,
                  processing: _processing,
                  canMark: canMark && !_processing,
                  canReview: finalized && !_processing,
                  onPresent: () => _markEntry(entry, AttendanceMark.present),
                  onAbsent: () => _markEntry(entry, AttendanceMark.absent),
                  onCorrect: () => _correct(entry),
                  onJustification: () => _reviewJustification(entry),
                ),
              ),
          ],
          if (_events.isNotEmpty) ...[
            const SizedBox(height: 12),
            const CourseSectionHeading(title: 'Historial de cambios'),
            const SizedBox(height: 8),
            for (final event in _events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EventTile(event: event, roster: _roster),
              ),
          ],
          if (finalized && !voided) ...[
            const SizedBox(height: 8),
            CourseStateCard(
              title: _publicationPending
                  ? 'Publicación pendiente'
                  : 'Registro finalizado',
              message: _publicationPending
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
                onPressed: _processing ? null : _finalize,
              ),
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
};

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.entry,
    required this.mark,
    required this.mode,
    required this.segment,
    required this.processing,
    required this.canMark,
    required this.canReview,
    required this.onPresent,
    required this.onAbsent,
    required this.onCorrect,
    required this.onJustification,
  });

  final AttendanceRosterEntry entry;
  final AttendanceRosterMark mark;
  final AttendanceMode mode;
  final AttendanceSegment? segment;
  final bool processing;
  final bool canMark;
  final bool canReview;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final VoidCallback onCorrect;
  final VoidCallback onJustification;

  String get _markLabel => switch (mark.mark) {
    AttendanceMark.unmarked => 'Sin marcar',
    AttendanceMark.present => 'Presente',
    AttendanceMark.absent =>
      mode == AttendanceMode.minutes
          ? 'Ausente · ${mark.absentUnits} min'
          : 'Ausente',
  };

  String? get _justificationLabel => switch (mark.justificationStatus) {
    AttendanceJustificationStatus.none => null,
    AttendanceJustificationStatus.inReview => 'En revisión',
    AttendanceJustificationStatus.justified =>
      'Justificada · ${mark.justifiedUnits} ${mode == AttendanceMode.minutes ? 'min' : 'encuentro'}',
    AttendanceJustificationStatus.notAccepted => 'No aceptada',
  };

  @override
  Widget build(BuildContext context) => CoursePanel(
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
                  const SizedBox(height: 3),
                  Text(
                    '$_markLabel${segment == null ? '' : ' · ${attendanceTimeLabel(segment!.startMinute)}–${attendanceTimeLabel(segment!.endMinute)}'}',
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
        if (_justificationLabel != null) ...[
          const SizedBox(height: 8),
          Text(
            _justificationLabel!,
            style: const TextStyle(color: AppColors.information),
          ),
        ],
        if (canMark) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: processing ? null : onPresent,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Presente'),
              ),
              OutlinedButton.icon(
                onPressed: processing ? null : onAbsent,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Ausente'),
              ),
            ],
          ),
        ],
        if (canReview) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: processing ? null : onCorrect,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Corregir registro'),
              ),
              if (mark.mark == AttendanceMark.absent)
                TextButton.icon(
                  onPressed: processing ? null : onJustification,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Revisar justificación'),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({
    required this.mode,
    required this.entry,
    required this.segment,
  });

  final AttendanceMode mode;
  final AttendanceRosterEntry entry;
  final AttendanceSegment? segment;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  final _reason = TextEditingController();
  final _units = TextEditingController();
  AttendanceMark _mark = AttendanceMark.present;

  @override
  void initState() {
    super.initState();
    if (widget.mode == AttendanceMode.minutes && widget.segment != null) {
      final old = widget.entry.segmentMarks[widget.segment!.id];
      _units.text = (old?.absentUnits ?? widget.segment!.durationMinutes)
          .toString();
      _mark = old?.mark ?? AttendanceMark.absent;
    } else {
      _mark = widget.entry.meetingMark?.mark ?? AttendanceMark.absent;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _units.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) return;
    int? units;
    if (widget.mode == AttendanceMode.minutes &&
        _mark == AttendanceMark.absent) {
      units = int.tryParse(_units.text.trim());
      final max = widget.segment!.durationMinutes;
      if (units == null || units < 0 || units > max) return;
      if (units == 0) _mark = AttendanceMark.present;
    }
    Navigator.of(context)
        .pop((mark: _mark, absentUnits: units, reason: reason));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Corregir registro'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La marca anterior se conserva en el historial. Estudiante: ${widget.entry.displayName}.',
          ),
          if (widget.mode == AttendanceMode.minutes &&
              widget
                      .entry
                      .segmentMarks[widget.segment!.id]!
                      .justificationStatus !=
                  AttendanceJustificationStatus.none)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'La corrección reinicia la revisión anterior de este tramo; vuelve a revisar el efecto de la justificación.',
              ),
            ),
          if (widget.mode == AttendanceMode.meeting &&
              widget.entry.meetingMark!.justificationStatus !=
                  AttendanceJustificationStatus.none)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'La corrección reinicia la revisión anterior; vuelve a revisar el efecto de la justificación.',
              ),
            ),
          const SizedBox(height: 10),
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
            selected: {_mark},
            onSelectionChanged: (value) => setState(() => _mark = value.first),
          ),
          if (widget.mode == AttendanceMode.minutes &&
              _mark == AttendanceMark.absent) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _units,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    'Minutos ausentes (máx. ${widget.segment!.durationMinutes})',
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
            decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar corrección')),
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
    if (reason.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
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
          Text(event.reason, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

String _eventLabel(AttendanceEventKind kind) => switch (kind) {
  AttendanceEventKind.correction => 'Corrección',
  AttendanceEventKind.justification => 'Revisión de justificación',
  AttendanceEventKind.rosterCorrection => 'Corrección de nómina',
  AttendanceEventKind.voidSession => 'Anulación',
};
