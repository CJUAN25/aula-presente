/// One immutable time slice of a minutes-mode session.
class AttendanceSegment {
  const AttendanceSegment({
    required this.id,
    required this.order,
    required this.startMinute,
    required this.endMinute,
    required this.durationMinutes,
    this.createdAt,
  });

  final String id;
  final int order;
  final int startMinute;
  final int endMinute;
  final int durationMinutes;
  final DateTime? createdAt;
}
