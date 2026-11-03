import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/domain/auth_access.dart';
import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/planned_meeting.dart';
import '../../schedule/domain/planned_meeting_generator.dart';
import '../domain/course.dart';
import '../domain/course_creation_result.dart';
import '../domain/course_failure.dart';
import '../domain/course_repository.dart';
import 'course_creation_flow.dart';
import 'course_detail_screen.dart';
import 'course_presentation_components.dart';

typedef CourseClock = DateTime Function();

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({
    super.key,
    required this.repository,
    required this.access,
    required this.onOpenProfile,
    required this.onSignOut,
    this.clock,
  });

  final CourseRepository repository;
  final AuthAccess access;
  final VoidCallback onOpenProfile;
  final Future<void> Function() onSignOut;
  final CourseClock? clock;

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  late final CourseClock _clock;
  List<Course>? _courses;
  Object? _loadError;
  bool _loadingCourses = true;
  int _selectedTab = 0;
  bool _openingCreate = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _clock = widget.clock ?? () => DateTime.now().toUtc();
    unawaited(_fetchCourses());
  }

  void _reload() {
    setState(() {
      _loadingCourses = true;
      _loadError = null;
    });
    unawaited(_fetchCourses());
  }

  Future<void> _fetchCourses() async {
    if (mounted) {
      setState(() {
        _loadingCourses = true;
        _loadError = null;
      });
    }
    try {
      final courses = await widget.repository.getAllOwnCourses(pageSize: 25);
      if (!mounted) return;
      setState(() {
        _courses = List.unmodifiable(courses);
        _loadError = null;
        _loadingCourses = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadingCourses = false;
      });
    }
  }

  Future<void> _openCreateFlow() async {
    if (_openingCreate) return;
    setState(() => _openingCreate = true);
    try {
      final result = await Navigator.of(context).push<CourseCreationResult>(
        MaterialPageRoute<CourseCreationResult>(
          builder: (_) => CourseCreationFlow(repository: widget.repository),
        ),
      );
      if (!mounted || result == null) return;
      if (!courseCreationBelongsToSession(result, widget.access.uid)) {
        _showMessage(
          'El curso sí quedó creado en la cuenta que inició la operación, pero la sesión cambió. No lo abrimos con la cuenta actual y no repetimos la creación. Inicia sesión con la cuenta anterior para consultarlo.',
        );
        return;
      }
      // The repository's confirmed result is enough to open the detail. A
      // separate list refresh or detail read cannot turn a confirmed write
      // into a failed creation.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CourseDetailScreen(course: result.course),
        ),
      );
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _openingCreate = false);
    }
  }

  Future<void> _openCourse(Course course) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CourseDetailScreen(course: course),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _confirmSignOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres cerrar la sesión de esta cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        _showMessage('No pudimos cerrar sesión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final courses = _courses ?? const <Course>[];
    final title = switch (_selectedTab) {
      0 => 'Aula Presente',
      1 => 'Mis cursos',
      _ => 'Mi agenda docente',
    };
    return CoursePage(
      title: title,
      actions: [
        IconButton(
          tooltip: 'Abrir perfil docente',
          onPressed: widget.onOpenProfile,
          icon: const Icon(Icons.account_circle_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (value) {
            if (value == 'refresh') _reload();
            if (value == 'profile') widget.onOpenProfile();
            if (value == 'sign_out') _confirmSignOut();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'refresh', child: Text('Actualizar cursos')),
            PopupMenuItem(value: 'profile', child: Text('Perfil docente')),
            PopupMenuItem(value: 'sign_out', child: Text('Cerrar sesión')),
          ],
        ),
      ],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Cursos',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 1
          ? FloatingActionButton.extended(
              onPressed: _openingCreate ? null : _openCreateFlow,
              icon: _openingCreate
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('Crear un curso'),
            )
          : null,
      child: _buildBody(courses),
    );
  }

  Widget _buildBody(List<Course> courses) {
    if (_loadingCourses && _courses == null) {
      return const CourseLoading(message: 'Cargando tus cursos…');
    }
    if (_loadError != null && _courses == null) {
      return CourseContent(
        children: [
          const SizedBox(height: 48),
          CourseStateCard(
            title: 'No pudimos cargar tus cursos',
            message: _courseErrorMessage(_loadError),
            icon: Icons.cloud_off_outlined,
            color: AppColors.danger,
            action: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }
    final tabBody = switch (_selectedTab) {
      0 => _home(courses),
      1 => _courseList(courses),
      _ => _agenda(courses),
    };
    if (_loadingCourses || _loadError != null) {
      return Column(
        children: [
          if (_loadingCourses) const LinearProgressIndicator(minHeight: 2),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: CourseStateCard(
                title: 'No se pudo actualizar la lista',
                message:
                    '${_courseErrorMessage(_loadError)} Mostramos los cursos que ya estaban cargados; vuelve a intentarlo para consultar los cambios más recientes.',
                icon: Icons.cloud_off_outlined,
                color: AppColors.danger,
                action: OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ),
            ),
          Expanded(child: tabBody),
        ],
      );
    }
    return tabBody;
  }

  Widget _home(List<Course> courses) {
    final upcoming = _upcomingMeetings(courses, limit: 3);
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchCourses();
      },
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: 'Espacio docente',
            title: 'Hola, profe',
            description: _firstName(widget.access.name) == null
                ? 'Consulta tus cursos y encuentros previstos.'
                : '${_firstName(widget.access.name)}, consulta tus cursos y encuentros previstos.',
          ),
          const SizedBox(height: 20),
          CoursePanel(
            color: AppColors.glass.withValues(alpha: 0.72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CourseStatePill(
                  label: 'Cursos propios',
                  icon: Icons.verified_user_outlined,
                ),
                const SizedBox(height: 14),
                Text(
                  '${courses.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 36,
                    height: 44 / 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'cursos guardados en tu cuenta',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          CourseSectionHeading(
            title: 'Próximos encuentros previstos',
            trailing: TextButton(
              onPressed: () => setState(() => _selectedTab = 2),
              child: const Text('Ver agenda'),
            ),
          ),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            const CourseStateCard(
              title: 'Tu agenda está vacía',
              message: 'Cuando guardes cursos con un horario vigente aparecerán aquí sus encuentros previstos.',
              icon: Icons.event_available_outlined,
            )
          else
            ...upcoming.map(
              (meeting) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MeetingPreviewTile(
                  meeting: meeting,
                  course: _courseById(courses, meeting.courseId),
                  onTap: () {
                    final course = _courseById(courses, meeting.courseId);
                    if (course != null) _openCourse(course);
                  },
                ),
              ),
            ),
          const SizedBox(height: 14),
          CoursePrimaryButton(
            label: _openingCreate ? 'Abriendo…' : 'Crear un curso',
            icon: Icons.add,
            busy: _openingCreate,
            onPressed: _openCreateFlow,
          ),
          const SizedBox(height: 8),
          CourseSecondaryButton(
            label: 'Consultar mis cursos',
            icon: Icons.menu_book_outlined,
            onPressed: () => setState(() => _selectedTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _courseList(List<Course> courses) => _CourseListView(
    courses: courses,
    onOpenCourse: _openCourse,
    onCreateCourse: _openCreateFlow,
    loading: _openingCreate,
    onRefresh: () async {
      await _fetchCourses();
    },
  );

  Widget _agenda(List<Course> courses) {
    final meetings = _upcomingMeetings(courses, withinDays: 30);
    return CourseContent(
      children: [
        const CoursePageHeading(
          eyebrow: 'Calendario académico · America/Bogota',
          title: 'Mi agenda docente',
          description: 'Encuentros previstos para los próximos 30 días, calculados desde tus horarios guardados.',
        ),
        const SizedBox(height: 18),
        if (meetings.isEmpty)
          const CourseStateCard(
            title: 'No hay encuentros próximos',
            message: 'No encontramos encuentros previstos en los próximos 30 días. Tus cursos y horarios guardados permanecen disponibles en Mis cursos.',
            icon: Icons.event_busy_outlined,
          )
        else
          ...meetings.map((meeting) {
            final course = _courseById(courses, meeting.courseId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MeetingPreviewTile(
                meeting: meeting,
                course: course,
                onTap: course == null ? null : () => _openCourse(course),
              ),
            );
          }),
        const SizedBox(height: 10),
        const CourseStateCard(
          title: 'Solo consulta',
          message: 'La agenda todavía no abre asistencia ni permite reprogramar o cancelar encuentros.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }

  List<PlannedMeeting> _upcomingMeetings(
    List<Course> courses, {
    int? withinDays,
    int? limit,
  }) {
    final nowUtc = _clock().toUtc();
    // Bogotá has a fixed UTC-05:00 offset. Convert the instant into the
    // academic civil date without consulting the device's local zone.
    final bogota = nowUtc.subtract(const Duration(hours: 5));
    final today = AcademicDate(
      year: bogota.year,
      month: bogota.month,
      day: bogota.day,
    );
    final end = withinDays == null ? null : today.addDays(withinDays);
    final meetings = <PlannedMeeting>[];
    for (final course in courses) {
      for (final meeting in generatePlannedMeetings(
        courseId: course.id,
        schedule: course.schedule,
      )) {
        if (meeting.date.compareTo(today) < 0) continue;
        if (end != null && meeting.date.compareTo(end) > 0) continue;
        meetings.add(meeting);
      }
    }
    meetings.sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      if (byDate != 0) return byDate;
      final byTime = left.startMinutes.compareTo(right.startMinutes);
      if (byTime != 0) return byTime;
      final byCourse = left.courseId.compareTo(right.courseId);
      if (byCourse != 0) return byCourse;
      return left.blockId.compareTo(right.blockId);
    });
    if (limit != null && meetings.length > limit) {
      return meetings.take(limit).toList(growable: false);
    }
    return meetings;
  }

  Course? _courseById(List<Course> courses, String id) {
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }
}

class _CourseListView extends StatefulWidget {
  const _CourseListView({
    required this.courses,
    required this.onOpenCourse,
    required this.onCreateCourse,
    required this.loading,
    required this.onRefresh,
  });

  final List<Course> courses;
  final ValueChanged<Course> onOpenCourse;
  final VoidCallback onCreateCourse;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  State<_CourseListView> createState() => _CourseListViewState();
}

class _CourseListViewState extends State<_CourseListView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.courses
        .where((course) {
          if (_query.isEmpty) return true;
          final searchable =
              '${course.subject} ${course.group} ${course.period} ${course.program}'
                  .toLowerCase();
          return searchable.contains(_query.toLowerCase());
        })
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CourseContent(
        children: [
          const CoursePageHeading(
            eyebrow: 'Espacio docente',
            title: 'Mis cursos',
            description: 'Consulta cursos creados desde tu cuenta docente.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value.trim()),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar curso',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty && widget.courses.isEmpty)
            CourseStateCard(
              title: 'Aún no tienes cursos',
              message: 'Crea un curso para definir su período y los días y horas de clase.',
              icon: Icons.menu_book_outlined,
              action: OutlinedButton.icon(
                onPressed: widget.loading ? null : widget.onCreateCourse,
                icon: const Icon(Icons.add),
                label: const Text('Crear un curso'),
              ),
            )
          else if (filtered.isEmpty)
            CourseStateCard(
              title: 'No encontramos coincidencias',
              message: 'Prueba con otra asignatura, grupo, período o programa.',
              icon: Icons.search_off_outlined,
            )
          else ...[
            CourseSectionHeading(
              title:
                  '${filtered.length} ${filtered.length == 1 ? 'curso' : 'cursos'}',
            ),
            const SizedBox(height: 10),
            ...filtered.map(
              (course) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CourseTile(
                  course: course,
                  onTap: () => widget.onOpenCourse(course),
                ),
              ),
            ),
          ],
          const SizedBox(height: 88),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course, required this.onTap});

  final Course course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: CoursePanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      height: 23 / 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Grupo ${course.group} · ${course.period}',
                    softWrap: true,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 19 / 13,
                    ),
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
  );
}

class _MeetingPreviewTile extends StatelessWidget {
  const _MeetingPreviewTile({
    required this.meeting,
    required this.course,
    required this.onTap,
  });

  final PlannedMeeting meeting;
  final Course? course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: CoursePanel(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_note_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course?.subject ?? 'Curso',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_weekdayName(meeting.weekday)} ${_dateLabel(meeting.date)} · ${meeting.startTime}–${meeting.endTime}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 20 / 13,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Encuentro previsto',
                    style: TextStyle(
                      color: AppColors.information,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ],
        ),
      ),
    ),
  );
}

String _courseErrorMessage(Object? error) {
  if (error is CourseFailure) {
    return switch (error.kind) {
      CourseFailureKind.unauthenticated =>
        'Tu sesión terminó. Inicia sesión otra vez para consultar tus cursos.',
      CourseFailureKind.emailNotVerified =>
        'Verifica tu correo para consultar tus cursos.',
      CourseFailureKind.profileInvalid =>
        'No pudimos confirmar tu perfil docente.',
      CourseFailureKind.teacherRoleRequired =>
        'Esta cuenta ya no tiene permiso docente para consultar cursos.',
      CourseFailureKind.permissionDenied => 'Firestore rechazó la consulta por permisos. Comprueba tu rol y las reglas publicadas.',
      CourseFailureKind.network =>
        'Revisa tu conexión y vuelve a cargar la lista.',
      CourseFailureKind.idempotencyConflict =>
        'El identificador de esta creación ya está asociado a otros datos.',
      CourseFailureKind.invalidCourse =>
        'Un curso guardado no tiene el formato esperado.',
      CourseFailureKind.unknown =>
        'No pudimos completar la consulta. Inténtalo de nuevo.',
    };
  }
  return 'Revisa tu conexión e inténtalo de nuevo.';
}

/// A confirmed write may return after Authentication changed. The result's
/// captured owner is checked before routing so it is never opened under a
/// different account.
bool courseCreationBelongsToSession(
  CourseCreationResult result,
  String? activeUid,
) =>
    activeUid != null &&
    activeUid.isNotEmpty &&
    result.course.ownerUid == activeUid;

String? _firstName(String? value) {
  final name = value?.trim();
  if (name == null || name.isEmpty) return null;
  return name.split(RegExp(r'\s+')).first;
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

String _dateLabel(AcademicDate date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
