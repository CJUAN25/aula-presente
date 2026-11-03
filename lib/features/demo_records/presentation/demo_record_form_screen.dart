import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../application/demo_record_validator.dart';
import '../domain/demo_record.dart';
import '../domain/demo_records_repository.dart';
import 'demo_records_messages.dart';

class DemoRecordFormScreen extends StatefulWidget {
  const DemoRecordFormScreen({
    super.key,
    required this.repository,
    this.record,
  });

  final DemoRecordsRepository repository;
  final DemoRecord? record;

  @override
  State<DemoRecordFormScreen> createState() => _DemoRecordFormScreenState();
}

class _DemoRecordFormScreenState extends State<DemoRecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.record != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.record?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.record?.description ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final record = widget.record;
      if (record == null) {
        await widget.repository.create(title: title, description: description);
      } else {
        await widget.repository.update(
          id: record.id,
          title: title,
          description: description,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = demoRecordsErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar registro' : 'Nuevo registro'),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                _editing
                    ? 'Actualiza la información de tu registro.'
                    : 'Completa los datos para crear un registro de prueba.',
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                enabled: !_saving,
                autofocus: !_editing,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: DemoRecordValidator.title,
                decoration: _inputDecoration('Título'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                enabled: !_saving,
                minLines: 4,
                maxLines: 7,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                validator: DemoRecordValidator.description,
                decoration: _inputDecoration('Descripción (opcional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_editing ? Icons.save_outlined : Icons.add),
                  label: Text(
                    _saving
                        ? 'Guardando…'
                        : _editing
                        ? 'Guardar cambios'
                        : 'Crear registro',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.surface,
    alignLabelWithHint: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.danger),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(message, style: const TextStyle(color: AppColors.text)),
  );
}
