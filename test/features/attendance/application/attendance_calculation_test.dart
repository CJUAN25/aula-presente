import 'package:aula_presente/features/attendance/application/attendance_course_summary_calculator.dart';
import 'package:aula_presente/features/attendance/application/attendance_record_calculator.dart';
import 'package:aula_presente/features/attendance/application/attendance_segment_factory.dart';
import 'package:aula_presente/features/attendance/domain/attendance_course_summary.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/attendance/domain/attendance_record.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/attendance/domain/attendance_segment.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one absence out of five meetings is exactly 20 percent', () {
    final records = [
      for (var day = 1; day <= 5; day++)
        _published(
          _meetingRecord(
            day: day,
            mark: day == 1 ? AttendanceMark.absent : AttendanceMark.present,
          ),
        ),
    ];

    final summary = AttendanceCourseSummaryCalculator.calculate(records);

    expect(summary.registeredUnits, 5);
    expect(summary.countedAbsenceUnits, 1);
    expect(summary.percent, 20);
    expect(summary.thresholdReached, isTrue);
  });

  test('one missing 60-minute segment in a 120-minute block is 60/120', () {
    final date = AcademicDate(year: 2026, month: 11, day: 2);
    final occurrence = AttendanceOccurrence(
      id: 'course-1|block-2|${date.isoDate}',
      courseId: 'course-1',
      kind: AttendanceOccurrenceKind.planned,
      scheduledDate: date,
      effectiveDate: date,
      startMinute: 480,
      endMinute: 600,
    );
    final segments = AttendanceSegmentFactory.forOccurrence(occurrence);
    final session = _session(
      id: occurrence.id,
      date: date,
      mode: AttendanceMode.minutes,
      segments: segments,
    );
    final entry = AttendanceRosterEntry(
      rosterEntryId: 'student-1',
      displayName: 'Estudiante',
      studentUid: 'uid-1',
      meetingMark: null,
      segmentMarks: {
        segments[0].id: _mark(AttendanceMark.absent, absent: 60),
        segments[1].id: _mark(AttendanceMark.present),
      },
      version: 1,
    );

    final record = AttendanceRecordCalculator.fromRosterEntry(
      session: session,
      entry: entry,
      segments: segments,
    );
    final summary = AttendanceCourseSummaryCalculator.calculate([
      _published(record),
    ]);

    expect(record.unitCount, 120);
    expect(record.absentUnits, 60);
    expect(record.result, AttendanceSessionResult.partial);
    expect(summary.registeredUnits, 120);
    expect(summary.countedAbsenceUnits, 60);
    expect(summary.percent, 50);
    expect(summary.thresholdReached, isTrue);
  });

  test(
    'accepted justification preserves gross absence but removes coverage',
    () {
      final record = _meetingRecord(
        day: 3,
        mark: AttendanceMark.absent,
        justificationStatus: AttendanceJustificationStatus.justified,
        justified: 1,
      );
      final summary = AttendanceCourseSummaryCalculator.calculate([
        _published(record),
      ]);

      expect(record.absentUnits, 1);
      expect(record.justifiedUnits, 1);
      expect(record.result, AttendanceSessionResult.justified);
      expect(summary.registeredUnits, 1);
      expect(summary.countedAbsenceUnits, 0);
      expect(summary.justifiedUnits, 1);
      expect(summary.thresholdReached, isFalse);
    },
  );

  test('absence under review remains counted provisionally', () {
    final record = _meetingRecord(
      day: 4,
      mark: AttendanceMark.absent,
      justificationStatus: AttendanceJustificationStatus.inReview,
    );
    final summary = AttendanceCourseSummaryCalculator.calculate([
      _published(record),
    ]);

    expect(record.inReviewUnits, 1);
    expect(summary.countedAbsenceUnits, 1);
    expect(summary.inReviewUnits, 1);
    expect(summary.thresholdReached, isTrue);
  });

  test('staged unmarked rows are not included in a student summary', () {
    final record = _meetingRecord(day: 5, mark: AttendanceMark.unmarked);
    final summary = AttendanceCourseSummaryCalculator.calculate([record]);

    expect(record.result, AttendanceSessionResult.unmarked);
    expect(summary.hasAttendance, isFalse);
    expect(summary.thresholdReached, isFalse);
  });

  test('voided published rows remain notices but add no units', () {
    final date = AcademicDate(year: 2026, month: 11, day: 6);
    final session = _session(
      id: 'course-1|block-1|${date.isoDate}',
      date: date,
      mode: AttendanceMode.meeting,
      status: AttendanceSessionStatus.voided,
    );
    final entry = AttendanceRosterEntry(
      rosterEntryId: 'student-1',
      displayName: 'Estudiante',
      studentUid: 'uid-1',
      meetingMark: _mark(AttendanceMark.absent),
      segmentMarks: const {},
      version: 2,
    );
    final record = AttendanceRecordCalculator.fromRosterEntry(
      session: session,
      entry: entry,
      segments: const [],
    );
    final summary = AttendanceCourseSummaryCalculator.calculate([record]);

    expect(record.visibility, AttendanceRecordVisibility.published);
    expect(record.result, AttendanceSessionResult.voided);
    expect(summary, isA<AttendanceCourseSummary>());
    expect(summary.registeredUnits, 0);
    expect(summary.countedAbsenceUnits, 0);
  });
}

AttendanceRecord _meetingRecord({
  required int day,
  required AttendanceMark mark,
  AttendanceJustificationStatus justificationStatus =
      AttendanceJustificationStatus.none,
  int justified = 0,
}) {
  final date = AcademicDate(year: 2026, month: 11, day: day);
  final session = _session(
    id: 'course-1|block-1|${date.isoDate}',
    date: date,
    mode: AttendanceMode.meeting,
  );
  final entry = AttendanceRosterEntry(
    rosterEntryId: 'student-1',
    displayName: 'Estudiante',
    studentUid: 'uid-1',
    meetingMark: _mark(
      mark,
      justificationStatus: justificationStatus,
      justified: justified,
    ),
    segmentMarks: const {},
    version: 1,
  );
  return AttendanceRecordCalculator.fromRosterEntry(
    session: session,
    entry: entry,
    segments: const [],
  );
}

AttendanceRosterMark _mark(
  AttendanceMark mark, {
  int absent = 0,
  AttendanceJustificationStatus justificationStatus =
      AttendanceJustificationStatus.none,
  int justified = 0,
}) => AttendanceRosterMark(
  mark: mark,
  absentUnits: absent == 0 && mark == AttendanceMark.absent ? 1 : absent,
  justificationStatus: justificationStatus,
  justifiedUnits: justified,
);

AttendanceSession _session({
  required String id,
  required AcademicDate date,
  required AttendanceMode mode,
  AttendanceSessionStatus status = AttendanceSessionStatus.finalized,
  List<AttendanceSegment> segments = const [],
}) => AttendanceSession(
  courseId: 'course-1',
  ownerUid: 'teacher-1',
  occurrenceId: id,
  occurrenceKind: AttendanceOccurrenceKind.planned,
  mode: mode,
  status: status,
  rosterState: AttendanceRosterState.ready,
  scheduledDate: date,
  effectiveDate: date,
  startMinute: 480,
  endMinute: mode == AttendanceMode.meeting ? 540 : 600,
  timezone: 'America/Bogota',
  segmentIds: segments.map((segment) => segment.id).toList(),
  rosterCount: 1,
  markedCount: 1,
  unmarkedCount: 0,
  version: 1,
  lastMutationRosterEntryId: null,
  lastMutationKind: null,
  lastEventId: null,
  createdAt: null,
  createdBy: 'teacher-1',
  updatedAt: null,
  updatedBy: 'teacher-1',
);

AttendanceRecord _published(AttendanceRecord record) => AttendanceRecord(
  courseId: record.courseId,
  sessionId: record.sessionId,
  rosterEntryId: record.rosterEntryId,
  visibility: AttendanceRecordVisibility.published,
  mode: record.mode,
  scheduledDate: record.scheduledDate,
  effectiveDate: record.effectiveDate,
  startMinute: record.startMinute,
  endMinute: record.endMinute,
  unitCount: record.unitCount,
  absentUnits: record.absentUnits,
  inReviewUnits: record.inReviewUnits,
  justifiedUnits: record.justifiedUnits,
  result: record.result,
  segments: record.segments,
  publishedAt: DateTime.utc(2026, 11, 30),
  updatedAt: DateTime.utc(2026, 11, 30),
);
