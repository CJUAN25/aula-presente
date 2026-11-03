import 'academic_date.dart';
import 'weekly_block.dart';

class CourseSchedule {
  CourseSchedule({
    required this.startDate,
    required this.endDate,
    required List<WeeklyBlock> weeklyBlocks,
    this.timezone = academicTimezone,
  }) : weeklyBlocks = List.unmodifiable(weeklyBlocks);

  static const String academicTimezone = 'America/Bogota';

  final AcademicDate startDate;
  final AcademicDate endDate;
  final List<WeeklyBlock> weeklyBlocks;
  final String timezone;

  CourseSchedule normalized() {
    final blocks = weeklyBlocks.map((block) => block.normalized()).toList()
      ..sort((left, right) {
        final byWeekday = left.weekday.compareTo(right.weekday);
        if (byWeekday != 0) return byWeekday;
        final byStart = _compareMinutes(left.startTime, right.startTime);
        if (byStart != 0) return byStart;
        final byEnd = _compareMinutes(left.endTime, right.endTime);
        if (byEnd != 0) return byEnd;
        return left.id.compareTo(right.id);
      });
    return CourseSchedule(
      startDate: startDate,
      endDate: endDate,
      weeklyBlocks: blocks,
      timezone: timezone,
    );
  }

  static int _compareMinutes(String left, String right) {
    final leftMinutes = WeeklyBlock.parseTimeMinutes(left);
    final rightMinutes = WeeklyBlock.parseTimeMinutes(right);
    if (leftMinutes != null && rightMinutes != null) {
      return leftMinutes.compareTo(rightMinutes);
    }
    if (leftMinutes == null && rightMinutes == null) {
      return left.compareTo(right);
    }
    return leftMinutes == null ? 1 : -1;
  }
}
