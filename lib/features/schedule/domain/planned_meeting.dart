import 'academic_date.dart';

/// An occurrence calculated from a course schedule. It is not an attendance
/// session and does not imply that attendance is open or has been taken.
class PlannedMeeting {
  const PlannedMeeting({
    required this.id,
    required this.courseId,
    required this.blockId,
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  /// Stable source identity: course, recurring block and original date.
  final String id;
  final String courseId;
  final String blockId;
  final AcademicDate date;
  final int weekday;
  final String startTime;
  final String endTime;
  final String? room;

  int get startMinutes => _timeMinutes(startTime);

  int get endMinutes => _timeMinutes(endTime);

  static int _timeMinutes(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid local time: $value');
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
}
