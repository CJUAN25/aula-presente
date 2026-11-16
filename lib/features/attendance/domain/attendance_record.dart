import '../../schedule/domain/academic_date.dart';
import 'attendance_mode.dart';
import 'attendance_session.dart';

enum AttendanceRecordVisibility {
  staged,
  published;

  String get value => name;

  static AttendanceRecordVisibility fromValue(String value) => switch (value) {
    'staged' => AttendanceRecordVisibility.staged,
    'published' => AttendanceRecordVisibility.published,
    _ => throw FormatException('Unsupported record visibility: $value'),
  };
}

/// Safe student-facing projection for one session and one academic identity.
/// `absentUnits` is gross absence; accepted coverage is kept separately in
/// `justifiedUnits`, so the course summary can derive counted absences.
class AttendanceRecord {
  AttendanceRecord({
    required this.courseId,
    required this.sessionId,
    required this.rosterEntryId,
    required this.visibility,
    required this.mode,
    required this.scheduledDate,
    required this.effectiveDate,
    required this.startMinute,
    required this.endMinute,
    required this.unitCount,
    required this.absentUnits,
    required this.inReviewUnits,
    required this.justifiedUnits,
    required this.result,
    required List<AttendanceRecordSegment> segments,
    this.schemaVersion = 1,
    this.publishedAt,
    this.updatedAt,
  }) : segments = List.unmodifiable(segments);

  final int schemaVersion;
  final String courseId;
  final String sessionId;
  final String rosterEntryId;
  final AttendanceRecordVisibility visibility;
  final AttendanceMode mode;
  final AcademicDate scheduledDate;
  final AcademicDate effectiveDate;
  final int startMinute;
  final int endMinute;
  final int unitCount;
  final int absentUnits;
  final int inReviewUnits;
  final int justifiedUnits;
  final AttendanceSessionResult result;
  final List<AttendanceRecordSegment> segments;
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  /// The route document identifier is deterministic across retries.
  String get recordId => '$sessionId|$rosterEntryId';
}

class AttendanceRecordSegment {
  const AttendanceRecordSegment({
    required this.segmentId,
    required this.startMinute,
    required this.endMinute,
    required this.durationMinutes,
    required this.mark,
    required this.absentMinutes,
    required this.justificationStatus,
    required this.justifiedMinutes,
  });

  final String segmentId;
  final int startMinute;
  final int endMinute;
  final int durationMinutes;
  final AttendanceMark mark;
  final int absentMinutes;
  final AttendanceJustificationStatus justificationStatus;
  final int justifiedMinutes;
}

class AttendanceRecordCursor {
  const AttendanceRecordCursor({
    required this.effectiveDate,
    required this.recordId,
  });

  final AcademicDate effectiveDate;
  final String recordId;
}

class AttendanceRecordPage {
  AttendanceRecordPage({
    required List<AttendanceRecord> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AttendanceRecord> items;
  final AttendanceRecordCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}
