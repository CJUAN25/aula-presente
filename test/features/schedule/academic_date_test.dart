import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';

void main() {
  group('AcademicDate', () {
    test('rejects dates that roll into another calendar day', () {
      expect(
        () => AcademicDate(year: 2026, month: 2, day: 29),
        throwsArgumentError,
      );
      expect(
        () => AcademicDate(year: 2026, month: 4, day: 31),
        throwsArgumentError,
      );
    });

    test('serializes a civil date as UTC midnight', () {
      final date = AcademicDate(year: 2024, month: 2, day: 29);
      final timestamp = date.toUtcTimestamp();

      expect(timestamp.isUtc, isTrue);
      expect(timestamp.hour, 0);
      expect(timestamp.minute, 0);
      expect(AcademicDate.fromUtcTimestamp(timestamp), date);
      expect(date.isoDate, '2024-02-29');
      expect(date.weekday, DateTime.thursday);
    });

    test(
      'fromDateTime uses the supplied civil fields, not its UTC instant',
      () {
        final utc = AcademicDate.fromDateTime(DateTime.utc(2026, 1, 2, 23));
        final local = AcademicDate.fromDateTime(DateTime(2026, 1, 2, 23));

        expect(utc, local);
        expect(utc.toUtcTimestamp(), DateTime.utc(2026, 1, 2));
      },
    );

    test('rejects non-midnight and local timestamps from persistence', () {
      expect(
        () => AcademicDate.fromUtcTimestamp(DateTime.utc(2026, 1, 2, 1)),
        throwsArgumentError,
      );
      expect(
        () => AcademicDate.fromUtcTimestamp(DateTime(2026, 1, 2)),
        throwsArgumentError,
      );
    });

    test('adds days across month end, year end and leap day', () {
      expect(
        AcademicDate(year: 2026, month: 1, day: 31).addDays(1).isoDate,
        '2026-02-01',
      );
      expect(
        AcademicDate(year: 2026, month: 12, day: 31).addDays(1).isoDate,
        '2027-01-01',
      );
      expect(
        AcademicDate(year: 2024, month: 2, day: 28).addDays(1).isoDate,
        '2024-02-29',
      );
    });
  });
}
