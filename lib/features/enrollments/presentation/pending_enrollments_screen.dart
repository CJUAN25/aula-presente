import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../schedule/domain/academic_date.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_repository.dart';
import '../domain/pending_enrollment.dart';
import '../domain/pending_enrollment_date_policy.dart';
import '../domain/pending_enrollment_page.dart';
import 'enrollment_components.dart';

/// Course-scoped view of authorizations that are not linked to a UID yet.
/// The owner can inspect its history and explicitly retire or reopen it.
class CoursePendingEnrollmentsScreen extends StatefulWidget {
  const CoursePendingEnrollmentsScreen({
    super.key,
    required this.course,
    required this.repository,
    this.status = 'pending',
  });

  final Course course;
  final EnrollmentRepository repository;
  final String status;

  bool get showingWithdrawn => status == 'withdrawn';

  @override
  State<CoursePendingEnrollmentsScreen> createState() =>
      _CoursePendingEnrollmentsScreenState();
}

class _CoursePendingEnrollmentsScreenState
    extends State<CoursePendingEnrollmentsScreen> {
  final _search = TextEditingController();
  final _items = <PendingEnrollment>[];
  PendingEnrollmentCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  List<PendingEnrollment> get _visibleItems {
    final text = _search.text.trim().toLowerCase();
    if (text.isEmpty) return _items;
    return _items
        .where((item) {
          return '${item.name} ${item.email} ${item.studentCode}'
              .toLowerCase()
              .contains(text);
        })
        .toList(growable: false);
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
      final page = await widget.repository.listCoursePendingEnrollments(
        courseId: widget.course.id,
        status: widget.status,
        cursor: _cursor,
      );
      if (!mounted || epoch != _epoch) return;
      if (widget.repository.currentUid != widget.course.ownerUid) {
        setState(() {
          _items.clear();
          _cursor = null;
          _hasMore = false;
          _error = const EnrollmentFailure(
            EnrollmentFailureKind.permissionDenied,
          );
        });
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(PendingEnrollment item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PendingEnrollmentDetailScreen(
          course: widget.course,
          pendingEnrollment: item,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted && changed == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository.currentUid != widget.course.ownerUid) {
      return const CoursePage(
        title: 'Pendientes de vincular',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final withdrawn = widget.showingWithdrawn;
    return CoursePage(
      title: withdrawn ? 'Pendientes retirados' : 'Pendientes de vincular',
      leading: IconButton(
        tooltip: 'Volver',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar pendientes',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          CoursePageHeading(
            title: withdrawn
                ? 'El historial sigue aquí.'
                : 'Cupos por vincular.',
            description: withdrawn
                ? 'Una autorización retirada no se activa al registrarse. Puedes reabrirla de forma explícita.'
                : 'El docente ya autorizó estas inscripciones. La cuenta debe verificar el mismo correo y código.',
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: enrollmentInputDecoration(
              'Buscar pendiente',
              'Nombre, correo o código',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CourseSecondaryButton(
                  label: withdrawn
                      ? 'Pendientes activos'
                      : 'Autorizaciones retiradas',
                  icon: Icons.history,
                  onPressed: () =>
                      Navigator.of(context).pushReplacement<void, void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CoursePendingEnrollmentsScreen(
                            course: widget.course,
                            repository: widget.repository,
                            status: withdrawn ? 'pending' : 'withdrawn',
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading && _items.isEmpty)
            const CourseLoading(message: 'Cargando inscripciones…'),
          if (_error != null)
            EnrollmentFailureCard(
              error: _error,
              onRetry: () => _load(reset: _items.isEmpty),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            CourseStateCard(
              title: withdrawn
                  ? 'No hay pendientes retirados'
                  : 'No hay cuentas pendientes de vincular',
              message: withdrawn
                  ? 'Las autorizaciones que retires conservarán aquí su historial.'
                  : 'Las filas confirmadas desde Excel aparecerán aquí hasta que el estudiante se registre y verifique su cuenta.',
              icon: withdrawn ? Icons.history : Icons.person_search_outlined,
            ),
          if (_search.text.trim().isNotEmpty &&
              _visibleItems.isEmpty &&
              _items.isNotEmpty)
            const CourseStateCard(
              title: 'Sin coincidencias cargadas',
              message: 'Revisa el nombre, correo o código.',
            ),
          for (final item in _visibleItems)
            EnrollmentTile(
              title: item.name,
              subtitle:
                  '${item.email} · ${item.studentCode} · ${withdrawn ? 'Retirada' : 'Pendiente de cuenta'}',
              iconAsset: 'df818.svg',
              onTap: () => _openDetail(item),
            ),
          if (_hasMore && _items.isNotEmpty)
            CourseSecondaryButton(
              label: _loading ? 'Cargando…' : 'Cargar más',
              onPressed: _loading ? null : () => _load(),
            ),
          if (!withdrawn) ...[
            const SizedBox(height: 12),
            const CourseStateCard(
              title: 'La autorización se conserva',
              message: 'No se crea una cuenta ni una contraseña. Cuando el estudiante verifique correo y código coincidentes, la materia se vincula automáticamente.',
              icon: Icons.verified_user_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

class PendingEnrollmentDetailScreen extends StatefulWidget {
  const PendingEnrollmentDetailScreen({
    super.key,
    required this.course,
    required this.pendingEnrollment,
    required this.repository,
  });

  final Course course;
  final PendingEnrollment pendingEnrollment;
  final EnrollmentRepository repository;

  @override
  State<PendingEnrollmentDetailScreen> createState() =>
      _PendingEnrollmentDetailScreenState();
}

class _PendingEnrollmentDetailScreenState
    extends State<PendingEnrollmentDetailScreen> {
  final _events = <PendingEnrollmentStatusEvent>[];
  PendingEnrollmentHistoryCursor? _cursor;
  bool _historyLoading = false;
  bool _hasMoreHistory = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  bool get _canManage => widget.repository.currentUid == widget.course.ownerUid;

  AcademicDate _todayBogota() {
    final bogota = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    return AcademicDate.fromDateTime(bogota);
  }

  AcademicDate _defaultEffectiveDate() {
    final today = _todayBogota();
    if (today.compareTo(widget.course.schedule.startDate) < 0) {
      return widget.course.schedule.startDate;
    }
    if (today.compareTo(widget.course.schedule.endDate) > 0) {
      return widget.course.schedule.endDate;
    }
    return today;
  }

  Future<AcademicDate?> _pickEffectiveDate({required bool reopening}) async {
    final today = _todayBogota();
    final courseStart = widget.course.schedule.startDate;
    final firstDate = reopening
        ? _minimumReopenDate(courseStart)
        : _minimumRetirementDate(today);
    final lastDate = reopening
        ? _minimum(
            today.compareTo(courseStart) < 0 ? courseStart : today,
            widget.course.schedule.endDate,
          )
        : _minimum(today, widget.course.schedule.endDate);
    if (firstDate.compareTo(lastDate) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay una fecha efectiva de retiro válida para esta autorización.',
          ),
        ),
      );
      return null;
    }
    final suggested = reopening ? _defaultEffectiveDate() : today;
    final initial = _clamp(suggested, firstDate, lastDate);
    final value = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(firstDate.year, firstDate.month, firstDate.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      helpText: reopening
          ? 'Fecha efectiva de reincorporación'
          : 'Fecha efectiva de retiro',
      cancelText: 'Cancelar',
      confirmText: 'Usar fecha',
    );
    return value == null ? null : AcademicDate.fromDateTime(value);
  }

  AcademicDate _minimumRetirementDate(AcademicDate today) {
    return minimumPendingWithdrawalDate(
      enrollment: widget.pendingEnrollment,
      today: today,
      courseStart: widget.course.schedule.startDate,
    );
  }

  AcademicDate _minimumReopenDate(AcademicDate courseStart) {
    if (_events.isEmpty) return courseStart;
    final lastEffectiveDate = _events.first.effectiveDate;
    return lastEffectiveDate.compareTo(courseStart) > 0
        ? lastEffectiveDate
        : courseStart;
  }

  AcademicDate _minimum(AcademicDate a, AcademicDate b) =>
      a.compareTo(b) <= 0 ? a : b;

  AcademicDate _clamp(
    AcademicDate value,
    AcademicDate minimum,
    AcademicDate maximum,
  ) {
    if (value.compareTo(minimum) < 0) return minimum;
    if (value.compareTo(maximum) > 0) return maximum;
    return value;
  }

  Future<void> _loadHistory() async {
    if (_historyLoading || !_hasMoreHistory) return;
    setState(() {
      _historyLoading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listPendingEnrollmentHistory(
        courseId: widget.course.id,
        email: widget.pendingEnrollment.email,
        cursor: _cursor,
      );
      if (!mounted || !_canManage) return;
      setState(() {
        _events.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMoreHistory = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _changeStatus() async {
    if (_busy || !_canManage) return;
    final pending = widget.pendingEnrollment;
    final reopening = pending.status == 'withdrawn';
    if (!reopening && pending.status != 'pending') return;
    final date = await _pickEffectiveDate(reopening: reopening);
    if (!mounted || date == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(reopening ? 'Reincorporar cupo' : 'Retirar cupo'),
        content: Text(
          reopening
              ? 'Desde ${date.isoDate} volverá a estar autorizada la vinculación. El historial anterior se conserva.'
              : 'Desde ${date.isoDate} esta autorización dejará de permitir la vinculación. El historial se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(reopening ? 'Reincorporar' : 'Retirar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.changePendingEnrollmentStatus(
        expected: pending,
        nextStatus: reopening ? 'pending' : 'withdrawn',
        operationId: widget.repository.newPendingStatusEventId(
          courseId: widget.course.id,
          email: pending.email,
        ),
        effectiveDate: date,
      );
      if (!mounted) return;
      final message = result.alreadyApplied
          ? 'El cambio ya estaba confirmado.'
          : reopening
          ? 'Cupo reincorporado desde ${date.isoDate}.'
          : 'Cupo retirado desde ${date.isoDate}.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String value) => switch (value) {
    'pending' => 'Pendiente de vincular',
    'linked' => 'Vinculada',
    'withdrawn' => 'Retirada',
    _ => value,
  };

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingEnrollment;
    if (!_canManage) {
      return const CoursePage(
        title: 'Detalle de inscripción',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }
    final canChange =
        pending.status == 'pending' || pending.status == 'withdrawn';
    final reopening = pending.status == 'withdrawn';
    return CoursePage(
      title: 'Pendiente de cuenta',
      leading: IconButton(
        tooltip: 'Volver',
        onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      bottomNavigationBar: canChange
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: CoursePrimaryButton(
                  label: reopening
                      ? 'Reincorporar autorización'
                      : 'Retirar autorización',
                  onPressed: _busy || (reopening && _events.isEmpty)
                      ? null
                      : _changeStatus,
                  busy: _busy,
                ),
              ),
            )
          : null,
      child: CourseContent(
        children: [
          CoursePageHeading(
            title: pending.status == 'pending'
                ? 'Su cupo ya está en la lista.'
                : pending.status == 'withdrawn'
                ? 'El historial sigue aquí.'
                : 'La cuenta ya está vinculada.',
            description:
                '${widget.course.subject} · ${widget.course.group} · ${widget.course.period}',
          ),
          const SizedBox(height: 16),
          CoursePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pending.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pending.email,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Código estudiantil · ${pending.studentCode}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estado · ${_statusLabel(pending.status)}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ingreso efectivo · ${pending.effectiveStartDate.isoDate}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CourseStateCard(
            title: 'Historial conservado',
            message: pending.status == 'pending'
                ? 'La persona debe registrarse, verificar este correo y tener el mismo código en su perfil. La materia se vincula al entrar en Mis materias.'
                : pending.status == 'withdrawn'
                ? 'Una cuenta que se registre después no activa este cupo. Reincorpóralo solo si corresponde.'
                : 'La matrícula canónica y su historial de estados se consultan en la lista activa o en retirados.',
            icon: Icons.history,
          ),
          const SizedBox(height: 18),
          const CourseSectionHeading(title: 'Cambios de esta autorización'),
          const SizedBox(height: 12),
          if (_events.isEmpty && _historyLoading)
            const CourseLoading(message: 'Cargando historial…'),
          if (_error != null)
            EnrollmentFailureCard(error: _error, onRetry: _loadHistory),
          if (_events.isEmpty && !_historyLoading && _error == null)
            const CourseStateCard(
              title: 'Autorización inicial',
              message: 'El docente confirmó esta inscripción desde una lista. Los cambios posteriores aparecen aquí.',
              icon: Icons.verified_outlined,
            ),
          for (final event in _events)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CoursePanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_statusLabel(event.fromStatus)} → ${_statusLabel(event.toStatus)}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fecha efectiva · ${event.effectiveDate.isoDate}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasMoreHistory)
            CourseSecondaryButton(
              label: _historyLoading ? 'Cargando…' : 'Cargar más historial',
              onPressed: _historyLoading ? null : _loadHistory,
            ),
        ],
      ),
    );
  }
}
