import 'attendance_session.dart';
import 'attendance_segment.dart';

enum AttendanceEventKind {
  correction,
  justification,
  rosterCorrection,
  restore,
  voidSession;

  String get value => switch (this) {
    AttendanceEventKind.voidSession => 'void',
    _ => name,
  };

  static AttendanceEventKind fromValue(String value) => switch (value) {
    'correction' => AttendanceEventKind.correction,
    'justification' => AttendanceEventKind.justification,
    'rosterCorrection' => AttendanceEventKind.rosterCorrection,
    'restore' => AttendanceEventKind.restore,
    'void' => AttendanceEventKind.voidSession,
    _ => throw FormatException('Unsupported attendance event kind: $value'),
  };
}

/// Immutable audit record for a post-finalization change or session void.
class AttendanceSessionEvent {
  AttendanceSessionEvent({
    required this.eventId,
    required this.kind,
    required this.changedAt,
    required this.changedBy,
    required this.reason,
    this.rosterEntryId,
    Map<String, Object?> oldValue = const {},
    Map<String, Object?> newValue = const {},
  }) : oldValue = Map.unmodifiable(oldValue),
       newValue = Map.unmodifiable(newValue);

  final String eventId;
  final AttendanceEventKind kind;
  final String? rosterEntryId;
  final Map<String, Object?> oldValue;
  final Map<String, Object?> newValue;
  final String reason;
  final DateTime? changedAt;
  final String? changedBy;
}

class AttendanceSessionEventCursor {
  const AttendanceSessionEventCursor({
    required this.changedAt,
    required this.eventId,
  });

  final DateTime changedAt;
  final String eventId;
}

class AttendanceSessionEventPage {
  AttendanceSessionEventPage({
    required List<AttendanceSessionEvent> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AttendanceSessionEvent> items;
  final AttendanceSessionEventCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

class AttendanceRosterCursor {
  const AttendanceRosterCursor({required this.rosterEntryId});

  final String rosterEntryId;
}

class AttendanceRosterPage {
  AttendanceRosterPage({
    required List<AttendanceRosterEntry> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AttendanceRosterEntry> items;
  final AttendanceRosterCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

class AttendanceSegmentCursor {
  const AttendanceSegmentCursor({required this.order});

  final int order;
}

class AttendanceSegmentPage {
  AttendanceSegmentPage({
    required List<AttendanceSegment> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AttendanceSegment> items;
  final AttendanceSegmentCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

class AttendanceRosterMutationResult {
  const AttendanceRosterMutationResult({
    required this.session,
    required this.entry,
    required this.alreadyApplied,
  });

  final AttendanceSession session;
  final AttendanceRosterEntry entry;
  final bool alreadyApplied;
}
