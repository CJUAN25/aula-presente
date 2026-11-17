import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../application/attendance_occurrence_resolver.dart';
import '../application/attendance_validator.dart';
import '../domain/attendance_calendar_change.dart';
import '../domain/attendance_config.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_occurrence.dart';
import '../domain/attendance_repository.dart';
import '../domain/attendance_session.dart';
import 'attendance_presentation_components.dart';
import 'attendance_session_screen.dart';

class TeacherAttendanceScreen extends StatefulWidget {
  const TeacherAttendanceScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final AttendanceRepository repository;

  @override
  State<TeacherAttendanceScreen> createState() =>
      _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  AttendanceConfig? _config;
  List<AttendanceCalendarChange> _changes = const [];
  List<AttendanceSession> _sessions = const [];
  AttendanceMode? _selectedMode;
  Object? _error;
  bool _loading = true;
  bool _saving = false;
  String? _openingMessage;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        widget.repository.getConfig(courseId: widget.course.id),
        widget.repository.listCalendarChanges(courseId: widget.course.id),
        widget.repository.listSessions(
          courseId: widget.course.id,
          from: widget.course.schedule.startDate,
          to: widget.course.schedule.endDate,
        ),
      ]);
      if (!mounted || epoch != _epoch) return;
      final config = results[0] as AttendanceConfig?;
      setState(() {
        _config = config;
        _selectedMode = config?.mode;
        _changes = results[1]! as List<AttendanceCalendarChange>;
        _sessions = results[2]! as List<AttendanceSession>;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  List<AttendanceOccurrence> get _occurrences =>
      AttendanceOccurrenceResolver.resolve(
        courseId: widget.course.id,
        plannedMeetings: generatePlannedMeetings(
          courseId: widget.course.id,
          schedule: widget.course.schedule,
        ),
        changes: _changes,
      );

  Map<String, AttendanceSession> get _sessionsById => {
    for (final session in _sessions) session.occurrenceId: session,
  };

  Map<String, AttendanceCalendarChange> get _changesById => {
    for (final change in _changes) change.occurrenceId: change,
  };

  Future<void> _saveMode() async {
    final mode = _selectedMode;
    if (_saving || mode == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = await widget.repository.setMode(
        course: widget.course,
        mode: mode,
      );
      if (!mounted) return;
      setState(() => _config = config);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Modalidad guardada: ${attendanceModeLabel(config.mode)}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openOccurrence(
    AttendanceOccurrence occurrence,
    AttendanceSession? existing,
  ) async {
    if (_saving || occurrence.kind == AttendanceOccurrenceKind.cancelled) {
      return;
    }
    if (_config == null) {
      _showMessage('Elige primero cómo se contarán las faltas de este curso.');
      return;
    }
    Object? openingError;
    try {
      AttendanceSession session;
      setState(() {
        _saving = true;
        _error = null;
        _openingMessage =
            existing == null ||
                existing.rosterState == AttendanceRosterState.building
            ? 'Preparando la lista y comprobando la matrícula…'
            : 'Abriendo la asistencia guardada…';
      });
      if (existing != null) {
        session = existing;
        if (existing.status == AttendanceSessionStatus.preparing &&
            existing.rosterState == AttendanceRosterState.building) {
          var reason = existing.lateRegistrationReason;
          if (AttendanceValidator.needsLateRegistrationReason(
            occurrence,
            nowUtc: DateTime.now().toUtc(),
            preparedAt: existing.createdAt,
            storedReason: reason,
          )) {
            reason = await _askReason(
              title: 'Registro posterior a la clase',
              label: 'Motivo opcional del registro posterior',
              confirmLabel: 'Completar lista',
            );
            if (reason == null || !mounted) return;
          }
          setState(() => _saving = true);
          session = await widget.repository.prepareSession(
            course: widget.course,
            occurrence: occurrence,
            lateRegistrationReason: reason,
          );
          if (!mounted) return;
        }
      } else {
        final pastStart = _isPastStart(occurrence);
        final reason = pastStart
            ? await _askReason(
                title: 'Registro posterior a la clase',
                label: 'Motivo opcional del registro posterior',
                confirmLabel: 'Registrar asistencia',
              )
            : null;
        if (pastStart && reason == null) return;
        setState(() => _saving = true);
        session = await widget.repository.prepareSession(
          course: widget.course,
          occurrence: occurrence,
          lateRegistrationReason: reason,
        );
        if (!mounted) return;
      }
      if (!mounted) return;
      if (session.status == AttendanceSessionStatus.preparing &&
          session.rosterState == AttendanceRosterState.ready &&
          _isPastStart(occurrence)) {
        session = await widget.repository.startSession(
          courseId: widget.course.id,
          occurrenceId: session.occurrenceId,
        );
        if (!mounted) return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TeacherAttendanceSessionScreen(
            course: widget.course,
            session: session,
            repository: widget.repository,
          ),
        ),
      );
    } catch (error) {
      openingError = error;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo abrir la asistencia. Puedes volver a intentarlo; el avance guardado se conserva.',
            ),
            action: SnackBarAction(
              label: 'Diagnóstico',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Detalle del intento'),
                  content: Text(attendanceErrorMessage(error)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _openingMessage = null;
        });
        await _load();
        if (mounted && openingError != null) {
          setState(() => _error = openingError);
        }
      }
    }
  }

  Future<void> _voidOccurrence(AttendanceSession session) async {
    if (_saving) return;
    final resuming = session.status == AttendanceSessionStatus.voiding;
    final reason = resuming
        ? session.reason
        : await _askReason(
            title: 'Anular asistencia',
            label: 'Motivo opcional de la anulación',
            confirmLabel: 'Anular asistencia',
          );
    if (!mounted || reason == null) return;
    setState(() => _saving = true);
    try {
      final operationId = resuming
          ? session.lastEventId
          : newAttendanceOperationId();
      if (operationId == null) {
        throw StateError('La anulación no conserva su evento.');
      }
      final result = await widget.repository.voidSession(
        courseId: widget.course.id,
        occurrenceId: session.occurrenceId,
        operationId: operationId,
        reason: reason,
      );
      if (mounted) {
        _showMessage(
          result.status == AttendanceSessionStatus.voided
              ? 'Asistencia anulada. La clase ya no suma faltas ni unidades.'
              : 'La anulación sigue pendiente. Pulsa Completar anulación para retomarla.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(attendanceErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _load();
      }
    }
  }

  bool _isPastStart(AttendanceOccurrence occurrence) {
    final bogota = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final today = AcademicDate.fromDateTime(bogota);
    if (occurrence.effectiveDate.compareTo(today) < 0) return true;
    if (occurrence.effectiveDate.compareTo(today) > 0) return false;
    return bogota.hour * 60 + bogota.minute >= occurrence.startMinute;
  }

  Future<String?> _askReason({
    required String title,
    required String label,
    required String confirmLabel,
  }) => showDialog<String>(
    context: context,
    builder: (_) => AttendanceReasonDialog(
      title: title,
      description:
          'Este motivo quedará asociado a la acción en el historial del curso.',
      fieldLabel: label,
      confirmLabel: confirmLabel,
    ),
  );

  Future<void> _editOccurrence(
    AttendanceOccurrence occurrence,
    AttendanceCalendarChangeKind kind,
  ) async {
    if (_saving || _sessionsById.containsKey(occurrence.id)) return;
    final reason = await _askReason(
      title: switch (kind) {
        AttendanceCalendarChangeKind.cancelled => 'Cancelar clase',
        AttendanceCalendarChangeKind.rescheduled => 'Reprogramar clase',
        AttendanceCalendarChangeKind.additional => 'Agregar clase',
      },
      label: 'Motivo (opcional)',
      confirmLabel: 'Continuar',
    );
    if (reason == null || !mounted) return;

    var effectiveDate = occurrence.effectiveDate;
    var startMinute = occurrence.startMinute;
    var endMinute = occurrence.endMinute;
    if (kind != AttendanceCalendarChangeKind.cancelled) {
      final date = await _selectDate(effectiveDate);
      if (date == null || !mounted) return;
      final start = await _selectTime(startMinute);
      if (start == null || !mounted) return;
      final end = await _selectTime(endMinute);
      if (end == null || !mounted) return;
      effectiveDate = date;
      startMinute = start;
      endMinute = end;
      if (endMinute <= startMinute) {
        _showMessage('La hora final debe ser posterior a la hora inicial.');
        return;
      }
      if (_hasOverlap(
        date: effectiveDate,
        startMinute: startMinute,
        endMinute: endMinute,
        excludingId: kind == AttendanceCalendarChangeKind.additional
            ? null
            : occurrence.id,
      )) {
        _showMessage('Ese horario se cruza con otro encuentro del curso.');
        return;
      }
    }

    final previous = _changesById[occurrence.id];
    final id = kind == AttendanceCalendarChangeKind.additional
        ? 'additional_${widget.course.id}_${DateTime.now().microsecondsSinceEpoch}'
        : occurrence.id;
    final originalDate = kind == AttendanceCalendarChangeKind.additional
        ? effectiveDate
        : occurrence.scheduledDate;
    final change = AttendanceCalendarChange(
      occurrenceId: id,
      kind: kind,
      originalDate: originalDate,
      effectiveDate: effectiveDate,
      startMinute: startMinute,
      endMinute: endMinute,
      reason: reason,
      version: kind == AttendanceCalendarChangeKind.additional
          ? 1
          : previous?.version ?? 1,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCalendarChange(
        course: widget.course,
        change: change,
      );
      if (!mounted) return;
      _showMessage(switch (kind) {
        AttendanceCalendarChangeKind.cancelled =>
          'Clase cancelada. No suma faltas.',
        AttendanceCalendarChangeKind.rescheduled =>
          'Clase reprogramada. Conserva una sola identidad.',
        AttendanceCalendarChangeKind.additional =>
          'Clase adicional agregada al calendario.',
      });
      await _load();
    } catch (error) {
      if (mounted) _showMessage(attendanceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<AcademicDate?> _selectDate(AcademicDate initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(
        widget.course.schedule.startDate.year,
        widget.course.schedule.startDate.month,
        widget.course.schedule.startDate.day,
      ),
      lastDate: DateTime(
        widget.course.schedule.endDate.year,
        widget.course.schedule.endDate.month,
        widget.course.schedule.endDate.day,
      ),
      helpText: 'Fecha efectiva de la clase',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    return date == null ? null : AcademicDate.fromDateTime(date);
  }

  Future<int?> _selectTime(int initialMinute) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinute ~/ 60,
        minute: initialMinute % 60,
      ),
      helpText: 'Hora local (Bogotá)',
    );
    return selected == null ? null : selected.hour * 60 + selected.minute;
  }

  bool _hasOverlap({
    required AcademicDate date,
    required int startMinute,
    required int endMinute,
    required String? excludingId,
  }) {
    for (final item in _occurrences) {
      if (item.id == excludingId ||
          item.kind == AttendanceOccurrenceKind.cancelled ||
          item.effectiveDate != date) {
        continue;
      }
      if (startMinute < item.endMinute && endMinute > item.startMinute) {
        return true;
      }
    }
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return CoursePage(
      title: 'Asistencia',
      leading: IconButton(
        tooltip: 'Volver al curso',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar asistencia',
          onPressed: _loading || _saving ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Agregar clase adicional',
          onPressed: _loading || _saving
              ? null
              : () => _editOccurrence(
                  AttendanceOccurrence(
                    id: '',
                    courseId: widget.course.id,
                    kind: AttendanceOccurrenceKind.additional,
                    scheduledDate: widget.course.schedule.startDate,
                    effectiveDate: widget.course.schedule.startDate,
                    startMinute: 8 * 60,
                    endMinute: 9 * 60,
                  ),
                  AttendanceCalendarChangeKind.additional,
                ),
          icon: const Icon(Icons.add),
        ),
      ],
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: 'Docente · ${widget.course.group}',
            title: widget.course.subject,
            description: 'Elige una clase, registra Presente o Ausente y finaliza la asistencia.',
          ),
          const SizedBox(height: 18),
          if (_openingMessage != null)
            AttendanceWaitStatus(message: _openingMessage!),
          if (_loading && config == null)
            const CourseLoading(
              message: 'Cargando calendario y configuración…',
            ),
          if (_error != null) ...[
            AttendanceErrorCard(error: _error!, onRetry: _load),
            const SizedBox(height: 14),
          ],
          if (config != null && !config.canChangeMode)
            CourseStatePill(
              label: attendanceModeLabel(config.mode),
              icon: Icons.fact_check_outlined,
            )
          else
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Forma de contar las faltas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    config == null
                        ? 'Elige una modalidad para este curso antes de preparar la primera asistencia.'
                        : config.canChangeMode
                        ? 'La modalidad queda fija después de crear la primera sesión.'
                        : 'Modalidad bloqueada: el curso ya tiene sesiones de asistencia.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  AttendanceModeChoice(
                    value: _selectedMode,
                    enabled:
                        !_saving && (config == null || config.canChangeMode),
                    onChanged: (value) => setState(() => _selectedMode = value),
                  ),
                  const SizedBox(height: 12),
                  CoursePrimaryButton(
                    label: config == null
                        ? 'Guardar modalidad'
                        : 'Actualizar modalidad',
                    icon: Icons.save_outlined,
                    busy: _saving,
                    onPressed: config != null && !config.canChangeMode
                        ? null
                        : _selectedMode == null
                        ? null
                        : _saveMode,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          CourseSectionHeading(
            title: 'Calendario de encuentros',
            trailing: Text('${_occurrences.length} clases'),
          ),
          const SizedBox(height: 10),
          if (!_loading && _occurrences.isEmpty)
            const CourseStateCard(
              title: 'Sin encuentros previstos',
              message: 'El horario semanal no produce encuentros dentro del período del curso.',
              icon: Icons.event_busy_outlined,
            ),
          for (final occurrence in _occurrences)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OccurrenceCard(
                occurrence: occurrence,
                session: _sessionsById[occurrence.id],
                calendarReason: _changesById[occurrence.id]?.reason,
                busy: _saving,
                late: _isPastStart(occurrence),
                onOpen: () =>
                    _openOccurrence(occurrence, _sessionsById[occurrence.id]),
                onCancel: () => _editOccurrence(
                  occurrence,
                  AttendanceCalendarChangeKind.cancelled,
                ),
                onReschedule: () => _editOccurrence(
                  occurrence,
                  AttendanceCalendarChangeKind.rescheduled,
                ),
                onVoid: () {
                  final session = _sessionsById[occurrence.id];
                  if (session != null) _voidOccurrence(session);
                },
              ),
            ),
          const SizedBox(height: 8),
          const CourseStateCard(
            title: 'El calendario no marca asistencia',
            message: 'Un encuentro previsto no entra en el cálculo hasta que se registra y finaliza. Las clases canceladas se excluyen; una reposición conserva la misma clase.',
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({
    required this.occurrence,
    required this.session,
    required this.calendarReason,
    required this.busy,
    required this.late,
    required this.onOpen,
    required this.onCancel,
    required this.onReschedule,
    required this.onVoid,
  });

  final AttendanceOccurrence occurrence;
  final AttendanceSession? session;
  final String? calendarReason;
  final bool busy;
  final bool late;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback? onVoid;

  String get _status {
    if (occurrence.kind == AttendanceOccurrenceKind.cancelled) {
      return 'Cancelada';
    }
    if (session != null) {
      return switch (session!.status) {
        AttendanceSessionStatus.preparing =>
          session!.rosterState == AttendanceRosterState.building
              ? 'Lista incompleta'
              : 'Lista preparada',
        AttendanceSessionStatus.inProgress => 'En curso',
        AttendanceSessionStatus.closing => 'Finalizando',
        AttendanceSessionStatus.finalized => 'Finalizada',
        AttendanceSessionStatus.voiding => 'Anulación en curso',
        AttendanceSessionStatus.voided => 'Anulada',
        AttendanceSessionStatus.restoring => 'Restaurando',
      };
    }
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final today = AcademicDate.fromDateTime(now);
    final past =
        occurrence.effectiveDate.compareTo(today) < 0 ||
        (occurrence.effectiveDate == today &&
            now.hour * 60 + now.minute >= occurrence.startMinute);
    return past ? 'Asistencia sin registrar' : 'Próxima';
  }

  String get _nextAction {
    if (session == null) {
      return late ? 'Registrar asistencia' : 'Preparar lista';
    }
    return switch (session!.status) {
      AttendanceSessionStatus.preparing =>
        session!.rosterState == AttendanceRosterState.building
            ? 'Completar lista'
            : late
            ? 'Registrar asistencia'
            : 'Ver lista',
      AttendanceSessionStatus.inProgress => 'Continuar asistencia',
      AttendanceSessionStatus.closing => 'Continuar cierre',
      AttendanceSessionStatus.finalized => 'Ver asistencia',
      AttendanceSessionStatus.voiding => 'Completar anulación',
      AttendanceSessionStatus.restoring => 'Continuar restauración',
      AttendanceSessionStatus.voided => 'Ver asistencia anulada',
    };
  }

  @override
  Widget build(BuildContext context) {
    final canChange = !busy && session == null;
    final time =
        '${attendanceTimeLabel(occurrence.startMinute)}–'
        '${attendanceTimeLabel(occurrence.endMinute)}';
    return CoursePanel(
      color: AppColors.glass.withValues(alpha: 0.52),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_note_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendanceDateLabel(occurrence.effectiveDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(time, style: const TextStyle(color: AppColors.muted)),
                    if (calendarReason?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Motivo: ${calendarReason!.trim()}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (occurrence.effectiveDate !=
                        occurrence.scheduledDate) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Programada ${attendanceDateLabel(occurrence.scheduledDate)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CourseStatePill(
                  label: _status,
                  icon: occurrence.kind == AttendanceOccurrenceKind.cancelled
                      ? Icons.event_busy_outlined
                      : Icons.circle_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (occurrence.kind != AttendanceOccurrenceKind.cancelled)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onOpen,
                  icon: Icon(
                    session == null
                        ? Icons.fact_check_outlined
                        : Icons.open_in_new,
                  ),
                  label: Text(_nextAction),
                ),
              if (canChange ||
                  (session != null &&
                      session!.status != AttendanceSessionStatus.voided))
                PopupMenuButton<String>(
                  tooltip: 'Más opciones de la clase',
                  enabled: !busy,
                  onSelected: (value) {
                    if (value == 'cancel') onCancel();
                    if (value == 'reschedule') onReschedule();
                    if (value == 'void') onVoid?.call();
                  },
                  itemBuilder: (_) => [
                    if (canChange)
                      const PopupMenuItem(
                        value: 'reschedule',
                        child: Text('Reprogramar clase'),
                      ),
                    if (canChange &&
                        occurrence.kind != AttendanceOccurrenceKind.cancelled)
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancelar clase'),
                      ),
                    if (session != null &&
                        session!.status != AttendanceSessionStatus.voided)
                      PopupMenuItem(
                        value: 'void',
                        child: Text(
                          session!.status == AttendanceSessionStatus.voiding
                              ? 'Completar anulación'
                              : 'Anular asistencia',
                        ),
                      ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz),
                        SizedBox(width: 4),
                        Text('Opciones'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
