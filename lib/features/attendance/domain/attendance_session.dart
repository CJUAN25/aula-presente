import '../../schedule/domain/academic_date.dart';
import 'attendance_failure.dart';
import 'attendance_mode.dart';
import 'attendance_occurrence.dart';
import 'attendance_segment.dart';

enum AttendanceSessionStatus {
  preparing,
  inProgress,
  closing,
  finalized,
  voiding,
  voided;

  String get value => name;

  static AttendanceSessionStatus fromValue(String value) => switch (value) {
    'preparing' => AttendanceSessionStatus.preparing,
    'inProgress' => AttendanceSessionStatus.inProgress,
    'closing' => AttendanceSessionStatus.closing,
    'finalized' => AttendanceSessionStatus.finalized,
    'voiding' => AttendanceSessionStatus.voiding,
    'voided' => AttendanceSessionStatus.voided,
    _ => throw FormatException('Unsupported attendance session status: $value'),
  };
}

enum AttendanceRosterState {
  building,
  ready;

  String get value => name;

  static AttendanceRosterState fromValue(String value) => switch (value) {
    'building' => AttendanceRosterState.building,
    'ready' => AttendanceRosterState.ready,
    _ => throw FormatException('Unsupported roster state: $value'),
  };
}

enum AttendanceMark {
  unmarked,
  present,
  absent;

  String get value => name;

  static AttendanceMark fromValue(String value) => switch (value) {
    'unmarked' => AttendanceMark.unmarked,
    'present' => AttendanceMark.present,
    'absent' => AttendanceMark.absent,
    _ => throw FormatException('Unsupported attendance mark: $value'),
  };
}

enum AttendanceJustificationStatus {
  none,
  inReview,
  justified,
  notAccepted;

  String get value => name;

  static AttendanceJustificationStatus fromValue(String value) =>
      switch (value) {
        'none' => AttendanceJustificationStatus.none,
        'inReview' => AttendanceJustificationStatus.inReview,
        'justified' => AttendanceJustificationStatus.justified,
        'notAccepted' => AttendanceJustificationStatus.notAccepted,
        _ => throw FormatException('Unsupported justification status: $value'),
      };
}

enum AttendanceSessionResult {
  unmarked,
  voided,
  present,
  absent,
  partial,
  justified;

  String get value => name;

  static AttendanceSessionResult fromValue(String value) => switch (value) {
    'unmarked' => AttendanceSessionResult.unmarked,
    'voided' => AttendanceSessionResult.voided,
    'present' => AttendanceSessionResult.present,
    'absent' => AttendanceSessionResult.absent,
    'partial' => AttendanceSessionResult.partial,
    'justified' => AttendanceSessionResult.justified,
    _ => throw FormatException('Unsupported attendance result: $value'),
  };
}

enum AttendanceFinalizeStatus { confirmed, reviewRequired, notConfirmed }

enum AttendanceMutationKind {
  mark,
  correction,
  justification,
  rosterCorrection,
  voidSession;

  String get value => switch (this) {
    AttendanceMutationKind.voidSession => 'void',
    _ => name,
  };

  static AttendanceMutationKind fromValue(String value) => switch (value) {
    'mark' => AttendanceMutationKind.mark,
    'correction' => AttendanceMutationKind.correction,
    'justification' => AttendanceMutationKind.justification,
    'rosterCorrection' => AttendanceMutationKind.rosterCorrection,
    'void' => AttendanceMutationKind.voidSession,
    _ => throw FormatException('Unsupported attendance mutation: $value'),
  };
}

class AttendanceSession {
  AttendanceSession({
    required this.courseId,
    required this.ownerUid,
    required this.occurrenceId,
    required this.occurrenceKind,
    required this.mode,
    required this.status,
    required this.rosterState,
    required this.scheduledDate,
    required this.effectiveDate,
    required this.startMinute,
    required this.endMinute,
    required this.timezone,
    required List<String> segmentIds,
    required this.rosterCount,
    required this.markedCount,
    required this.unmarkedCount,
    this.unmarkedConfirmed = false,
    required this.version,
    required this.lastMutationRosterEntryId,
    required this.lastMutationKind,
    required this.lastEventId,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.schemaVersion = 1,
    this.unmarkedConfirmedAt,
    this.unmarkedConfirmedBy,
    this.finalizedAt,
    this.voidedAt,
    this.reason,
    this.lateRegistrationReason,
  }) : segmentIds = List.unmodifiable(segmentIds);

  final int schemaVersion;
  final String courseId;
  final String ownerUid;
  final String occurrenceId;
  final AttendanceOccurrenceKind occurrenceKind;
  final AttendanceMode mode;
  final AttendanceSessionStatus status;
  final AttendanceRosterState rosterState;
  final AcademicDate scheduledDate;
  final AcademicDate effectiveDate;
  final int startMinute;
  final int endMinute;
  final String timezone;
  final List<String> segmentIds;
  final int rosterCount;
  final int markedCount;
  final int unmarkedCount;
  final bool unmarkedConfirmed;
  final int version;
  final String? lastMutationRosterEntryId;
  final AttendanceMutationKind? lastMutationKind;
  final String? lastEventId;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? unmarkedConfirmedAt;
  final String? unmarkedConfirmedBy;
  final DateTime? finalizedAt;
  final DateTime? voidedAt;
  final String? reason;
  final String? lateRegistrationReason;
}

/// The generic academic units for one student and one roster entry. In
/// meeting mode one unit is a class; in minutes mode units are actual minutes.
class AttendanceRosterMark {
  const AttendanceRosterMark({
    required this.mark,
    required this.absentUnits,
    required this.justificationStatus,
    required this.justifiedUnits,
  });

  final AttendanceMark mark;
  final int absentUnits;
  final AttendanceJustificationStatus justificationStatus;
  final int justifiedUnits;

  factory AttendanceRosterMark.unmarked() => const AttendanceRosterMark(
    mark: AttendanceMark.unmarked,
    absentUnits: 0,
    justificationStatus: AttendanceJustificationStatus.none,
    justifiedUnits: 0,
  );
}

class AttendanceRosterEntry {
  AttendanceRosterEntry({
    required this.rosterEntryId,
    required this.displayName,
    required this.studentUid,
    required this.meetingMark,
    required Map<String, AttendanceRosterMark> segmentMarks,
    required this.version,
    this.updatedAt,
    this.updatedBy,
  }) : segmentMarks = Map.unmodifiable(segmentMarks);

  final String rosterEntryId;
  final String displayName;
  final String? studentUid;
  final AttendanceRosterMark? meetingMark;
  final Map<String, AttendanceRosterMark> segmentMarks;
  final int version;
  final DateTime? updatedAt;
  final String? updatedBy;

  factory AttendanceRosterEntry.unmarkedForMode({
    required String rosterEntryId,
    required String displayName,
    required String? studentUid,
    required AttendanceMode mode,
    required Iterable<AttendanceSegment> segments,
  }) {
    if (rosterEntryId.trim().isEmpty || displayName.trim().isEmpty) {
      throw ArgumentError('A roster entry needs an identity and display name.');
    }
    final segmentList = segments.toList();
    if ((mode == AttendanceMode.meeting && segmentList.isNotEmpty) ||
        (mode == AttendanceMode.minutes && segmentList.isEmpty)) {
      throw ArgumentError('Roster segments do not match the attendance mode.');
    }
    final marks = {
      for (final segment in segmentList)
        segment.id: AttendanceRosterMark.unmarked(),
    };
    if (marks.length != segmentList.length) {
      throw ArgumentError('Roster segment IDs must be unique.');
    }
    return AttendanceRosterEntry(
      rosterEntryId: rosterEntryId,
      displayName: displayName,
      studentUid: studentUid,
      meetingMark: mode == AttendanceMode.meeting
          ? AttendanceRosterMark.unmarked()
          : null,
      segmentMarks: mode == AttendanceMode.minutes ? marks : const {},
      version: 0,
    );
  }
}

class AttendanceFinalizeResult {
  const AttendanceFinalizeResult({
    required this.status,
    required this.unmarkedCount,
    this.session,
    this.confirmationRequired = false,
    this.writeConfirmed = false,
    this.publicationPending = false,
    this.failureKind,
  });

  final AttendanceFinalizeStatus status;
  final int unmarkedCount;
  final AttendanceSession? session;
  final bool confirmationRequired;
  final bool writeConfirmed;

  /// The session reached `finalized`, but one or more student projections
  /// remain staged and can be published by retrying finalization.
  final bool publicationPending;
  final AttendanceFailureKind? failureKind;
}
