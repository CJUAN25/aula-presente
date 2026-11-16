import '../../schedule/domain/course_schedule.dart';
import '../../schedule/domain/weekly_block.dart';
import '../../attendance/domain/attendance_mode.dart';

/// An in-memory create operation. It has no owner UID: the repository derives
/// ownership from the currently authenticated Firebase user.
class CourseDraft {
  const CourseDraft({
    required this.id,
    required this.subject,
    required this.group,
    required this.period,
    required this.program,
    required this.schedule,
    this.attendanceMode,
  });

  /// Stable operation ID retained across form navigation and retries.
  final String id;
  final String subject;
  final String group;
  final String period;
  final String program;
  final CourseSchedule schedule;

  /// Explicitly selected when creating a new course. Null is kept so
  /// validation can reject incomplete drafts without assigning a default.
  final AttendanceMode? attendanceMode;

  CourseDraft normalized() => CourseDraft(
    id: id,
    subject: normalizeCourseText(subject),
    group: normalizeCourseText(group),
    period: normalizeCourseText(period),
    program: normalizeCourseText(program),
    schedule: schedule.normalized(),
    attendanceMode: attendanceMode,
  );

  /// Normalized business values used to compare an idempotent retry.
  /// Ownership and server timestamps are deliberately excluded.
  Map<String, Object?> get canonicalFields {
    final normalizedDraft = normalized();
    final schedule = normalizedDraft.schedule;
    return {
      'subject': normalizedDraft.subject,
      'group': normalizedDraft.group,
      'period': normalizedDraft.period,
      'program': normalizedDraft.program,
      'timezone': schedule.timezone,
      'startDate': schedule.startDate.toUtcTimestamp(),
      'endDate': schedule.endDate.toUtcTimestamp(),
      'weeklyBlockIds': schedule.weeklyBlocks
          .map((WeeklyBlock block) => block.id)
          .toList(growable: false),
      'status': 'planned',
      'schemaVersion': 1,
    };
  }

  /// Canonically ordered child documents keyed by their stable path IDs.
  /// No document duplicates its ID field.
  Map<String, Map<String, Object?>> get canonicalWeeklyBlockDocuments {
    final blocks = normalized().schedule.weeklyBlocks;
    return Map.unmodifiable({
      for (var order = 0; order < blocks.length; order++)
        blocks[order].id: blocks[order].toCanonicalDocument(order: order),
    });
  }
}

String normalizeCourseText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
