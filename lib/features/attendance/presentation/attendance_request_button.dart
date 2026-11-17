import 'package:flutter/material.dart';

import '../domain/attendance_justification_request.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import 'attendance_presentation_components.dart';

class AttendanceRequestButton extends StatefulWidget {
  const AttendanceRequestButton({
    super.key,
    required this.record,
    required this.segmentId,
    required this.repository,
  });
  final AttendanceRecord record;
  final String? segmentId;
  final AttendanceRepository repository;

  @override
  State<AttendanceRequestButton> createState() =>
      _AttendanceRequestButtonState();
}

class _AttendanceRequestButtonState extends State<AttendanceRequestButton> {
  AttendanceJustificationRequest? _request;
  Object? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.getMyJustification(
        record: widget.record,
        segmentId: widget.segmentId,
      );
      if (mounted) setState(() => _request = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _request != null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _RequestTextDialog(),
    );
    if (!mounted || text == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.submitJustification(
        record: widget.record,
        segmentId: widget.segmentId,
        text: text,
      );
      if (mounted) setState(() => _request = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error != null) ...[
        Text(attendanceErrorMessage(_error!)),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Revisar solicitud'),
        ),
      ],
      if (_request != null)
        Text(switch (_request!.status) {
          AttendanceRequestStatus.pending => 'Solicitud pendiente. La falta sigue contando mientras el docente la revisa.',
          AttendanceRequestStatus.approved => 'Justificación aprobada. Si tienes dudas, comunícate con tu docente.',
          AttendanceRequestStatus.rejected => 'Justificación rechazada. La falta sigue contando. Si tienes dudas, comunícate con tu docente.',
        }),
      OutlinedButton.icon(
        onPressed: _busy || _request != null || _error != null ? null : _submit,
        icon: const Icon(Icons.message_outlined),
        label: Text(
          _busy
              ? 'Consultando solicitud…'
              : _request == null
              ? 'Solicitar justificación'
              : 'Solicitud enviada',
        ),
      ),
    ],
  );
}

class _RequestTextDialog extends StatefulWidget {
  const _RequestTextDialog();
  @override
  State<_RequestTextDialog> createState() => _RequestTextDialogState();
}

class _RequestTextDialogState extends State<_RequestTextDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Solicitar justificaci\u00f3n'),
    content: TextField(
      controller: _text,
      minLines: 2,
      maxLines: 4,
      maxLength: 500,
      decoration: const InputDecoration(
        labelText: 'Explica brevemente tu ausencia',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isNotEmpty) {
            Navigator.pop(context, _text.text.trim());
          }
        },
        child: const Text('Enviar solicitud'),
      ),
    ],
  );
}
