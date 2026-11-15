import 'enrollment.dart';
import 'pending_enrollment.dart';
import 'pending_enrollment_page.dart';

/// A display row for one academic identity in a single course roster.
///
/// The roster snapshot is course-scoped. Canonical enrollments take precedence
/// over pending authorizations when both have the same stable roster identity.
/// Legacy enrollments without that identity use their UID and are never
/// associated with a pending row by name or email similarity.
class CourseEnrollmentHistoryEntry {
  const CourseEnrollmentHistoryEntry._({
    required this.enrollment,
    required this.pending,
  }) : assert((enrollment == null) != (pending == null));

  final Enrollment? enrollment;
  final PendingEnrollment? pending;

  String get identityKey {
    final canonical = enrollment;
    if (canonical != null) {
      final rosterEntryId = canonical.rosterEntryId;
      if (rosterEntryId == null || rosterEntryId.startsWith('legacy:')) {
        return 'uid:${canonical.studentUid}';
      }
      if (rosterEntryId.isEmpty) {
        throw StateError('Enrollment rosterEntryId cannot be empty.');
      }
      return 'roster:$rosterEntryId';
    }

    final authorization = pending!;
    if (authorization.rosterEntryId.isEmpty) {
      throw StateError('Pending rosterEntryId cannot be empty.');
    }
    return 'roster:${authorization.rosterEntryId}';
  }

  String get displayName => enrollment?.name ?? pending!.name;

  String get statusLabel {
    final canonical = enrollment;
    if (canonical != null) {
      return switch (canonical.status) {
        'active' => 'Activo',
        'withdrawn' => 'Retirado',
        _ => throw StateError('Unsupported enrollment status.'),
      };
    }

    return switch (pending!.status) {
      'pending' => 'Pendiente de vincular',
      'withdrawn' => 'Autorización retirada',
      _ => throw StateError('Unsupported pending enrollment status.'),
    };
  }

  DateTime? get createdAt => enrollment?.createdAt ?? pending?.createdAt;

  String get _currentStatus => enrollment?.status ?? pending!.status;

  DateTime? get _lastStatusChangedAt =>
      enrollment?.lastStatusChangedAt ?? pending?.lastStatusChangedAt;

  /// Builds stable, deduplicated history rows from a fully loaded course
  /// snapshot. It does not read status events; each source already carries its
  /// current status.
  static List<CourseEnrollmentHistoryEntry> fromSnapshot(
    CourseRosterSnapshot snapshot,
  ) {
    if (!snapshot.complete) {
      throw StateError('Cannot build history from an incomplete roster.');
    }
    final courseIds = <String>{
      ...snapshot.activeEnrollments.map((row) => row.courseId),
      ...snapshot.withdrawnEnrollments.map((row) => row.courseId),
      ...snapshot.pendingEnrollments.map((row) => row.courseId),
      ...snapshot.withdrawnPendingEnrollments.map((row) => row.courseId),
    };
    if (courseIds.length > 1) {
      throw StateError('A course roster snapshot cannot mix courses.');
    }

    final canonicalByIdentity = <String, CourseEnrollmentHistoryEntry>{};

    // Canonical rows come first so they win a collision with an authorization.
    for (final enrollment in [
      ...snapshot.activeEnrollments,
      ...snapshot.withdrawnEnrollments,
    ]) {
      final entry = CourseEnrollmentHistoryEntry._(
        enrollment: enrollment,
        pending: null,
      );
      _keepLatestVersion(canonicalByIdentity, entry);
    }

    final pendingByIdentity = <String, CourseEnrollmentHistoryEntry>{};
    for (final authorization in [
      ...snapshot.pendingEnrollments,
      ...snapshot.withdrawnPendingEnrollments,
    ]) {
      // A linked authorization is represented by its canonical enrollment.
      if (authorization.status == 'linked') continue;
      final entry = CourseEnrollmentHistoryEntry._(
        enrollment: null,
        pending: authorization,
      );
      _keepLatestVersion(pendingByIdentity, entry);
    }

    // Stable identity collisions across sources always resolve to the
    // canonical enrollment, independent of the source timestamps.
    final byIdentity = Map<String, CourseEnrollmentHistoryEntry>.from(
      canonicalByIdentity,
    );
    for (final entry in pendingByIdentity.values) {
      byIdentity.putIfAbsent(entry.identityKey, () => entry);
    }

    final entries = byIdentity.values.toList()..sort(_compareHistoryEntries);
    return List.unmodifiable(entries);
  }

  static void _keepLatestVersion(
    Map<String, CourseEnrollmentHistoryEntry> entries,
    CourseEnrollmentHistoryEntry candidate,
  ) {
    final key = candidate.identityKey;
    final current = entries[key];
    if (current == null) {
      entries[key] = candidate;
      return;
    }

    final versionOrder = _compareVersion(current, candidate);
    if (versionOrder == 0) {
      if (current._currentStatus != candidate._currentStatus) {
        throw StateError(
          'Conflicting roster statuses share the same version timestamps.',
        );
      }
      return;
    }
    if (versionOrder < 0) entries[key] = candidate;
  }

  /// Negative means [left] is older, positive means it is newer. Compare the
  /// status-change marker first, then creation time as a stable fallback.
  static int _compareVersion(
    CourseEnrollmentHistoryEntry left,
    CourseEnrollmentHistoryEntry right,
  ) {
    final statusChangeOrder = _compareNullableDates(
      left._lastStatusChangedAt,
      right._lastStatusChangedAt,
    );
    if (statusChangeOrder != 0) return statusChangeOrder;
    return _compareNullableDates(left.createdAt, right.createdAt);
  }

  static int _compareNullableDates(DateTime? left, DateTime? right) {
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    return left.compareTo(right);
  }

  static int _compareHistoryEntries(
    CourseEnrollmentHistoryEntry left,
    CourseEnrollmentHistoryEntry right,
  ) {
    final leftCreatedAt = left.createdAt;
    final rightCreatedAt = right.createdAt;
    if (leftCreatedAt == null && rightCreatedAt != null) return 1;
    if (leftCreatedAt != null && rightCreatedAt == null) return -1;
    if (leftCreatedAt != null && rightCreatedAt != null) {
      final dateOrder = rightCreatedAt.compareTo(leftCreatedAt);
      if (dateOrder != 0) return dateOrder;
    }
    return left.identityKey.compareTo(right.identityKey);
  }
}
