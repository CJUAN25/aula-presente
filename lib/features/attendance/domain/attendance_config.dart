import 'attendance_mode.dart';

/// Course-level attendance configuration. A missing config is represented by
/// a null repository result; existing courses require an explicit choice.
class AttendanceConfig {
  const AttendanceConfig({
    required this.mode,
    required this.sessionCount,
    this.lastSessionId,
    this.schemaVersion = 1,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  final int schemaVersion;
  final AttendanceMode mode;
  final int sessionCount;
  final String? lastSessionId;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get canChangeMode => sessionCount == 0;
}
