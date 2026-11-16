import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/enrollment_status_change.dart';
import '../../enrollments/domain/pending_enrollment.dart';
import '../../enrollments/domain/pending_enrollment_page.dart';
import '../../schedule/domain/academic_date.dart';
import '../domain/attendance_roster.dart';

/// Reconstructs exactly who belongs to a course on one effective civil date.
/// All input histories must be server-complete; an ambiguous legacy pending
/// history is returned as `needsReview` and must block session preparation.
class AttendanceRosterResolver {
  const AttendanceRosterResolver._();

  static AttendanceRosterResolution resolveForDate({
    required CourseRosterSnapshot snapshot,
    required Map<String, List<EnrollmentStatusEvent>>
    enrollmentEventsByStudentUid,
    required Map<String, List<PendingEnrollmentStatusEvent>>
    pendingEventsByEmail,
    Map<String, PendingEnrollment> linkedAuthorizationsByStudentUid = const {},
    required AcademicDate effectiveDate,
  }) {
    if (!snapshot.complete) {
      throw const AttendanceRosterResolutionFailure(
        'The course roster snapshot is incomplete.',
      );
    }

    final allEnrollments = [
      ...snapshot.activeEnrollments,
      ...snapshot.withdrawnEnrollments,
    ];
    final allPending = [
      ...snapshot.pendingEnrollments,
      ...snapshot.withdrawnPendingEnrollments,
    ];
    final courses = <String>{
      ...allEnrollments.map((row) => row.courseId),
      ...allPending.map((row) => row.courseId),
    };
    if (courses.length > 1) {
      throw const AttendanceRosterResolutionFailure(
        'The roster snapshot contains multiple courses.',
      );
    }

    final canonicalByUid = <String, Enrollment>{};
    final canonicalByRosterId = <String, Enrollment>{};
    final canonicalRows = <({Enrollment row, String id})>[];
    for (final enrollment in allEnrollments) {
      if (enrollment.status != 'active' && enrollment.status != 'withdrawn') {
        throw const AttendanceRosterResolutionFailure(
          'The enrollment snapshot contains an unsupported status.',
        );
      }
      final id = _canonicalRosterId(enrollment);
      final priorUid = canonicalByUid[enrollment.studentUid];
      final priorIdentity = canonicalByRosterId[id];
      if (priorUid != null || priorIdentity != null) {
        throw AttendanceRosterResolutionFailure(
          'Duplicate canonical roster identity: $id',
        );
      }
      canonicalByUid[enrollment.studentUid] = enrollment;
      canonicalByRosterId[id] = enrollment;
      canonicalRows.add((row: enrollment, id: id));
    }

    final entries = <String, AttendanceRosterIdentity>{};
    final issues = <String, AttendanceRosterResolutionIssue>{};
    for (final item in canonicalRows) {
      final row = item.row;
      final initialDate = row.effectiveStartDate ?? _legacyStartDate(row);
      final events = enrollmentEventsByStudentUid[row.studentUid] ?? const [];
      _validateLatestEventMarker(
        events: events,
        latestEventId: row.lastStatusEventId,
        latestChangedAt: row.lastStatusChangedAt,
        eventId: (event) => event.operationId,
        changedAt: (event) => event.changedAt,
      );
      final linked = linkedAuthorizationsByStudentUid[row.studentUid];
      final bool active;
      if (linked == null) {
        active = _isMemberOnDate(
          initialStatus: 'active',
          currentStatus: row.status,
          effectiveStartDate: initialDate,
          events: events,
          target: effectiveDate,
        );
      } else {
        final pendingEvents = pendingEventsByEmail[linked.email] ?? const [];
        _validateLinkedPair(row, linked);
        _validateLatestEventMarker(
          events: pendingEvents,
          latestEventId: linked.lastEventId,
          latestChangedAt: linked.lastStatusChangedAt,
          eventId: (event) => event.operationId,
          changedAt: (event) => event.changedAt,
        );
        final resolution = _resolveLinkedMembershipOnDate(
          enrollment: row,
          pending: linked,
          enrollmentEvents: events,
          pendingEvents: pendingEvents,
          target: effectiveDate,
        );
        if (resolution == null) {
          issues[item.id] = AttendanceRosterResolutionIssue(
            rosterEntryId: item.id,
            kind: AttendanceRosterIssueKind.needsReview,
          );
          continue;
        }
        active = resolution;
      }
      if (active) {
        entries[item.id] = AttendanceRosterIdentity(
          rosterEntryId: item.id,
          displayName: row.name,
          studentUid: row.studentUid,
        );
      }
    }

    for (final pending in allPending) {
      if (pending.rosterEntryId.trim().isEmpty) {
        throw const AttendanceRosterResolutionFailure(
          'A pending roster entry has no stable identity.',
        );
      }
      final canonical =
          canonicalByRosterId[pending.rosterEntryId] ??
          (pending.studentUid == null
              ? null
              : canonicalByUid[pending.studentUid]);
      if (pending.status == 'linked') {
        if (canonical != null) continue;
        issues[pending.rosterEntryId] = AttendanceRosterResolutionIssue(
          rosterEntryId: pending.rosterEntryId,
          kind: AttendanceRosterIssueKind.needsReview,
        );
        continue;
      }
      // The canonical document always wins a stable identity collision, even
      // when an old authorization document has not yet reflected `linked`.
      if (canonical != null || entries.containsKey(pending.rosterEntryId)) {
        continue;
      }
      if (pending.status != 'pending' && pending.status != 'withdrawn') {
        throw const AttendanceRosterResolutionFailure(
          'The pending roster snapshot contains an unsupported status.',
        );
      }

      final events = pendingEventsByEmail[pending.email] ?? const [];
      _validateLatestEventMarker(
        events: events,
        latestEventId: pending.lastEventId,
        latestChangedAt: pending.lastStatusChangedAt,
        eventId: (event) => event.operationId,
        changedAt: (event) => event.changedAt,
      );
      final pendingMember = _resolvePendingOnDate(
        pending: pending,
        events: events,
        target: effectiveDate,
      );
      if (pendingMember == null) {
        issues[pending.rosterEntryId] = AttendanceRosterResolutionIssue(
          rosterEntryId: pending.rosterEntryId,
          kind: AttendanceRosterIssueKind.needsReview,
        );
      } else if (pendingMember) {
        entries[pending.rosterEntryId] = AttendanceRosterIdentity(
          rosterEntryId: pending.rosterEntryId,
          displayName: pending.name,
          studentUid: pending.studentUid,
        );
      }
    }

    final result = entries.values.toList()
      ..sort(
        (left, right) => left.rosterEntryId.compareTo(right.rosterEntryId),
      );
    final sortedIssues = issues.values.toList()
      ..sort(
        (left, right) => left.rosterEntryId.compareTo(right.rosterEntryId),
      );
    return AttendanceRosterResolution(entries: result, issues: sortedIssues);
  }

  static String _canonicalRosterId(Enrollment enrollment) {
    final id = enrollment.rosterEntryId;
    if (id == null || id.isEmpty || id.startsWith('legacy:')) {
      return 'legacy:${enrollment.studentUid}';
    }
    return id;
  }

  static AcademicDate _legacyStartDate(Enrollment enrollment) {
    final createdAt = enrollment.createdAt;
    if (createdAt == null) {
      throw const AttendanceRosterResolutionFailure(
        'A legacy enrollment has no effective date or creation timestamp.',
      );
    }
    return _bogotaDate(createdAt);
  }

  static bool _isMemberOnDate({
    required String initialStatus,
    required String currentStatus,
    required AcademicDate effectiveStartDate,
    required List<EnrollmentStatusEvent> events,
    required AcademicDate target,
  }) {
    final ordered = [...events]..sort(_compareEnrollmentEvents);
    var state = initialStatus;
    for (final event in ordered) {
      final date = event.effectiveDate ?? _bogotaDate(event.changedAt);
      if (date.compareTo(effectiveStartDate) < 0) {
        throw const AttendanceRosterResolutionFailure(
          'An enrollment status event predates its effective start date.',
        );
      }
      if (event.fromStatus != state ||
          !_validEnrollmentTransition(event.fromStatus, event.toStatus)) {
        throw const AttendanceRosterResolutionFailure(
          'Enrollment status history is incomplete or inconsistent.',
        );
      }
      state = event.toStatus;
    }
    if (state != currentStatus) {
      throw const AttendanceRosterResolutionFailure(
        'Enrollment status does not match its complete event history.',
      );
    }

    if (target.compareTo(effectiveStartDate) < 0) return false;
    state = initialStatus;
    for (final event in ordered) {
      final date = event.effectiveDate ?? _bogotaDate(event.changedAt);
      if (date.compareTo(target) > 0) break;
      state = event.toStatus;
    }
    return state == 'active';
  }

  static bool? _resolvePendingOnDate({
    required PendingEnrollment pending,
    required List<PendingEnrollmentStatusEvent> events,
    required AcademicDate target,
  }) {
    final ordered = [...events]..sort(_comparePendingEvents);
    final ambiguousReopenIndexes = <int>[];
    for (var i = 0; i < ordered.length; i++) {
      final event = ordered[i];
      if (event.fromStatus == 'withdrawn' &&
          event.toStatus == 'pending' &&
          event.fromEffectiveStartDate == null) {
        ambiguousReopenIndexes.add(i);
      }
    }

    var firstEventIndex = 0;
    var initialStatus = 'pending';
    var effectiveStartDate = pending.effectiveStartDate;
    for (final event in ordered) {
      final previousDate = event.fromEffectiveStartDate;
      if (previousDate != null) {
        effectiveStartDate = previousDate;
        break;
      }
    }

    if (ambiguousReopenIndexes.isNotEmpty) {
      final latestAmbiguousIndex = ambiguousReopenIndexes.last;
      final ambiguousReopen = ordered[latestAmbiguousIndex];
      // A legacy event lost the previous start date. Dates before the last
      // known re-entry cannot be reconstructed safely; do not infer from
      // createdAt or the current mutable field.
      if (target.compareTo(ambiguousReopen.effectiveDate) < 0) return null;
      firstEventIndex = latestAmbiguousIndex;
      initialStatus = ambiguousReopen.fromStatus;
      effectiveStartDate = ambiguousReopen.effectiveDate;
    }

    if (effectiveStartDate == pending.effectiveStartDate &&
        pending.status == 'pending') {
      final lastPending = ordered.where((event) => event.toStatus == 'pending');
      if (lastPending.isNotEmpty &&
          lastPending.last.effectiveDate != pending.effectiveStartDate) {
        throw const AttendanceRosterResolutionFailure(
          'Pending effective date does not match its latest transition.',
        );
      }
    }

    var state = initialStatus;
    var currentEffectiveStartDate = effectiveStartDate;
    for (var i = firstEventIndex; i < ordered.length; i++) {
      final event = ordered[i];
      if (!_validPendingTransition(event.fromStatus, event.toStatus) ||
          event.fromStatus != state) {
        throw const AttendanceRosterResolutionFailure(
          'Pending status history is incomplete or inconsistent.',
        );
      }
      final recordedPreviousDate = event.fromEffectiveStartDate;
      if (recordedPreviousDate != null &&
          recordedPreviousDate != currentEffectiveStartDate) {
        throw const AttendanceRosterResolutionFailure(
          'Pending event effective-start snapshot does not match its prior state.',
        );
      }
      if (i == firstEventIndex &&
          event.fromStatus == 'withdrawn' &&
          event.toStatus == 'pending') {
        // This transition is the known boundary for a legacy history.
        currentEffectiveStartDate = event.effectiveDate;
      }
      state = event.toStatus;
      if (state == 'pending') currentEffectiveStartDate = event.effectiveDate;
    }
    if (state != pending.status) {
      throw const AttendanceRosterResolutionFailure(
        'Pending status does not match its complete event history.',
      );
    }
    if (pending.status == 'pending' &&
        currentEffectiveStartDate != pending.effectiveStartDate) {
      throw const AttendanceRosterResolutionFailure(
        'Pending effective date does not match its current state.',
      );
    }

    if (target.compareTo(effectiveStartDate) < 0) return false;
    state = initialStatus;
    for (var i = firstEventIndex; i < ordered.length; i++) {
      final event = ordered[i];
      if (event.effectiveDate.compareTo(target) > 0) break;
      state = event.toStatus;
    }
    return state == 'pending';
  }

  static int _compareEnrollmentEvents(
    EnrollmentStatusEvent left,
    EnrollmentStatusEvent right,
  ) {
    final leftDate = left.effectiveDate ?? _bogotaDate(left.changedAt);
    final rightDate = right.effectiveDate ?? _bogotaDate(right.changedAt);
    final dateOrder = leftDate.compareTo(rightDate);
    if (dateOrder != 0) return dateOrder;
    final timeOrder = left.changedAt.compareTo(right.changedAt);
    if (timeOrder != 0) return timeOrder;
    return left.operationId.compareTo(right.operationId);
  }

  static int _comparePendingEvents(
    PendingEnrollmentStatusEvent left,
    PendingEnrollmentStatusEvent right,
  ) {
    final dateOrder = left.effectiveDate.compareTo(right.effectiveDate);
    if (dateOrder != 0) return dateOrder;
    final timeOrder = left.changedAt.compareTo(right.changedAt);
    if (timeOrder != 0) return timeOrder;
    return left.operationId.compareTo(right.operationId);
  }

  static bool _validEnrollmentTransition(String from, String to) =>
      (from == 'active' && to == 'withdrawn') ||
      (from == 'withdrawn' && to == 'active');

  static bool _validPendingTransition(String from, String to) =>
      (from == 'pending' && to == 'withdrawn') ||
      (from == 'withdrawn' && to == 'pending');

  static void _validateLinkedPair(
    Enrollment enrollment,
    PendingEnrollment pending,
  ) {
    if (pending.status != 'linked' ||
        pending.studentUid != enrollment.studentUid ||
        pending.courseId != enrollment.courseId ||
        pending.ownerUid != enrollment.ownerUid ||
        pending.email != enrollment.email ||
        pending.studentCode != enrollment.studentCode) {
      throw const AttendanceRosterResolutionFailure(
        'The linked authorization does not match its canonical enrollment.',
      );
    }
    final canonicalId = _canonicalRosterId(enrollment);
    final isLegacy = canonicalId == 'legacy:${enrollment.studentUid}';
    if (!isLegacy && pending.rosterEntryId != canonicalId) {
      throw const AttendanceRosterResolutionFailure(
        'The linked authorization has a different stable roster identity.',
      );
    }
  }

  static bool? _resolveLinkedMembershipOnDate({
    required Enrollment enrollment,
    required PendingEnrollment pending,
    required List<EnrollmentStatusEvent> enrollmentEvents,
    required List<PendingEnrollmentStatusEvent> pendingEvents,
    required AcademicDate target,
  }) {
    final linkTimestamp = pending.linkedAt ?? enrollment.createdAt;
    if (linkTimestamp == null) return null;
    final linkDate = _bogotaDate(linkTimestamp);
    if (target.compareTo(linkDate) >= 0) {
      final canonicalStart = enrollment.effectiveStartDate ?? linkDate;
      return _isMemberOnDate(
        initialStatus: 'active',
        currentStatus: enrollment.status,
        effectiveStartDate: canonicalStart,
        events: enrollmentEvents,
        target: target,
      );
    }

    // Before linking, the exact authorization's own timeline is the source of
    // membership. A `linked` transition itself is the exclusive boundary.
    final ordered = [...pendingEvents]..sort(_comparePendingEvents);
    final linkEvents = ordered
        .where((event) => event.toStatus == 'linked')
        .toList();
    if (linkEvents.length != 1) return null;
    final linkEvent = linkEvents.single;
    if (linkEvent.fromStatus != 'pending' ||
        (linkEvent.fromEffectiveStartDate != null &&
            linkEvent.fromEffectiveStartDate != pending.effectiveStartDate)) {
      return null;
    }
    final preLinkEvents = ordered
        .where((event) => event.toStatus != 'linked')
        .toList();
    final ambiguousReopens = <int>[];
    for (var i = 0; i < preLinkEvents.length; i++) {
      final event = preLinkEvents[i];
      if (event.fromStatus == 'withdrawn' &&
          event.toStatus == 'pending' &&
          event.fromEffectiveStartDate == null) {
        ambiguousReopens.add(i);
      }
    }

    var startIndex = 0;
    var initialStatus = 'pending';
    var initialDate = pending.effectiveStartDate;
    for (final event in preLinkEvents) {
      final previousDate = event.fromEffectiveStartDate;
      if (previousDate != null) {
        initialDate = previousDate;
        break;
      }
    }
    if (ambiguousReopens.isNotEmpty) {
      final index = ambiguousReopens.last;
      final boundary = preLinkEvents[index];
      if (target.compareTo(boundary.effectiveDate) < 0) return null;
      startIndex = index;
      initialStatus = boundary.fromStatus;
      initialDate = boundary.effectiveDate;
    }

    var state = initialStatus;
    var effectiveStart = initialDate;
    for (var i = startIndex; i < preLinkEvents.length; i++) {
      final event = preLinkEvents[i];
      if (!_validPendingTransition(event.fromStatus, event.toStatus) ||
          event.fromStatus != state) {
        return null;
      }
      final recordedPreviousDate = event.fromEffectiveStartDate;
      if (recordedPreviousDate != null &&
          recordedPreviousDate != effectiveStart) {
        return null;
      }
      state = event.toStatus;
      if (state == 'pending') effectiveStart = event.effectiveDate;
    }
    // Immediately before the atomic link, a linkable authorization must have
    // been pending. A withdrawn or inconsistent source is never guessed.
    if (state != 'pending') return null;
    if (target.compareTo(initialDate) < 0) return false;

    state = initialStatus;
    for (var i = startIndex; i < preLinkEvents.length; i++) {
      final event = preLinkEvents[i];
      if (event.effectiveDate.compareTo(target) > 0) break;
      state = event.toStatus;
    }
    return state == 'pending';
  }

  static AcademicDate _bogotaDate(DateTime timestamp) =>
      AcademicDate.fromDateTime(
        timestamp.toUtc().subtract(const Duration(hours: 5)),
      );

  static void _validateLatestEventMarker<T>({
    required List<T> events,
    required String? latestEventId,
    required DateTime? latestChangedAt,
    required String Function(T event) eventId,
    required DateTime Function(T event) changedAt,
  }) {
    if (latestEventId == null) {
      if (latestChangedAt != null) {
        throw const AttendanceRosterResolutionFailure(
          'A latest status timestamp has no matching event ID.',
        );
      }
      return;
    }
    final matches = events.where((event) => eventId(event) == latestEventId);
    if (matches.length != 1 || latestChangedAt == null) {
      throw const AttendanceRosterResolutionFailure(
        'The complete status history does not contain the latest event.',
      );
    }
    final event = matches.single;
    if (changedAt(event) != latestChangedAt) {
      throw const AttendanceRosterResolutionFailure(
        'The latest status event does not match the current roster snapshot.',
      );
    }
  }
}
