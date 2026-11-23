import 'package:flutter/material.dart';

import '../domain/attendance_justification_request.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';

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
  String? _error;
  bool _busy = true;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AttendanceRequestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record != widget.record ||
        oldWidget.segmentId != widget.segmentId ||
        oldWidget.repository != widget.repository) {
      _request = null;
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.getMyJustification(
        record: widget.record,
        segmentId: widget.segmentId,
      );
      if (mounted && epoch == _epoch) setState(() => _request = result);
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = 'No pudimos consultar tu solicitud.');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _request != null) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (context) => const _RequestTextDialog(),
      );
      if (!mounted || epoch != _epoch || text == null) return;
      final result = await widget.repository.submitJustification(
        record: widget.record,
        segmentId: widget.segmentId,
        text: text,
      );
      if (mounted && epoch == _epoch) setState(() => _request = result);
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = 'No pudimos confirmar el envío. Consulta tu solicitud antes de volver a enviarla.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error != null) ...[
        Text(_error!),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Volver a consultar'),
        ),
      ],
      if (_request != null)
        Text(switch (_request!.status) {
          AttendanceRequestStatus.pending => 'Solicitud pendiente. La falta sigue contando mientras el docente la revisa.',
          AttendanceRequestStatus.approved => 'Justificación aprobada. Si tienes dudas, comunícate con tu docente.',
          AttendanceRequestStatus.rejected => 'Justificación rechazada. La falta sigue contando. Si tienes dudas, comunícate con tu docente.',
        }),
      OutlinedButton.icon(
        onPressed: _busy || _request != null || _error != null || !_canSubmit
            ? null
            : _submit,
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

  bool get _canSubmit => widget.segmentId == null
      ? widget.record.absentUnits > 0 && widget.record.justifiedUnits == 0
      : widget.record.segments.any(
          (segment) =>
              segment.segmentId == widget.segmentId &&
              segment.absentMinutes > 0 &&
              segment.justifiedMinutes == 0,
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
