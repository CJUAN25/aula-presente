import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/enrollment_repository_scope.dart';
import '../../enrollments/presentation/teacher_enrollment_screens.dart';
import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/planned_meeting.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../domain/course.dart';
import 'course_presentation_components.dart';

class CourseDetailScreen extends StatelessWidget {
  const CourseDetailScreen({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final meetings = generatePlannedMeetings(
      courseId: course.id,
      schedule: course.schedule,
    );
    return CoursePage(
      title: 'Detalle del curso',
      leading: IconButton(
        tooltip: 'Volver',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: 'Curso docente',
            title: course.subject,
            description: 'Consulta el grupo, el período y el horario previsto.',
          ),
          const SizedBox(height: 20),
          CoursePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CourseStatePill(
                      label: course.group,
                      icon: Icons.groups_2_outlined,
                    ),
                    const CourseStatePill(
                      label: 'Planificado',
                      icon: Icons.event_available_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _CourseMetadata(label: 'Programa', value: course.program),
                const SizedBox(height: 12),
                _CourseMetadata(label: 'Período', value: course.period),
                const SizedBox(height: 12),
                _CourseMetadata(
                  label: 'Fechas',
                  value:
                      '${_dateLabel(course.schedule.startDate)} – ${_dateLabel(course.schedule.endDate)}',
                ),
                const SizedBox(height: 12),
                _CourseMetadata(
                  label: 'Zona horaria académica',
                  value: course.schedule.timezone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CourseSectionHeading(
            title: 'Estudiantes y matrícula',
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TeacherEnrollmentHubScreen(
                    course: course,
                    repository: EnrollmentRepositoryScope.read(context),
                  ),
                ),
              ),
              icon: const Icon(Icons.groups_2_outlined, size: 18),
              label: const Text('Gestionar'),
            ),
          ),
          const SizedBox(height: 10),
          const CourseStateCard(
            title: 'Inscripción manual',
            message: 'Agrega cuentas existentes y consulta estudiantes inscritos. Excel e invitaciones estarán disponibles después.',
            icon: Icons.group_add_outlined,
          ),
          const SizedBox(height: 20),
          CourseSectionHeading(
            title: 'Horario semanal',
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CourseCalendarScreen(course: course),
                ),
              ),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text('Calendario'),
            ),
          ),
          const SizedBox(height: 10),
          ...course.schedule.weeklyBlocks.map(
            (block) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CoursePanel(
                padding: const EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
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
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          CoursePanel(
            color: AppColors.glass.withValues(alpha: 0.48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.information,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${meetings.length} encuentros previstos. Aún no se crean sesiones ni se registra asistencia.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CourseCalendarScreen extends StatelessWidget {
  const CourseCalendarScreen({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final meetings = generatePlannedMeetings(
      courseId: course.id,
      schedule: course.schedule,
    );
    return CoursePage(
      title: 'Calendario del curso',
      leading: IconButton(
        tooltip: 'Volver al curso',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: meetings.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CourseStateCard(
                  title: 'Sin encuentros previstos',
                  message: 'El horario todavía no produce encuentros dentro del rango del curso.',
                  icon: Icons.event_busy_outlined,
                ),
              ),
            )
          : ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: meetings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoursePageHeading(
                          eyebrow: course.group,
                          title: course.subject,
                          description: 'Encuentros calculados desde el horario semanal. Son previstos; no representan asistencia abierta o realizada.',
                        ),
                        const SizedBox(height: 14),
                        CourseStatePill(
                          label: '${meetings.length} previstos',
                          icon: Icons.event_note_outlined,
                        ),
                      ],
                    ),
                  );
                }
                final meeting = meetings[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MeetingTile(
                    meeting: meeting,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PlannedMeetingDetailScreen(
                          course: course,
                          meeting: meeting,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class PlannedMeetingDetailScreen extends StatelessWidget {
  const PlannedMeetingDetailScreen({
    super.key,
    required this.course,
    required this.meeting,
  });

  final Course course;
  final PlannedMeeting meeting;

  @override
  Widget build(BuildContext context) => CoursePage(
    title: 'Detalle del encuentro',
    leading: IconButton(
      tooltip: 'Volver al calendario',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back),
    ),
    child: CourseContent(
      children: [
        CoursePageHeading(
          eyebrow: 'Encuentro previsto',
          title: course.subject,
          description: course.group,
        ),
        const SizedBox(height: 20),
        CoursePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CourseMetadata(label: 'Fecha', value: _dateLabel(meeting.date)),
              const SizedBox(height: 14),
              _CourseMetadata(
                label: 'Horario',
                value: '${meeting.startTime}–${meeting.endTime}',
              ),
              const SizedBox(height: 14),
              _CourseMetadata(
                label: 'Día',
                value: _weekdayName(meeting.weekday),
              ),
              if (meeting.room?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                _CourseMetadata(label: 'Aula', value: meeting.room!),
              ],
              const SizedBox(height: 14),
              const _CourseMetadata(
                label: 'Estado',
                value: 'Previsto · no es una sesión de asistencia',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({required this.meeting, required this.onTap});

  final PlannedMeeting meeting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: CoursePanel(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_weekdayName(meeting.weekday)} ${_dateLabel(meeting.date)}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${meeting.startTime}–${meeting.endTime}'
                      '${meeting.room?.isNotEmpty == true ? ' · Aula ${meeting.room}' : ''}',
                      style: const TextStyle(color: AppColors.muted),
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
    ),
  );
}

class _CourseMetadata extends StatelessWidget {
  const _CourseMetadata({required this.label, required this.value});

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
      const SizedBox(height: 3),
      Text(
        value,
        softWrap: true,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

String _weekdayName(int weekday) => const [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
][weekday - 1];

String _dateLabel(AcademicDate date) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  return '${date.day} de ${months[date.month - 1]} de ${date.year}';
}
