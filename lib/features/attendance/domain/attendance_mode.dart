/// The course's attendance unit. The serialized values are part of the
/// Firestore contract and must remain `meeting` and `minutes`.
enum AttendanceMode {
  meeting,
  minutes;

  String get value => name;

  static AttendanceMode fromValue(String value) => switch (value) {
    'meeting' => AttendanceMode.meeting,
    'minutes' => AttendanceMode.minutes,
    _ => throw FormatException('Unsupported attendance mode: $value'),
  };
}
