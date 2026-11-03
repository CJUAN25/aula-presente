import 'package:aula_presente/features/administration/application/teacher_access_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeacherAccessValidator.rejectionReason', () {
    test('normalizes the reason by trimming surrounding spaces', () {
      expect(
        TeacherAccessValidator.normalizeRejectionReason('  Motivo  '),
        'Motivo',
      );
      expect(TeacherAccessValidator.rejectionReasonError('  Motivo  '), isNull);
    });

    test('rejects empty and whitespace-only reasons', () {
      expect(
        TeacherAccessValidator.rejectionReasonError(''),
        'Escribe el motivo del rechazo.',
      );
      expect(
        TeacherAccessValidator.rejectionReasonError('   '),
        'Escribe el motivo del rechazo.',
      );
    });

    test('accepts a reason of 500 characters', () {
      expect(TeacherAccessValidator.rejectionReasonError('a' * 500), isNull);
    });

    test('rejects a reason of 501 characters', () {
      expect(
        TeacherAccessValidator.rejectionReasonError('a' * 501),
        'Usa máximo 500 caracteres.',
      );
    });
  });
}
