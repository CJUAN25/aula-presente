import 'planned_meeting.dart';

class MeetingConflict {
  const MeetingConflict({
    required this.candidateMeeting,
    required this.existingCourseId,
    required this.existingMeeting,
  });

  final PlannedMeeting candidateMeeting;
  final String existingCourseId;
  final PlannedMeeting existingMeeting;
}
