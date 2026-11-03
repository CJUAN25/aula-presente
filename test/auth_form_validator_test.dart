import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/auth/application/auth_form_validator.dart';

void main() {
  group('AuthFormValidator', () {
    test('valida correo y contraseña sin persistir valores', () {
      expect(AuthFormValidator.email(''), isNotNull);
      expect(AuthFormValidator.email('correo-invalido'), isNotNull);
      expect(AuthFormValidator.email('persona@udla.edu.co'), isNull);
      expect(AuthFormValidator.email('x' * 255 + '@example.edu'), isNotNull);
      expect(AuthFormValidator.password('corta'), isNotNull);
      expect(AuthFormValidator.password('clave-valida'), isNull);
    });

    test('comprueba nombre y confirmación de contraseña', () {
      expect(AuthFormValidator.fullName(' A '), isNotNull);
      expect(AuthFormValidator.fullName('Ana Pérez'), isNull);
      expect(AuthFormValidator.fullName('x' * 101), isNotNull);
      expect(AuthFormValidator.studentCode(''), isNull);
      expect(AuthFormValidator.studentCode('COD-001'), isNull);
      expect(AuthFormValidator.studentCode('x' * 41), isNotNull);
      expect(AuthFormValidator.confirmation('secreto123', ''), isNotNull);
      expect(
        AuthFormValidator.confirmation('secreto123', 'secreto124'),
        isNotNull,
      );
      expect(
        AuthFormValidator.confirmation('secreto123', 'secreto123'),
        isNull,
      );
    });
  });
}
