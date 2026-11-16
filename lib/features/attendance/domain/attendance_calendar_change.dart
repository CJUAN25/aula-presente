import '../../schedule/domain/academic_date.dart';

enum AttendanceCalendarChangeKind {
  cancelled,
  rescheduled,
  additional;

  String get value => name;

  static AttendanceCalendarChangeKind fromValue(String value) =>
      switch (value) {
        'cancelled' => AttendanceCalendarChangeKind.cancelled,
        'rescheduled' => AttendanceCalendarChangeKind.rescheduled,
        'additional' => AttendanceCalendarChangeKind.additional,
        _ => throw FormatException('Unsupported calendar change: $value'),
      };
}

/// Explicit exception to the recurring schedule. It never changes the
/// identity of an ordinary occurrence.
class AttendanceCalendarChange {
  const AttendanceCalendarChange({
    required this.occurrenceId,
    required this.kind,
    required this.originalDate,
    required this.effectiveDate,
    required this.startMinute,
    required this.endMinute,
    required this.reason,
    required this.version,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  final String occurrenceId;
  final AttendanceCalendarChangeKind kind;
  final AcademicDate originalDate;
  final AcademicDate effectiveDate;
  final int startMinute;
  final int endMinute;
  final String reason;
  final int version;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
}
