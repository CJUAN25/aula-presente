/// A recurring local-time block in the fixed academic zone America/Bogota.
class WeeklyBlock {
  const WeeklyBlock({
    required this.id,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    this.room,
  });

  final String id;

  /// ISO weekday: Monday is 1 and Sunday is 7.
  final int weekday;

  /// Local 24-hour time in `HH:mm` form.
  final String startTime;

  /// Local 24-hour time in `HH:mm` form, later than [startTime].
  final String endTime;

  final String? room;

  int? get startMinutes => parseTimeMinutes(startTime);

  int? get endMinutes => parseTimeMinutes(endTime);

  WeeklyBlock normalized() => WeeklyBlock(
    id: id,
    weekday: weekday,
    startTime: startTime.trim(),
    endTime: endTime.trim(),
    room: normalizeRoom(room),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'weekday': weekday,
    'startTime': startTime,
    'endTime': endTime,
    'room': room,
  };

  /// Values stored in a `weekly_blocks/{id}` document. The stable block ID is
  /// the document path and intentionally is not duplicated as a field.
  Map<String, Object?> toCanonicalDocument({required int order}) {
    final startMinute = startMinutes;
    final endMinute = endMinutes;
    if (startMinute == null || endMinute == null) {
      throw FormatException('A canonical block requires valid HH:mm times.');
    }
    return {
      'weekday': weekday,
      'startMinute': startMinute,
      'endMinute': endMinute,
      'room': normalizeRoom(room),
      'order': order,
    };
  }

  static int? parseTimeMinutes(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static String? normalizeRoom(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
