abstract final class AuthFormValidator {
  static String? email(String? value) {
    value ??= '';
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Escribe tu correo institucional.';
    if (trimmed.length > 254) {
      return 'El correo no puede superar 254 caracteres.';
    }
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(trimmed);
    return valid ? null : 'Escribe un correo válido.';
  }

  static String? password(String? value) {
    value ??= '';
    if (value.isEmpty) return 'Escribe tu contraseña.';
    if (value.length < 8) return 'Usa al menos 8 caracteres.';
    return null;
  }

  static String? fullName(String? value) {
    value ??= '';
    if (value.trim().length < 3) return 'Escribe tu nombre completo.';
    if (value.trim().length > 100) return 'Usa máximo 100 caracteres.';
    return null;
  }

  static String? studentCode(String? value) {
    value ??= '';
    final code = value.trim();
    if (code.isEmpty) return null;
    if (code.length > 40) return 'Usa máximo 40 caracteres.';
    return null;
  }

  static String? confirmation(String password, String? confirmation) {
    confirmation ??= '';
    if (confirmation.isEmpty) return 'Confirma tu contraseña.';
    if (password != confirmation) return 'Las contraseñas no coinciden.';
    return null;
  }
}
