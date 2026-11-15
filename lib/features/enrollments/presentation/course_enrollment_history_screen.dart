import 'package:flutter/material.dart';

import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/course_enrollment_history_entry.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_repository.dart';
import 'enrollment_components.dart';
import 'enrollment_history_screen.dart';
import 'pending_enrollments_screen.dart';

/// Read-only, course-scoped overview of confirmed enrollment identities.
///
/// The repository loads all four sources through stable server-backed pages.
/// Individual event subcollections are read only after a row is opened.
class CourseEnrollmentHistoryScreen extends StatefulWidget {
  const CourseEnrollmentHistoryScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final EnrollmentRepository repository;

  @override
  State<CourseEnrollmentHistoryScreen> createState() =>
      _CourseEnrollmentHistoryScreenState();
}

class _CourseEnrollmentHistoryScreenState
    extends State<CourseEnrollmentHistoryScreen> {
  late final String? _sessionUid;
  final _search = TextEditingController();
  List<CourseEnrollmentHistoryEntry> _entries = const [];
  Object? _error;
  bool _loading = false;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _sessionUid = widget.repository.currentUid;
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  bool get _sessionIsValid =>
      _sessionUid != null &&
      _sessionUid == widget.course.ownerUid &&
      widget.repository.currentUid == _sessionUid;

  Future<void> _load() async {
    if (_loading) return;
    final epoch = ++_loadEpoch;
    if (!_sessionIsValid) {
      setState(() {
        _entries = const [];
        _error = const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
        _loading = false;
      });
      return;
    }

    setState(() {
      _entries = const [];
      _error = null;
      _loading = true;
    });
    try {
      final snapshot = await widget.repository.loadCourseRosterSnapshot(
        courseId: widget.course.id,
      );
      if (!mounted || epoch != _loadEpoch) return;
      if (!_sessionIsValid) {
        setState(() {
          _entries = const [];
          _error = const EnrollmentFailure(
            EnrollmentFailureKind.unauthenticated,
          );
        });
        return;
      }
      setState(() {
        _entries = CourseEnrollmentHistoryEntry.fromSnapshot(snapshot);
      });
    } catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _entries = const [];
          _error = error;
        });
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
    }
  }

  List<CourseEnrollmentHistoryEntry> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((entry) {
          final enrollment = entry.enrollment;
          final pending = entry.pending;
          final email = enrollment?.email ?? pending?.email ?? '';
          final code = enrollment?.studentCode ?? pending?.studentCode ?? '';
          return '${entry.displayName} $email $code'.toLowerCase().contains(
            query,
          );
        })
        .toList(growable: false);
  }

  Future<void> _openEntry(CourseEnrollmentHistoryEntry entry) async {
    if (!_sessionIsValid) return;
    final enrollment = entry.enrollment;
    final pending = entry.pending;
    if (enrollment != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EnrollmentHistoryScreen(
            course: widget.course,
            enrollment: enrollment,
            repository: widget.repository,
          ),
        ),
      );
    } else if (pending != null) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PendingEnrollmentDetailScreen(
            course: widget.course,
            pendingEnrollment: pending,
            repository: widget.repository,
          ),
        ),
      );
    }
    if (mounted && _sessionIsValid) await _load();
  }

  String _rowSubtitle(CourseEnrollmentHistoryEntry entry) {
    final email = entry.enrollment?.email ?? entry.pending?.email ?? '';
    return email.isEmpty ? entry.statusLabel : '${entry.statusLabel} · $email';
  }

  String _rowIcon(CourseEnrollmentHistoryEntry entry) =>
      switch (entry.enrollment?.status ?? entry.pending?.status) {
        'withdrawn' => 'df818.svg',
        'active' => '51a24.svg',
        _ => '19383.svg',
      };

  @override
  Widget build(BuildContext context) {
    if (!_sessionIsValid) {
      return const CoursePage(
        title: 'Historial de matrícula',
        child: Center(child: Text('La sesión cambió. Vuelve a entrar.')),
      );
    }

    return CoursePage(
      title: 'Historial de matrícula',
      leading: IconButton(
        tooltip: 'Volver a gestionar estudiantes',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar historial',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: CourseContent(
        children: [
          CoursePageHeading(
            title: 'Historial de matrícula',
            description:
                '${widget.course.subject} · Grupo ${widget.course.group} · ${widget.course.period}',
          ),
          const SizedBox(height: 16),
          const CourseStateCard(
            title: 'Movimientos confirmados',
            message: 'El estado indica la situación actual de cada inscripción en este curso.',
            icon: Icons.history,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: enrollmentInputDecoration(
              'Buscar estudiante',
              'Nombre, correo o código',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 16),
          if (_loading && _entries.isEmpty)
            const CourseLoading(message: 'Cargando historial del curso…'),
          if (_error != null)
            EnrollmentFailureCard(error: _error, onRetry: _load),
          if (!_loading && _error == null && _entries.isEmpty)
            const CourseStateCard(
              title: 'Aún no hay matrículas confirmadas',
              message: 'Las filas revisadas en Excel solo aparecen aquí después de confirmar el cambio.',
              icon: Icons.people_outline,
            ),
          if (_search.text.trim().isNotEmpty &&
              _visibleEntries.isEmpty &&
              _entries.isNotEmpty)
            const CourseStateCard(
              title: 'Sin coincidencias',
              message: 'Prueba con otro nombre, correo o código.',
              icon: Icons.search_off,
            ),
          for (final entry in _visibleEntries)
            EnrollmentTile(
              title: entry.displayName,
              subtitle: _rowSubtitle(entry),
              iconAsset: _rowIcon(entry),
              onTap: () => _openEntry(entry),
            ),
        ],
      ),
    );
  }
}
