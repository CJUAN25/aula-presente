import '../domain/course_entry_failure.dart';
import '../domain/course_invitation.dart';

import 'dart:math';

abstract final class CourseEntryValidator {
  static const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  static void validateValidity(Duration validity) {
    if (validity < CourseInvitation.minValidity ||
        validity > CourseInvitation.maxValidity ||
        validity.inMicroseconds % Duration.microsecondsPerSecond != 0) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
  }

  static String generateCode({Random? random}) {
    final source = random ?? Random.secure();
    return List.generate(
      16,
      (_) => alphabet[source.nextInt(alphabet.length)],
    ).join();
  }

  static String normalizeCode(String input) {
    final code = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (code.length != 16 || code.split('').any((c) => !alphabet.contains(c))) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
    return code;
  }

  static String normalizeRejectionReason(String input) {
    final reason = input.trim();
    if (reason.isEmpty || reason.length > 500) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
    return reason;
  }
}
