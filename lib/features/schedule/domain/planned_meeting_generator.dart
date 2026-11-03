import 'academic_date.dart';
import 'course_schedule.dart';
import 'planned_meeting.dart';
import 'weekly_block.dart';

/// Calculates recurring occurrences over the inclusive civil date range.
///
/// [schedule] must pass [CourseScheduleValidation] before calling this
/// function. The generated values are planned calendar entries only; no
/// attendance session documents are created.
List<PlannedMeeting> generatePlannedMeetings({
  required String courseId,
  required CourseSchedule schedule,
}) {
  if (schedule.endDate.compareTo(schedule.startDate) < 0) {
    throw ArgumentError('The schedule end date precedes its start date.');
  }

  final meetings = <PlannedMeeting>[];
  for (
    var date = schedule.startDate;
    date.compareTo(schedule.endDate) <= 0;
    date = date.addDays(1)
  ) {
    for (final block in schedule.weeklyBlocks) {
      final start = block.startMinutes;
      final end = block.endMinutes;
      if (date.weekday != block.weekday ||
          start == null ||
          end == null ||
          end <= start) {
        continue;
      }
      meetings.add(_meeting(courseId, date, block));
    }
  }

  meetings.sort((left, right) {
    final byDate = left.date.compareTo(right.date);
    if (byDate != 0) return byDate;
    final byStart = left.startMinutes.compareTo(right.startMinutes);
    if (byStart != 0) return byStart;
    return left.blockId.compareTo(right.blockId);
  });
  return List.unmodifiable(meetings);
}

PlannedMeeting _meeting(String courseId, AcademicDate date, WeeklyBlock block) {
  return PlannedMeeting(
    id: '$courseId|${block.id}|${date.isoDate}',
    courseId: courseId,
    blockId: block.id,
    date: date,
    weekday: block.weekday,
    startTime: block.startTime,
    endTime: block.endTime,
    room: block.room,
  );
}
