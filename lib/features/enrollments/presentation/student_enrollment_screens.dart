import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_detail_screen.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../schedule/domain/planned_meeting.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
import 'enrollment_components.dart';

class StudentCoursesScreen extends StatefulWidget {
  const StudentCoursesScreen({super.key, required this.repository});

  final EnrollmentRepository repository;

  @override
  State<StudentCoursesScreen> createState() => _StudentCoursesScreenState();
}

class _StudentCoursesScreenState extends State<StudentCoursesScreen> {
  final _search = TextEditingController();
  final List<Enrollment> _items = [];
  late final String? _sessionUid;
  EnrollmentCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _publishing = false;
  Object? _error;
  Object? _directoryError;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _sessionUid = widget.repository.currentUid;
    _search.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _publishDirectory();
    await _load(reset: true);
  }

  Future<void> _publishDirectory() async {
    if (_publishing) return;
    setState(() {
      _publishing = true;
      _directoryError = null;
    });
    try {
      await widget.repository.ensureStudentDirectoryEntry();
    } catch (error) {
      if (mounted) setState(() => _directoryError = error);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
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
      final page = await widget.repository.listMyCourses(cursor: _cursor);
      if (!mounted || epoch != _epoch) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() {
          _items.clear();
          _error = StateError('La sesión cambió.');
        });
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = error;
          if (error is EnrollmentFailure &&
              error.kind == EnrollmentFailureKind.permissionDenied) {
            _items.clear();
            _cursor = null;
            _hasMore = false;
          }
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _openCourse(Enrollment enrollment) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => StudentEnrolledCourseScreen(
        enrollment: enrollment,
        repository: widget.repository,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Mis materias',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _items
        : _items
              .where(
                (item) => '${item.subject} ${item.group}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
    return CoursePage(
      title: 'Mis materias',
      leading: IconButton(
        tooltip: 'Volver al perfil',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar materias',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Tu semestre,\nen un solo lugar.'),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: enrollmentInputDecoration(
              'Buscar materia',
              'Nombre o grupo entre los cursos cargados',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
          if (_directoryError != null) ...[
            CourseStateCard(
              title: 'No apareces aún para agregados manuales',
              message:
                  '${enrollmentErrorMessage(_directoryError)} Actualiza después de comprobar las reglas.',
              color: AppColors.danger,
              action: OutlinedButton(
                onPressed: _publishDirectory,
                child: const Text('Reintentar publicación'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_loading && _items.isEmpty)
            const CourseLoading(message: 'Cargando tus materias…'),
          if (_error != null) ...[
            EnrollmentFailureCard(
              error: _error,
              onRetry: () => _load(reset: _items.isEmpty),
            ),
            const SizedBox(height: 16),
          ],
          if (!_loading && _error == null && _items.isEmpty)
            const CourseStateCard(
              title: 'Aún no tienes materias inscritas',
              message: 'El docente debe agregar tu cuenta existente al curso. No necesitas un código de unión para esta entrega.',
              icon: Icons.menu_book_outlined,
            ),
          if (query.isNotEmpty && visible.isEmpty && _items.isNotEmpty)
            const CourseStateCard(
              title: 'Sin coincidencias cargadas',
              message: 'Comprueba el nombre o carga más cursos para ampliar la búsqueda.',
            ),
          for (final item in visible)
            EnrollmentTile(
              title: item.subject,
              subtitle: 'Grupo ${item.group} · ${item.period}',
              iconAsset: '51a24.svg',
              onTap: () => _openCourse(item),
            ),
          if (_hasMore && _items.isNotEmpty) ...[
            const SizedBox(height: 4),
            CourseSecondaryButton(
              label: _loading ? 'Cargando…' : 'Cargar más materias',
              onPressed: _loading ? null : () => _load(),
            ),
          ],
          const SizedBox(height: 16),
          CourseSecondaryButton(
            label: 'Mi horario',
            icon: Icons.calendar_month_outlined,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    StudentScheduleScreen(repository: widget.repository),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const CourseStateCard(
            title: 'Vincular otra materia',
            message: 'Los códigos de unión y las solicitudes del estudiante llegarán en otra entrega. Pide al docente que te agregue manualmente.',
            icon: Icons.info_outline,
          ),
        ],
      ),
    );
  }
}

class StudentEnrolledCourseScreen extends StatefulWidget {
  const StudentEnrolledCourseScreen({
    super.key,
    required this.enrollment,
    required this.repository,
  });

  final Enrollment enrollment;
  final EnrollmentRepository repository;

  @override
  State<StudentEnrolledCourseScreen> createState() =>
      _StudentEnrolledCourseScreenState();
}

class _StudentEnrolledCourseScreenState
    extends State<StudentEnrolledCourseScreen> {
  late final String? _sessionUid;
  Course? _course;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _sessionUid = widget.repository.currentUid;
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _course = null;
    });
    try {
      final course = await widget.repository.getMyEnrolledCourse(
        widget.enrollment.courseId,
      );
      if (mounted && widget.repository.currentUid == _sessionUid) {
        setState(() => _course = course);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Materia inscrita',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final course = _course;
    return CoursePage(
      title: widget.enrollment.subject,
      leading: IconButton(
        tooltip: 'Volver a mis materias',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: 'Materia inscrita',
            title: widget.enrollment.subject,
            description:
                'Grupo ${widget.enrollment.group} · ${widget.enrollment.period}',
          ),
          const SizedBox(height: 20),
          if (_loading && course == null)
            const CourseLoading(message: 'Cargando información del curso…'),
          if (_error != null)
            EnrollmentFailureCard(error: _error, onRetry: _load),
          if (_error == null && course != null) ...[
            CoursePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Programa: ${course.program}',
                    style: const TextStyle(color: AppColors.text),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Período: ${course.period}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Del ${_date(course.schedule.startDate.day, course.schedule.startDate.month, course.schedule.startDate.year)} al ${_date(course.schedule.endDate.day, course.schedule.endDate.month, course.schedule.endDate.year)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const CourseSectionHeading(title: 'Horario semanal'),
            const SizedBox(height: 10),
            for (final block in course.schedule.weeklyBlocks)
              EnrollmentTile(
                title:
                    '${_weekday(block.weekday)} · ${block.startTime}–${block.endTime}',
                subtitle: block.room == null
                    ? 'Grupo ${course.group}'
                    : 'Grupo ${course.group} · Aula ${block.room}',
                iconAsset: '8315a.svg',
              ),
            CourseStateCard(
              title:
                  '${generatePlannedMeetings(courseId: course.id, schedule: course.schedule).length} encuentros previstos',
              message: 'Este calendario es informativo. No son sesiones de asistencia ni porcentajes.',
              icon: Icons.event_note_outlined,
            ),
            const SizedBox(height: 16),
            CoursePrimaryButton(
              label: 'Ver calendario previsto',
              icon: Icons.calendar_month_outlined,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CourseCalendarScreen(course: course),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StudentScheduleScreen extends StatefulWidget {
  const StudentScheduleScreen({super.key, required this.repository});

  final EnrollmentRepository repository;

  @override
  State<StudentScheduleScreen> createState() => _StudentScheduleScreenState();
}

class _StudentScheduleScreenState extends State<StudentScheduleScreen> {
  late final String? _sessionUid;
  final List<Course> _courses = [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sessionUid = widget.repository.currentUid;
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _courses.clear();
    });
    try {
      final courses = <Course>[];
      EnrollmentCursor? cursor;
      do {
        final page = await widget.repository.listMyCourses(cursor: cursor);
        for (final item in page.items) {
          courses.add(
            await widget.repository.getMyEnrolledCourse(item.courseId),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      if (mounted && widget.repository.currentUid == _sessionUid) {
        setState(() {
          _courses
            ..clear()
            ..addAll(courses);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Mi horario',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final weekly =
        <
          ({Course course, int weekday, String start, String end, String? room})
        >[];
    final meetings = <({Course course, PlannedMeeting meeting})>[];
    for (final course in _courses) {
      for (final block in course.schedule.weeklyBlocks) {
        weekly.add((
          course: course,
          weekday: block.weekday,
          start: block.startTime,
          end: block.endTime,
          room: block.room,
        ));
      }
      for (final meeting in generatePlannedMeetings(
        courseId: course.id,
        schedule: course.schedule,
      )) {
        meetings.add((course: course, meeting: meeting));
      }
    }
    weekly.sort((a, b) {
      final day = a.weekday.compareTo(b.weekday);
      return day != 0 ? day : a.start.compareTo(b.start);
    });
    meetings.sort((a, b) {
      final date = a.meeting.date.compareTo(b.meeting.date);
      return date != 0
          ? date
          : a.meeting.startTime.compareTo(b.meeting.startTime);
    });
    return CoursePage(
      title: 'Mi horario',
      leading: IconButton(
        tooltip: 'Volver',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Tus clases, organizadas.'),
          const SizedBox(height: 20),
          if (_loading) const CourseLoading(message: 'Cargando horario…'),
          if (_error != null)
            EnrollmentFailureCard(error: _error, onRetry: _load),
          if (!_loading && _error == null && weekly.isEmpty)
            const CourseStateCard(
              title: 'Sin horario aún',
              message: 'Cuando un docente te inscriba, tus bloques semanales aparecerán aquí.',
            ),
          if (!_loading && _error == null) ...[
            for (final slot in weekly)
              EnrollmentTile(
                title: '${_weekday(slot.weekday)} · ${slot.course.subject}',
                subtitle:
                    '${slot.start}–${slot.end} · Grupo ${slot.course.group}${slot.room == null ? '' : ' · Aula ${slot.room}'}',
                iconAsset: '8315a.svg',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CourseCalendarScreen(course: slot.course),
                  ),
                ),
              ),
            if (meetings.isNotEmpty) ...[
              const SizedBox(height: 8),
              const CourseSectionHeading(title: 'Encuentros previstos'),
              const SizedBox(height: 10),
              for (final occurrence in meetings.take(30))
                EnrollmentTile(
                  title: occurrence.course.subject,
                  subtitle:
                      '${_date(occurrence.meeting.date.day, occurrence.meeting.date.month, occurrence.meeting.date.year)} · ${occurrence.meeting.startTime}–${occurrence.meeting.endTime}',
                  iconAsset: '8315a.svg',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CourseCalendarScreen(course: occurrence.course),
                    ),
                  ),
                ),
              if (meetings.length > 30)
                const CourseStateCard(
                  title: 'Más encuentros',
                  message: 'Abre el calendario de cada materia para consultar todas las fechas.',
                ),
            ],
          ],
        ],
      ),
    );
  }
}

String _weekday(int day) => const [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
][day - 1];
String _date(int day, int month, int year) =>
    '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
