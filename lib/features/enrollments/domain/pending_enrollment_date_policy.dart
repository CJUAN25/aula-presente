import '../../schedule/domain/academic_date.dart';
import 'pending_enrollment.dart';

/// Returns the earliest date the teacher may choose to withdraw a pending
/// roster entry, matching the repository's date validation.
AcademicDate minimumPendingWithdrawalDate({
  required PendingEnrollment enrollment,
  required AcademicDate today,
  required AcademicDate courseStart,
}) {
  final authorizedAtBogota = AcademicDate.fromDateTime(
    enrollment.authorizedAt.toUtc().subtract(const Duration(hours: 5)),
  );
  final courseHasNotStarted = today.compareTo(courseStart) < 0;
  var minimum = courseHasNotStarted ? authorizedAtBogota : courseStart;

  // A pending authorization whose effective start is still in the future may
  // be cancelled today. Once that date arrives, preserve it as the beginning
  // of the period that can be withdrawn.
  if (enrollment.status == 'pending' &&
      enrollment.effectiveStartDate.compareTo(today) <= 0 &&
      enrollment.effectiveStartDate.compareTo(minimum) > 0) {
    minimum = enrollment.effectiveStartDate;
  }
  if (authorizedAtBogota.compareTo(minimum) > 0) {
    minimum = authorizedAtBogota;
  }
  return minimum;
}
