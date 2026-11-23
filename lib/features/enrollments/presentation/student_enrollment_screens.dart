import 'package:flutter/material.dart';

import '../../../app/enrollment_route_observer.dart';
import '../../../app/attendance_repository_scope.dart';
import '../../../app/course_entry_repository_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../course_entry/presentation/student_course_entry_screens.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_detail_screen.dart';
import '../../attendance/presentation/student_attendance_screen.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../schedule/domain/planned_meeting.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
import '../domain/pending_enrollment_result.dart';
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
  bool _refreshing = false;
  Object? _error;
  Object? _directoryError;
  Object? _linkError;
  PendingEnrollmentLinkSummary? _linkSummary;
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
    if (_refreshing) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return;
    }
    setState(() {
      _refreshing = true;
      _publishing = true;
      _directoryError = null;
      _linkError = null;
      _linkSummary = null;
    });
    final initial = _load(reset: true);
    Object? directoryError;
    Object? linkError;
    PendingEnrollmentLinkSummary? summary;
    var attemptedLink = false;
    try {
      await widget.repository.ensureStudentDirectoryEntry();
    } catch (error) {
      linkError = error;
      directoryError = error;
    }
    if (directoryError == null &&
        mounted &&
        widget.repository.currentUid == _sessionUid) {
      try {
        attemptedLink = true;
        summary = await widget.repository.linkOwnPendingEnrollments();
      } catch (error) {
        linkError = error;
      }
    }
    await initial;
    if (!mounted) return;
    final sameAccount = widget.repository.currentUid == _sessionUid;
    final mayHaveChangedCourses =
        attemptedLink &&
        (linkError != null ||
            (summary?.rows.any(
                  (row) =>
                      row.outcome != PendingEnrollmentLinkOutcome.needsReview,
                ) ??
                false));
    if (sameAccount && mayHaveChangedCourses) {
      await _load(reset: true);
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _publishing = false;
      if (widget.repository.currentUid == _sessionUid) {
        _directoryError = directoryError;
        _linkError = linkError;
        _linkSummary = summary;
      } else {
        _items.clear();
        _cursor = null;
        _hasMore = false;
      }
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_sessionUid == null ||
        widget.repository.currentUid != _sessionUid ||
        (_loading && !reset)) {
      return;
    }
    final epoch = ++_epoch;
    final requestCursor = reset ? null : _cursor;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listMyCourses(cursor: requestCursor);
      if (!mounted || epoch != _epoch) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() {
          _items.clear();
          _error = StateError('La sesión cambió.');
        });
        return;
      }
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = error;
          if (error is EnrollmentFailure &&
              const {
                EnrollmentFailureKind.permissionDenied,
                EnrollmentFailureKind.unauthenticated,
                EnrollmentFailureKind.emailNotVerified,
                EnrollmentFailureKind.profileInvalid,
                EnrollmentFailureKind.studentRoleRequired,
              }.contains(error.kind)) {
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

  Widget? _pendingLinkCard() {
    if (_linkError != null) {
      final directoryFailed = _directoryError != null;
      return CourseStateCard(
        title: directoryFailed
            ? 'No se pudo actualizar tu entrada para el curso'
            : 'No se comprobaron las inscripciones pendientes',
        message: directoryFailed
            ? '${enrollmentErrorMessage(_directoryError)} Las materias que ya tenías siguen disponibles.'
            : '${enrollmentErrorMessage(_linkError)} Tus materias actuales siguen disponibles.',
        color: AppColors.danger,
        action: OutlinedButton(
          onPressed: _refreshing ? null : _refresh,
          child: const Text('Reintentar comprobación'),
        ),
      );
    }
    final summary = _linkSummary;
    if (summary == null) return null;
    if (summary.studentCodeMissing) {
      return const CourseStateCard(
        title: 'Falta el código estudiantil del perfil',
        message: 'No se puede comprobar automáticamente una inscripción pendiente. Confirma el código con el docente y vuelve a actualizar.',
        color: AppColors.information,
        icon: Icons.info_outline,
      );
    }

    final messages = <String>[];
    if (summary.linked > 0) {
      messages.add(
        'Se vinculó ${summary.linked} ${summary.linked == 1 ? 'materia' : 'materias'}. Ya puedes verla en Mis materias.',
      );
    }
    if (summary.needsReview > 0) {
      messages.add(
        '${summary.needsReview} inscripción${summary.needsReview == 1 ? '' : 'es'} necesita${summary.needsReview == 1 ? '' : 'n'} revisión del docente.',
      );
    }
    if (summary.failed > 0) {
      messages.add(
        'No se pudo confirmar ${summary.failed} inscripción${summary.failed == 1 ? '' : 'es'}. Actualiza para volver a intentarlo.',
      );
    }
    if (summary.hasJoinRequestForTeacherReview) {
      messages.add(
        'Una solicitud previa de ingreso quedó pendiente de revisión del docente.',
      );
    }
    if (messages.isEmpty) return null;
    final hasProblem = summary.needsReview > 0 || summary.failed > 0;
    return CourseStateCard(
      title: hasProblem
          ? 'Hay inscripciones que requieren atención'
          : 'Inscripción confirmada',
      message: messages.join(' '),
      color: hasProblem ? AppColors.information : AppColors.primary,
      icon: hasProblem ? Icons.info_outline : Icons.check_circle_outline,
      action: hasProblem
          ? TextButton(
              onPressed: _refreshing ? null : _refresh,
              child: const Text('Reintentar'),
            )
          : null,
    );
  }

  Future<void> _openCourse(Enrollment enrollment) async {
    if (widget.repository.currentUid != _sessionUid) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StudentEnrolledCourseScreen(
          enrollment: enrollment,
          repository: widget.repository,
        ),
      ),
    );
  }

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
    final pendingLinkCard = _pendingLinkCard();
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
          onPressed: _loading || _refreshing ? null : _refresh,
          icon: _refreshing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          const CoursePageHeading(title: 'Tu semestre,\nen un solo lugar.'),
          const SizedBox(height: 16),
          if (_publishing)
            const CourseStateCard(
              title: 'Comprobando tu inscripción',
              message: 'Actualizando la entrada del perfil y buscando altas confirmadas por el docente.',
              color: AppColors.information,
              icon: Icons.sync,
            ),
          if (pendingLinkCard != null) ...[
            pendingLinkCard,
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _search,
            decoration: enrollmentInputDecoration(
              'Buscar materia',
              'Nombre o grupo entre los cursos cargados',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
          if (_loading && _items.isEmpty)
            const CourseLoading(message: 'Cargando tus materias…'),
          if (_error != null) ...[
            EnrollmentFailureCard(error: _error, onRetry: _refresh),
            const SizedBox(height: 16),
          ],
          if (!_loading && !_publishing && _error == null && _items.isEmpty)
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
          CourseSecondaryButton(
            label: 'Vincular otra materia',
            icon: Icons.key_outlined,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StudentCourseCodeScreen(
                  repository: CourseEntryRepositoryScope.read(context),
                  enrollmentRepository: widget.repository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Consultar solicitudes de ingreso',
            icon: Icons.assignment_outlined,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MyJoinRequestsScreen(
                  repository: CourseEntryRepositoryScope.read(context),
                  enrollmentRepository: widget.repository,
                ),
              ),
            ),
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
    extends State<StudentEnrolledCourseScreen>
    with WidgetsBindingObserver, RouteAware {
  late final String? _sessionUid;
  ModalRoute<void>? _subscribedRoute;
  Course? _course;
  Object? _error;
  bool _withdrawn = false;
  bool _loading = false;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionUid = widget.repository.currentUid;
    _load();
  }

  @override
  void didUpdateWidget(covariant StudentEnrolledCourseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enrollment.courseId == widget.enrollment.courseId &&
        identical(oldWidget.repository, widget.repository)) {
      return;
    }
    _loadEpoch++;
    _course = null;
    _withdrawn = false;
    _error = null;
    _loading = false;
    _load();
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
  void didPopNext() => _load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    aulaPresenteRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(() {
        _course = null;
        _error = const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
        _withdrawn = false;
      });
      return;
    }
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
      _withdrawn = false;
    });
    try {
      final course = await widget.repository.getMyEnrolledCourse(
        widget.enrollment.courseId,
      );
      if (mounted &&
          epoch == _loadEpoch &&
          widget.repository.currentUid == _sessionUid) {
        setState(() => _course = course);
      }
    } catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _course = null;
          _withdrawn =
              error is EnrollmentFailure &&
              error.kind == EnrollmentFailureKind.withdrawn;
          _error = _withdrawn ? null : error;
        });
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
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
          if (_loading && course != null)
            const CourseLoading(message: 'Comprobando el acceso al curso…'),
          if (_withdrawn)
            CourseStateCard(
              title: 'Tu inscripción fue retirada',
              message: 'El docente retiró tu acceso a esta materia. El registro y su historial se conservan; contacta al docente para solicitar una reincorporación.',
              color: AppColors.information,
              icon: Icons.info_outline,
              action: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Volver a mis materias'),
              ),
            ),
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
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CourseCalendarScreen(
                          course: course,
                          studentRepository: widget.repository,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            CourseSecondaryButton(
              label: 'Consultar asistencia',
              icon: Icons.fact_check_outlined,
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => StudentAttendanceScreen(
                          course: course,
                          repository: AttendanceRepositoryScope.read(context),
                        ),
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

class _StudentScheduleScreenState extends State<StudentScheduleScreen>
    with WidgetsBindingObserver, RouteAware {
  late final String? _sessionUid;
  ModalRoute<void>? _subscribedRoute;
  final List<Course> _courses = [];
  bool _loading = false;
  Object? _error;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionUid = widget.repository.currentUid;
    _load();
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
  void didPopNext() => _load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    aulaPresenteRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(() {
        _courses.clear();
        _error = const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      });
      return;
    }
    final epoch = ++_loadEpoch;
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
        if (!mounted || epoch != _loadEpoch) return;
        if (widget.repository.currentUid != _sessionUid) {
          throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
        }
        for (final item in page.items) {
          courses.add(
            await widget.repository.getMyEnrolledCourse(item.courseId),
          );
          if (!mounted || epoch != _loadEpoch) return;
          if (widget.repository.currentUid != _sessionUid) {
            throw const EnrollmentFailure(
              EnrollmentFailureKind.unauthenticated,
            );
          }
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      if (mounted &&
          epoch == _loadEpoch &&
          widget.repository.currentUid == _sessionUid) {
        setState(() {
          _courses
            ..clear()
            ..addAll(courses);
        });
      }
    } catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _courses.clear();
          _error = error;
        });
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
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
                    builder: (_) => CourseCalendarScreen(
                      course: slot.course,
                      studentRepository: widget.repository,
                    ),
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
                      builder: (_) => CourseCalendarScreen(
                        course: occurrence.course,
                        studentRepository: widget.repository,
                      ),
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
