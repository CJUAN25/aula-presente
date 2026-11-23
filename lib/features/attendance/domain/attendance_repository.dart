import '../../courses/domain/course.dart';
import '../../schedule/domain/academic_date.dart';
import 'attendance_calendar_change.dart';
import 'attendance_config.dart';
import 'attendance_mode.dart';
import 'attendance_occurrence.dart';
import 'attendance_record.dart';
import 'attendance_session.dart';
import 'attendance_session_event.dart';
import 'attendance_justification_request.dart';

/// Persistence boundary for course attendance. Implementations must derive
/// authenticated identities from Firebase Auth and enforce the published
/// Firestore rules; presentation code never passes a student UID.
abstract interface class AttendanceRepository {
  Future<AttendanceSession> restoreSession({
    required String courseId,
    required String occurrenceId,
  });
  Future<AttendanceJustificationRequest?> getMyJustification({
    required AttendanceRecord record,
    required String? segmentId,
  });
  Future<AttendanceJustificationRequest> submitJustification({
    required AttendanceRecord record,
    required String? segmentId,
    required String text,
  });
  Future<List<AttendanceJustificationRequest>> listJustificationRequests({
    required String courseId,
    required String occurrenceId,
  });
  Future<bool> hasPendingJustifications({required String courseId});
  Future<PendingAttendanceRequestPage> listPendingJustifications({
    required String courseId,
    String? afterId,
    int pageSize = 20,
  });
  Future<void> decideJustificationRequest({
    required String courseId,
    required AttendanceJustificationRequest request,
    required bool approve,
  });
  Future<AttendanceConfig?> getConfig({required String courseId});

  Future<AttendanceConfig> setMode({
    required Course course,
    required AttendanceMode mode,
  });

  Future<List<AttendanceCalendarChange>> listCalendarChanges({
    required String courseId,
    bool forStudent = false,
  });

  Future<AttendanceCalendarChange> saveCalendarChange({
    required Course course,
    required AttendanceCalendarChange change,
  });

  Future<List<AttendanceSession>> listSessions({
    required String courseId,
    required AcademicDate from,
    required AcademicDate to,
  });

  Future<AttendanceSession?> getSession({
    required String courseId,
    required String occurrenceId,
  });

  /// Loads the complete canonical roster and all status-event pages before
  /// materializing/resuming the complete roster. Future occurrences remain
  /// `preparing`; [startSession] opens marking only at the effective start.
  Future<AttendanceSession> prepareSession({
    required Course course,
    required AttendanceOccurrence occurrence,
    String? lateRegistrationReason,
  });

  /// Transitions a ready session from `preparing` to `inProgress` only at or
  /// after its effective local start time. Future sessions remain preparing.
  Future<AttendanceSession> startSession({
    required String courseId,
    required String occurrenceId,
  });

  Future<AttendanceRosterPage> listRoster({
    required AttendanceSession session,
    AttendanceRosterCursor? cursor,
    int pageSize = 25,
  });

  Future<AttendanceRosterEntry?> getRosterEntry({
    required AttendanceSession session,
    required String rosterEntryId,
  });

  Future<AttendanceSegmentPage> listSegments({
    required AttendanceSession session,
    AttendanceSegmentCursor? cursor,
    int pageSize = 25,
  });

  Future<AttendanceSessionEventPage> listSessionEvents({
    required AttendanceSession session,
    AttendanceSessionEventCursor? cursor,
    int pageSize = 25,
  });

  Future<AttendanceRosterMutationResult> setMeetingMark({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required AttendanceMark mark,
  });

  Future<AttendanceRosterMutationResult> setSegmentMark({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String segmentId,
    required AttendanceMark mark,
    int? absentUnits,
  });

  Future<AttendanceFinalizeResult> finalizeSession({
    required String courseId,
    required String occurrenceId,
    required bool confirmUnmarked,
  });

  Future<AttendanceSession> voidSession({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required String reason,
  });

  Future<AttendanceRosterMutationResult> correctRosterEntry({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required AttendanceRosterEntry replacement,
    required String reason,
  });

  Future<AttendanceRosterMutationResult> decideJustification({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String? segmentId,
    required String operationId,
    required AttendanceJustificationStatus status,
    required int justifiedUnits,
    required String reason,
  });

  /// UID and rosterEntryId are resolved from the authenticated student's
  /// canonical active enrollment by the data layer, never from the UI.
  Future<AttendanceRecordPage> listMyAttendanceRecords({
    required String courseId,
    AttendanceRecordCursor? cursor,
    int pageSize = 25,
  });
}
