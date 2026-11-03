import 'package:aula_presente/features/demo_records/application/demo_record_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoRecordValidator.title', () {
    test('requiere contenido después de quitar espacios', () {
      expect(DemoRecordValidator.title('   '), 'Escribe un título.');
    });

    test('acepta títulos de hasta 120 caracteres', () {
      expect(DemoRecordValidator.title(' a '), isNull);
      expect(DemoRecordValidator.title('a' * 120), isNull);
    });

    test('rechaza títulos mayores de 120 caracteres', () {
      expect(
        DemoRecordValidator.title('a' * 121),
        'Usa máximo 120 caracteres.',
      );
    });
  });

  group('DemoRecordValidator.description', () {
    test('permite descripción vacía y hasta 1000 caracteres', () {
      expect(DemoRecordValidator.description(''), isNull);
      expect(DemoRecordValidator.description('a' * 1000), isNull);
    });

    test('rechaza descripciones mayores de 1000 caracteres', () {
      expect(
        DemoRecordValidator.description('a' * 1001),
        'Usa máximo 1000 caracteres.',
      );
    });
  });
}
