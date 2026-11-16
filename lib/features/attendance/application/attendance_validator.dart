import '../domain/attendance_calendar_change.dart';
import '../domain/attendance_config.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_occurrence.dart';

enum AttendanceValidationIssue {
  modeAlreadyLocked,
  invalidConfiguration,
  invalidCalendarChange,
  cancelledOccurrence,
  invalidReason,
}

class AttendanceValidationFailure implements Exception {
  const AttendanceValidationFailure(this.issue);

  final AttendanceValidationIssue issue;
}

class AttendanceValidator {
  const AttendanceValidator._();

  static bool needsLateRegistrationReason(
    AttendanceOccurrence occurrence, {
    required DateTime nowUtc,
    DateTime? preparedAt,
    String? storedReason,
  }) {
    if (storedReason?.trim().isNotEmpty == true) return false;
    final start = occurrence.effectiveDate.toUtcTimestamp().add(
      Duration(hours: 5, minutes: occurrence.startMinute),
    );
    // An on-time preparation is not a new late registration when resumed.
    return !nowUtc.toUtc().isBefore(start) &&
        (preparedAt == null || !preparedAt.toUtc().isBefore(start));
  }

  static void validateModeChange({
    required AttendanceConfig? current,
    required AttendanceMode nextMode,
  }) {
    if (current == null) return;
    if (current.sessionCount < 0 ||
        (current.sessionCount == 0 && current.lastSessionId != null) ||
        (current.sessionCount > 0 && current.lastSessionId == null)) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidConfiguration,
      );
    }
    if (current.sessionCount > 0 && current.mode != nextMode) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.modeAlreadyLocked,
      );
    }
  }

  static void validateCalendarChange(AttendanceCalendarChange change) {
    final reason = change.reason.trim();
    if (change.occurrenceId.trim().isEmpty ||
        reason.isEmpty ||
        reason.length > 500 ||
        change.version < 1 ||
        change.startMinute < 0 ||
        change.endMinute > 1440 ||
        change.endMinute <= change.startMinute) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidCalendarChange,
      );
    }
  }

  static void validateCanPrepare(AttendanceOccurrence occurrence) {
    if (occurrence.kind == AttendanceOccurrenceKind.cancelled) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.cancelledOccurrence,
      );
    }
    if (occurrence.id.trim().isEmpty ||
        occurrence.id.contains('/') ||
        occurrence.courseId.trim().isEmpty ||
        occurrence.courseId.contains('/') ||
        occurrence.startMinute < 0 ||
        occurrence.endMinute > 1440 ||
        occurrence.endMinute <= occurrence.startMinute ||
        occurrence.timezone != 'America/Bogota') {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidCalendarChange,
      );
    }
  }

  static String validateVoidReason(String value) {
    final reason = value.trim();
    if (reason.isEmpty || reason.length > 500) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidReason,
      );
    }
    return reason;
  }

  static String? validateLateRegistrationReason(
    String? value, {
    required bool isPastOccurrence,
  }) {
    final reason = value?.trim() ?? '';
    if (isPastOccurrence && reason.isEmpty) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidReason,
      );
    }
    if (reason.length > 500) {
      throw const AttendanceValidationFailure(
        AttendanceValidationIssue.invalidReason,
      );
    }
    return reason.isEmpty ? null : reason;
  }
}
