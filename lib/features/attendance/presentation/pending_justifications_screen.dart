import 'package:flutter/material.dart';

import '../../courses/domain/course.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_justification_request.dart';
import '../domain/attendance_repository.dart';
import '../domain/attendance_session.dart';
import 'attendance_presentation_components.dart';

class PendingJustificationsScreen extends StatefulWidget {
  const PendingJustificationsScreen({
    super.key,
    required this.course,
    required this.repository,
  });

  final Course course;
  final AttendanceRepository repository;

  @override
  State<PendingJustificationsScreen> createState() =>
      _PendingJustificationsScreenState();
}

class _PendingJustificationsScreenState
    extends State<PendingJustificationsScreen> {
  final _items = <PendingAttendanceRequest>[];
  String? _cursor;
  Object? _error;
  bool _loading = false;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _cursor = null;
        _items.clear();
      }
    });
    try {
      final page = await widget.repository.listPendingJustifications(
        courseId: widget.course.id,
        afterId: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _encounter(PendingAttendanceRequest item) {
    final start = item.segment?.startMinute ?? item.session.startMinute;
    final end = item.segment?.endMinute ?? item.session.endMinute;
    return '${attendanceDateLabel(item.session.effectiveDate)} · '
        '${attendanceTimeLabel(start)}–${attendanceTimeLabel(end)}';
  }

  Future<void> _review(PendingAttendanceRequest item) async {
    if (_reviewing || _loading) return;
    setState(() => _reviewing = true);
    final finalized = item.session.status == AttendanceSessionStatus.finalized;
    try {
      final approve = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.studentName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_encounter(item)),
                const SizedBox(height: 12),
                Text(item.request.text),
                const SizedBox(height: 12),
                Text(
                  !finalized
                      ? 'Esta sesión debe estar finalizada para decidir la solicitud.'
                      : item.hasAbsence
                      ? 'Al aprobar, solo se descuenta la ausencia de esta solicitud.'
                      : 'La marca cambió y ya no hay una ausencia que aprobar. Puedes rechazar esta solicitud.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
            OutlinedButton(
              onPressed: finalized ? () => Navigator.pop(context, false) : null,
              child: const Text('Rechazar'),
            ),
            FilledButton(
              onPressed: finalized && item.hasAbsence
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Aprobar'),
            ),
          ],
        ),
      );
      if (!mounted || approve == null) return;
      await widget.repository.decideJustificationRequest(
        courseId: widget.course.id,
        request: item.request,
        approve: approve,
      );
      if (!mounted) return;
      _message('Solicitud resuelta.');
      await _load(reset: true);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      if (error.kind == AttendanceFailureKind.conflict ||
          error.kind == AttendanceFailureKind.invalidTransition) {
        _message(
          'La solicitud o la asistencia cambió. Revisa el estado actualizado.',
        );
        await _load(reset: true);
      } else {
        _message(attendanceErrorMessage(error));
      }
    } catch (error) {
      if (mounted) _message(attendanceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => CoursePage(
    title: 'Justificaciones pendientes',
    actions: [
      IconButton(
        tooltip: 'Actualizar justificaciones',
        onPressed: _loading || _reviewing ? null : () => _load(reset: true),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: CourseContent(
      children: [
        CoursePageHeading(
          title: widget.course.subject,
          description: 'Abre una solicitud para leer el texto y decidir.',
        ),
        const SizedBox(height: 16),
        if (_error != null)
          AttendanceErrorCard(
            error: _error!,
            onRetry: () => _load(reset: _items.isEmpty),
          ),
        if (!_loading && _items.isEmpty && _error == null)
          const CourseStateCard(
            title: 'Sin solicitudes pendientes',
            message: 'Las solicitudes nuevas del curso aparecerán aquí.',
            icon: Icons.inbox_outlined,
          ),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CoursePanel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(item.studentName),
                  subtitle: Text(_encounter(item)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _reviewing || _loading ? null : () => _review(item),
                ),
              ),
            ),
          ),
        if (_loading) const CourseLoading(message: 'Cargando justificaciones…'),
        if (!_loading && _error == null && _cursor != null)
          CourseSecondaryButton(
            label: 'Cargar más solicitudes',
            onPressed: _reviewing ? null : () => _load(reset: false),
          ),
      ],
    ),
  );
}
