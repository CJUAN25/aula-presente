import 'enrollment.dart';

class EnrollmentStatusChangeResult {
  const EnrollmentStatusChangeResult({
    required this.enrollment,
    required this.alreadyApplied,
  });

  final Enrollment enrollment;

  /// True when this operation ID was already committed and is still the
  /// enrollment's latest transition.
  final bool alreadyApplied;
}

class EnrollmentStatusEvent {
  const EnrollmentStatusEvent({
    required this.operationId,
    required this.fromStatus,
    required this.toStatus,
    required this.changedAt,
    required this.changedBy,
  });

  /// The document ID under `status_events/{operationId}`.
  final String operationId;
  final String fromStatus;
  final String toStatus;
  final DateTime changedAt;
  final String changedBy;
}

class EnrollmentHistoryCursor {
  const EnrollmentHistoryCursor({
    required this.changedAt,
    required this.operationId,
  });

  final DateTime changedAt;
  final String operationId;
}

class EnrollmentHistoryPage {
  EnrollmentHistoryPage({
    required List<EnrollmentStatusEvent> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<EnrollmentStatusEvent> items;
  final EnrollmentHistoryCursor? nextCursor;

  bool get hasMore => nextCursor != null;
}
