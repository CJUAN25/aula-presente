import 'dart:convert';

import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/schedule/application/schedule_conflict_detector.dart';
import 'package:aula_presente/features/schedule/application/schedule_conflict_diagnostic.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'report contains every actual overlap witness but counts candidate once',
    () {
      final check = checkScheduleConflicts(
        candidate: _draft(),
        existingCourses: [
          _course('first-secret-id'),
          _course('second-secret-id'),
        ],
      );
      final report =
          jsonDecode(scheduleConflictDiagnostic(check)) as Map<String, dynamic>;

      expect(report['affectedCandidateMeetingCount'], 1);
      expect(report['overlapPairCount'], 2);
      final pairs = report['overlapPairs'] as List;
      expect(pairs.map((p) => p['existing']['course']), [
        'course-1',
        'course-2',
      ]);
      expect(pairs.map((p) => p['candidate']['meeting']).toSet(), {
        'draft|block-1|2026-11-02',
      });
      for (final pair in pairs) {
        expect(pair['candidate']['date'], '2026-11-02');
        expect(pair['existing']['date'], '2026-11-02');
        expect(pair['candidate']['startMinute'], 480);
        expect(pair['existing']['endMinute'], 600);
      }
    },
  );

  test('report uses aliases and omits private fields and real identifiers', () {
    final text = scheduleConflictDiagnostic(
      checkScheduleConflicts(
        candidate: _draft(),
        existingCourses: [_course('first-secret-id')],
      ),
    );
    for (final secret in [
      'first-secret-id',
      'private-draft-id',
      'private-block-id',
      'private-title',
      'private-room',
      'private-owner',
      'private-group',
      'private-program',
      'private-period',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(
      jsonDecode(text)['diagnosticVersion'],
      'aula-schedule-2026-11-02-v1',
    );
  });

  test('same course ID is reported as excluded, with no self overlap', () {
    final check = checkScheduleConflicts(
      candidate: _draft(),
      existingCourses: [_course('private-draft-id')],
    );
    final report = jsonDecode(scheduleConflictDiagnostic(check));
    expect(report['affectedCandidateMeetingCount'], 0);
    expect(report['overlapPairs'], isEmpty);
    expect(report['existingCourses'].single['sameIdAsDraft'], true);
    expect(report['existingCourses'].single['excludedFromComparison'], true);
    expect(report['existingCourses'].single['course'], 'draft');
  });
}

CourseSchedule _schedule() => CourseSchedule(
  startDate: AcademicDate(year: 2026, month: 11, day: 2),
  endDate: AcademicDate(year: 2026, month: 11, day: 2),
  weeklyBlocks: const [
    WeeklyBlock(
      id: 'private-block-id',
      weekday: 1,
      startTime: '08:00',
      endTime: '10:00',
      room: 'private-room',
    ),
  ],
);

CourseDraft _draft() => CourseDraft(
  id: 'private-draft-id',
  subject: 'private-title',
  group: 'private-group',
  period: 'private-period',
  program: 'private-program',
  schedule: _schedule(),
);

Course _course(String id) => Course(
  id: id,
  ownerUid: 'private-owner',
  subject: 'private-title',
  group: 'private-group',
  period: 'private-period',
  program: 'private-program',
  schedule: _schedule(),
);
