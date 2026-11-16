import '../../attendance/application/attendance_occurrence_resolver.dart';
import '../../attendance/domain/attendance_calendar_change.dart';
import '../../attendance/domain/attendance_occurrence.dart';
import '../../attendance/presentation/attendance_presentation_components.dart';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/attendance_repository_scope.dart';
import '../../../app/enrollment_repository_scope.dart';
import '../../../app/enrollment_route_observer.dart';
import '../../enrollments/domain/enrollment_failure.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/presentation/enrollment_components.dart';
import '../../enrollments/presentation/teacher_enrollment_screens.dart';
import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/planned_meeting.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../../attendance/presentation/teacher_attendance_screens.dart';
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
          const SizedBox(height: 18),
          CourseSectionHeading(
            title: 'Asistencia',
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TeacherAttendanceScreen(
                    course: course,
                    repository: AttendanceRepositoryScope.read(context),
                  ),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Gestionar'),
            ),
          ),
          const SizedBox(height: 10),
          const CourseStateCard(
            title: 'Registro manual por encuentro o por horas',
            message: 'Prepara sesiones, toma lista, finaliza el registro y corrige resultados con historial. Los estudiantes consultan únicamente sus propios resultados publicados.',
            icon: Icons.fact_check_outlined,
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
                    '${meetings.length} encuentros previstos desde el horario. La asistencia se gestiona por separado en el panel del curso.',
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

class CourseCalendarScreen extends StatefulWidget {
  const CourseCalendarScreen({
    super.key,
    required this.course,
    this.studentRepository,
  });

  final Course course;
  final EnrollmentRepository? studentRepository;

  @override
  State<CourseCalendarScreen> createState() => _CourseCalendarScreenState();
}

class _CourseCalendarScreenState extends State<CourseCalendarScreen>
    with WidgetsBindingObserver, RouteAware {
  late final String? _sessionUid = widget.studentRepository?.currentUid;
  ModalRoute<void>? _subscribedRoute;
  List<AttendanceCalendarChange> _calendarChanges = const [];
  Course? _authorizedCourse;
  Object? _accessError;
  bool _loadingAccess = false;
  bool _withdrawn = false;
  int _accessEpoch = 0;

  @override
  void initState() {
    super.initState();
    if (widget.studentRepository != null) {
      WidgetsBinding.instance.addObserver(this);
      _refreshStudentAccess();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.studentRepository == null) return;
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        aulaPresenteRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      aulaPresenteRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() => _refreshStudentAccess();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.studentRepository == null) return;
    if (state == AppLifecycleState.resumed) {
      _refreshStudentAccess();
    } else {
      _accessEpoch++;
      if (mounted) {
        setState(() {
          _authorizedCourse = null;
          _accessError = null;
          _withdrawn = false;
          _loadingAccess = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.studentRepository != null) {
      WidgetsBinding.instance.removeObserver(this);
      aulaPresenteRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  Future<void> _refreshStudentAccess() async {
    final repository = widget.studentRepository;
    if (repository == null || _loadingAccess) return;
    final sessionUid = _sessionUid;
    if (sessionUid == null || repository.currentUid != sessionUid) {
      setState(() {
        _authorizedCourse = null;
        _accessError = const EnrollmentFailure(
          EnrollmentFailureKind.unauthenticated,
        );
        _withdrawn = false;
        _loadingAccess = false;
      });
      return;
    }
    final epoch = ++_accessEpoch;
    setState(() {
      _authorizedCourse = null;
      _accessError = null;
      _withdrawn = false;
      _loadingAccess = true;
    });
    try {
      final enrollment = await repository.getCourseEnrollment(
        courseId: widget.course.id,
        studentUid: sessionUid,
      );
      if (!mounted || epoch != _accessEpoch) return;
      if (repository.currentUid != sessionUid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      if (enrollment.status != 'active') {
        setState(() => _withdrawn = true);
        return;
      }
      final scope = context
          .getInheritedWidgetOfExactType<AttendanceRepositoryScope>();
      if (scope == null) {
        throw StateError('AttendanceRepositoryScope is missing.');
      }
      final changes = await scope.repository.listCalendarChanges(
        courseId: widget.course.id,
        forStudent: true,
      );
      if (!mounted || epoch != _accessEpoch) return;
      if (repository.currentUid != sessionUid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      setState(() {
        _authorizedCourse = widget.course;
        _calendarChanges = changes;
      });
    } catch (error) {
      if (mounted && epoch == _accessEpoch) {
        setState(() {
          _authorizedCourse = null;
          _accessError = error;
        });
      }
    } finally {
      if (mounted && epoch == _accessEpoch) {
        setState(() => _loadingAccess = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.studentRepository == null
        ? widget.course
        : _authorizedCourse;
    if (widget.studentRepository != null && course == null) {
      return CoursePage(
        title: 'Calendario del curso',
        leading: IconButton(
          tooltip: 'Volver al curso',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        child: Center(
          child: _loadingAccess
              ? const CourseLoading(message: 'Comprobando tu inscripción…')
              : _withdrawn
              ? CourseStateCard(
                  title: 'Tu inscripción fue retirada',
                  message: 'El horario dejó de estar disponible. Contacta al docente si necesitas que te reincorpore.',
                  icon: Icons.info_outline,
                  action: TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Volver a mis materias'),
                  ),
                )
              : _accessError != null
              ? EnrollmentFailureCard(
                  error: _accessError!,
                  onRetry: _refreshStudentAccess,
                )
              : const CourseLoading(message: 'Comprobando tu inscripción…'),
        ),
      );
    }
    final authorizedCourse = course!;
    final meetings = generatePlannedMeetings(
      courseId: authorizedCourse.id,
      schedule: authorizedCourse.schedule,
    );
    final occurrences = AttendanceOccurrenceResolver.resolve(
      courseId: authorizedCourse.id,
      plannedMeetings: meetings,
      changes: _calendarChanges,
    );
    return CoursePage(
      title: 'Calendario del curso',
      leading: IconButton(
        tooltip: 'Volver al curso',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: occurrences.isEmpty
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
              itemCount: occurrences.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoursePageHeading(
                          eyebrow: authorizedCourse.group,
                          title: authorizedCourse.subject,
                          description: 'Encuentros calculados desde el horario semanal. Son previstos; no representan asistencia abierta o realizada.',
                        ),
                        const SizedBox(height: 14),
                        CourseStatePill(
                          label:
                              '${occurrences.where((e) => e.kind != AttendanceOccurrenceKind.cancelled).length} previstos',
                          icon: Icons.event_note_outlined,
                        ),
                      ],
                    ),
                  );
                }
                final occurrence = occurrences[index - 1];
                if (widget.studentRepository != null) {
                  final status = switch (occurrence.kind) {
                    AttendanceOccurrenceKind.cancelled => 'Cancelada',
                    AttendanceOccurrenceKind.rescheduled => 'Reprogramada',
                    AttendanceOccurrenceKind.additional => 'Adicional',
                    AttendanceOccurrenceKind.planned => 'Prevista',
                  };
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        '$status · ${attendanceDateLabel(occurrence.effectiveDate)}',
                      ),
                      subtitle: Text(
                        '${attendanceTimeLabel(occurrence.startMinute)}–${attendanceTimeLabel(occurrence.endMinute)} · America/Bogota',
                      ),
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
                          course: authorizedCourse,
                          meeting: meeting,
                          studentRepository: widget.studentRepository,
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
    this.studentRepository,
  });

  final Course course;
  final PlannedMeeting meeting;
  final EnrollmentRepository? studentRepository;

  @override
  Widget build(BuildContext context) => studentRepository == null
      ? _buildMeeting(context)
      : _AuthorizedPlannedMeetingScreen(
          course: course,
          meeting: meeting,
          repository: studentRepository!,
        );

  Widget _buildMeeting(BuildContext context) => _MeetingDetailContent(
    course: course,
    meeting: meeting,
    accessMessage: null,
  );
}

class _AuthorizedPlannedMeetingScreen extends StatefulWidget {
  const _AuthorizedPlannedMeetingScreen({
    required this.course,
    required this.meeting,
    required this.repository,
  });

  final Course course;
  final PlannedMeeting meeting;
  final EnrollmentRepository repository;

  @override
  State<_AuthorizedPlannedMeetingScreen> createState() =>
      _AuthorizedPlannedMeetingScreenState();
}

class _AuthorizedPlannedMeetingScreenState
    extends State<_AuthorizedPlannedMeetingScreen>
    with WidgetsBindingObserver, RouteAware {
  late final String? _sessionUid = widget.repository.currentUid;
  ModalRoute<void>? _subscribedRoute;
  bool _loading = true;
  bool _withdrawn = false;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess(force: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        aulaPresenteRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      aulaPresenteRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() => _checkAccess(force: true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccess(force: true);
    } else {
      _epoch++;
      if (mounted) {
        setState(() {
          _loading = false;
          _withdrawn = false;
          _error = null;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    aulaPresenteRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _checkAccess({bool force = false}) async {
    if (_loading && !force) return;
    final uid = _sessionUid;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _withdrawn = false;
      _error = null;
    });
    try {
      if (uid == null || widget.repository.currentUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      final enrollment = await widget.repository.getCourseEnrollment(
        courseId: widget.course.id,
        studentUid: uid,
      );
      if (!mounted || epoch != _epoch) return;
      if (widget.repository.currentUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      if (enrollment.status != 'active') {
        setState(() => _withdrawn = true);
      }
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CoursePage(
        title: 'Detalle del encuentro',
        child: CourseLoading(message: 'Comprobando tu inscripción…'),
      );
    }
    if (_withdrawn || _error != null) {
      return CoursePage(
        title: 'Detalle del encuentro',
        leading: IconButton(
          tooltip: 'Volver al calendario',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        child: _withdrawn
            ? CourseStateCard(
                title: 'Tu inscripción fue retirada',
                message: 'Este encuentro ya no está disponible. Contacta al docente si necesitas que te reincorpore.',
                icon: Icons.info_outline,
                action: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Volver al calendario'),
                ),
              )
            : EnrollmentFailureCard(error: _error!, onRetry: _checkAccess),
      );
    }
    return _MeetingDetailContent(
      course: widget.course,
      meeting: widget.meeting,
      accessMessage: null,
    );
  }
}

class _MeetingDetailContent extends StatelessWidget {
  const _MeetingDetailContent({
    required this.course,
    required this.meeting,
    required this.accessMessage,
  });

  final Course course;
  final PlannedMeeting meeting;
  final String? accessMessage;

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
        if (accessMessage != null)
          CourseStateCard(
            title: 'Tu inscripción fue retirada',
            message: accessMessage!,
            icon: Icons.info_outline,
          )
        else ...[
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
                _CourseMetadata(
                  label: 'Fecha',
                  value: _dateLabel(meeting.date),
                ),
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
