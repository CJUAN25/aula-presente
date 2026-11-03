import 'dart:convert';

import '../domain/course_schedule.dart';
import '../domain/planned_meeting.dart';
import 'schedule_conflict_detector.dart';

/// Explicitly requested debug export. Uses an allowlist: never serializes a
/// Course/User object, document ID, title, room, UID or authentication value.
String scheduleConflictDiagnostic(ScheduleConflictCheck check) {
  final courseAliases = <String, String>{check.candidate.id: 'draft'};
  var courseNumber = 0;
  for (final course in check.existingCourses) {
    courseAliases.putIfAbsent(course.id, () => 'course-${++courseNumber}');
  }
  final blockAliases = <String, Map<String, String>>{};
  String blockAlias(String courseId, String blockId) {
    final blocks = blockAliases.putIfAbsent(courseId, () => {});
    return blocks.putIfAbsent(blockId, () => 'block-${blocks.length + 1}');
  }

  Map<String, Object?> schedule(String courseId, CourseSchedule value) => {
    'course': courseAliases[courseId],
    'startDate': value.startDate.isoDate,
    'endDate': value.endDate.isoDate,
    'timezone': value.timezone,
    'blocks': [
      for (final block in value.weeklyBlocks)
        {
          'block': blockAlias(courseId, block.id),
          'weekdayIso': block.weekday,
          'startTime': block.startTime,
          'endTime': block.endTime,
          'startMinute': block.startMinutes,
          'endMinute': block.endMinutes,
        },
    ],
  };

  Map<String, Object?> meeting(PlannedMeeting value) => {
    'meeting':
        '${courseAliases[value.courseId]}|'
        '${blockAlias(value.courseId, value.blockId)}|${value.date.isoDate}',
    'course': courseAliases[value.courseId],
    'block': blockAlias(value.courseId, value.blockId),
    'date': value.date.isoDate,
    'weekdayIso': value.weekday,
    'startMinute': value.startMinutes,
    'endMinute': value.endMinutes,
  };

  return const JsonEncoder.withIndent('  ').convert({
    'diagnosticVersion': 'aula-schedule-2026-11-02-v1',
    'inputBoundary': 'CourseRepository.getAllOwnCourses decoded values',
    'rule': 'same academic date AND a.start < b.end AND b.start < a.end',
    'weekdayConvention': '1=Monday ... 7=Sunday; local time in 24h',
    'existingCourseCount': check.existingCourses.length,
    'distinctExistingCourseCount': check.existingCourses
        .map((c) => c.id)
        .toSet()
        .length,
    'candidate': schedule(check.candidate.id, check.candidate.schedule),
    'existingCourses': [
      for (final course in check.existingCourses)
        {
          ...schedule(course.id, course.schedule),
          'sameIdAsDraft': course.id == check.candidate.id,
          'excludedFromComparison': course.id == check.candidate.id,
        },
    ],
    'candidateMeetings': check.candidateMeetings.map(meeting).toList(),
    'existingMeetings': [
      for (final meetings in check.existingMeetingsByCourse.values)
        for (final value in meetings) meeting(value),
    ],
    'affectedCandidateMeetingCount': check.conflicts.length,
    'overlapPairCount': check.overlapPairs.length,
    'overlapPairs': [
      for (final pair in check.overlapPairs)
        {
          'candidate': meeting(pair.candidateMeeting),
          'existing': meeting(pair.existingMeeting),
        },
    ],
  });
}
