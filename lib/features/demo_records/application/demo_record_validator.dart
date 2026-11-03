abstract final class DemoRecordValidator {
  static String? title(String? value) {
    final title = value?.trim() ?? '';
    if (title.isEmpty) return 'Escribe un título.';
    if (title.length > 120) return 'Usa máximo 120 caracteres.';
    return null;
  }

  static String? description(String? value) {
    if ((value ?? '').length > 1000) return 'Usa máximo 1000 caracteres.';
    return null;
  }
}
