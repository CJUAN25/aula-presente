import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../schedule/application/schedule_conflict_detector.dart';
import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/course_schedule.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../../schedule/domain/weekly_block.dart';
import '../../attendance/domain/attendance_mode.dart';
import '../application/course_draft_validator.dart';
import '../domain/course_creation_result.dart';
import '../domain/course_draft.dart';
import '../domain/course_failure.dart';
import '../domain/course_repository.dart';
import 'course_presentation_components.dart';
import 'course_schedule_diagnostic_screen.dart';

class CourseCreationFlow extends StatefulWidget {
  const CourseCreationFlow({super.key, required this.repository});

  final CourseRepository repository;

  @override
  State<CourseCreationFlow> createState() => _CourseCreationFlowState();
}

class _CourseCreationFlowState extends State<CourseCreationFlow> {
  final _metadataFormKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _groupController = TextEditingController();
  final _periodController = TextEditingController();
  final _programController = TextEditingController();
  final _id = _newStableId();
  final List<WeeklyBlock> _blocks = [];

  late AcademicDate? _startDate;
  late AcademicDate? _endDate;
  int _step = 0;
  bool _saving = false;
  bool _checkingOnly = false;
  AttendanceMode? _attendanceMode;
  String? _operationError;
  List<CourseValidationIssue> _validationIssues = const [];

  @override
  void initState() {
    super.initState();
    _startDate = null;
    _endDate = null;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _groupController.dispose();
    _periodController.dispose();
    _programController.dispose();
    super.dispose();
  }

  CourseDraft? get _draft {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return null;
    return CourseDraft(
      id: _id,
      subject: _subjectController.text,
      group: _groupController.text,
      period: _periodController.text,
      program: _programController.text,
      attendanceMode: _attendanceMode,
      schedule: CourseSchedule(
        startDate: start,
        endDate: end,
        weeklyBlocks: _blocks,
      ),
    ).normalized();
  }

  Future<void> _selectDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _startDate == null || _endDate == null
          ? null
          : DateTimeRange(
              start: DateTime(
                _startDate!.year,
                _startDate!.month,
                _startDate!.day,
              ),
              end: DateTime(_endDate!.year, _endDate!.month, _endDate!.day),
            ),
      helpText: 'Selecciona el período del curso',
      saveText: 'Aplicar',
      cancelText: 'Cancelar',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: AppColors.primaryInk,
          ),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      // Capture the selected civil fields and never treat this as a UTC class
      // instant. AcademicDate serializes the same date independently.
      _startDate = AcademicDate.fromDateTime(selected.start);
      _endDate = AcademicDate.fromDateTime(selected.end);
      _validationIssues = const [];
      _operationError = null;
    });
  }

  Future<void> _editBlock({WeeklyBlock? block}) async {
    final updated = await showModalBottomSheet<WeeklyBlock>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _WeeklyBlockEditor(
        initial: block,
        stableId: block?.id ?? _newStableId(),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final index = _blocks.indexWhere((item) => item.id == updated.id);
      if (index < 0) {
        _blocks.add(updated);
      } else {
        _blocks[index] = updated;
      }
      _validationIssues = const [];
      _operationError = null;
    });
  }

  Future<bool> _confirmDiscard() async {
    final hasChanges =
        _subjectController.text.trim().isNotEmpty ||
        _groupController.text.trim().isNotEmpty ||
        _periodController.text.trim().isNotEmpty ||
        _programController.text.trim().isNotEmpty ||
        _attendanceMode != null ||
        _startDate != null ||
        _endDate != null ||
        _blocks.isNotEmpty;
    if (!hasChanges) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Descartar borrador'),
            content: const Text(
              'Los datos de este curso aún no se han guardado. ¿Quieres salir y descartarlos?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Seguir editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onBack() async {
    if (_saving) return;
    if (_step > 0) {
      setState(() {
        _step -= 1;
        _operationError = null;
        _validationIssues = const [];
      });
      return;
    }
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  Future<void> _onClose() async {
    if (_saving) return;
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  void _continueFromDetails() {
    if (_metadataFormKey.currentState?.validate() != true) return;
    if (_attendanceMode == null) {
      setState(() {
        _operationError = 'Elige cómo se contarán las faltas de este curso.';
      });
      return;
    }
    setState(() {
      _step = 1;
      _operationError = null;
      _validationIssues = const [];
    });
  }

  void _continueToReview() {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) {
      setState(() {
        _operationError = 'Selecciona las fechas de inicio y final del curso.';
      });
      return;
    }
    if (_blocks.isEmpty) {
      setState(() {
        _operationError = 'Agrega al menos un bloque semanal.';
      });
      return;
    }
    final draft = _draft!;
    final issues = CourseDraftValidator.validate(draft);
    if (issues.isNotEmpty) {
      setState(() {
        _validationIssues = issues;
        _operationError = null;
      });
      return;
    }
    setState(() {
      _step = 2;
      _validationIssues = const [];
      _operationError = null;
    });
  }

  Future<void> _createCourse({bool diagnosticOnly = false}) async {
    if (_saving) return;
    final draft = _draft;
    if (draft == null) {
      setState(() => _operationError = 'Completa los datos y el horario.');
      return;
    }
    final issues = CourseDraftValidator.validate(draft);
    if (issues.isNotEmpty) {
      setState(() {
        _validationIssues = issues;
        _step =
            issues.any(
              (issue) =>
                  issue.field.startsWith('weeklyBlocks') ||
                  issue.field == 'startDate' ||
                  issue.field == 'endDate',
            )
            ? 1
            : 0;
      });
      return;
    }

    setState(() {
      _saving = true;
      _checkingOnly = diagnosticOnly;
      _operationError = null;
    });
    try {
      // Conflict detection must see all pages. A failed query remains an error;
      // it is never presented as a conflict-free result.
      final existing = await widget.repository.getAllOwnCourses(pageSize: 25);
      if (!mounted) return;
      final check = checkScheduleConflicts(
        candidate: draft,
        existingCourses: existing,
      );
      if (diagnosticOnly) {
        await _showScheduleDiagnostic(check);
        return;
      }
      if (check.conflicts.isNotEmpty) {
        final confirmed = await _confirmConflicts(check);
        if (confirmed != true || !mounted) return;
      }

      final result = await widget.repository.createCourse(draft);
      if (!mounted) return;
      // Only this typed, confirmed repository result completes the create flow.
      Navigator.of(context).pop<CourseCreationResult>(result);
    } catch (error) {
      if (mounted) setState(() => _operationError = _createErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _checkingOnly = false;
        });
      }
    }
  }

  Future<void> _showScheduleDiagnostic(ScheduleConflictCheck check) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CourseScheduleDiagnosticScreen(check: check),
        ),
      );

  Future<bool?> _confirmConflicts(
    ScheduleConflictCheck check,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Horario en conflicto'),
      content: Text(
        'Hay ${check.conflicts.length} ${check.conflicts.length == 1 ? 'encuentro que coincide' : 'encuentros que coinciden'} con otros cursos de tu agenda. Esta comprobación es informativa y no reserva horarios entre dispositivos. ¿Quieres crear el curso de todos modos?',
      ),
      actions: [
        if (kDebugMode)
          TextButton(
            onPressed: () => _showScheduleDiagnostic(check),
            child: const Text('Ver diagnóstico'),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Volver al borrador'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Crear de todos modos'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _onBack();
    },
    child: CoursePage(
      title: _stepTitle,
      leading: IconButton(
        tooltip: _step == 0 ? 'Cancelar' : 'Volver',
        onPressed: _saving ? null : _onBack,
        icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _onClose,
          child: const Text('Salir'),
        ),
      ],
      child: _buildStep(),
    ),
  );

  String get _stepTitle => switch (_step) {
    0 => 'Crear curso',
    1 => 'Horario del curso',
    _ => 'Revisar calendario',
  };

  Widget _buildStep() => switch (_step) {
    0 => _detailsStep(),
    1 => _scheduleStep(),
    _ => _reviewStep(),
  };

  Widget _detailsStep() => CourseContent(
    children: [
      const CoursePageHeading(
        eyebrow: 'Nuevo curso · 1 de 3',
        title: 'Datos del curso',
        description:
            'Completa la información que identificarás en tu espacio docente.',
      ),
      const SizedBox(height: 20),
      Form(
        key: _metadataFormKey,
        child: Column(
          children: [
            _textField(
              controller: _subjectController,
              label: 'Asignatura',
              hint: 'Nombre de la asignatura',
              maxLength: 120,
              requiredMessage: 'Escribe la asignatura.',
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _groupController,
              label: 'Grupo',
              hint: 'Ej. 02',
              maxLength: 40,
              requiredMessage: 'Escribe el grupo.',
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _periodController,
              label: 'Período académico',
              hint: 'Escribe el período',
              maxLength: 32,
              requiredMessage: 'Escribe el período académico.',
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _programController,
              label: 'Programa',
              hint: 'Escribe el programa',
              maxLength: 120,
              requiredMessage: 'Escribe el programa.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const CourseSectionHeading(title: 'Forma de contar las faltas'),
      const SizedBox(height: 8),
      _attendanceModeChoice(
        value: AttendanceMode.meeting,
        title: 'Por encuentro',
        detail:
            'Cada clase cuenta como una unidad. Una ausencia suma una falta.',
        icon: Icons.event_available_outlined,
      ),
      const SizedBox(height: 8),
      _attendanceModeChoice(
        value: AttendanceMode.minutes,
        title: 'Por horas',
        detail:
            'Registra tramos en minutos y permite ajustar ausencias parciales.',
        icon: Icons.schedule_outlined,
      ),
      if (_operationError != null) ...[
        const SizedBox(height: 12),
        CourseStateCard(
          title: 'Revisa los datos',
          message: _operationError!,
          icon: Icons.error_outline,
          color: AppColors.danger,
        ),
      ],
      const SizedBox(height: 18),
      CoursePrimaryButton(
        label: 'Definir calendario',
        icon: Icons.arrow_forward,
        onPressed: _continueFromDetails,
      ),
      const SizedBox(height: 16),
      const CourseStateCard(
        title: 'Sin catálogos inventados',
        message: 'El período y el programa se guardan como texto; la app no propone valores institucionales.',
        icon: Icons.info_outline,
      ),
    ],
  );

  Widget _attendanceModeChoice({
    required AttendanceMode value,
    required String title,
    required String detail,
    required IconData icon,
  }) {
    final selected = _attendanceMode == value;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $detail',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _saving
            ? null
            : () => setState(() {
                FocusScope.of(context).unfocus();
                _attendanceMode = value;
                _operationError = null;
                _validationIssues = const [];
              }),
        child: CoursePanel(
          padding: const EdgeInsets.all(15),
          borderColor: selected ? AppColors.primary : AppColors.outline,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleStep() => CourseContent(
    children: [
      const CoursePageHeading(
        eyebrow: 'Nuevo curso · 2 de 3',
        title: 'Define el horario',
        description: 'Elige fechas inclusivas y agrega entre uno y ocho bloques semanales.',
      ),
      const SizedBox(height: 18),
      CoursePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vigencia del curso',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Las fechas se interpretan en el calendario académico de Colombia.',
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saving ? null : _selectDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _startDate == null || _endDate == null
                    ? 'Elegir fechas'
                    : '${_dateLabel(_startDate!)} – ${_dateLabel(_endDate!)}',
              ),
            ),
            if (_startDate != null && _endDate != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_startDate!.daysUntil(_endDate!) + 1} días calendario · máximo 366',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      CourseSectionHeading(
        title: 'Bloques semanales (${_blocks.length}/8)',
        trailing: IconButton(
          tooltip: 'Agregar bloque semanal',
          onPressed: _saving || _blocks.length >= 8 ? null : () => _editBlock(),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ),
      const SizedBox(height: 10),
      if (_blocks.isEmpty)
        CourseStateCard(
          title: 'Agrega tu primer horario',
          message: 'Puedes definir varios días y horas. Los encuentros se calcularán después de guardar.',
          icon: Icons.schedule_outlined,
          action: OutlinedButton.icon(
            onPressed: _saving ? null : () => _editBlock(),
            icon: const Icon(Icons.add),
            label: const Text('Agregar día y horario'),
          ),
        )
      else
        ..._blocks.asMap().entries.map((entry) {
          final block = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CoursePanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule_outlined, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_weekdayName(block.weekday)} · ${block.startTime}–${block.endTime}',
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (block.room?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Aula ${block.room}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones del horario',
                    onSelected: (action) {
                      if (action == 'edit') _editBlock(block: block);
                      if (action == 'delete') {
                        setState(
                          () => _blocks.removeWhere(
                            (item) => item.id == block.id,
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Quitar')),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      if (_blocks.length < 8) ...[
        const SizedBox(height: 3),
        CourseSecondaryButton(
          label: 'Agregar otro día',
          icon: Icons.add,
          onPressed: _saving ? null : () => _editBlock(),
        ),
      ],
      if (_operationError != null) ...[
        const SizedBox(height: 14),
        CourseStateCard(
          title: 'Revisa el horario',
          message: _operationError!,
          icon: Icons.error_outline,
          color: AppColors.danger,
        ),
      ],
      ..._issueCards(),
      const SizedBox(height: 18),
      CoursePrimaryButton(
        label: 'Revisar calendario',
        icon: Icons.arrow_forward,
        onPressed: _saving ? null : _continueToReview,
      ),
      const SizedBox(height: 10),
      const Text(
        'Se aceptan bloques consecutivos. No se permiten horarios que se crucen o pasen de medianoche.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: 12, height: 18 / 12),
      ),
    ],
  );

  Widget _reviewStep() {
    final draft = _draft;
    if (draft == null) {
      return const CourseLoading(message: 'Preparando vista previa…');
    }
    final meetings = generatePlannedMeetings(
      courseId: draft.id,
      schedule: draft.schedule,
    );
    final preview = meetings.take(10).toList(growable: false);
    return CourseContent(
      children: [
        const CoursePageHeading(
          eyebrow: 'Nuevo curso · 3 de 3',
          title: 'Revisar calendario',
          description: 'Confirma la información y consulta las fechas previstas antes de crear el curso.',
        ),
        const SizedBox(height: 18),
        CoursePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                draft.subject,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Grupo ${draft.group} · ${draft.period}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Text(
                draft.program,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Text(
                'Faltas ${draft.attendanceMode == AttendanceMode.meeting ? 'por encuentro' : 'por horas'}',
                style: const TextStyle(color: AppColors.primary),
              ),
              const Divider(height: 24),
              Text(
                '${_dateLabel(draft.schedule.startDate)} – ${_dateLabel(draft.schedule.endDate)}',
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 8),
              Text(
                '${draft.schedule.weeklyBlocks.length} bloques semanales · ${meetings.length} encuentros previstos',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              ...draft.schedule.weeklyBlocks.map(
                (block) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '${_weekdayName(block.weekday)} · ${block.startTime}–${block.endTime}'
                    '${block.room?.isNotEmpty == true ? ' · Aula ${block.room}' : ''}',
                    style: const TextStyle(color: AppColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const CourseSectionHeading(title: 'Primeros encuentros'),
        const SizedBox(height: 8),
        ...preview.map(
          (meeting) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CoursePanel(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_weekdayName(meeting.weekday)} ${_dateLabel(meeting.date)}\n${meeting.startTime}–${meeting.endTime}',
                      style: const TextStyle(
                        color: AppColors.text,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (meetings.length > preview.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Y ${meetings.length - preview.length} encuentros más. El calendario completo estará disponible después de guardar.',
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ),
        const SizedBox(height: 8),
        if (_operationError != null) ...[
          CourseStateCard(
            title: 'No pudimos confirmar el curso',
            message: _operationError!,
            icon: Icons.error_outline,
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
        ],
        ..._issueCards(),
        CoursePrimaryButton(
          label: _checkingOnly
              ? 'Consultando agenda…'
              : _saving
              ? 'Guardando curso…'
              : 'Crear curso',
          icon: Icons.check,
          busy: _saving,
          onPressed: _saving ? null : _createCourse,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving
                ? null
                : () => _createCourse(diagnosticOnly: true),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Diagnosticar sin guardar (debug)'),
          ),
        ],
        const SizedBox(height: 10),
        CourseSecondaryButton(
          label: 'Volver a corregir',
          icon: Icons.edit_outlined,
          onPressed: _saving ? null : _onBack,
        ),
        const SizedBox(height: 12),
        const Text(
          'El calendario es previsto. Los festivos, las sesiones de asistencia y los cambios futuros no se gestionan todavía.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            height: 18 / 12,
          ),
        ),
      ],
    );
  }

  List<Widget> _issueCards() => _validationIssues
      .map(
        (issue) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CourseStateCard(
            title: 'Revisa ${_fieldLabel(issue.field)}',
            message: issue.message,
            icon: Icons.error_outline,
            color: AppColors.danger,
          ),
        ),
      )
      .toList(growable: false);

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    required String requiredMessage,
  }) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.sentences,
    maxLength: maxLength,
    validator: (value) {
      final normalized = CourseDraftValidator.normalizeText(value ?? '');
      if (normalized.isEmpty) return requiredMessage;
      if (normalized.length > maxLength) return 'Máximo $maxLength caracteres.';
      return null;
    },
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      counterText: '',
    ),
  );
}

class _WeeklyBlockEditor extends StatefulWidget {
  const _WeeklyBlockEditor({required this.stableId, this.initial});

  final String stableId;
  final WeeklyBlock? initial;

  @override
  State<_WeeklyBlockEditor> createState() => _WeeklyBlockEditorState();
}

class _WeeklyBlockEditorState extends State<_WeeklyBlockEditor> {
  static const _weekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  late int _weekday;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _roomController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _weekday = initial?.weekday ?? 1;
    _start =
        _parseTime(initial?.startTime) ?? const TimeOfDay(hour: 8, minute: 0);
    _end = _parseTime(initial?.endTime) ?? const TimeOfDay(hour: 9, minute: 0);
    _roomController = TextEditingController(text: initial?.room ?? '');
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      helpText: start ? 'Hora de inicio' : 'Hora de finalización',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
      _error = null;
    });
  }

  void _save() {
    final start = _formatTime(_start);
    final end = _formatTime(_end);
    final startMinutes = _start.hour * 60 + _start.minute;
    final endMinutes = _end.hour * 60 + _end.minute;
    if (endMinutes <= startMinutes) {
      setState(() => _error = 'La hora final debe ser posterior a la inicial.');
      return;
    }
    Navigator.of(context).pop<WeeklyBlock>(
      WeeklyBlock(
        id: widget.stableId,
        weekday: _weekday,
        startTime: start,
        endTime: end,
        room: WeeklyBlock.normalizeRoom(_roomController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Día y horario',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(labelText: 'Día de la semana'),
              items: List.generate(
                _weekdays.length,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(_weekdays[index]),
                ),
              ),
              onChanged: (value) {
                if (value != null) setState(() => _weekday = value);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(start: true),
                    icon: const Icon(Icons.login_outlined),
                    label: Text('Inicio ${_formatTime(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(start: false),
                    icon: const Icon(Icons.logout_outlined),
                    label: Text('Fin ${_formatTime(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roomController,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Aula (opcional)',
                hintText: 'Escribe el aula',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 12),
            CoursePrimaryButton(
              label: widget.initial == null
                  ? 'Agregar horario'
                  : 'Guardar cambios',
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}

String _newStableId() {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
  final random = Random.secure();
  return List.generate(
    24,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

TimeOfDay? _parseTime(String? value) {
  if (value == null || !RegExp(r'^[0-2][0-9]:[0-5][0-9]$').hasMatch(value)) {
    return null;
  }
  final parts = value.split(':');
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || hour > 23 || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _weekdayName(int weekday) => const [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
][weekday - 1];

String _dateLabel(AcademicDate date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String _fieldLabel(String field) {
  if (field.startsWith('weeklyBlocks')) return 'el horario';
  return switch (field) {
    'subject' => 'la asignatura',
    'group' => 'el grupo',
    'period' => 'el período',
    'program' => 'el programa',
    'startDate' || 'endDate' => 'las fechas',
    _ => 'la información',
  };
}

String _createErrorMessage(Object error) {
  if (error is CourseFailure) {
    return switch (error.kind) {
      CourseFailureKind.unauthenticated =>
        'Tu sesión terminó. Inicia sesión de nuevo antes de crear el curso.',
      CourseFailureKind.emailNotVerified =>
        'Verifica tu correo para crear cursos.',
      CourseFailureKind.profileInvalid =>
        'No pudimos confirmar tu perfil docente.',
      CourseFailureKind.teacherRoleRequired =>
        'Tu cuenta ya no tiene el rol docente necesario para crear cursos.',
      CourseFailureKind.permissionDenied => 'Firestore rechazó la creación por permisos. Tu borrador sigue aquí; comprueba tu rol y las reglas publicadas.',
      CourseFailureKind.network => 'No se confirmó la creación por un problema de conexión. Conservamos este mismo borrador para que puedas reintentar sin duplicarlo.',
      CourseFailureKind.idempotencyConflict => 'El identificador de este borrador ya existe con otros datos. No se sobrescribió el curso; vuelve atrás y contacta soporte.',
      CourseFailureKind.invalidCourse => 'El servidor rechazó los datos del curso. Revisa los campos y el horario.',
      CourseFailureKind.unknown => 'No pudimos completar la creación. Conservamos el borrador para reintentar.',
    };
  }
  return 'No pudimos comprobar todos los cursos o guardar este borrador. Revisa tu conexión e inténtalo otra vez; se conserva el mismo identificador para no duplicar la creación.';
}
