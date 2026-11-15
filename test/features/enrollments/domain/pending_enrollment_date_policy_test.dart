import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_date_policy.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('minimumPendingWithdrawalDate', () {
    final today = _date(2026, 11, 14);

    test('permite cancelar hoy si el inicio autorizado aún es futuro', () {
      final minimum = minimumPendingWithdrawalDate(
        enrollment: _pending(effectiveStartDate: _date(2026, 11, 20)),
        today: today,
        courseStart: _date(2026, 11, 1),
      );

      expect(minimum, _date(2026, 11, 10));
      expect(minimum.compareTo(today), lessThanOrEqualTo(0));
    });

    test(
      'preserva la fecha inicial cuando el periodo pendiente ya comenzó',
      () {
        final minimum = minimumPendingWithdrawalDate(
          enrollment: _pending(effectiveStartDate: _date(2026, 11, 12)),
          today: today,
          courseStart: _date(2026, 11, 1),
        );

        expect(minimum, _date(2026, 11, 12));
      },
    );

    test('permite cancelar una autorización antes del inicio del curso', () {
      final minimum = minimumPendingWithdrawalDate(
        enrollment: _pending(effectiveStartDate: _date(2026, 12, 1)),
        today: today,
        courseStart: _date(2026, 12, 1),
      );

      expect(minimum, _date(2026, 11, 10));
    });
  });
}

PendingEnrollment _pending({required AcademicDate effectiveStartDate}) =>
    PendingEnrollment(
      courseId: 'course-1',
      ownerUid: 'teacher-1',
      subject: 'Matemáticas',
      group: 'A',
      period: '2026-2',
      email: 'student@example.invalid',
      studentCode: '000123',
      name: 'Estudiante de prueba',
      status: 'pending',
      effectiveStartDate: effectiveStartDate,
      rosterEntryId: 'student@example.invalid',
      studentUid: null,
      authorizedAt: DateTime.utc(2026, 11, 10, 18),
      linkedAt: null,
      createdAt: DateTime.utc(2026, 11, 10, 18),
      updatedAt: DateTime.utc(2026, 11, 10, 18),
      lastEventId: null,
      lastStatusChangedAt: null,
    );

AcademicDate _date(int year, int month, int day) =>
    AcademicDate(year: year, month: month, day: day);
