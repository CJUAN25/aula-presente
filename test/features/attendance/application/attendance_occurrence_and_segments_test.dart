import 'package:aula_presente/features/attendance/application/attendance_occurrence_resolver.dart';
import 'package:aula_presente/features/attendance/application/attendance_segment_factory.dart';
import 'package:aula_presente/features/attendance/application/attendance_validator.dart';
import 'package:aula_presente/features/attendance/domain/attendance_calendar_change.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/planned_meeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final planned = PlannedMeeting(
    id: 'course-1|block-1|2026-11-16',
    courseId: 'course-1',
    blockId: 'block-1',
    date: AcademicDate(year: 2026, month: 11, day: 16),
    weekday: DateTime.monday,
    startTime: '08:00',
    endTime: '10:00',
    room: 'A-101',
  );

  test('keeps PlannedMeeting.id for ordinary and rescheduled occurrences', () {
    final regular = AttendanceOccurrenceResolver.resolve(
      courseId: 'course-1',
      plannedMeetings: [planned],
      changes: const [],
    );
    expect(regular.single.id, planned.id);
    expect(regular.single.kind, AttendanceOccurrenceKind.planned);

    final changed = AttendanceOccurrenceResolver.resolve(
      courseId: 'course-1',
      plannedMeetings: [planned],
      changes: [
        AttendanceCalendarChange(
          occurrenceId: planned.id,
          kind: AttendanceCalendarChangeKind.rescheduled,
          originalDate: AcademicDate(year: 2026, month: 11, day: 16),
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 18),
          startMinute: 600,
          endMinute: 720,
          reason: 'Salón no disponible',
          version: 1,
        ),
      ],
    );
    expect(changed.single.id, planned.id);
    expect(changed.single.kind, AttendanceOccurrenceKind.rescheduled);
    expect(changed.single.scheduledDate.isoDate, '2026-11-16');
    expect(changed.single.effectiveDate.isoDate, '2026-11-18');
  });

  test('keeps cancellations and adds an independent extra occurrence', () {
    final occurrences = AttendanceOccurrenceResolver.resolve(
      courseId: 'course-1',
      plannedMeetings: [planned],
      changes: [
        AttendanceCalendarChange(
          occurrenceId: planned.id,
          kind: AttendanceCalendarChangeKind.cancelled,
          originalDate: AcademicDate(year: 2026, month: 11, day: 16),
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 16),
          startMinute: 480,
          endMinute: 600,
          reason: 'Festivo',
          version: 2,
        ),
        AttendanceCalendarChange(
          occurrenceId: 'course-1|extra|2026-11-20',
          kind: AttendanceCalendarChangeKind.additional,
          originalDate: AcademicDate(year: 2026, month: 11, day: 20),
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 20),
          startMinute: 480,
          endMinute: 540,
          reason: 'Reposición',
          version: 1,
        ),
      ],
    );

    expect(occurrences, hasLength(2));
    expect(
      occurrences
          .singleWhere(
            (item) => item.kind == AttendanceOccurrenceKind.cancelled,
          )
          .id,
      planned.id,
    );
    expect(
      occurrences
          .singleWhere(
            (item) => item.kind == AttendanceOccurrenceKind.additional,
          )
          .id,
      'course-1|extra|2026-11-20',
    );
  });

  test(
    'splits duration into contiguous stable segments of at most 60 minutes',
    () {
      final occurrence = AttendanceOccurrence(
        id: 'course-1|block-2|2026-11-16',
        courseId: 'course-1',
        kind: AttendanceOccurrenceKind.planned,
        scheduledDate: AcademicDate(year: 2026, month: 11, day: 16),
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 16),
        startMinute: 360,
        endMinute: 490,
      );
      final segments = AttendanceSegmentFactory.forOccurrence(occurrence);

      expect(segments.map((segment) => segment.durationMinutes), [60, 60, 10]);
      expect(segments.map((segment) => segment.id), [
        'course-1|block-2|2026-11-16|segment|0',
        'course-1|block-2|2026-11-16|segment|1',
        'course-1|block-2|2026-11-16|segment|2',
      ]);
      expect(segments[0].endMinute, segments[1].startMinute);
      expect(segments[1].endMinute, segments[2].startMinute);
    },
  );

  test('refuses to prepare cancelled or malformed occurrences', () {
    final cancelled = AttendanceOccurrence(
      id: planned.id,
      courseId: 'course-1',
      kind: AttendanceOccurrenceKind.cancelled,
      scheduledDate: AcademicDate(year: 2026, month: 11, day: 16),
      effectiveDate: AcademicDate(year: 2026, month: 11, day: 16),
      startMinute: 480,
      endMinute: 600,
    );
    expect(
      () => AttendanceValidator.validateCanPrepare(cancelled),
      throwsA(isA<AttendanceValidationFailure>()),
    );
    expect(
      () => AttendanceSegmentFactory.forOccurrence(cancelled),
      throwsArgumentError,
    );
  });
}
