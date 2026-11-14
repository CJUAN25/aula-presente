import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme/app_theme.dart';
import '../../courses/presentation/course_presentation_components.dart';
import '../domain/enrollment_failure.dart';

String enrollmentErrorMessage(Object? error, {bool uncertainWrite = false}) {
  if (error is EnrollmentFailure) {
    return switch (error.kind) {
      EnrollmentFailureKind.unauthenticated =>
        'La sesión cambió o terminó. Inicia sesión de nuevo.',
      EnrollmentFailureKind.emailNotVerified =>
        'Verifica tu correo antes de continuar.',
      EnrollmentFailureKind.profileInvalid =>
        'No pudimos confirmar el perfil de esta cuenta.',
      EnrollmentFailureKind.teacherRoleRequired =>
        'Esta cuenta no tiene permiso docente para gestionar el curso.',
      EnrollmentFailureKind.studentRoleRequired =>
        'Esta cuenta no tiene permiso de estudiante.',
      EnrollmentFailureKind.invalidInput =>
        'Revisa el correo y el código antes de continuar.',
      EnrollmentFailureKind.candidateChanged => 'Los datos de esta cuenta cambiaron. Búscala otra vez antes de confirmar.',
      EnrollmentFailureKind.staleEnrollment => 'La inscripción cambió desde que abriste la ficha. Actualiza la lista antes de decidir.',
      EnrollmentFailureKind.courseUnavailable =>
        'Este curso ya no está disponible para tu cuenta.',
      EnrollmentFailureKind.permissionDenied => 'Firestore rechazó la operación por permisos. Comprueba tu acceso y las reglas publicadas.',
      EnrollmentFailureKind.network =>
        uncertainWrite
            ? 'Se interrumpió la conexión. Consulta la lista antes de reintentar: la inscripción podría haberse guardado.'
            : 'Se interrumpió la conexión. Vuelve a consultar cuando tengas Internet.',
      EnrollmentFailureKind.invalidData =>
        'Los datos recibidos no tienen el formato esperado.',
      EnrollmentFailureKind.unknown => 'No pudimos completar la operación. Consulta la lista y vuelve a intentarlo.',
    };
  }
  return 'No pudimos completar la operación. Revisa tu conexión e inténtalo otra vez.';
}

InputDecoration enrollmentInputDecoration(String label, String hint) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: AppColors.glass.withValues(alpha: 0.66),
      contentPadding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 84),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
    );

class EnrollmentTile extends StatelessWidget {
  const EnrollmentTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String iconAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: CoursePanel(
          color: AppColors.glass.withValues(alpha: 0.62),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SvgPicture.asset(
                  'assets/figma/$iconAsset',
                  width: 24,
                  height: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                SvgPicture.asset(
                  'assets/figma/8aca9.svg',
                  width: 20,
                  height: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class EnrollmentFailureCard extends StatelessWidget {
  const EnrollmentFailureCard({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CourseStateCard(
    title: 'No pudimos cargar la información',
    message: enrollmentErrorMessage(error),
    color: AppColors.danger,
    icon: Icons.cloud_off_outlined,
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Reintentar'),
    ),
  );
}
