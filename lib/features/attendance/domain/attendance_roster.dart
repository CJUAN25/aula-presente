class AttendanceRosterIdentity {
  const AttendanceRosterIdentity({
    required this.rosterEntryId,
    required this.displayName,
    required this.studentUid,
  });

  final String rosterEntryId;
  final String displayName;
  final String? studentUid;
}

enum AttendanceRosterIssueKind { needsReview }

class AttendanceRosterResolutionIssue {
  const AttendanceRosterResolutionIssue({
    required this.rosterEntryId,
    required this.kind,
  });

  final String rosterEntryId;
  final AttendanceRosterIssueKind kind;
}

class AttendanceRosterResolution {
  AttendanceRosterResolution({
    required List<AttendanceRosterIdentity> entries,
    required List<AttendanceRosterResolutionIssue> issues,
  }) : entries = List.unmodifiable(entries),
       issues = List.unmodifiable(issues);

  final List<AttendanceRosterIdentity> entries;
  final List<AttendanceRosterResolutionIssue> issues;

  bool get canPrepareSession => issues.isEmpty;
}

class AttendanceRosterResolutionFailure implements Exception {
  const AttendanceRosterResolutionFailure(this.reason);

  final String reason;

  @override
  String toString() => 'AttendanceRosterResolutionFailure: $reason';
}
