import 'package:flutter/material.dart';

import '../../../app/course_entry_repository_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../course_entry/presentation/course_invitation_screens.dart';
import '../../course_entry/presentation/teacher_join_request_screens.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../application/enrollment_validator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
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
              const EnrollmentTile(
                title: 'Importar / actualizar Excel',
                subtitle: 'Disponible en una entrega posterior',
                iconAsset: 'bcab7.svg',
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
              const CourseStateCard(
                title: 'Más funciones después',
                message: 'Retiros, histórico e importación de Excel todavía no están disponibles.',
                icon: Icons.info_outline,
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
  });

  final Course course;
  final EnrollmentRepository repository;

  @override
  State<CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<CourseStudentsScreen> {
  final List<Enrollment> _items = [];
  EnrollmentCursor? _cursor;
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
      ? const CoursePage(
          title: 'Estudiantes del curso',
          child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
        )
      : CoursePage(
          title: 'Estudiantes del curso',
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          child: CourseContent(
            children: [
              const CoursePageHeading(title: 'Tu lista de estudiantes.'),
              const SizedBox(height: 12),
              Text(
                '${widget.course.subject} · ${widget.course.group}',
                style: const TextStyle(color: AppColors.muted),
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
                  title: 'Aún no hay estudiantes inscritos',
                  message: 'Agrega una cuenta existente con correo verificado para empezar.',
                  icon: Icons.group_outlined,
                ),
              for (final enrollment in _items)
                EnrollmentTile(
                  title: enrollment.name,
                  subtitle:
                      'Datos al inscribir · ${enrollment.email}${enrollment.studentCode == null ? '' : ' · ${enrollment.studentCode}'}',
                  iconAsset: 'df818.svg',
                ),
              if (_hasMore && _items.isNotEmpty)
                CourseSecondaryButton(
                  label: _loading ? 'Cargando…' : 'Cargar más estudiantes',
                  onPressed: _loading ? null : () => _load(),
                ),
              const SizedBox(height: 16),
              CoursePrimaryButton(
                label: 'Agregar estudiante',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: _add,
              ),
              const SizedBox(height: 12),
              const CourseStateCard(
                title: 'Retiros e histórico',
                message:
                    'Esta función se incorporará en una entrega posterior.',
              ),
            ],
          ),
        );
}

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
