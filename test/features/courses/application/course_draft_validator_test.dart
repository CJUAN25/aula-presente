import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/courses/application/course_draft_validator.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';

void main() {
  CourseDraft draft({
    String id = 'course_operation_000001',
    String subject = ' Bases   de Datos ',
    String group = ' 2 ',
    String period = '2026-2',
    String program = ' Ingeniería de Sistemas ',
    AttendanceMode? attendanceMode = AttendanceMode.meeting,
  }) => CourseDraft(
    id: id,
    subject: subject,
    group: group,
    period: period,
    program: program,
    attendanceMode: attendanceMode,
    schedule: CourseSchedule(
      startDate: AcademicDate(year: 2026, month: 10, day: 26),
      endDate: AcademicDate(year: 2026, month: 10, day: 26),
      weeklyBlocks: const [
        WeeklyBlock(
          id: 'block_monday_000000001',
          weekday: DateTime.monday,
          startTime: '09:00',
          endTime: '10:00',
          room: ' A   101 ',
        ),
      ],
    ),
  );

  test('normalizes text and optional room without changing stable IDs', () {
    final normalized = draft().normalized();

    expect(normalized.subject, 'Bases de Datos');
    expect(normalized.group, '2');
    expect(normalized.program, 'Ingeniería de Sistemas');
    expect(normalized.id, 'course_operation_000001');
    expect(normalized.schedule.weeklyBlocks.single.room, 'A 101');
  });

  test('reports required and over-limit values by field', () {
    final issues = CourseDraftValidator.validate(
      draft(subject: ' ', program: 'P' * 121),
    );

    expect(
      issues.where((issue) => issue.field == 'subject').map((e) => e.code),
      contains('required'),
    );
    expect(
      issues.where((issue) => issue.field == 'program').map((e) => e.code),
      contains('text_too_long'),
    );
  });

  test('requires an explicit attendance mode for a new course', () {
    final issues = CourseDraftValidator.validate(draft(attendanceMode: null));

    expect(
      issues
          .where((issue) => issue.field == 'attendanceMode')
          .map((e) => e.code),
      ['attendance_mode_required'],
    );
  });

  test(
    'accepts the supported limits and exposes only safe canonical fields',
    () {
      final validDraft = draft(
        subject: 'S' * 120,
        group: 'G' * 40,
        period: 'P' * 32,
        program: 'A' * 120,
      );
      final canonical = validDraft.canonicalFields;

      expect(CourseDraftValidator.validate(validDraft), isEmpty);
      expect(
        canonical.keys,
        containsAll([
          'subject',
          'group',
          'period',
          'program',
          'timezone',
          'startDate',
          'endDate',
          'weeklyBlockIds',
          'status',
          'schemaVersion',
        ]),
      );
      expect(canonical, isNot(contains('ownerUid')));
      expect(canonical, isNot(contains('createdAt')));
      expect(canonical, isNot(contains('updatedAt')));
      expect(canonical['startDate'], DateTime.utc(2026, 10, 26));
      expect(canonical['status'], 'planned');
      expect(canonical['schemaVersion'], 1);
    },
  );

  test(
    'canonicalizes block order without changing visual order or block IDs',
    () {
      const mondayLate = WeeklyBlock(
        id: 'block_monday_late_00001',
        weekday: DateTime.monday,
        startTime: '11:00',
        endTime: '12:00',
      );
      const mondayEarly = WeeklyBlock(
        id: 'block_monday_early_0001',
        weekday: DateTime.monday,
        startTime: '09:00',
        endTime: '10:00',
      );
      final startDate = AcademicDate(year: 2026, month: 10, day: 26);
      final endDate = AcademicDate(year: 2026, month: 11, day: 2);

      CourseDraft withOrder(List<WeeklyBlock> blocks) => CourseDraft(
        id: 'course_operation_000001',
        subject: 'Bases de Datos',
        group: '2',
        period: '2026-2',
        program: 'Ingeniería',
        attendanceMode: AttendanceMode.meeting,
        schedule: CourseSchedule(
          startDate: startDate,
          endDate: endDate,
          weeklyBlocks: blocks,
        ),
      );

      final visualOrderOne = withOrder([mondayLate, mondayEarly]);
      final visualOrderTwo = withOrder([mondayEarly, mondayLate]);
      final canonicalOne = visualOrderOne.canonicalFields;
      final canonicalTwo = visualOrderTwo.canonicalFields;

      expect(canonicalOne, equals(canonicalTwo));
      final canonicalBlockIds = canonicalOne['weeklyBlockIds']! as List<String>;
      expect(canonicalBlockIds, [mondayEarly.id, mondayLate.id]);
      expect(
        visualOrderOne.canonicalWeeklyBlockDocuments,
        equals(visualOrderTwo.canonicalWeeklyBlockDocuments),
      );
      expect(visualOrderOne.canonicalWeeklyBlockDocuments.keys, [
        mondayEarly.id,
        mondayLate.id,
      ]);
      expect(visualOrderOne.canonicalWeeklyBlockDocuments[mondayEarly.id], {
        'weekday': DateTime.monday,
        'startMinute': 9 * 60,
        'endMinute': 10 * 60,
        'room': null,
        'order': 0,
      });
      expect(
        visualOrderOne.canonicalWeeklyBlockDocuments[mondayEarly.id],
        isNot(contains('id')),
      );
      expect(visualOrderOne.schedule.weeklyBlocks.map((block) => block.id), [
        mondayLate.id,
        mondayEarly.id,
      ]);
      expect(visualOrderTwo.schedule.weeklyBlocks.map((block) => block.id), [
        mondayEarly.id,
        mondayLate.id,
      ]);
    },
  );
}
