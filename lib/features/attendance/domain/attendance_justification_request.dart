import 'attendance_segment.dart';
import 'attendance_session.dart';

enum AttendanceRequestStatus { pending, approved, rejected }

/// One immutable submission per academic identity and encounter/time slice.
class AttendanceJustificationRequest {
  const AttendanceJustificationRequest({
    required this.id,
    required this.sessionId,
    required this.rosterEntryId,
    required this.studentUid,
    required this.segmentId,
    required this.text,
    required this.status,
    this.createdAt,
    this.decidedAt,
    this.decidedBy,
  });

  final String id;
  final String sessionId;
  final String rosterEntryId;
  final String studentUid;
  final String? segmentId;
  final String text;
  final AttendanceRequestStatus status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;

  static String documentId(
    String sessionId,
    String identity,
    String? segmentId,
  ) => '$sessionId|$identity|${segmentId ?? "meeting"}';
}

class PendingAttendanceRequest {
  const PendingAttendanceRequest({
    required this.request,
    required this.studentName,
    required this.session,
    required this.segment,
    required this.hasAbsence,
  });

  final AttendanceJustificationRequest request;
  final String studentName;
  final AttendanceSession session;
  final AttendanceSegment? segment;
  final bool hasAbsence;
}

class PendingAttendanceRequestPage {
  const PendingAttendanceRequestPage({required this.items, this.nextCursor});

  final List<PendingAttendanceRequest> items;
  final String? nextCursor;
}
