import 'package:flutter/material.dart';

import '../../../app/course_entry_repository_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../course_entry/presentation/course_invitation_screens.dart';
import '../../course_entry/presentation/teacher_join_request_screens.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../excel_import/presentation/excel_import_screen.dart';
import '../application/enrollment_validator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
import '../domain/enrollment_status_change.dart';
import '../domain/student_candidate.dart';
import 'enrollment_components.dart';

class TeacherEnrollmentHubScreen extends StatefulWidget {
  const TeacherEnrollmentHubScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final EnrollmentRepository repository;

  @override
  State<TeacherEnrollmentHubScreen> createState() =>
      _TeacherEnrollmentHubScreenState();
}

class _TeacherEnrollmentHubScreenState
    extends State<TeacherEnrollmentHubScreen> {
  int? _count;
  Object? _error;
  bool _loading = false;
  int _countEpoch = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final epoch = ++_countEpoch;
    setState(() {
      _loading = true;
      _error = null;
      _count = null;
    });
    try {
      final count = await widget.repository.countCourseStudents(
        widget.course.id,
      );
      if (mounted && epoch == _countEpoch) {
        setState(() {
          _count = count;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && epoch == _countEpoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _countEpoch) setState(() => _loading = false);
    }
  }

  Future<void> _openStudents() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CourseStudentsScreen(
          course: widget.course,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openWithdrawnStudents() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CourseStudentsScreen(
          course: widget.course,
          repository: widget.repository,
          status: 'withdrawn',
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddStudentScreen(
          course: widget.course,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openExcelImport() async {
    final openStudents = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ExcelImportScreen(
          course: widget.course,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    if (openStudents == true) {
      await _openStudents();
    } else {
      _refresh();
    }
  }

  Future<void> _openInvitation() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => CourseInvitationScreen(
        course: widget.course,
        repository: CourseEntryRepositoryScope.read(context),
      ),
    ),
  );

  Future<void> _openJoinRequests() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TeacherJoinRequestsScreen(
        course: widget.course,
        repository: CourseEntryRepositoryScope.read(context),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      widget.repository.currentUid != widget.course.ownerUid
      ? const CoursePage(
          title: 'Gestionar estudiantes',
          child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
        )
      : CoursePage(
          title: 'Gestionar estudiantes',
          leading: IconButton(
            tooltip: 'Volver al curso',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          child: CourseContent(
            children: [
              const CoursePageHeading(title: 'Tu grupo, al día.'),
              const SizedBox(height: 8),
              Text(
                '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              CoursePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading && _count == null)
                      const LinearProgressIndicator(),
                    if (_count != null)
                      Text(
                        '$_count',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      _count == null
                          ? 'Inscritos: cantidad pendiente'
                          : 'Estudiantes inscritos',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                EnrollmentFailureCard(error: _error, onRetry: _refresh),
              ],
              const SizedBox(height: 16),
              EnrollmentTile(
                title: 'Importar Excel',
                subtitle: 'Revisar coincidencias y confirmar altas',
                iconAsset: 'bcab7.svg',
                onTap: _openExcelImport,
              ),
              EnrollmentTile(
                title: 'Agregar estudiante',
                subtitle: 'Correo conocido y código opcional',
                iconAsset: '19383.svg',
                onTap: _openAdd,
              ),
              EnrollmentTile(
                title: 'Invitar a mi curso',
                subtitle: 'Código temporal · aprobación docente',
                iconAsset: '9c45e.svg',
                onTap: _openInvitation,
              ),
              EnrollmentTile(
                title: 'Solicitudes',
                subtitle: 'Revisa y decide ingresos pendientes',
                iconAsset: '19383.svg',
                onTap: _openJoinRequests,
              ),
              EnrollmentTile(
                title: 'Lista de estudiantes',
                subtitle: 'Inscritos actuales del curso',
                iconAsset: '19383.svg',
                onTap: _openStudents,
              ),
              EnrollmentTile(
                title: 'Retirados e histórico',
                subtitle: 'Consulta retiros y reincorporaciones',
                iconAsset: '19383.svg',
                onTap: _openWithdrawnStudents,
              ),
            ],
          ),
        );
}

class CourseStudentsScreen extends StatefulWidget {
  const CourseStudentsScreen({
    super.key,
    required this.course,
    required this.repository,
    this.status = 'active',
  });

  final Course course;
  final EnrollmentRepository repository;
  final String status;

  bool get showingWithdrawn => status == 'withdrawn';

  @override
  State<CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<CourseStudentsScreen> {
  final _search = TextEditingController();
  final List<Enrollment> _items = [];
  EnrollmentCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Enrollment> get _visibleItems {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((enrollment) {
      final searchable =
          '${enrollment.name} ${enrollment.email} ${enrollment.studentCode ?? ''}'
              .toLowerCase();
      return searchable.contains(query);
    }).toList();
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
      final page = await widget.repository.listCourseStudents(
        courseId: widget.course.id,
        status: widget.status,
        cursor: _cursor,
      );
      if (!mounted || epoch != _epoch) return;
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

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddStudentScreen(
          course: widget.course,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted && saved == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) =>
      widget.repository.currentUid != widget.course.ownerUid
      ? CoursePage(
          title: widget.showingWithdrawn
              ? 'Retirados e histórico'
              : 'Estudiantes del curso',
          child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
        )
      : CoursePage(
          title: widget.showingWithdrawn
              ? 'Retirados e histórico'
              : 'Estudiantes del curso',
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Actualizar estudiantes',
              onPressed: _loading ? null : () => _load(reset: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
          child: CourseContent(
            children: [
              CoursePageHeading(
                title: widget.showingWithdrawn
                    ? 'Retiros e historial.'
                    : 'Tu lista de estudiantes.',
                description: widget.showingWithdrawn
                    ? 'Las decisiones anteriores se conservan en la matrícula.'
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.course.subject} · ${widget.course.group}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                decoration: enrollmentInputDecoration(
                  'Buscar estudiante',
                  'Nombre, correo o código entre los cargados',
                ).copyWith(prefixIcon: const Icon(Icons.search)),
              ),
              const SizedBox(height: 20),
              if (_loading && _items.isEmpty)
                const CourseLoading(message: 'Cargando estudiantes…'),
              if (_error != null)
                EnrollmentFailureCard(
                  error: _error,
                  onRetry: () => _load(reset: _items.isEmpty),
                ),
              if (!_loading && _error == null && _items.isEmpty)
                const CourseStateCard(
                  title: 'Aún no hay estudiantes en esta lista',
                  message: 'Los retiros conservan la inscripción y su historial. Puedes volver a esta lista después de una reincorporación.',
                  icon: Icons.group_outlined,
                ),
              if (_search.text.trim().isNotEmpty &&
                  _visibleItems.isEmpty &&
                  _items.isNotEmpty)
                const CourseStateCard(
                  title: 'Sin coincidencias cargadas',
                  message: 'Comprueba el nombre, correo o código, o carga más estudiantes.',
                ),
              for (final enrollment in _visibleItems)
                EnrollmentTile(
                  title: enrollment.name,
                  subtitle: widget.showingWithdrawn
                      ? 'Retirado · ${enrollment.email}'
                      : 'Datos al inscribir · ${enrollment.email}${enrollment.studentCode == null ? '' : ' · ${enrollment.studentCode}'}',
                  iconAsset: 'df818.svg',
                  onTap: () => Navigator.of(context)
                      .push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => StudentEnrollmentDetailScreen(
                            course: widget.course,
                            enrollment: enrollment,
                            repository: widget.repository,
                          ),
                        ),
                      )
                      .then((changed) {
                        if (mounted && changed == true) {
                          _load(reset: true);
                        }
                      }),
                ),
              if (_hasMore && _items.isNotEmpty)
                CourseSecondaryButton(
                  label: _loading ? 'Cargando…' : 'Cargar más estudiantes',
                  onPressed: _loading ? null : () => _load(),
                ),
              const SizedBox(height: 16),
              if (!widget.showingWithdrawn) ...[
                CoursePrimaryButton(
                  label: 'Agregar estudiante',
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: _add,
                ),
                const SizedBox(height: 12),
                CourseSecondaryButton(
                  label: 'Retirados e histórico',
                  icon: Icons.history,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CourseStudentsScreen(
                        course: widget.course,
                        repository: widget.repository,
                        status: 'withdrawn',
                      ),
                    ),
                  ),
                ),
              ] else ...[
                CourseSecondaryButton(
                  label: 'Volver a estudiantes activos',
                  icon: Icons.group_outlined,
                  onPressed: () =>
                      Navigator.of(context).pushReplacement<void, void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CourseStudentsScreen(
                            course: widget.course,
                            repository: widget.repository,
                          ),
                        ),
                      ),
                ),
              ],
            ],
          ),
        );
}

class StudentEnrollmentDetailScreen extends StatelessWidget {
  const StudentEnrollmentDetailScreen({
    super.key,
    required this.course,
    required this.enrollment,
    required this.repository,
  });

  final Course course;
  final Enrollment enrollment;
  final EnrollmentRepository repository;

  Future<void> _openStatusChange(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EnrollmentStatusChangeScreen(
          course: course,
          expected: enrollment,
          repository: repository,
        ),
      ),
    );
    if (context.mounted && changed == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = enrollment.status == 'active';
    return CoursePage(
      title: 'Ficha del estudiante',
      leading: IconButton(
        tooltip: 'Volver a estudiantes',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          CoursePageHeading(
            eyebrow: isActive ? 'Inscripción activa' : 'Inscripción retirada',
            title: enrollment.name,
            description:
                '${course.subject} · ${course.group} · ${course.period}',
          ),
          const SizedBox(height: 20),
          CoursePanel(
            color: AppColors.glass.withValues(alpha: 0.62),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Datos al inscribir',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  enrollment.email,
                  style: const TextStyle(color: AppColors.text),
                ),
                if (enrollment.studentCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Código ${enrollment.studentCode}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
                if (enrollment.createdAt != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Inscrito el ${_enrollmentDate(enrollment.createdAt!)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
                if (enrollment.lastStatusChangedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${isActive ? 'Reincorporado' : 'Retirado'} el ${_enrollmentDate(enrollment.lastStatusChangedAt!)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          CourseStateCard(
            title: isActive ? 'Inscripción del curso' : 'Historial conservado',
            message: isActive
                ? 'El retiro afecta únicamente esta materia. El curso, su horario y los otros estudiantes permanecen iguales.'
                : 'La inscripción original y las decisiones anteriores se conservan. Reincorporar vuelve a habilitar el acceso a esta materia.',
            icon: isActive ? Icons.info_outline : Icons.history,
          ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: 'Ver historial de inscripción',
            icon: Icons.history,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => EnrollmentHistoryScreen(
                  course: course,
                  enrollment: enrollment,
                  repository: repository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isActive)
            CoursePrimaryButton(
              label: 'Retirar del curso',
              icon: Icons.person_remove_outlined,
              onPressed: () => _openStatusChange(context),
            )
          else
            CoursePrimaryButton(
              label: 'Reincorporar al curso',
              icon: Icons.person_add_alt_1_outlined,
              onPressed: () => _openStatusChange(context),
            ),
        ],
      ),
    );
  }
}

class EnrollmentStatusChangeScreen extends StatefulWidget {
  const EnrollmentStatusChangeScreen({
    super.key,
    required this.course,
    required this.expected,
    required this.repository,
  });

  final Course course;
  final Enrollment expected;
  final EnrollmentRepository repository;

  @override
  State<EnrollmentStatusChangeScreen> createState() =>
      _EnrollmentStatusChangeScreenState();
}

class _EnrollmentStatusChangeScreenState
    extends State<EnrollmentStatusChangeScreen> {
  late final String? _sessionUid = widget.repository.currentUid;
  late final String _operationId = widget.repository.newStatusEventId(
    courseId: widget.expected.courseId,
    studentUid: widget.expected.studentUid,
  );
  bool _busy = false;
  bool _sessionChanged = false;
  EnrollmentStatusChangeResult? _result;
  Object? _error;

  bool get _isWithdrawal => widget.expected.status == 'active';
  String get _nextStatus => _isWithdrawal ? 'withdrawn' : 'active';

  Future<void> _confirm() async {
    if (_busy || _result != null) return;
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      setState(
        () => _error = const EnrollmentFailure(
          EnrollmentFailureKind.unauthenticated,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.changeEnrollmentStatus(
        expected: widget.expected,
        nextStatus: _nextStatus,
        operationId: _operationId,
      );
      if (!mounted) return;
      if (widget.repository.currentUid != _sessionUid) {
        setState(() => _sessionChanged = true);
      } else {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _returnToStudents() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    if (_sessionUid == null || widget.repository.currentUid != _sessionUid) {
      return const CoursePage(
        title: 'Confirmar cambio',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final result = _result;
    if (_sessionChanged) {
      return CoursePage(
        title: 'Sesión cambiada',
        child: CourseContent(
          children: [
            const CoursePageHeading(title: 'La sesión cambió.'),
            const SizedBox(height: 16),
            const CourseStateCard(
              title: 'Cambio confirmado en la cuenta anterior',
              message: 'La escritura fue confirmada por el servidor antes de cambiar de sesión. Inicia sesión con la cuenta docente del curso para volver a consultar el resultado; no repitas la acción.',
            ),
            const SizedBox(height: 20),
            CourseSecondaryButton(
              label: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      );
    }
    if (result != null) {
      final withdrawal = result.enrollment.status == 'withdrawn';
      return CoursePage(
        title: withdrawal ? 'Retiro confirmado' : 'Reincorporación confirmada',
        child: CourseContent(
          children: [
            CoursePageHeading(
              title: withdrawal
                  ? 'Estudiante retirado.'
                  : 'Reincorporación confirmada.',
            ),
            const SizedBox(height: 16),
            EnrollmentTile(
              title: result.enrollment.name,
              subtitle:
                  '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
              iconAsset: 'df818.svg',
            ),
            const SizedBox(height: 12),
            CourseStateCard(
              title: result.alreadyApplied
                  ? 'Cambio ya confirmado'
                  : 'Historial actualizado',
              message: withdrawal
                  ? 'El acceso del estudiante a esta materia fue retirado. La inscripción y el horario del curso se conservaron.'
                  : 'El acceso a esta materia está activo otra vez. Se conservó la fecha de inscripción original y el historial del retiro.',
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 20),
            CoursePrimaryButton(
              label: 'Ver estudiantes',
              onPressed: _returnToStudents,
            ),
          ],
        ),
      );
    }
    final permissionDenied =
        _error is EnrollmentFailure &&
        (_error as EnrollmentFailure).kind ==
            EnrollmentFailureKind.permissionDenied;
    final stale =
        _error is EnrollmentFailure &&
        (_error as EnrollmentFailure).kind ==
            EnrollmentFailureKind.staleEnrollment;
    return CoursePage(
      title: _isWithdrawal ? 'Retirar estudiante' : 'Reincorporar estudiante',
      leading: IconButton(
        tooltip: 'Volver a la ficha',
        onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: CourseContent(
        children: [
          CoursePageHeading(
            title: _isWithdrawal
                ? '¿Retirar a este estudiante del curso?'
                : '¿Reincorporar a este estudiante?',
          ),
          const SizedBox(height: 16),
          EnrollmentTile(
            title: widget.expected.name,
            subtitle:
                '${widget.expected.email}${widget.expected.studentCode == null ? '' : ' · ${widget.expected.studentCode}'}',
            iconAsset: 'df818.svg',
          ),
          CoursePanel(
            child: Text(
              '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
              style: const TextStyle(color: AppColors.text),
            ),
          ),
          const SizedBox(height: 12),
          CoursePanel(
            color: AppColors.glass.withValues(alpha: 0.62),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_available_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Al confirmar',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isWithdrawal
                            ? 'El servidor registrará la fecha efectiva del retiro al confirmar.'
                            : 'El servidor registrará la fecha efectiva del nuevo ingreso al confirmar.',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CourseStateCard(
            title: _isWithdrawal
                ? 'Retiro de este curso'
                : 'Historial preservado',
            message: _isWithdrawal
                ? 'El retiro quita el acceso de este estudiante a la materia. No borra la inscripción ni modifica el curso o su horario.'
                : 'La reincorporación restaura el acceso a esta materia, conserva la fecha de ingreso original y registra un nuevo evento.',
            icon: Icons.info_outline,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            CourseStateCard(
              title: stale
                  ? 'La inscripción cambió'
                  : permissionDenied
                  ? 'No tienes permiso para completar esta operación'
                  : 'No se confirmó el cambio',
              message: stale
                  ? 'Otro cambio modificó esta inscripción. No repetimos la decisión; vuelve a la lista y consulta el estado actual.'
                  : permissionDenied
                  ? 'Firestore rechazó el cambio. Comprueba que sigues siendo docente de este curso y que las reglas publicadas permiten la operación.'
                  : enrollmentErrorMessage(_error, uncertainWrite: true),
              color: AppColors.danger,
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || stale ? null : _confirm,
              style: _isWithdrawal
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: AppColors.background,
                    )
                  : null,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isWithdrawal
                          ? Icons.person_remove_outlined
                          : Icons.check,
                    ),
              label: Text(
                _busy
                    ? 'Guardando…'
                    : _isWithdrawal
                    ? 'Confirmar retiro'
                    : 'Confirmar reincorporación',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          CourseSecondaryButton(
            label: _busy ? 'Procesando…' : 'Conservar inscripción',
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class EnrollmentHistoryScreen extends StatefulWidget {
  const EnrollmentHistoryScreen({
    super.key,
    required this.course,
    required this.enrollment,
    required this.repository,
  });

  final Course course;
  final Enrollment enrollment;
  final EnrollmentRepository repository;

  @override
  State<EnrollmentHistoryScreen> createState() =>
      _EnrollmentHistoryScreenState();
}

class _EnrollmentHistoryScreenState extends State<EnrollmentHistoryScreen> {
  final List<EnrollmentStatusEvent> _events = [];
  EnrollmentHistoryCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final epoch = ++_epoch;
    if (reset) {
      _events.clear();
      _cursor = null;
      _hasMore = true;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listEnrollmentHistory(
        courseId: widget.course.id,
        studentUid: widget.enrollment.studentUid,
        cursor: _cursor,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _events.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => CoursePage(
    title: 'Historial de inscripción',
    leading: IconButton(
      tooltip: 'Volver a la ficha',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back),
    ),
    actions: [
      IconButton(
        tooltip: 'Actualizar historial',
        onPressed: _loading ? null : () => _load(reset: true),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: CourseContent(
      children: [
        CoursePageHeading(
          title: 'Cambios de ${widget.enrollment.name}.',
          description:
              '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
        ),
        const SizedBox(height: 16),
        CourseStateCard(
          title: 'Historial de solo consulta',
          message: 'Cada evento refleja una transición confirmada por el servidor. Ninguna entrada de esta lista se puede editar o eliminar.',
          icon: Icons.history,
        ),
        const SizedBox(height: 12),
        if (_loading && _events.isEmpty)
          const CourseLoading(message: 'Cargando historial…'),
        if (_error != null)
          EnrollmentFailureCard(
            error: _error,
            onRetry: () => _load(reset: _events.isEmpty),
          ),
        if (!_loading && _error == null && _events.isEmpty)
          const CourseStateCard(
            title: 'Todavía no hay cambios de estado',
            message:
                'La inscripción no ha registrado retiros ni reincorporaciones.',
            icon: Icons.event_note_outlined,
          ),
        for (final event in _events)
          EnrollmentTile(
            title: event.toStatus == 'withdrawn'
                ? 'Retiro confirmado'
                : 'Reincorporación confirmada',
            subtitle:
                '${_enrollmentDateTime(event.changedAt)} · ${event.fromStatus == 'active' ? 'Activo' : 'Retirado'} → ${event.toStatus == 'active' ? 'Activo' : 'Retirado'}',
            iconAsset: event.toStatus == 'withdrawn'
                ? 'df818.svg'
                : '51a24.svg',
          ),
        if (!_hasMore && widget.enrollment.createdAt != null)
          EnrollmentTile(
            title: 'Ingreso registrado',
            subtitle:
                '${_enrollmentDateTime(widget.enrollment.createdAt!)} · Inicio de la inscripción',
            iconAsset: '51a24.svg',
          ),
        if (_hasMore && _events.isNotEmpty)
          CourseSecondaryButton(
            label: _loading ? 'Cargando…' : 'Cargar más historial',
            onPressed: _loading ? null : () => _load(),
          ),
      ],
    ),
  );
}

String _enrollmentDate(DateTime value) {
  final local = _academicLocal(value);
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _enrollmentDateTime(DateTime value) {
  final local = _academicLocal(value);
  return '${_enrollmentDate(value)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Academic timestamps are displayed in Colombia's UTC-5 timezone regardless
/// of the device timezone. Colombia does not observe daylight saving time.
DateTime _academicLocal(DateTime value) =>
    value.toUtc().subtract(const Duration(hours: 5));

enum _AddStep { form, review, conflict, confirmed, sessionChanged }

class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final EnrollmentRepository repository;

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  _AddStep _step = _AddStep.form;
  StudentCandidate? _candidate;
  EnrollmentResult? _result;
  bool _busy = false;
  Object? _error;
  int _queryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _email.addListener(_invalidateSelection);
    _code.addListener(_invalidateSelection);
  }

  void _invalidateSelection() {
    _queryGeneration++;
    if (_step != _AddStep.form && _step != _AddStep.confirmed) {
      setState(() {
        _candidate = null;
        _step = _AddStep.form;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_busy) return;
    final generation = _queryGeneration;
    String email;
    try {
      email = EnrollmentValidator.exactEmail(_email.text);
    } on EnrollmentFailure catch (error) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _candidate = null;
    });
    try {
      final candidate = await widget.repository.findStudentByEmail(email);
      if (!mounted || generation != _queryGeneration) return;
      if (candidate == null) {
        setState(
          () => _error = const EnrollmentFailure(
            EnrollmentFailureKind.courseUnavailable,
          ),
        );
        return;
      }
      if (_code.text.trim().isNotEmpty &&
          candidate.studentCode != _code.text.trim()) {
        setState(() => _step = _AddStep.conflict);
        return;
      }
      setState(() {
        _candidate = candidate;
        _step = _AddStep.review;
      });
    } catch (error) {
      if (mounted && generation == _queryGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _candidate == null) return;
    final candidate = _candidate!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.enrollStudent(
        courseId: widget.course.id,
        candidate: candidate,
      );
      if (!mounted) return;
      if (result.enrollment.ownerUid != widget.course.ownerUid ||
          widget.repository.currentUid != widget.course.ownerUid) {
        setState(() {
          _candidate = null;
          _result = null;
          _step = _AddStep.sessionChanged;
        });
        return;
      }
      setState(() {
        _result = result;
        _step = _AddStep.confirmed;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWithdrawnEnrollment() async {
    final result = _result;
    if (result == null || result.enrollment.status != 'withdrawn') return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StudentEnrollmentDetailScreen(
          course: widget.course,
          enrollment: result.enrollment,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted && changed == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) =>
      widget.repository.currentUid != widget.course.ownerUid &&
          _step != _AddStep.sessionChanged
      ? const CoursePage(
          title: 'Agregar estudiante',
          child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
        )
      : CoursePage(
          title: switch (_step) {
            _AddStep.form => 'Agregar estudiante',
            _AddStep.review || _AddStep.conflict => 'Revisar coincidencia',
            _AddStep.confirmed => 'Inscripción confirmada',
            _AddStep.sessionChanged => 'Sesión cambiada',
          },
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: _busy
                ? null
                : () {
                    if (_step == _AddStep.review ||
                        _step == _AddStep.conflict) {
                      setState(() {
                        _step = _AddStep.form;
                        _candidate = null;
                        _error = null;
                      });
                    } else {
                      Navigator.of(context).pop(_step == _AddStep.confirmed);
                    }
                  },
            icon: const Icon(Icons.arrow_back),
          ),
          child: CourseContent(
            children: switch (_step) {
              _AddStep.form => _form(),
              _AddStep.review => _review(),
              _AddStep.conflict => _conflict(),
              _AddStep.confirmed => _confirmed(),
              _AddStep.sessionChanged => _sessionChanged(),
            },
          ),
        );

  List<Widget> _form() => [
    const CoursePageHeading(title: 'Incorpora a tu estudiante.'),
    const SizedBox(height: 16),
    TextField(
      controller: _email,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      decoration: enrollmentInputDecoration(
        'Correo institucional',
        'Correo exacto de la cuenta',
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _code,
      enabled: !_busy,
      textInputAction: TextInputAction.done,
      decoration: enrollmentInputDecoration(
        'Código estudiantil (opcional)',
        'Si lo conoces, conserva los ceros',
      ),
    ),
    const SizedBox(height: 16),
    const CourseStateCard(
      title: 'Comprobación de identidad',
      message: 'El nombre se obtiene de la cuenta encontrada. El código, si lo escribes, debe coincidir exactamente. Solo se inscriben cuentas existentes.',
    ),
    if (_error != null) ...[
      const SizedBox(height: 16),
      CourseStateCard(
        title: 'No se encontró una cuenta apta',
        message:
            _error is EnrollmentFailure &&
                (_error as EnrollmentFailure).kind ==
                    EnrollmentFailureKind.courseUnavailable
            ? 'Pide al estudiante que verifique su correo y abra Mis materias en esta versión. Luego vuelve a buscarlo.'
            : enrollmentErrorMessage(_error),
        color: AppColors.danger,
      ),
    ],
    const SizedBox(height: 20),
    CoursePrimaryButton(
      label: _busy ? 'Buscando…' : 'Comprobar y agregar',
      icon: Icons.check,
      busy: _busy,
      onPressed: _busy ? null : _find,
    ),
  ];

  List<Widget> _review() {
    final candidate = _candidate!;
    return [
      const CoursePageHeading(
        title: 'Revisa a quién agregarás.',
        description: 'Confirma los datos de la cuenta antes de inscribirla.',
      ),
      const SizedBox(height: 20),
      EnrollmentTile(
        title: candidate.name,
        subtitle:
            '${candidate.email}${candidate.studentCode == null ? '' : ' · ${candidate.studentCode}'}',
        iconAsset: 'df818.svg',
      ),
      CoursePanel(
        child: Text(
          '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
          style: const TextStyle(color: AppColors.text),
        ),
      ),
      const SizedBox(height: 16),
      const CourseStateCard(
        title: 'Ingreso efectivo',
        message: 'Se registrará la fecha del servidor al confirmar. No se crean faltas por clases previas.',
        icon: Icons.info_outline,
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        CourseStateCard(
          title: 'No se confirmó la inscripción',
          message: enrollmentErrorMessage(_error, uncertainWrite: true),
          color: AppColors.danger,
        ),
        if (_error is EnrollmentFailure &&
            (_error as EnrollmentFailure).kind ==
                EnrollmentFailureKind.network) ...[
          const SizedBox(height: 10),
          CourseSecondaryButton(
            label: 'Consultar estudiantes',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ],
      const SizedBox(height: 20),
      CoursePrimaryButton(
        label: _busy ? 'Inscribiendo…' : 'Confirmar inscripción',
        icon: Icons.check,
        busy: _busy,
        onPressed: _busy ? null : _confirm,
      ),
      const SizedBox(height: 12),
      CourseSecondaryButton(
        label: 'Corregir datos',
        onPressed: _busy
            ? null
            : () => setState(() {
                _candidate = null;
                _step = _AddStep.form;
                _error = null;
              }),
      ),
    ];
  }

  List<Widget> _conflict() => [
    const CoursePageHeading(title: 'Estos datos no coinciden.'),
    const SizedBox(height: 20),
    const CourseStateCard(
      title: 'Código y correo diferentes',
      message: 'No se vincula por nombre ni se modifica otra cuenta automáticamente. Confirma los datos con el estudiante.',
      color: AppColors.danger,
    ),
    const SizedBox(height: 20),
    CoursePrimaryButton(
      label: 'Corregir datos',
      onPressed: () => setState(() => _step = _AddStep.form),
    ),
  ];

  List<Widget> _confirmed() {
    final result = _result!;
    if (result.enrollment.status == 'withdrawn') {
      return [
        const CoursePageHeading(title: 'La inscripción está retirada.'),
        const SizedBox(height: 20),
        EnrollmentTile(
          title: result.enrollment.name,
          subtitle:
              '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
          iconAsset: 'df818.svg',
        ),
        const SizedBox(height: 12),
        const CourseStateCard(
          title: 'No se creó otra matrícula',
          message: 'Esta cuenta ya tiene un registro histórico para el curso. El docente puede revisar el historial y reincorporarla; no se creó un duplicado ni se cambió su estado automáticamente.',
        ),
        const SizedBox(height: 20),
        CoursePrimaryButton(
          label: 'Revisar e inscribir de nuevo',
          onPressed: _openWithdrawnEnrollment,
        ),
        const SizedBox(height: 12),
        CourseSecondaryButton(
          label: 'Volver a estudiantes',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ];
    }
    return [
      CoursePageHeading(
        title: result.alreadyEnrolled
            ? 'Ya estaba inscrito.'
            : 'Inscripción confirmada.',
      ),
      const SizedBox(height: 20),
      EnrollmentTile(
        title: result.enrollment.name,
        subtitle:
            '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
        iconAsset: '51a24.svg',
      ),
      const SizedBox(height: 16),
      CoursePrimaryButton(
        label: 'Ver estudiantes',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ];
  }

  List<Widget> _sessionChanged() => [
    const CoursePageHeading(title: 'La sesión cambió.'),
    const SizedBox(height: 20),
    const CourseStateCard(
      title: 'Guardado confirmado en la cuenta anterior',
      message: 'La inscripción quedó guardada para la cuenta docente que inició la operación. Inicia sesión con esa cuenta para consultarla; no repitas el agregado desde esta sesión.',
    ),
    const SizedBox(height: 20),
    CourseSecondaryButton(
      label: 'Volver',
      onPressed: () => Navigator.of(context).maybePop(),
    ),
  ];
}
