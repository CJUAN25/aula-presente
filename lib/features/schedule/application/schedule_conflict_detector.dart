import '../../courses/domain/course.dart';
import '../../courses/domain/course_draft.dart';
import '../domain/meeting_conflict.dart';
import '../domain/planned_meeting.dart';
import '../domain/planned_meeting_generator.dart';

/// Finds time conflicts only where actual recurring dates intersect.
///
/// The caller must supply every own course (follow all repository pages).
/// This is informational validation, not a cross-device reservation.
List<MeetingConflict> findScheduleConflicts({
  required CourseDraft candidate,
  required Iterable<Course> existingCourses,
}) => checkScheduleConflicts(
  candidate: candidate,
  existingCourses: existingCourses,
).conflicts;

/// One immutable evaluation: the UI and diagnostic use the same inputs and
/// overlap witnesses. No second calendar calculation is used for the report.
class ScheduleConflictCheck {
  ScheduleConflictCheck({
    required this.candidate,
    required Iterable<Course> existingCourses,
    required Iterable<PlannedMeeting> candidateMeetings,
    required Map<String, List<PlannedMeeting>> existingMeetingsByCourse,
    required Iterable<MeetingConflict> overlapPairs,
  }) : existingCourses = List.unmodifiable(existingCourses),
       candidateMeetings = List.unmodifiable(candidateMeetings),
       existingMeetingsByCourse = Map.unmodifiable(existingMeetingsByCourse),
       overlapPairs = List.unmodifiable(overlapPairs),
       conflicts = List.unmodifiable(
         {for (final pair in overlapPairs) pair.candidateMeeting.id: pair}
             .values,
       );

  final CourseDraft candidate;
  final List<Course> existingCourses;
  final List<PlannedMeeting> candidateMeetings;
  final Map<String, List<PlannedMeeting>> existingMeetingsByCourse;
  final List<MeetingConflict> overlapPairs;

  /// One witness per distinct proposed meeting (the number in the warning).
  final List<MeetingConflict> conflicts;
}

ScheduleConflictCheck checkScheduleConflicts({
  required CourseDraft candidate,
  required Iterable<Course> existingCourses,
}) {
  final courses = List<Course>.unmodifiable(existingCourses);
  final candidateMeetings = generatePlannedMeetings(
    courseId: candidate.id,
    schedule: candidate.schedule,
  );
  final candidatesByDate = <String, List<PlannedMeeting>>{};
  for (final meeting in candidateMeetings) {
    candidatesByDate.putIfAbsent(meeting.date.isoDate, () => []).add(meeting);
  }

  final overlapPairs = <MeetingConflict>[];
  final existingMeetingsByCourse = <String, List<PlannedMeeting>>{};
  for (final course in courses) {
    if (course.id == candidate.id) continue;
    final existingMeetings = generatePlannedMeetings(
      courseId: course.id,
      schedule: course.schedule,
    );
    existingMeetingsByCourse[course.id] = existingMeetings;
    for (final existing in existingMeetings) {
      for (final proposed
          in candidatesByDate[existing.date.isoDate] ?? const []) {
        if (proposed.startMinutes < existing.endMinutes &&
            existing.startMinutes < proposed.endMinutes) {
          overlapPairs.add(
            MeetingConflict(
              candidateMeeting: proposed,
              existingCourseId: course.id,
              existingMeeting: existing,
            ),
          );
        }
      }
    }
  }
  overlapPairs.sort((left, right) {
    final byDate = left.candidateMeeting.date.compareTo(
      right.candidateMeeting.date,
    );
    if (byDate != 0) return byDate;
    final byStart = left.candidateMeeting.startMinutes.compareTo(
      right.candidateMeeting.startMinutes,
    );
    if (byStart != 0) return byStart;
    final byCourse = left.existingCourseId.compareTo(right.existingCourseId);
    if (byCourse != 0) return byCourse;
    return left.existingMeeting.blockId.compareTo(
      right.existingMeeting.blockId,
    );
  });
  return ScheduleConflictCheck(
    candidate: candidate,
    existingCourses: courses,
    candidateMeetings: candidateMeetings,
    existingMeetingsByCourse: existingMeetingsByCourse,
    overlapPairs: overlapPairs,
  );
}
