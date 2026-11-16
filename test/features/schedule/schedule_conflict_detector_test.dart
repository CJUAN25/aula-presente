import 'package:flutter_test/flutter_test.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/schedule/application/schedule_conflict_detector.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';

void main() {
  final start = AcademicDate(year: 2026, month: 10, day: 26);
  final end = AcademicDate(year: 2026, month: 11, day: 2);

  CourseSchedule schedule({
    required int weekday,
    required String startTime,
    required String endTime,
    AcademicDate? scheduleStart,
    AcademicDate? scheduleEnd,
  }) => CourseSchedule(
    startDate: scheduleStart ?? start,
    endDate: scheduleEnd ?? end,
    weeklyBlocks: [
      WeeklyBlock(
        id: 'block_$weekday${startTime.replaceAll(':', '')}000000',
        weekday: weekday,
        startTime: startTime,
        endTime: endTime,
      ),
    ],
  );

  CourseDraft draft(CourseSchedule value) => CourseDraft(
    id: 'draft_0000000000000001',
    subject: 'Candidate',
    group: '1',
    period: '2026-2',
    program: 'Engineering',
    attendanceMode: AttendanceMode.meeting,
    schedule: value,
  );

  Course course(String id, CourseSchedule value) => Course(
    id: id,
    ownerUid: 'teacher-1',
    subject: id,
    group: '1',
    period: '2026-2',
    program: 'Engineering',
    schedule: value,
  );

  test('reports a conflict only for a shared occurrence date and overlap', () {
    final candidate = draft(
      schedule(weekday: DateTime.monday, startTime: '09:00', endTime: '10:00'),
    );
    final existing = course(
      'existing-1',
      schedule(weekday: DateTime.monday, startTime: '09:30', endTime: '10:30'),
    );

    final conflicts = findScheduleConflicts(
      candidate: candidate,
      existingCourses: [existing],
    );

    expect(conflicts, hasLength(2)); // Both Mondays intersect the date range.
    expect(conflicts.first.existingCourseId, 'existing-1');
  });

  test('ignores different weekdays and blocks that only touch endpoints', () {
    final candidate = draft(
      schedule(weekday: DateTime.monday, startTime: '09:00', endTime: '10:00'),
    );
    final differentWeekday = course(
      'tuesday-course',
      schedule(weekday: DateTime.tuesday, startTime: '09:30', endTime: '10:30'),
    );
    final adjacent = course(
      'adjacent-course',
      schedule(weekday: DateTime.monday, startTime: '10:00', endTime: '11:00'),
    );

    expect(
      findScheduleConflicts(
        candidate: candidate,
        existingCourses: [differentWeekday, adjacent],
      ),
      isEmpty,
    );
  });

  test('requires a common date in the overlapping ranges', () {
    final candidate = draft(
      schedule(
        weekday: DateTime.monday,
        startTime: '09:00',
        endTime: '10:00',
        scheduleStart: AcademicDate(year: 2026, month: 10, day: 26),
        scheduleEnd: AcademicDate(year: 2026, month: 10, day: 26),
      ),
    );
    final laterMonday = course(
      'later-course',
      schedule(
        weekday: DateTime.monday,
        startTime: '09:30',
        endTime: '10:30',
        scheduleStart: AcademicDate(year: 2026, month: 11, day: 2),
        scheduleEnd: AcademicDate(year: 2026, month: 11, day: 2),
      ),
    );

    expect(
      findScheduleConflicts(
        candidate: candidate,
        existingCourses: [laterMonday],
      ),
      isEmpty,
    );
  });

  test('skips the same stable draft ID during reconciliation', () {
    final candidateSchedule = schedule(
      weekday: DateTime.monday,
      startTime: '09:00',
      endTime: '10:00',
    );

    expect(
      findScheduleConflicts(
        candidate: draft(candidateSchedule),
        existingCourses: [course('draft_0000000000000001', candidateSchedule)],
      ),
      isEmpty,
    );
  });

  test('Móvil lunes/viernes y Lógica martes/jueves no comparten fecha', () {
    final rangeStart = AcademicDate(year: 2026, month: 11, day: 2);
    final rangeEnd = AcademicDate(year: 2026, month: 11, day: 15);
    CourseSchedule twoDays(List<WeeklyBlock> blocks) => CourseSchedule(
      startDate: rangeStart,
      endDate: rangeEnd,
      weeklyBlocks: blocks,
    );
    final mobile = course(
      'mobile',
      twoDays(const [
        WeeklyBlock(
          id: 'mobile_monday_block_01',
          weekday: 1,
          startTime: '08:00',
          endTime: '10:00',
        ),
        WeeklyBlock(
          id: 'mobile_friday_block_01',
          weekday: 5,
          startTime: '06:00',
          endTime: '10:00',
        ),
      ]),
    );
    final logic = draft(
      twoDays(const [
        WeeklyBlock(
          id: 'logic_tuesday_block_01',
          weekday: 2,
          startTime: '08:00',
          endTime: '09:00',
        ),
        WeeklyBlock(
          id: 'logic_thursday_block01',
          weekday: 4,
          startTime: '08:00',
          endTime: '09:00',
        ),
      ]),
    );

    expect(
      findScheduleConflicts(candidate: logic, existingCourses: [mobile]),
      isEmpty,
    );
  });

  test('one proposed meeting overlapping two courses counts once', () {
    final oneMonday = schedule(
      weekday: DateTime.monday,
      startTime: '08:00',
      endTime: '10:00',
      scheduleStart: AcademicDate(year: 2026, month: 10, day: 26),
      scheduleEnd: AcademicDate(year: 2026, month: 10, day: 26),
    );
    final candidate = draft(oneMonday);
    final first = course('first-course', oneMonday);
    final second = course('second-course', oneMonday);

    expect(
      findScheduleConflicts(
        candidate: candidate,
        existingCourses: [first, second],
      ),
      hasLength(1),
    );
  });

  test(
    'received Monday/Tuesday data explains 17 conflicts; Friday yields zero',
    () {
      final rangeStart = AcademicDate(year: 2026, month: 11, day: 1);
      final rangeEnd = AcademicDate(year: 2027, month: 2, day: 28);
      CourseSchedule period(List<WeeklyBlock> blocks) => CourseSchedule(
        startDate: rangeStart,
        endDate: rangeEnd,
        weeklyBlocks: blocks,
      );
      final candidate = draft(
        period(const [
          WeeklyBlock(
            id: 'candidate_tuesday_0001',
            weekday: 2,
            startTime: '08:00',
            endTime: '09:00',
          ),
          WeeklyBlock(
            id: 'candidate_thursday001',
            weekday: 4,
            startTime: '08:00',
            endTime: '09:00',
          ),
        ]),
      );
      Course existing(int secondWeekday) => course(
        'synthetic-existing',
        period([
          const WeeklyBlock(
            id: 'existing_monday_00001',
            weekday: 1,
            startTime: '08:00',
            endTime: '10:00',
          ),
          WeeklyBlock(
            id: 'existing_second_00001',
            weekday: secondWeekday,
            startTime: '06:00',
            endTime: '10:00',
          ),
        ]),
      );

      final conflicts = findScheduleConflicts(
        candidate: candidate,
        existingCourses: [existing(2)],
      );
      expect(conflicts.map((c) => c.candidateMeeting.date.isoDate), [
        '2026-11-03',
        '2026-11-10',
        '2026-11-17',
        '2026-11-24',
        '2026-12-01',
        '2026-12-08',
        '2026-12-15',
        '2026-12-22',
        '2026-12-29',
        '2027-01-05',
        '2027-01-12',
        '2027-01-19',
        '2027-01-26',
        '2027-02-02',
        '2027-02-09',
        '2027-02-16',
        '2027-02-23',
      ]);
      for (final conflict in conflicts) {
        expect(conflict.existingCourseId, 'synthetic-existing');
        expect(conflict.existingMeeting.blockId, 'existing_second_00001');
        expect(conflict.candidateMeeting.weekday, DateTime.tuesday);
        expect(conflict.candidateMeeting.date, conflict.existingMeeting.date);
      }
      expect(
        findScheduleConflicts(
          candidate: candidate,
          existingCourses: [existing(5)],
        ),
        isEmpty,
      );
    },
  );

  for (final (
        candidateStart,
        candidateEnd,
        existingStart,
        existingEnd,
        expected,
      )
      in [
        ('08:00', '10:00', '09:00', '11:00', 1),
        ('08:00', '10:00', '10:00', '12:00', 0),
        ('08:00', '10:00', '08:00', '10:00', 1),
        ('08:00', '10:00', '08:30', '09:30', 1),
      ]) {
    test(
      'Monday $candidateStart–$candidateEnd versus $existingStart–$existingEnd yields $expected affected meeting',
      () {
        final monday = AcademicDate(year: 2026, month: 10, day: 26);
        final proposed = draft(
          schedule(
            weekday: 1,
            startTime: candidateStart,
            endTime: candidateEnd,
            scheduleStart: monday,
            scheduleEnd: monday,
          ),
        );
        final stored = course(
          'stored',
          schedule(
            weekday: 1,
            startTime: existingStart,
            endTime: existingEnd,
            scheduleStart: monday,
            scheduleEnd: monday,
          ),
        );

        expect(
          findScheduleConflicts(candidate: proposed, existingCourses: [stored]),
          hasLength(expected),
        );
      },
    );
  }
}
