import '../domain/attendance_course_summary.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_session.dart';

/// Aggregates all published, paginated student projections for a course.
/// Duplicate page rows are ignored only when their values match; conflicting
/// copies fail instead of inflating or silently changing the summary.
class AttendanceCourseSummaryCalculator {
  const AttendanceCourseSummaryCalculator._();

  static AttendanceCourseSummary calculate(Iterable<AttendanceRecord> records) {
    final unique = <String, AttendanceRecord>{};
    final courseIds = <String>{};
    for (final record in records) {
      if (record.visibility != AttendanceRecordVisibility.published) continue;
      courseIds.add(record.courseId);
      if (record.result == AttendanceSessionResult.voided) continue;
      if (record.result == AttendanceSessionResult.unmarked) {
        throw ArgumentError(
          'An unmarked attendance record cannot be published.',
        );
      }
      final previous = unique[record.recordId];
      if (previous != null) {
        if (!_sameRecord(previous, record)) {
          throw StateError(
            'Conflicting pages contain the same attendance record.',
          );
        }
        continue;
      }
      unique[record.recordId] = record;
    }

    var registered = 0;
    var countedAbsence = 0;
    var inReview = 0;
    var justified = 0;
    for (final record in unique.values) {
      if (record.unitCount <= 0 ||
          record.absentUnits < 0 ||
          record.absentUnits > record.unitCount ||
          record.justifiedUnits < 0 ||
          record.justifiedUnits > record.absentUnits ||
          record.inReviewUnits < 0 ||
          record.inReviewUnits > record.absentUnits ||
          record.inReviewUnits > record.absentUnits - record.justifiedUnits) {
        throw ArgumentError('Attendance record contains inconsistent units.');
      }
      registered += record.unitCount;
      final counted = record.absentUnits - record.justifiedUnits;
      countedAbsence += counted;
      inReview += record.inReviewUnits;
      justified += record.justifiedUnits;
      switch (record.result) {
        case AttendanceSessionResult.present:
          if (counted != 0) {
            throw ArgumentError('Present results cannot count absences.');
          }
        case AttendanceSessionResult.justified:
          if (record.absentUnits == 0 || counted != 0) {
            throw ArgumentError(
              'Justified result needs fully covered absence.',
            );
          }
        case AttendanceSessionResult.absent:
          if (counted != record.unitCount) {
            throw ArgumentError(
              'Absent result must count all registered units.',
            );
          }
        case AttendanceSessionResult.partial:
          if (counted <= 0 || counted >= record.unitCount) {
            throw ArgumentError('Partial result has an invalid absence range.');
          }
        case AttendanceSessionResult.unmarked:
        case AttendanceSessionResult.voided:
          throw ArgumentError(
            'A non-final result cannot enter course summary.',
          );
      }
    }
    if (courseIds.length > 1) {
      throw ArgumentError('Attendance records must belong to one course.');
    }
    if (countedAbsence > registered) {
      throw ArgumentError('Counted absences cannot exceed registered units.');
    }
    return AttendanceCourseSummary(
      registeredUnits: registered,
      countedAbsenceUnits: countedAbsence,
      inReviewUnits: inReview,
      justifiedUnits: justified,
    );
  }

  static bool _sameRecord(AttendanceRecord left, AttendanceRecord right) {
    if (left.courseId != right.courseId ||
        left.sessionId != right.sessionId ||
        left.rosterEntryId != right.rosterEntryId ||
        left.visibility != right.visibility ||
        left.mode != right.mode ||
        left.scheduledDate != right.scheduledDate ||
        left.effectiveDate != right.effectiveDate ||
        left.startMinute != right.startMinute ||
        left.endMinute != right.endMinute ||
        left.unitCount != right.unitCount ||
        left.absentUnits != right.absentUnits ||
        left.inReviewUnits != right.inReviewUnits ||
        left.justifiedUnits != right.justifiedUnits ||
        left.result != right.result ||
        left.segments.length != right.segments.length) {
      return false;
    }
    for (var i = 0; i < left.segments.length; i++) {
      final a = left.segments[i];
      final b = right.segments[i];
      if (a.segmentId != b.segmentId ||
          a.startMinute != b.startMinute ||
          a.endMinute != b.endMinute ||
          a.durationMinutes != b.durationMinutes ||
          a.mark != b.mark ||
          a.absentMinutes != b.absentMinutes ||
          a.justificationStatus != b.justificationStatus ||
          a.justifiedMinutes != b.justifiedMinutes) {
        return false;
      }
    }
    return true;
  }
}
