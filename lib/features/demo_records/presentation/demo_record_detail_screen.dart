import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/demo_record.dart';
import '../domain/demo_records_repository.dart';
import 'demo_record_form_screen.dart';
import 'demo_records_messages.dart';

class DemoRecordDetailScreen extends StatefulWidget {
  const DemoRecordDetailScreen({
    super.key,
    required this.recordId,
    required this.repository,
  });

  final String recordId;
  final DemoRecordsRepository repository;

  @override
  State<DemoRecordDetailScreen> createState() => _DemoRecordDetailScreenState();
}

class _DemoRecordDetailScreenState extends State<DemoRecordDetailScreen> {
  late Future<DemoRecord?> _record;
  bool _deleting = false;
  bool _openingEditor = false;

  @override
  void initState() {
    super.initState();
    _record = widget.repository.getRecord(widget.recordId);
  }

  void _reload() =>
      setState(() => _record = widget.repository.getRecord(widget.recordId));

  Future<void> _edit(DemoRecord record) async {
    if (_openingEditor || _deleting) return;
    setState(() => _openingEditor = true);
    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DemoRecordFormScreen(
            repository: widget.repository,
            record: record,
          ),
        ),
      );
      if (changed == true && mounted) _reload();
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este registro?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.repository.delete(widget.recordId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(demoRecordsErrorMessage(error))),
          );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del registro')),
      body: FutureBuilder<DemoRecord?>(
        future: _record,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DetailMessage(
              message: demoRecordsErrorMessage(snapshot.error),
              actionLabel: 'Reintentar',
              onAction: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final record = snapshot.data;
          if (record == null) {
            return const _DetailMessage(
              message: 'Este registro ya no está disponible.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                record.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.outline),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  record.description.isEmpty
                      ? 'Sin descripción.'
                      : record.description,
                  style: const TextStyle(color: AppColors.text, height: 1.55),
                ),
              ),
              const SizedBox(height: 18),
              _TimestampRow(label: 'Creado', value: record.createdAt),
              const SizedBox(height: 8),
              _TimestampRow(label: 'Actualizado', value: record.updatedAt),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _deleting || _openingEditor
                      ? null
                      : () => _edit(record),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _deleting || _openingEditor ? null : _delete,
                  icon: _deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(_deleting ? 'Eliminando…' : 'Eliminar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimestampRow extends StatelessWidget {
  const _TimestampRow({required this.label, required this.value});

  final String label;
  final DateTime? value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: AppColors.muted)),
      ),
      Text(
        value == null ? 'Sin dato' : _formatDate(value!.toLocal()),
        style: const TextStyle(color: AppColors.text),
      ),
    ],
  );
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} · $hour:$minute';
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
