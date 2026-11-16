import '../domain/attendance_calendar_change.dart';
import '../domain/attendance_occurrence.dart';
import '../../schedule/domain/planned_meeting.dart';

/// Combines generated weekly occurrences with explicit exceptions.
/// Cancelled rows remain represented so a previous session is not lost from
/// the calendar; callers must prevent opening a new session for them.
class AttendanceOccurrenceResolver {
  const AttendanceOccurrenceResolver._();

  static List<AttendanceOccurrence> resolve({
    required String courseId,
    required Iterable<PlannedMeeting> plannedMeetings,
    required Iterable<AttendanceCalendarChange> changes,
  }) {
    final plannedById = <String, PlannedMeeting>{};
    for (final meeting in plannedMeetings) {
      if (meeting.courseId != courseId) {
        throw ArgumentError('Planned meeting belongs to another course.');
      }
      if (plannedById.containsKey(meeting.id)) {
        throw ArgumentError('Duplicate planned occurrence ID: ${meeting.id}');
      }
      plannedById[meeting.id] = meeting;
    }

    final changeById = <String, AttendanceCalendarChange>{};
    for (final change in changes) {
      if (change.occurrenceId.trim().isEmpty ||
          change.occurrenceId.contains('/')) {
        throw ArgumentError('Calendar change ID is not a valid document ID.');
      }
      if (changeById.containsKey(change.occurrenceId)) {
        throw ArgumentError(
          'Duplicate calendar change ID: ${change.occurrenceId}',
        );
      }
      if (change.version < 1) {
        throw ArgumentError.value(change.version, 'version');
      }
      if (change.startMinute < 0 ||
          change.endMinute > 1440 ||
          change.endMinute <= change.startMinute) {
        throw ArgumentError('Calendar change has an invalid local time range.');
      }
      changeById[change.occurrenceId] = change;
    }

    final resolved = <String, AttendanceOccurrence>{};
    for (final meeting in plannedById.values) {
      final change = changeById.remove(meeting.id);
      if (change == null) {
        resolved[meeting.id] = AttendanceOccurrence.fromPlannedMeeting(meeting);
        continue;
      }
      if (change.kind == AttendanceCalendarChangeKind.additional) {
        throw ArgumentError(
          'An additional occurrence must use an independent ID.',
        );
      }
      if (change.originalDate != meeting.date) {
        throw ArgumentError(
          'Calendar change originalDate must match the planned occurrence.',
        );
      }
      resolved[meeting.id] = AttendanceOccurrence(
        id: meeting.id,
        courseId: meeting.courseId,
        kind: switch (change.kind) {
          AttendanceCalendarChangeKind.cancelled =>
            AttendanceOccurrenceKind.cancelled,
          AttendanceCalendarChangeKind.rescheduled =>
            AttendanceOccurrenceKind.rescheduled,
          AttendanceCalendarChangeKind.additional => throw StateError(
            'Additional change used an existing occurrence ID.',
          ),
        },
        scheduledDate: meeting.date,
        effectiveDate: change.effectiveDate,
        startMinute: change.startMinute,
        endMinute: change.endMinute,
        blockId: meeting.blockId,
        weekday: meeting.weekday,
        room: meeting.room,
      );
    }

    // Preserve explicit changes whose original recurrence is no longer in a
    // current generated range. Additional classes always have independent IDs.
    for (final change in changeById.values) {
      final kind = switch (change.kind) {
        AttendanceCalendarChangeKind.cancelled =>
          AttendanceOccurrenceKind.cancelled,
        AttendanceCalendarChangeKind.rescheduled =>
          AttendanceOccurrenceKind.rescheduled,
        AttendanceCalendarChangeKind.additional =>
          AttendanceOccurrenceKind.additional,
      };
      resolved[change.occurrenceId] = AttendanceOccurrence(
        id: change.occurrenceId,
        courseId: courseId,
        kind: kind,
        scheduledDate: change.originalDate,
        effectiveDate: change.effectiveDate,
        startMinute: change.startMinute,
        endMinute: change.endMinute,
      );
    }

    final result = resolved.values.toList()
      ..sort((left, right) {
        final dateOrder = left.effectiveDate.compareTo(right.effectiveDate);
        if (dateOrder != 0) return dateOrder;
        final timeOrder = left.startMinute.compareTo(right.startMinute);
        if (timeOrder != 0) return timeOrder;
        return left.id.compareTo(right.id);
      });
    return List.unmodifiable(result);
  }
}
