import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/course_invitation.dart';
import 'course_entry_components.dart';

Future<Duration?> chooseInvitationValidity(
  BuildContext context, {
  required Duration initial,
  DateTime? createdAt,
  bool replacingCode = false,
}) => showDialog<Duration>(
  context: context,
  builder: (_) => _ValidityDialog(
    initial: initial,
    createdAt: createdAt,
    replacingCode: replacingCode,
  ),
);

class _ValidityDialog extends StatefulWidget {
  const _ValidityDialog({
    required this.initial,
    this.createdAt,
    required this.replacingCode,
  });
  final Duration initial;
  final DateTime? createdAt;
  final bool replacingCode;

  @override
  State<_ValidityDialog> createState() => _ValidityDialogState();
}

class _ValidityDialogState extends State<_ValidityDialog> {
  final _form = GlobalKey<FormState>();
  late bool _days = widget.initial.inHours % 24 == 0;
  late final _amount = TextEditingController(
    text: '${_days ? widget.initial.inDays : widget.initial.inHours}',
  );

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    filled: true,
    fillColor: AppColors.glass.withValues(alpha: 0.66),
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.outline),
    ),
  );

  Duration? get _value {
    final amount = int.tryParse(_amount.text);
    if (amount == null) return null;
    final value = Duration(hours: amount * (_days ? 24 : 1));
    return value >= CourseInvitation.minValidity &&
            value <= CourseInvitation.maxValidity
        ? value
        : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    title: Text(
      widget.replacingCode ? '¿Renovar el código?' : 'Elegir vencimiento',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.replacingCode)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'El código anterior dejará de servir. Las solicitudes y matrículas existentes se conservan.',
                ),
              ),
            const Text('Elige una duración entre 1 hora y 90 días.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: _fieldDecoration('Duración total'),
              onChanged: (_) => setState(() {}),
              validator: (_) => _value == null
                  ? 'Elige de 1 a 2160 horas o de 1 a 90 días.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              initialValue: _days,
              decoration: _fieldDecoration('Unidad'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Días')),
                DropdownMenuItem(value: false, child: Text('Horas')),
              ],
              onChanged: (value) => setState(() => _days = value ?? true),
            ),
            const SizedBox(height: 16),
            if (_value != null)
              Text(
                widget.createdAt == null
                    ? 'El nuevo código vencerá ${invitationValidityLabel(_value!)} después de generarlo.'
                    : 'Nuevo vencimiento: ${invitationDateTime(widget.createdAt!.add(_value!))}.',
              ),
            if (widget.createdAt != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Se conserva el mismo código. El nuevo vencimiento debe ser futuro.',
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) Navigator.of(context).pop(_value);
        },
        child: Text(
          widget.replacingCode ? 'Confirmar renovación' : 'Guardar vencimiento',
        ),
      ),
    ],
  );
}
