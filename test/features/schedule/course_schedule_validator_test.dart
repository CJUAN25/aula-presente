import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/schedule/application/course_schedule_validator.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';

void main() {
  final firstMonday = AcademicDate(year: 2026, month: 10, day: 26);
  const mondayBlock = WeeklyBlock(
    id: 'block_monday_000000001',
    weekday: DateTime.monday,
    startTime: '09:00',
    endTime: '10:00',
  );

  CourseSchedule schedule({
    AcademicDate? start,
    AcademicDate? end,
    List<WeeklyBlock> blocks = const [mondayBlock],
    String timezone = CourseSchedule.academicTimezone,
  }) => CourseSchedule(
    startDate: start ?? firstMonday,
    endDate: end ?? firstMonday,
    weeklyBlocks: blocks,
    timezone: timezone,
  );

  test('accepts a range with 366 inclusive dates and rejects 367', () {
    final validRange = schedule(
      start: AcademicDate(year: 2026, month: 1, day: 1),
      end: AcademicDate(year: 2027, month: 1, day: 1),
    );
    final invalidRange = schedule(
      start: AcademicDate(year: 2026, month: 1, day: 1),
      end: AcademicDate(year: 2027, month: 1, day: 2),
    );

    expect(
      CourseScheduleValidator.validate(validRange).map((issue) => issue.code),
      isNot(contains('range_too_long')),
    );
    expect(
      CourseScheduleValidator.validate(invalidRange).map((issue) => issue.code),
      contains('range_too_long'),
    );
  });

  test('allows eight valid blocks and rejects nine', () {
    final eight = List.generate(
      8,
      (index) => WeeklyBlock(
        id: 'block_${index.toString().padLeft(16, '0')}',
        weekday: DateTime.monday,
        startTime: '${(index * 2).toString().padLeft(2, '0')}:00',
        endTime: '${(index * 2 + 1).toString().padLeft(2, '0')}:00',
      ),
    );
    final nine = [
      ...eight,
      const WeeklyBlock(
        id: 'block_9999999999999999',
        weekday: DateTime.monday,
        startTime: '20:00',
        endTime: '21:00',
      ),
    ];

    expect(
      CourseScheduleValidator.validate(schedule(blocks: eight))
          .map((issue) => issue.code),
      isNot(contains('block_count')),
    );
    expect(
      CourseScheduleValidator.validate(schedule(blocks: nine))
          .map((issue) => issue.code),
      contains('block_count'),
    );
  });

  test('allows adjacent blocks and rejects overlapping blocks', () {
    const adjacent = [
      mondayBlock,
      WeeklyBlock(
        id: 'block_monday_000000002',
        weekday: DateTime.monday,
        startTime: '10:00',
        endTime: '11:00',
      ),
    ];
    const overlapping = [
      mondayBlock,
      WeeklyBlock(
        id: 'block_monday_000000002',
        weekday: DateTime.monday,
        startTime: '09:30',
        endTime: '10:30',
      ),
    ];

    expect(
      CourseScheduleValidator.validate(schedule(blocks: adjacent))
          .map((issue) => issue.code),
      isNot(contains('overlapping_blocks')),
    );
    expect(
      CourseScheduleValidator.validate(schedule(blocks: overlapping))
          .map((issue) => issue.code),
      contains('overlapping_blocks'),
    );
  });

  test('rejects repeated block IDs and exact repeated blocks', () {
    final repeatedId = [
      mondayBlock,
      WeeklyBlock(
        id: mondayBlock.id,
        weekday: DateTime.wednesday,
        startTime: '09:00',
        endTime: '10:00',
      ),
    ];
    const duplicate = [
      mondayBlock,
      WeeklyBlock(
        id: 'block_monday_000000002',
        weekday: DateTime.monday,
        startTime: '09:00',
        endTime: '10:00',
      ),
    ];

    expect(
      CourseScheduleValidator.validate(schedule(blocks: repeatedId))
          .map((issue) => issue.code),
      contains('duplicate_block_id'),
    );
    expect(
      CourseScheduleValidator.validate(schedule(blocks: duplicate))
          .map((issue) => issue.code),
      contains('duplicate_block'),
    );
  });

  test('rejects a valid weekly block with no occurrence in its date range', () {
    final tuesday = AcademicDate(year: 2026, month: 10, day: 27);
    final tuesdayOnly = schedule(
      start: tuesday,
      end: tuesday,
      blocks: const [
        WeeklyBlock(
          id: 'block_monday_000000001',
          weekday: DateTime.monday,
          startTime: '09:00',
          endTime: '10:00',
        ),
      ],
    );

    expect(
      CourseScheduleValidator.validate(tuesdayOnly).map((issue) => issue.code),
      contains('no_occurrences'),
    );
  });

  test('checks invalid block data at every list position', () {
    const validWednesday = WeeklyBlock(
      id: 'block_wednesday_00001',
      weekday: DateTime.wednesday,
      startTime: '10:00',
      endTime: '11:00',
    );
    const invalid = WeeklyBlock(
      id: 'bad',
      weekday: 8,
      startTime: '13:00',
      endTime: '12:00',
    );

    for (final blocks in [
      const [invalid, validWednesday],
      const [validWednesday, invalid, validWednesday],
      const [validWednesday, invalid],
    ]) {
      final issues = CourseScheduleValidator.validate(
        schedule(
          start: AcademicDate(year: 2026, month: 10, day: 28),
          end: AcademicDate(year: 2026, month: 10, day: 28),
          blocks: blocks,
        ),
      );
      expect(issues.map((issue) => issue.code), contains('invalid_weekday'));
      expect(issues.map((issue) => issue.code), contains('invalid_block_id'));
      expect(issues.map((issue) => issue.code), contains('invalid_time_range'));
    }
  });

  test('fixes the academic timezone to Bogota', () {
    final invalidTimezone = schedule(timezone: 'UTC');
    expect(
      CourseScheduleValidator.validate(invalidTimezone)
          .map((issue) => issue.code),
      contains('unsupported_timezone'),
    );
    expect(invalidTimezone.normalized().timezone, 'UTC');
  });
}
