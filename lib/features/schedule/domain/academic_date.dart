/// A civil academic date independent of the device's local time zone.
///
/// Firestore stores this value as a UTC timestamp at exactly 00:00. That
/// timestamp is a serialization format only; it is not a class start instant.
class AcademicDate implements Comparable<AcademicDate> {
  factory AcademicDate({
    required int year,
    required int month,
    required int day,
  }) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError.value('$year-$month-$day', 'date', 'Invalid date');
    }
    return AcademicDate._(year, month, day);
  }

  factory AcademicDate.fromDateTime(DateTime dateTime) => AcademicDate(
    year: dateTime.year,
    month: dateTime.month,
    day: dateTime.day,
  );

  /// Reads the UTC-midnight representation used for Firestore date fields.
  factory AcademicDate.fromUtcTimestamp(DateTime value) {
    if (!value.isUtc ||
        value.hour != 0 ||
        value.minute != 0 ||
        value.second != 0 ||
        value.millisecond != 0 ||
        value.microsecond != 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a UTC-midnight academic date timestamp',
      );
    }
    return AcademicDate(year: value.year, month: value.month, day: value.day);
  }

  const AcademicDate._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// Serializes this civil date without consulting the device time zone.
  DateTime toUtcTimestamp() => DateTime.utc(year, month, day);

  DateTime get asUtcDateTime => toUtcTimestamp();

  int get weekday => DateTime.utc(year, month, day).weekday;

  AcademicDate addDays(int days) {
    final next = DateTime.utc(year, month, day + days);
    return AcademicDate(year: next.year, month: next.month, day: next.day);
  }

  int daysUntil(AcademicDate other) =>
      other.toUtcTimestamp().difference(toUtcTimestamp()).inDays;

  String get isoDate =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(AcademicDate other) =>
      toUtcTimestamp().compareTo(other.toUtcTimestamp());

  @override
  bool operator ==(Object other) =>
      other is AcademicDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => isoDate;
}
