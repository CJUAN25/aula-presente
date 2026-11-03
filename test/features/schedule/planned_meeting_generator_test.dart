import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/planned_meeting_generator.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';

void main() {
  const blockMonday = WeeklyBlock(
    id: 'block_monday_00000001',
    weekday: DateTime.monday,
    startTime: '09:00',
    endTime: '10:00',
    room: 'A-101',
  );
  const blockWednesday = WeeklyBlock(
    id: 'block_wednesday_00001',
    weekday: DateTime.wednesday,
    startTime: '08:00',
    endTime: '09:00',
  );

  test('includes both endpoint dates and supports a one-day range', () {
    final monday = AcademicDate(year: 2026, month: 10, day: 26);
    final schedule = CourseSchedule(
      startDate: monday,
      endDate: monday,
      weeklyBlocks: const [blockMonday],
    );

    final meetings = generatePlannedMeetings(
      courseId: 'course-1',
      schedule: schedule,
    );

    expect(meetings, hasLength(1));
    expect(meetings.single.date, monday);
    expect(meetings.single.id, 'course-1|${blockMonday.id}|2026-10-26');
  });

  test('generates sorted occurrences over month and year boundaries', () {
    final schedule = CourseSchedule(
      startDate: AcademicDate(year: 2026, month: 12, day: 30),
      endDate: AcademicDate(year: 2027, month: 1, day: 5),
      weeklyBlocks: const [blockMonday, blockWednesday],
    );

    final meetings = generatePlannedMeetings(
      courseId: 'course-1',
      schedule: schedule,
    );

    expect(meetings.map((meeting) => meeting.date.isoDate), [
      '2026-12-30',
      '2027-01-04',
    ]);
    expect(
      meetings.map((meeting) => meeting.id).toSet(),
      hasLength(meetings.length),
    );
  });

  test('generates leap-day occurrence and stable IDs across repeated runs', () {
    final schedule = CourseSchedule(
      startDate: AcademicDate(year: 2024, month: 2, day: 29),
      endDate: AcademicDate(year: 2024, month: 2, day: 29),
      weeklyBlocks: const [
        WeeklyBlock(
          id: 'block_thursday_000001',
          weekday: DateTime.thursday,
          startTime: '14:00',
          endTime: '15:00',
        ),
      ],
    );

    final first = generatePlannedMeetings(
      courseId: 'course-7',
      schedule: schedule,
    );
    final second = generatePlannedMeetings(
      courseId: 'course-7',
      schedule: schedule,
    );

    expect(first.single.date.isoDate, '2024-02-29');
    expect(first.single.id, second.single.id);
  });

  test(
    'orders same-day blocks by local start time, regardless of input order',
    () {
      const late = WeeklyBlock(
        id: 'block_late_0000000001',
        weekday: DateTime.monday,
        startTime: '11:00',
        endTime: '12:00',
      );
      const early = WeeklyBlock(
        id: 'block_early_000000001',
        weekday: DateTime.monday,
        startTime: '08:00',
        endTime: '09:00',
      );
      final monday = AcademicDate(year: 2026, month: 10, day: 26);
      final schedule = CourseSchedule(
        startDate: monday,
        endDate: monday,
        weeklyBlocks: const [late, early],
      );

      final meetings = generatePlannedMeetings(
        courseId: 'course-1',
        schedule: schedule,
      );

      expect(meetings.map((meeting) => meeting.startTime), ['08:00', '11:00']);
      expect(meetings, isA<List>());
    },
  );

  test('interprets block hours independently of host timezone settings', () {
    final date = AcademicDate(year: 2026, month: 10, day: 26);
    final schedule = CourseSchedule(
      startDate: date,
      endDate: date,
      weeklyBlocks: const [blockMonday],
    );

    final meetings = generatePlannedMeetings(
      courseId: 'course-1',
      schedule: schedule,
    );

    expect(meetings.single.startTime, '09:00');
    expect(meetings.single.endTime, '10:00');
    expect(schedule.timezone, 'America/Bogota');
    expect(meetings.single.date, date);
  });

  test('rejects a reversed date range', () {
    final schedule = CourseSchedule(
      startDate: AcademicDate(year: 2026, month: 10, day: 27),
      endDate: AcademicDate(year: 2026, month: 10, day: 26),
      weeklyBlocks: const [blockMonday],
    );

    expect(
      () => generatePlannedMeetings(courseId: 'course-1', schedule: schedule),
      throwsArgumentError,
    );
  });
}
