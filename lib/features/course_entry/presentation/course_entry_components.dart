import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/course_entry_failure.dart';
import '../domain/course_invitation.dart';
import '../domain/join_request.dart';

String courseEntryErrorMessage(Object? error, {bool uncertainWrite = false}) {
  if (error is CourseEntryFailure) {
    return switch (error.kind) {
      CourseEntryFailureKind.unauthenticated =>
        'La sesión cambió o terminó. Inicia sesión de nuevo.',
      CourseEntryFailureKind.emailNotVerified =>
        'Verifica tu correo antes de continuar.',
      CourseEntryFailureKind.profileInvalid =>
        'No pudimos confirmar el perfil de esta cuenta.',
      CourseEntryFailureKind.teacherRoleRequired =>
        'Esta cuenta no tiene permiso docente para administrar este curso.',
      CourseEntryFailureKind.studentRoleRequired =>
        'Esta cuenta no tiene permiso de estudiante.',
      CourseEntryFailureKind.invalidInput =>
        'Revisa el código o los datos ingresados.',
      CourseEntryFailureKind.invalidTransition => 'El estado de la invitación cambió o este código se desactivó definitivamente. Actualiza la invitación o genera otro código.',
      CourseEntryFailureKind.inviteUnavailable =>
        'El código no es válido o ya no está disponible.',
      CourseEntryFailureKind.courseUnavailable =>
        'El curso ya no está disponible para esta operación.',
      CourseEntryFailureKind.alreadyResolved => 'La solicitud ya fue resuelta. Actualiza la lista para consultar su estado.',
      CourseEntryFailureKind.permissionDenied => 'Firestore rechazó la operación por permisos. Comprueba tu rol y las reglas publicadas.',
      CourseEntryFailureKind.network =>
        uncertainWrite
            ? 'La conexión se interrumpió. Consulta el estado antes de volver a intentarlo; el cambio podría haberse guardado.'
            : 'No hay conexión con el servidor. Revisa Internet y vuelve a intentarlo.',
      CourseEntryFailureKind.invalidData =>
        'Los datos recibidos no tienen el formato esperado.',
      CourseEntryFailureKind.unknown => 'No pudimos completar la operación. Inténtalo de nuevo o consulta su estado.',
    };
  }
  return 'No pudimos completar la operación. Revisa tu conexión e inténtalo otra vez.';
}

class CourseEntryFailureCard extends StatelessWidget {
  const CourseEntryFailureCard({
    super.key,
    required this.error,
    this.onRetry,
    this.uncertainWrite = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool uncertainWrite;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CourseStateCard(
        title: 'No pudimos completar la operación',
        message: courseEntryErrorMessage(error, uncertainWrite: uncertainWrite),
        icon: Icons.cloud_off_outlined,
        color: AppColors.danger,
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
      ),
      CourseEntryDiagnostic(error: error),
    ],
  );
}

class CourseEntryDiagnostic extends StatelessWidget {
  const CourseEntryDiagnostic({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || error is! CourseEntryFailure) {
      return const SizedBox.shrink();
    }
    final failure = error as CourseEntryFailure;
    final report =
        'course-entry-v2 | paso=${failure.diagnosticStep ?? 'operation'} | error=${failure.diagnosticCode ?? failure.kind.name}';
    return ExpansionTile(
      title: const Text('Diagnóstico (debug)'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(report),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
          },
          child: const Text('Copiar diagnóstico'),
        ),
      ],
    );
  }
}

String invitationStateLabel(CourseInvitationState state) => switch (state) {
  CourseInvitationState.active => 'Activo',
  CourseInvitationState.paused => 'Pausado',
  CourseInvitationState.inactive => 'Desactivado',
};

String invitationExpiryLabel(DateTime? expiresAt) => expiresAt == null
    ? 'Confirmando la fecha de vigencia…'
    : 'Vence el ${invitationDateTime(expiresAt)}';

String invitationDateTime(DateTime value) {
  final local = value.toLocal();
  return '${shortDate(value)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String invitationValidityLabel(Duration value) =>
    value.inHours % 24 == 0 ? '${value.inDays} días' : '${value.inHours} horas';

String joinRequestStatusLabel(JoinRequestStatus status) => switch (status) {
  JoinRequestStatus.pending => 'Pendiente de aprobación',
  JoinRequestStatus.approved => 'Aprobada',
  JoinRequestStatus.rejected => 'Rechazada',
};

String shortDate(DateTime? value) {
  if (value == null) return 'Fecha pendiente de confirmar';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class CourseEntryCodePanel extends StatelessWidget {
  const CourseEntryCodePanel({
    super.key,
    required this.code,
    required this.label,
    this.onCopy,
  });

  final String code;
  final String label;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) => CoursePanel(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 18 / 12,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                code,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  height: 26 / 18,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            tooltip: 'Copiar código',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, color: AppColors.primary),
          ),
      ],
    ),
  );
}
