import '../domain/attendance_occurrence.dart';
import '../domain/attendance_segment.dart';

/// Creates deterministic, consecutive segments no longer than 60 minutes.
class AttendanceSegmentFactory {
  const AttendanceSegmentFactory._();

  static List<AttendanceSegment> forOccurrence(
    AttendanceOccurrence occurrence,
  ) {
    if (occurrence.kind == AttendanceOccurrenceKind.cancelled) {
      throw ArgumentError('A cancelled occurrence cannot have segments.');
    }
    final start = occurrence.startMinute;
    final end = occurrence.endMinute;
    if (occurrence.id.trim().isEmpty ||
        occurrence.id.contains('/') ||
        start < 0 ||
        end > 1440 ||
        end <= start) {
      throw ArgumentError('Occurrence has an invalid local time range.');
    }

    final segments = <AttendanceSegment>[];
    var cursor = start;
    var order = 0;
    while (cursor < end) {
      final segmentEnd = cursor + 60 < end ? cursor + 60 : end;
      segments.add(
        AttendanceSegment(
          id: '${occurrence.id}|segment|$order',
          order: order,
          startMinute: cursor,
          endMinute: segmentEnd,
          durationMinutes: segmentEnd - cursor,
        ),
      );
      cursor = segmentEnd;
      order++;
    }
    return List.unmodifiable(segments);
  }
}
