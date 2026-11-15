import 'enrollment.dart';
import 'pending_enrollment.dart';

class PendingEnrollmentCursor {
  const PendingEnrollmentCursor({required this.createdAt, required this.email});

  final DateTime createdAt;
  final String email;
}

class PendingEnrollmentPage {
  PendingEnrollmentPage({
    required List<PendingEnrollment> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<PendingEnrollment> items;
  final PendingEnrollmentCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

/// Complete, server-read view used when a teacher compares an explicitly
/// complete class roster. It is only created after every page has loaded.
class CourseRosterSnapshot {
  CourseRosterSnapshot({
    required List<Enrollment> activeEnrollments,
    required List<Enrollment> withdrawnEnrollments,
    required List<PendingEnrollment> pendingEnrollments,
    required List<PendingEnrollment> withdrawnPendingEnrollments,
    required this.complete,
  }) : activeEnrollments = List.unmodifiable(activeEnrollments),
       withdrawnEnrollments = List.unmodifiable(withdrawnEnrollments),
       pendingEnrollments = List.unmodifiable(pendingEnrollments),
       withdrawnPendingEnrollments = List.unmodifiable(
         withdrawnPendingEnrollments,
       );

  final List<Enrollment> activeEnrollments;
  final List<Enrollment> withdrawnEnrollments;
  final List<PendingEnrollment> pendingEnrollments;
  final List<PendingEnrollment> withdrawnPendingEnrollments;

  /// True only after all four server-backed paginations have completed.
  final bool complete;
}

/// Bounded exact-code lookup for the partial-add workflow. A third match marks
/// the identity as ambiguous without reading the full roster.
class CourseRosterIdentityLookup {
  CourseRosterIdentityLookup({
    required List<Enrollment> enrollmentMatches,
    required List<PendingEnrollment> pendingMatches,
    required this.hasMoreEnrollmentMatches,
    required this.hasMorePendingMatches,
  }) : enrollmentMatches = List.unmodifiable(enrollmentMatches),
       pendingMatches = List.unmodifiable(pendingMatches);

  final List<Enrollment> enrollmentMatches;
  final List<PendingEnrollment> pendingMatches;
  final bool hasMoreEnrollmentMatches;
  final bool hasMorePendingMatches;
}

class PendingEnrollmentHistoryCursor {
  const PendingEnrollmentHistoryCursor({
    required this.changedAt,
    required this.operationId,
  });

  final DateTime changedAt;
  final String operationId;
}

class PendingEnrollmentHistoryPage {
  PendingEnrollmentHistoryPage({
    required List<PendingEnrollmentStatusEvent> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<PendingEnrollmentStatusEvent> items;
  final PendingEnrollmentHistoryCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}
