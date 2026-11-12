import 'dart:math';

import 'package:aula_presente/features/course_entry/application/course_entry_validator.dart';
import 'package:aula_presente/features/course_entry/domain/course_entry_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourseEntryValidator', () {
    test('invitation lifetime is finite from one hour to ninety days', () {
      CourseEntryValidator.validateValidity(const Duration(hours: 1));
      CourseEntryValidator.validateValidity(const Duration(days: 90));
      for (final invalid in [
        const Duration(seconds: 3599),
        const Duration(days: 91),
        const Duration(microseconds: 3600000001),
      ]) {
        expect(
          () => CourseEntryValidator.validateValidity(invalid),
          throwsA(isA<CourseEntryFailure>()),
        );
      }
    });
    test('normalizes grouped and lowercase codes in one place', () {
      expect(
        CourseEntryValidator.normalizeCode(' abcd-2345 efgh-jkmn '),
        'ABCD2345EFGHJKMN',
      );
    });

    test('rejects a malformed code before it can form a document path', () {
      for (final value in [
        'ABCDEFGHIJKLMNO',
        'ABCDEFGHIJKLMNO/',
        'ABCDEFGHIJKLMN0P',
        'ABCDEFGHIJKLMN1P',
      ]) {
        expect(
          () => CourseEntryValidator.normalizeCode(value),
          throwsA(
            isA<CourseEntryFailure>().having(
              (failure) => failure.kind,
              'kind',
              CourseEntryFailureKind.invalidInput,
            ),
          ),
        );
      }
    });

    test('secure generator uses the exact 32-symbol alphabet and 16 chars', () {
      final generated = CourseEntryValidator.generateCode(random: Random(19));
      expect(generated, hasLength(16));
      expect(
        generated.split('').every(CourseEntryValidator.alphabet.contains),
        isTrue,
      );
      expect(CourseEntryValidator.alphabet, '23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
    });

    test('reject reason is trimmed and length limited', () {
      expect(
        CourseEntryValidator.normalizeRejectionReason('  Grupo completo  '),
        'Grupo completo',
      );
      expect(
        () => CourseEntryValidator.normalizeRejectionReason('  '),
        throwsA(isA<CourseEntryFailure>()),
      );
      expect(
        () => CourseEntryValidator.normalizeRejectionReason(
          List.filled(501, 'x').join(),
        ),
        throwsA(isA<CourseEntryFailure>()),
      );
    });
  });
}
