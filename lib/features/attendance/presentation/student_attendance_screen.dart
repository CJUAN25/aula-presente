import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../application/attendance_course_summary_calculator.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import '../domain/attendance_session.dart';
import 'attendance_presentation_components.dart';
import 'attendance_request_button.dart';

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final AttendanceRepository repository;

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  final List<AttendanceRecord> _records = [];
  Object? _error;
  bool _loading = true;
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
      _records.clear();
    });
    try {
      AttendanceRecordCursor? cursor;
      do {
        final page = await widget.repository.listMyAttendanceRecords(
          courseId: widget.course.id,
          cursor: cursor,
        );
        if (!mounted || epoch != _epoch) return;
        _records.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _records.clear();
          _error = error;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = AttendanceCourseSummaryCalculator.calculate(_records);
    final mode = _records.isEmpty ? null : _records.first.mode;
    return CoursePage(
      title: 'Asistencia',
      leading: IconButton(
        tooltip: 'Volver a la materia',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar asistencia',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: 'Estudiante · ${widget.course.group}',
            title: widget.course.subject,
            description: 'Consulta tus registros publicados y cómo se calcula el seguimiento.',
          ),
          const SizedBox(height: 18),
          if (_loading && _records.isEmpty)
            const CourseLoading(message: 'Cargando tus registros…'),
          if (_error != null) ...[
            AttendanceErrorCard(error: _error!, onRetry: _load),
            const SizedBox(height: 14),
          ],
          if (_error == null)
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.hasAttendance
                        ? '${summary.roundedPercent}% de faltas computables'
                        : 'Todavía no hay asistencia registrada',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (summary.hasAttendance) ...[
                    Text(
                      '${mode == AttendanceMode.meeting ? '${summary.countedAbsenceUnits} ${summary.countedAbsenceUnits == 1 ? 'falta' : 'faltas'}' : attendanceUnitsLabel(summary.countedAbsenceUnits, mode ?? AttendanceMode.meeting)} de ${attendanceUnitsLabel(summary.registeredUnits, mode ?? AttendanceMode.meeting)} computables',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (summary.justifiedUnits > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${attendanceUnitsLabel(summary.justifiedUnits, mode ?? AttendanceMode.meeting)} con justificación aprobada',
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ],
                    if (summary.inReviewUnits > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${attendanceUnitsLabel(summary.inReviewUnits, mode ?? AttendanceMode.meeting)} en revisión; se incluyen provisionalmente en el numerador.',
                        style: const TextStyle(color: AppColors.information),
                      ),
                    ],
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: (summary.percent / 100).clamp(0, 1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      color: summary.thresholdReached
                          ? AppColors.danger
                          : AppColors.primary,
                      backgroundColor: AppColors.glass,
                    ),
                    const SizedBox(height: 10),
                    if (summary.thresholdReached)
                      const Text(
                        'Umbral alcanzado en el seguimiento. Este corte no significa una pérdida definitiva de la materia.',
                        style: TextStyle(color: AppColors.danger),
                      )
                    else
                      const Text(
                        'El seguimiento se calcula sobre clases finalizadas y unidades ya registradas.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 14),
          const CourseStateCard(
            title: 'Cómo se calcula',
            message: 'El porcentaje es faltas computables ÷ unidades registradas × 100. Las unidades con justificación aprobada conservan su lugar en el denominador y dejan de sumar al numerador. Las excusas en revisión se muestran y cuentan provisionalmente. Solo entran sesiones finalizadas; las futuras y las anuladas no suman.',
            icon: Icons.calculate_outlined,
          ),
          const SizedBox(height: 16),
          const CourseSectionHeading(title: 'Historial de asistencia'),
          const SizedBox(height: 10),
          if (!_loading && _error == null && _records.isEmpty)
            const CourseStateCard(
              title: 'Aún no hay registros publicados',
              message: 'Cuando el docente finalice una sesión, aparecerá aquí. Un borrador o una clase prevista no se cuentan como falta.',
              icon: Icons.event_note_outlined,
            ),
          if (_error == null)
            for (final record in _records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StudentRecordTile(
                  key: ValueKey('${record.recordId}|${record.updatedAt}'),
                  record: record,
                  repository: widget.repository,
                ),
              ),
          const SizedBox(height: 12),
          const Text(
            'La fórmula es una convención operativa del curso para mostrar el seguimiento. No asigna una nota ni reemplaza la revisión académica institucional.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StudentRecordTile extends StatelessWidget {
  const _StudentRecordTile({
    super.key,
    required this.record,
    required this.repository,
  });

  final AttendanceRecord record;
  final AttendanceRepository repository;

  @override
  Widget build(BuildContext context) {
    final voided = record.result == AttendanceSessionResult.voided;
    final result = switch (record.result) {
      AttendanceSessionResult.unmarked => 'Sin marcar',
      AttendanceSessionResult.voided => 'Registro anulado',
      AttendanceSessionResult.present => 'Presente',
      AttendanceSessionResult.absent => 'Ausente',
      AttendanceSessionResult.partial => 'Ausencia parcial',
      AttendanceSessionResult.justified => 'Justificada',
    };
    return CoursePanel(
      color: voided
          ? AppColors.glass.withValues(alpha: 0.4)
          : AppColors.surface,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                voided ? Icons.block_outlined : Icons.fact_check_outlined,
                color: voided ? AppColors.muted : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendanceDateLabel(record.effectiveDate),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${attendanceTimeLabel(record.startMinute)}–${attendanceTimeLabel(record.endMinute)}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CourseStatePill(label: result),
            ],
          ),
          if (voided) ...[
            const SizedBox(height: 10),
            const Text(
              'La clase se conserva en el historial y se excluye del cálculo.',
              style: TextStyle(color: AppColors.muted),
            ),
          ] else if (record.mode == AttendanceMode.meeting) ...[
            if (record.absentUnits > 0)
              AttendanceRequestButton(
                record: record,
                segmentId: null,
                repository: repository,
              ),
            const SizedBox(height: 10),
            Text(
              record.absentUnits == 0
                  ? '0 faltas de 1 encuentro'
                  : '${record.absentUnits - record.justifiedUnits} falta${record.absentUnits - record.justifiedUnits == 1 ? '' : 's'} computable${record.absentUnits - record.justifiedUnits == 1 ? '' : 's'} de 1 encuentro',
              style: const TextStyle(color: AppColors.muted),
            ),
            if (record.inReviewUnits > 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Justificación en revisión; la ausencia se cuenta provisionalmente.',
                  style: TextStyle(color: AppColors.information),
                ),
              ),
            if (record.justifiedUnits > 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Ausencia justificada por el docente.',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              '${attendanceUnitsLabel(record.absentUnits - record.justifiedUnits, AttendanceMode.minutes)} computables de ${attendanceUnitsLabel(record.unitCount, AttendanceMode.minutes)}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            for (final segment in record.segments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SegmentRecordLine(segment: segment),
                    if (segment.absentMinutes > 0)
                      AttendanceRequestButton(
                        record: record,
                        segmentId: segment.segmentId,
                        repository: repository,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SegmentRecordLine extends StatelessWidget {
  const _SegmentRecordLine({required this.segment});

  final AttendanceRecordSegment segment;

  @override
  Widget build(BuildContext context) {
    final status = switch (segment.justificationStatus) {
      AttendanceJustificationStatus.none => null,
      AttendanceJustificationStatus.inReview => ' · En revisión',
      AttendanceJustificationStatus.justified => ' · Justificada',
      AttendanceJustificationStatus.notAccepted => ' · No aceptada',
    };
    final label = switch (segment.mark) {
      AttendanceMark.unmarked => 'Sin marcar',
      AttendanceMark.present => 'Presente',
      AttendanceMark.absent =>
        '${attendanceUnitsLabel(segment.absentMinutes, AttendanceMode.minutes)} ausentes',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.subdirectory_arrow_right,
          size: 16,
          color: AppColors.muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${attendanceTimeLabel(segment.startMinute)}–${attendanceTimeLabel(segment.endMinute)} · $label${status ?? ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
