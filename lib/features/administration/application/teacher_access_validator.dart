abstract final class TeacherAccessValidator {
  static String? rejectionReasonError(String? value) {
    final reason = value?.trim() ?? '';
    if (reason.isEmpty) return 'Escribe el motivo del rechazo.';
    if (reason.length > 500) return 'Usa máximo 500 caracteres.';
    return null;
  }

  static String normalizeRejectionReason(String value) => value.trim();
}
