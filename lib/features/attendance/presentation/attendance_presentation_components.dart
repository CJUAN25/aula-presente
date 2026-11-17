import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../../schedule/domain/academic_date.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_mode.dart';

class AttendanceWaitStatus extends StatefulWidget {
  const AttendanceWaitStatus({super.key, required this.message});
  final String message;

  @override
  State<AttendanceWaitStatus> createState() => _AttendanceWaitStatusState();
}

class _AttendanceWaitStatusState extends State<AttendanceWaitStatus> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CourseLoading(
    message: _seconds < 8
        ? widget.message
        : '${widget.message} Está tardando más de lo habitual ($_seconds s). El avance guardado se conserva; espera la confirmación o el error.',
  );
}

String attendanceErrorMessage(Object error) {
  if (error is AttendanceFailure) {
    if (error.message != null) return error.message!;
    return switch (error.kind) {
      AttendanceFailureKind.unauthenticated =>
        'La sesión terminó. Inicia sesión de nuevo para continuar.',
      AttendanceFailureKind.emailNotVerified =>
        'Verifica tu correo antes de gestionar la asistencia.',
      AttendanceFailureKind.profileInvalid =>
        'No pudimos confirmar el perfil de esta cuenta.',
      AttendanceFailureKind.teacherRoleRequired =>
        'Esta cuenta no tiene permiso docente para este curso.',
      AttendanceFailureKind.studentRoleRequired =>
        'Esta cuenta no tiene permiso de estudiante.',
      AttendanceFailureKind.permissionDenied => 'Firestore rechazó la operación por permisos. Comprueba que tu perfil sea docente del curso y que las reglas estén activadas.',
      AttendanceFailureKind.notFound =>
        'El curso o registro ya no está disponible. Actualiza la información.',
      AttendanceFailureKind.invalidInput =>
        'Revisa los datos, el horario y el motivo antes de guardar.',
      AttendanceFailureKind.invalidData => 'Los datos recibidos no tienen el formato esperado. No se modificó la asistencia.',
      AttendanceFailureKind.incompleteRoster => 'No se pudo cargar toda la nómina. Reintenta antes de preparar la asistencia.',
      AttendanceFailureKind.rosterHistoryNeedsReview => 'El historial de matrícula no permite confirmar quién debía asistir ese día. Solicita una revisión antes de continuar.',
      AttendanceFailureKind.staleSession => 'La sesión cambió en otro dispositivo. Actualiza antes de volver a guardar.',
      AttendanceFailureKind.invalidTransition =>
        'La sesión ya cambió de estado y esta acción no se puede repetir.',
      AttendanceFailureKind.conflict => 'Otro dispositivo actualizó este registro. Vuelve a cargarlo y revisa el cambio.',
      AttendanceFailureKind.unavailable => 'No pudimos confirmar la operación por una interrupción de conexión. Actualiza antes de intentarlo de nuevo.',
    };
  }
  return 'No pudimos completar la operación. Revisa tu conexión y vuelve a intentarlo.';
}

String attendanceDateLabel(AcademicDate date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String attendanceTimeLabel(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:'
    '${(minute % 60).toString().padLeft(2, '0')}';

String attendanceModeLabel(AttendanceMode mode) => switch (mode) {
  AttendanceMode.meeting => 'Por encuentro',
  AttendanceMode.minutes => 'Por horas',
};

String attendanceUnitsLabel(int units, AttendanceMode mode) {
  if (mode == AttendanceMode.meeting) {
    return '$units ${units == 1 ? 'encuentro' : 'encuentros'}';
  }
  final hours = units ~/ 60;
  final minutes = units % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours ${hours == 1 ? 'hora' : 'horas'}';
  return '$hours h $minutes min';
}

String newAttendanceOperationId() =>
    'op_${DateTime.now().microsecondsSinceEpoch.toString().padLeft(20, '0')}';

class AttendanceModeChoice extends StatelessWidget {
  const AttendanceModeChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final AttendanceMode? value;
  final ValueChanged<AttendanceMode?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ModeCard(
        title: 'Por encuentro',
        description: 'Una marca resume toda la clase. Una ausencia cuenta como un encuentro.',
        icon: Icons.event_available_outlined,
        selected: value == AttendanceMode.meeting,
        enabled: enabled,
        onTap: () => onChanged(AttendanceMode.meeting),
      ),
      const SizedBox(height: 10),
      _ModeCard(
        title: 'Por horas',
        description: 'Cada tramo de hasta 60 minutos se registra por separado.',
        icon: Icons.schedule_outlined,
        selected: value == AttendanceMode.minutes,
        enabled: enabled,
        onTap: () => onChanged(AttendanceMode.minutes),
      ),
    ],
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$title. $description',
    child: Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outline,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class AttendanceErrorCard extends StatelessWidget {
  const AttendanceErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CourseStateCard(
    title: 'No pudimos cargar la asistencia',
    message: attendanceErrorMessage(error),
    color: AppColors.danger,
    icon: Icons.cloud_off_outlined,
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Reintentar'),
    ),
  );
}

class AttendanceReasonDialog extends StatefulWidget {
  const AttendanceReasonDialog({
    super.key,
    required this.title,
    required this.description,
    this.fieldLabel = 'Motivo',
    this.confirmLabel = 'Confirmar',
  });

  final String title;
  final String description;
  final String fieldLabel;
  final String confirmLabel;

  @override
  State<AttendanceReasonDialog> createState() => _AttendanceReasonDialogState();
}

class _AttendanceReasonDialogState extends State<AttendanceReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.description),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.fieldLabel),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.of(context).pop(value);
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
