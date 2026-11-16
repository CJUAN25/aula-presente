/// Aggregate for one student's published attendance records in one course.
/// All values stay in integer academic units; percentage is informational and
/// the loss threshold is evaluated with integer arithmetic.
class AttendanceCourseSummary {
  const AttendanceCourseSummary({
    required this.registeredUnits,
    required this.countedAbsenceUnits,
    required this.inReviewUnits,
    required this.justifiedUnits,
  });

  final int registeredUnits;
  final int countedAbsenceUnits;
  final int inReviewUnits;
  final int justifiedUnits;

  bool get hasAttendance => registeredUnits > 0;

  double get percent =>
      hasAttendance ? 100 * countedAbsenceUnits / registeredUnits : 0;

  int get roundedPercent => percent.round();

  bool get thresholdReached =>
      registeredUnits > 0 && 5 * countedAbsenceUnits >= registeredUnits;
}
