import '../domain/attendance_mode.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_session.dart';
import '../domain/attendance_segment.dart';

/// Derives the staged, per-session projection from the private roster mark.
/// No course-level percentage or grade is stored in a session record.
class AttendanceRecordCalculator {
  const AttendanceRecordCalculator._();

  static AttendanceRecord fromRosterEntry({
    required AttendanceSession session,
    required AttendanceRosterEntry entry,
    required Iterable<AttendanceSegment> segments,
  }) {
    if (session.status == AttendanceSessionStatus.voiding ||
        session.status == AttendanceSessionStatus.voided) {
      return voidedForRosterEntry(
        session: session,
        entry: entry,
        segments: segments,
      );
    }
    final orderedSegments = segments.toList()
      ..sort((left, right) => left.order.compareTo(right.order));
    if (session.mode == AttendanceMode.meeting) {
      if (orderedSegments.isNotEmpty || entry.segmentMarks.isNotEmpty) {
        throw ArgumentError('Meeting-mode attendance must not have segments.');
      }
      final mark = entry.meetingMark;
      if (mark == null) {
        throw ArgumentError('Meeting mode requires one meeting mark.');
      }
      _validateMark(mark, capacity: 1);
      final rawAbsent = mark.absentUnits;
      final justified = mark.justifiedUnits;
      final unmarked = mark.mark == AttendanceMark.unmarked;
      return AttendanceRecord(
        courseId: session.courseId,
        sessionId: session.occurrenceId,
        rosterEntryId: entry.rosterEntryId,
        visibility: AttendanceRecordVisibility.staged,
        mode: session.mode,
        scheduledDate: session.scheduledDate,
        effectiveDate: session.effectiveDate,
        startMinute: session.startMinute,
        endMinute: session.endMinute,
        unitCount: 1,
        absentUnits: rawAbsent,
        inReviewUnits:
            mark.justificationStatus == AttendanceJustificationStatus.inReview
            ? rawAbsent
            : 0,
        justifiedUnits: justified,
        result: _result(
          unmarked: unmarked,
          unitCount: 1,
          absentUnits: rawAbsent,
          justifiedUnits: justified,
        ),
        segments: const [],
      );
    }

    if (entry.meetingMark != null) {
      throw ArgumentError('Minutes mode must not have a meeting mark.');
    }
    final expectedIds = session.segmentIds.toSet();
    final actualIds = orderedSegments.map((segment) => segment.id).toSet();
    if (expectedIds.length != session.segmentIds.length ||
        actualIds.length != orderedSegments.length ||
        expectedIds.length != actualIds.length ||
        !expectedIds.containsAll(actualIds) ||
        !actualIds.containsAll(expectedIds)) {
      throw ArgumentError('Session segment IDs do not match its segment list.');
    }
    for (var index = 0; index < orderedSegments.length; index++) {
      if (session.segmentIds[index] != orderedSegments[index].id) {
        throw ArgumentError(
          'Session segment order does not match segment IDs.',
        );
      }
    }
    if (entry.segmentMarks.keys.toSet().length != entry.segmentMarks.length ||
        entry.segmentMarks.length != expectedIds.length ||
        !entry.segmentMarks.keys.toSet().containsAll(expectedIds)) {
      throw ArgumentError('Roster marks do not cover the session segments.');
    }

    var unitCount = 0;
    var rawAbsent = 0;
    var inReview = 0;
    var justified = 0;
    var hasUnmarked = false;
    final recordSegments = <AttendanceRecordSegment>[];
    var expectedStart = session.startMinute;
    for (final segment in orderedSegments) {
      if (segment.endMinute <= segment.startMinute ||
          segment.startMinute != expectedStart ||
          segment.durationMinutes != segment.endMinute - segment.startMinute ||
          segment.durationMinutes > 60 ||
          segment.durationMinutes < 1) {
        throw ArgumentError('Attendance segment has an invalid duration.');
      }
      final mark = entry.segmentMarks[segment.id]!;
      expectedStart = segment.endMinute;
      _validateMark(mark, capacity: segment.durationMinutes);
      unitCount += segment.durationMinutes;
      rawAbsent += mark.absentUnits;
      if (mark.justificationStatus == AttendanceJustificationStatus.inReview) {
        inReview += mark.absentUnits;
      }
      justified += mark.justifiedUnits;
      if (mark.mark == AttendanceMark.unmarked) hasUnmarked = true;
      recordSegments.add(
        AttendanceRecordSegment(
          segmentId: segment.id,
          startMinute: segment.startMinute,
          endMinute: segment.endMinute,
          durationMinutes: segment.durationMinutes,
          mark: mark.mark,
          absentMinutes: mark.absentUnits,
          justificationStatus: mark.justificationStatus,
          justifiedMinutes: mark.justifiedUnits,
        ),
      );
    }

    if (unitCount != session.endMinute - session.startMinute) {
      throw ArgumentError('Segments must cover the full session duration.');
    }
    if (expectedStart != session.endMinute) {
      throw ArgumentError('Segments must end at the session end minute.');
    }
    return AttendanceRecord(
      courseId: session.courseId,
      sessionId: session.occurrenceId,
      rosterEntryId: entry.rosterEntryId,
      visibility: AttendanceRecordVisibility.staged,
      mode: session.mode,
      scheduledDate: session.scheduledDate,
      effectiveDate: session.effectiveDate,
      startMinute: session.startMinute,
      endMinute: session.endMinute,
      unitCount: unitCount,
      absentUnits: rawAbsent,
      inReviewUnits: inReview,
      justifiedUnits: justified,
      result: _result(
        unmarked: hasUnmarked,
        unitCount: unitCount,
        absentUnits: rawAbsent,
        justifiedUnits: justified,
      ),
      segments: recordSegments,
    );
  }

  /// Creates the student-visible void notice while a void operation stages
  /// every projection. It has no academic units and never carries the private
  /// reason from the audit event.
  static AttendanceRecord voidedForRosterEntry({
    required AttendanceSession session,
    required AttendanceRosterEntry entry,
    required Iterable<AttendanceSegment> segments,
  }) => AttendanceRecord(
    courseId: session.courseId,
    sessionId: session.occurrenceId,
    rosterEntryId: entry.rosterEntryId,
    visibility: AttendanceRecordVisibility.published,
    mode: session.mode,
    scheduledDate: session.scheduledDate,
    effectiveDate: session.effectiveDate,
    startMinute: session.startMinute,
    endMinute: session.endMinute,
    unitCount: 0,
    absentUnits: 0,
    inReviewUnits: 0,
    justifiedUnits: 0,
    result: AttendanceSessionResult.voided,
    segments: const [],
  );

  static void _validateMark(
    AttendanceRosterMark mark, {
    required int capacity,
  }) {
    if (mark.absentUnits < 0 ||
        mark.absentUnits > capacity ||
        mark.justifiedUnits < 0 ||
        mark.justifiedUnits > mark.absentUnits) {
      throw ArgumentError('Attendance mark units are outside the valid range.');
    }
    switch (mark.mark) {
      case AttendanceMark.unmarked:
      case AttendanceMark.present:
        if (mark.absentUnits != 0 || mark.justifiedUnits != 0) {
          throw ArgumentError(
            'An unmarked/present unit cannot contain absence.',
          );
        }
        if (mark.justificationStatus != AttendanceJustificationStatus.none) {
          throw ArgumentError('An unmarked/present unit cannot be justified.');
        }
      case AttendanceMark.absent:
        if (mark.absentUnits == 0) {
          throw ArgumentError('An absent mark must contain absent units.');
        }
        if (mark.justificationStatus !=
                AttendanceJustificationStatus.justified &&
            mark.justifiedUnits != 0) {
          throw ArgumentError('Only accepted coverage can reduce absence.');
        }
        if (mark.justificationStatus ==
                AttendanceJustificationStatus.justified &&
            mark.justifiedUnits == 0) {
          throw ArgumentError(
            'Accepted justification needs positive coverage.',
          );
        }
    }
  }

  static AttendanceSessionResult _result({
    required bool unmarked,
    required int unitCount,
    required int absentUnits,
    required int justifiedUnits,
  }) {
    if (unmarked) return AttendanceSessionResult.unmarked;
    final counted = absentUnits - justifiedUnits;
    if (counted == 0) {
      return absentUnits == 0
          ? AttendanceSessionResult.present
          : AttendanceSessionResult.justified;
    }
    if (counted == unitCount) return AttendanceSessionResult.absent;
    return AttendanceSessionResult.partial;
  }
}
