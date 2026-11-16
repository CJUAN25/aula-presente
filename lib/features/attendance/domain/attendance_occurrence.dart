import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/planned_meeting.dart';

enum AttendanceOccurrenceKind {
  planned,
  cancelled,
  rescheduled,
  additional;

  String get value => name;

  static AttendanceOccurrenceKind fromValue(String value) => switch (value) {
    'planned' => AttendanceOccurrenceKind.planned,
    'cancelled' => AttendanceOccurrenceKind.cancelled,
    'rescheduled' => AttendanceOccurrenceKind.rescheduled,
    'additional' => AttendanceOccurrenceKind.additional,
    _ => throw FormatException('Unsupported occurrence kind: $value'),
  };
}

/// Effective class occurrence assembled from the planned schedule and one
/// explicit calendar change. [id] stays equal to `PlannedMeeting.id` for a
/// normal or rescheduled meeting; additional meetings have their own ID.
class AttendanceOccurrence {
  const AttendanceOccurrence({
    required this.id,
    required this.courseId,
    required this.kind,
    required this.scheduledDate,
    required this.effectiveDate,
    required this.startMinute,
    required this.endMinute,
    this.blockId,
    this.weekday,
    this.room,
    this.timezone = 'America/Bogota',
  });

  factory AttendanceOccurrence.fromPlannedMeeting(PlannedMeeting meeting) =>
      AttendanceOccurrence(
        id: meeting.id,
        courseId: meeting.courseId,
        kind: AttendanceOccurrenceKind.planned,
        scheduledDate: meeting.date,
        effectiveDate: meeting.date,
        startMinute: meeting.startMinutes,
        endMinute: meeting.endMinutes,
        blockId: meeting.blockId,
        weekday: meeting.weekday,
        room: meeting.room,
      );

  final String id;
  final String courseId;
  final AttendanceOccurrenceKind kind;
  final AcademicDate scheduledDate;
  final AcademicDate effectiveDate;
  final int startMinute;
  final int endMinute;
  final String? blockId;
  final int? weekday;
  final String? room;
  final String timezone;

  int get durationMinutes => endMinute - startMinute;
}
