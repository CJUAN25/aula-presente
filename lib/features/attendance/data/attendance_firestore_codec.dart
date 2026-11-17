import 'package:cloud_firestore/cloud_firestore.dart';

import '../../schedule/domain/academic_date.dart';
import '../domain/attendance_calendar_change.dart';
import '../domain/attendance_config.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_occurrence.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_segment.dart';
import '../domain/attendance_session.dart';
import '../domain/attendance_session_event.dart';

/// Converts attendance domain values to and from the exact Firestore schema.
/// Business calculations stay in `attendance/application`; this class only
/// handles field names, timestamps, and structural validation.
class AttendanceFirestoreCodec {
  const AttendanceFirestoreCodec._();

  static const _configFields = {
    'schemaVersion',
    'mode',
    'sessionCount',
    'lastSessionId',
    'createdAt',
    'createdBy',
    'updatedAt',
    'updatedBy',
  };

  static const _calendarFields = {
    'occurrenceId',
    'kind',
    'originalDate',
    'effectiveDate',
    'startMinute',
    'endMinute',
    'reason',
    'version',
    'createdAt',
    'createdBy',
    'updatedAt',
    'updatedBy',
  };

  static const _sessionFields = {
    'schemaVersion',
    'courseId',
    'ownerUid',
    'occurrenceId',
    'occurrenceKind',
    'mode',
    'status',
    'rosterState',
    'scheduledDate',
    'effectiveDate',
    'startMinute',
    'endMinute',
    'timezone',
    'segmentIds',
    'rosterCount',
    'markedCount',
    'unmarkedCount',
    'unmarkedConfirmed',
    'unmarkedConfirmedAt',
    'unmarkedConfirmedBy',
    'lastMutationRosterEntryId',
    'lastMutationKind',
    'lastEventId',
    'version',
    'createdAt',
    'createdBy',
    'updatedAt',
    'updatedBy',
    'finalizedAt',
    'voidedAt',
    'reason',
    'lateRegistrationReason',
  };

  static const _sessionRequiredFields = {
    'schemaVersion',
    'courseId',
    'ownerUid',
    'occurrenceId',
    'occurrenceKind',
    'mode',
    'status',
    'rosterState',
    'scheduledDate',
    'effectiveDate',
    'startMinute',
    'endMinute',
    'timezone',
    'segmentIds',
    'rosterCount',
    'markedCount',
    'unmarkedCount',
    'unmarkedConfirmed',
    'lastMutationRosterEntryId',
    'lastMutationKind',
    'lastEventId',
    'version',
    'createdAt',
    'createdBy',
    'updatedAt',
    'updatedBy',
  };

  static const _segmentFields = {
    'segmentId',
    'order',
    'startMinute',
    'endMinute',
    'durationMinutes',
    'createdAt',
  };

  static const _eventFields = {
    'kind',
    'rosterEntryId',
    'oldValue',
    'newValue',
    'reason',
    'changedAt',
    'changedBy',
  };

  static const _recordRequiredFields = {
    'schemaVersion',
    'courseId',
    'sessionId',
    'rosterEntryId',
    'visibility',
    'mode',
    'scheduledDate',
    'effectiveDate',
    'startMinute',
    'endMinute',
    'unitCount',
    'absentUnits',
    'inReviewUnits',
    'justifiedUnits',
    'result',
    'publishedAt',
    'updatedAt',
  };

  static const _recordFields = {..._recordRequiredFields, 'segments'};

  static AttendanceConfig configFromMap(Map<String, dynamic> data) {
    _requireExactFields(data, _configFields);
    if (data['schemaVersion'] != 1 ||
        data['sessionCount'] is! int ||
        (data['sessionCount'] as int) < 0 ||
        (data['lastSessionId'] != null && data['lastSessionId'] is! String) ||
        data['createdBy'] is! String ||
        data['updatedBy'] is! String) {
      throw const FormatException('Invalid attendance config.');
    }
    return AttendanceConfig(
      schemaVersion: 1,
      mode: AttendanceMode.fromValue(_string(data, 'mode')),
      sessionCount: data['sessionCount'] as int,
      lastSessionId: data['lastSessionId'] as String?,
      createdAt: _dateTime(data['createdAt']),
      createdBy: data['createdBy'] as String,
      updatedAt: _dateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String,
    );
  }

  static Map<String, Object?> newConfig({
    required AttendanceMode mode,
    required String uid,
  }) => {
    'schemaVersion': 1,
    'mode': mode.value,
    'sessionCount': 0,
    'lastSessionId': null,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static Map<String, Object?> updateConfig({
    required AttendanceMode mode,
    required String uid,
  }) => {
    'mode': mode.value,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static Map<String, Object?> incrementConfigForSession({
    required int sessionCount,
    required String occurrenceId,
    required String uid,
  }) => {
    'sessionCount': sessionCount + 1,
    'lastSessionId': occurrenceId,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static AttendanceCalendarChange calendarChangeFromMap(
    Map<String, dynamic> data, {
    required String expectedOccurrenceId,
  }) {
    _requireExactFields(data, _calendarFields);
    if (data['occurrenceId'] != expectedOccurrenceId ||
        data['startMinute'] is! int ||
        data['endMinute'] is! int ||
        data['version'] is! int ||
        (data['version'] as int) < 1 ||
        data['reason'] is! String ||
        data['createdBy'] is! String ||
        data['updatedBy'] is! String) {
      throw const FormatException('Invalid attendance calendar change.');
    }
    return AttendanceCalendarChange(
      occurrenceId: expectedOccurrenceId,
      kind: AttendanceCalendarChangeKind.fromValue(_string(data, 'kind')),
      originalDate: _academicDate(data['originalDate']),
      effectiveDate: _academicDate(data['effectiveDate']),
      startMinute: data['startMinute'] as int,
      endMinute: data['endMinute'] as int,
      reason: data['reason'] as String,
      version: data['version'] as int,
      createdAt: _dateTime(data['createdAt']),
      createdBy: data['createdBy'] as String,
      updatedAt: _dateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String,
    );
  }

  static Map<String, Object?> calendarChangeForCreate({
    required AttendanceCalendarChange change,
    required String uid,
  }) => {
    'occurrenceId': change.occurrenceId,
    'kind': change.kind.value,
    'originalDate': Timestamp.fromDate(change.originalDate.toUtcTimestamp()),
    'effectiveDate': Timestamp.fromDate(change.effectiveDate.toUtcTimestamp()),
    'startMinute': change.startMinute,
    'endMinute': change.endMinute,
    'reason': change.reason,
    'version': 1,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static Map<String, Object?> calendarChangeForUpdate({
    required AttendanceCalendarChange change,
    required String uid,
  }) => {
    'kind': change.kind.value,
    'originalDate': Timestamp.fromDate(change.originalDate.toUtcTimestamp()),
    'effectiveDate': Timestamp.fromDate(change.effectiveDate.toUtcTimestamp()),
    'startMinute': change.startMinute,
    'endMinute': change.endMinute,
    'reason': change.reason,
    'version': change.version + 1,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static AttendanceSession sessionFromMap(
    Map<String, dynamic> data, {
    required String expectedCourseId,
    required String expectedOccurrenceId,
  }) {
    _requireExactFields(data, _sessionFields, required: _sessionRequiredFields);
    final segmentIds = data['segmentIds'];
    if (data['schemaVersion'] != 1 ||
        data['courseId'] != expectedCourseId ||
        data['occurrenceId'] != expectedOccurrenceId ||
        data['ownerUid'] is! String ||
        data['timezone'] != 'America/Bogota' ||
        segmentIds is! List ||
        segmentIds.any((value) => value is! String) ||
        data['rosterCount'] is! int ||
        data['markedCount'] is! int ||
        data['unmarkedCount'] is! int ||
        data['unmarkedConfirmed'] is! bool ||
        data['version'] is! int ||
        data['version'] as int < 1 ||
        data['createdBy'] is! String ||
        data['updatedBy'] is! String ||
        (data['unmarkedConfirmedAt'] != null &&
            data['unmarkedConfirmedAt'] is! Timestamp) ||
        (data['unmarkedConfirmedBy'] != null &&
            data['unmarkedConfirmedBy'] is! String) ||
        (data['lastMutationRosterEntryId'] != null &&
            data['lastMutationRosterEntryId'] is! String) ||
        (data['lastMutationKind'] != null &&
            data['lastMutationKind'] is! String) ||
        (data['lastEventId'] != null && data['lastEventId'] is! String) ||
        (data['finalizedAt'] != null && data['finalizedAt'] is! Timestamp) ||
        (data['voidedAt'] != null && data['voidedAt'] is! Timestamp) ||
        (data['reason'] != null && data['reason'] is! String) ||
        (data['lateRegistrationReason'] != null &&
            data['lateRegistrationReason'] is! String)) {
      throw const FormatException('Invalid attendance session.');
    }
    final confirmed = data['unmarkedConfirmed'] as bool;
    final hasConfirmedAt = data['unmarkedConfirmedAt'] is Timestamp;
    final hasConfirmedBy = data['unmarkedConfirmedBy'] is String;
    if (confirmed != (hasConfirmedAt && hasConfirmedBy) ||
        (data['unmarkedConfirmedAt'] != null && !hasConfirmedAt) ||
        (data['unmarkedConfirmedBy'] != null && !hasConfirmedBy)) {
      throw const FormatException('Invalid unmarked confirmation metadata.');
    }
    final status = _sessionStatus(_string(data, 'status'));
    if ((status == AttendanceSessionStatus.finalized &&
            data['finalizedAt'] is! Timestamp) ||
        (status == AttendanceSessionStatus.voided &&
            data['voidedAt'] is! Timestamp) ||
        (data['reason'] != null && data['reason'] is! String) ||
        (status == AttendanceSessionStatus.restoring &&
            (data['finalizedAt'] is! Timestamp ||
                data['voidedAt'] is! Timestamp))) {
      throw const FormatException('Invalid terminal session metadata.');
    }
    final lastMutationKind = data['lastMutationKind'] == null
        ? null
        : _mutationKind(data['lastMutationKind'] as String);
    if ((lastMutationKind == null) !=
            (data['lastMutationRosterEntryId'] == null &&
                data['lastEventId'] == null) ||
        (lastMutationKind == AttendanceMutationKind.mark &&
            (data['lastMutationRosterEntryId'] == null ||
                data['lastEventId'] != null)) ||
        (lastMutationKind == AttendanceMutationKind.voidSession &&
            (data['lastMutationRosterEntryId'] != null ||
                data['lastEventId'] == null)) ||
        (lastMutationKind != null &&
            lastMutationKind != AttendanceMutationKind.mark &&
            lastMutationKind != AttendanceMutationKind.voidSession &&
            lastMutationKind != AttendanceMutationKind.restore &&
            (data['lastMutationRosterEntryId'] == null ||
                data['lastEventId'] == null))) {
      throw const FormatException('Invalid attendance mutation markers.');
    }
    return AttendanceSession(
      schemaVersion: 1,
      courseId: expectedCourseId,
      ownerUid: data['ownerUid'] as String,
      occurrenceId: expectedOccurrenceId,
      occurrenceKind: _occurrenceKind(_string(data, 'occurrenceKind')),
      mode: AttendanceMode.fromValue(_string(data, 'mode')),
      status: status,
      rosterState: _rosterState(_string(data, 'rosterState')),
      scheduledDate: _academicDate(data['scheduledDate']),
      effectiveDate: _academicDate(data['effectiveDate']),
      startMinute: _int(data, 'startMinute'),
      endMinute: _int(data, 'endMinute'),
      timezone: 'America/Bogota',
      segmentIds: List<String>.from(segmentIds),
      rosterCount: data['rosterCount'] as int,
      markedCount: data['markedCount'] as int,
      unmarkedCount: data['unmarkedCount'] as int,
      unmarkedConfirmed: confirmed,
      version: data['version'] as int,
      createdAt: _dateTime(data['createdAt']),
      createdBy: data['createdBy'] as String,
      updatedAt: _dateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String,
      unmarkedConfirmedAt: _dateTime(data['unmarkedConfirmedAt']),
      unmarkedConfirmedBy: data['unmarkedConfirmedBy'] as String?,
      lastMutationRosterEntryId: data['lastMutationRosterEntryId'] as String?,
      lastMutationKind: lastMutationKind,
      lastEventId: data['lastEventId'] as String?,
      finalizedAt: _dateTime(data['finalizedAt']),
      voidedAt: _dateTime(data['voidedAt']),
      reason: data['reason'] as String?,
      lateRegistrationReason: data['lateRegistrationReason'] as String?,
    );
  }

  static Map<String, Object?> newSession({
    required AttendanceOccurrence occurrence,
    required AttendanceMode mode,
    required String uid,
    required List<String> segmentIds,
    required int rosterCount,
    String? lateRegistrationReason,
  }) => {
    'schemaVersion': 1,
    'courseId': occurrence.courseId,
    'ownerUid': uid,
    'occurrenceId': occurrence.id,
    'occurrenceKind': occurrence.kind.value,
    'mode': mode.value,
    'status': AttendanceSessionStatus.preparing.value,
    'rosterState': AttendanceRosterState.building.value,
    'scheduledDate': Timestamp.fromDate(
      occurrence.scheduledDate.toUtcTimestamp(),
    ),
    'effectiveDate': Timestamp.fromDate(
      occurrence.effectiveDate.toUtcTimestamp(),
    ),
    'startMinute': occurrence.startMinute,
    'endMinute': occurrence.endMinute,
    'timezone': occurrence.timezone,
    'segmentIds': segmentIds,
    'rosterCount': rosterCount,
    'markedCount': 0,
    'unmarkedCount': rosterCount,
    'unmarkedConfirmed': false,
    'lastMutationRosterEntryId': null,
    'lastMutationKind': null,
    'lastEventId': null,
    'version': 1,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
    ...?lateRegistrationReason == null
        ? null
        : {'lateRegistrationReason': lateRegistrationReason},
  };

  static Map<String, Object?> segmentForCreate({
    required AttendanceSegment segment,
  }) => {
    'segmentId': segment.id,
    'order': segment.order,
    'startMinute': segment.startMinute,
    'endMinute': segment.endMinute,
    'durationMinutes': segment.durationMinutes,
    'createdAt': FieldValue.serverTimestamp(),
  };

  static AttendanceSegment segmentFromMap(
    Map<String, dynamic> data, {
    required String expectedId,
  }) {
    _requireExactFields(data, _segmentFields);
    if (data['segmentId'] != expectedId ||
        data['order'] is! int ||
        data['startMinute'] is! int ||
        data['endMinute'] is! int ||
        data['durationMinutes'] is! int) {
      throw const FormatException('Invalid attendance segment.');
    }
    return AttendanceSegment(
      id: expectedId,
      order: data['order'] as int,
      startMinute: data['startMinute'] as int,
      endMinute: data['endMinute'] as int,
      durationMinutes: data['durationMinutes'] as int,
      createdAt: _dateTime(data['createdAt']),
    );
  }

  static Map<String, Object?> rosterDocument({
    required AttendanceRosterEntry entry,
    required AttendanceMode mode,
    required String uid,
    bool includeUpdatedAt = true,
  }) {
    final data = <String, Object?>{
      'rosterEntryId': entry.rosterEntryId,
      'displayName': entry.displayName,
      'version': entry.version,
      'updatedBy': uid,
    };
    if (entry.studentUid != null) data['studentUid'] = entry.studentUid;
    if (mode == AttendanceMode.meeting) {
      data['meetingMark'] = entry.meetingMark!.mark.value;
      data['justificationStatus'] =
          entry.meetingMark!.justificationStatus.value;
      data['justifiedUnits'] = entry.meetingMark!.justifiedUnits;
    } else {
      data['segments'] = {
        for (final item in entry.segmentMarks.entries)
          item.key: _rosterMarkToMap(item.value),
      };
    }
    if (includeUpdatedAt) data['updatedAt'] = FieldValue.serverTimestamp();
    return data;
  }

  static AttendanceRosterEntry rosterEntryFromMap(
    Map<String, dynamic> data, {
    required String expectedRosterEntryId,
    required AttendanceMode mode,
  }) {
    final required = <String>{
      'rosterEntryId',
      'displayName',
      'version',
      'updatedAt',
      'updatedBy',
    };
    if (mode == AttendanceMode.meeting) {
      required.add('meetingMark');
    } else {
      required.add('segments');
    }
    final allowed = {
      ...required,
      'studentUid',
      if (mode == AttendanceMode.meeting) ...{
        'justificationStatus',
        'justifiedUnits',
      },
    };
    if (mode == AttendanceMode.meeting) {
      required.addAll({'justificationStatus', 'justifiedUnits'});
    }
    _requireExactFields(data, allowed, required: required);
    if (data['rosterEntryId'] != expectedRosterEntryId ||
        data['displayName'] is! String ||
        (data['displayName'] as String).trim().isEmpty ||
        data['version'] is! int ||
        (data['version'] as int) < 0 ||
        data['updatedBy'] is! String ||
        (data['studentUid'] != null && data['studentUid'] is! String)) {
      throw const FormatException('Invalid attendance roster entry.');
    }
    if (mode == AttendanceMode.meeting) {
      return AttendanceRosterEntry(
        rosterEntryId: expectedRosterEntryId,
        displayName: data['displayName'] as String,
        studentUid: data['studentUid'] as String?,
        meetingMark: AttendanceRosterMark(
          mark: _mark(_string(data, 'meetingMark')),
          absentUnits:
              _mark(_string(data, 'meetingMark')) == AttendanceMark.absent
              ? 1
              : 0,
          justificationStatus: _justificationStatus(
            _string(data, 'justificationStatus'),
          ),
          justifiedUnits: _int(data, 'justifiedUnits'),
        ),
        segmentMarks: const {},
        version: data['version'] as int,
        updatedAt: _dateTime(data['updatedAt']),
        updatedBy: data['updatedBy'] as String,
      );
    }
    final rawSegments = data['segments'];
    if (rawSegments is! Map) {
      throw const FormatException('Invalid attendance segment marks.');
    }
    final segments = <String, AttendanceRosterMark>{};
    for (final entry in rawSegments.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid attendance segment mark.');
      }
      segments[entry.key as String] = _rosterMarkFromMap(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    return AttendanceRosterEntry(
      rosterEntryId: expectedRosterEntryId,
      displayName: data['displayName'] as String,
      studentUid: data['studentUid'] as String?,
      meetingMark: null,
      segmentMarks: segments,
      version: data['version'] as int,
      updatedAt: _dateTime(data['updatedAt']),
      updatedBy: data['updatedBy'] as String,
    );
  }

  static Map<String, Object?> stagedRecord(AttendanceRecord record) => {
    'schemaVersion': record.schemaVersion,
    'courseId': record.courseId,
    'sessionId': record.sessionId,
    'rosterEntryId': record.rosterEntryId,
    'visibility': AttendanceRecordVisibility.staged.value,
    'mode': record.mode.value,
    'scheduledDate': Timestamp.fromDate(record.scheduledDate.toUtcTimestamp()),
    'effectiveDate': Timestamp.fromDate(record.effectiveDate.toUtcTimestamp()),
    'startMinute': record.startMinute,
    'endMinute': record.endMinute,
    'unitCount': record.unitCount,
    'absentUnits': record.absentUnits,
    'inReviewUnits': record.inReviewUnits,
    'justifiedUnits': record.justifiedUnits,
    'result': record.result.value,
    if (record.segments.isNotEmpty)
      'segments': record.segments
          .map(
            (segment) => {
              'segmentId': segment.segmentId,
              'startMinute': segment.startMinute,
              'endMinute': segment.endMinute,
              'durationMinutes': segment.durationMinutes,
              'mark': segment.mark.value,
              'absentUnits': segment.absentMinutes,
              'justificationStatus': segment.justificationStatus.value,
              'justifiedUnits': segment.justifiedMinutes,
            },
          )
          .toList(growable: false),
    'publishedAt': null,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Map<String, Object?> publishRecordUpdate() => {
    'visibility': AttendanceRecordVisibility.published.value,
    'publishedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Map<String, Object?> voidedPublishedRecord(AttendanceRecord record) {
    if (record.visibility != AttendanceRecordVisibility.published ||
        record.result != AttendanceSessionResult.voided ||
        record.unitCount != 0 ||
        record.absentUnits != 0 ||
        record.inReviewUnits != 0 ||
        record.justifiedUnits != 0 ||
        record.segments.isNotEmpty) {
      throw ArgumentError('Invalid voided attendance projection.');
    }
    return {
      ...stagedRecord(record),
      'visibility': AttendanceRecordVisibility.published.value,
      'publishedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Fields permitted to change when an immutable published result is
  /// corrected. Identity, schedule, mode and publication time stay fixed.
  static Map<String, Object?> auditedRecordUpdate(AttendanceRecord record) => {
    'absentUnits': record.absentUnits,
    'inReviewUnits': record.inReviewUnits,
    'justifiedUnits': record.justifiedUnits,
    'result': record.result.value,
    if (record.segments.isNotEmpty)
      'segments': record.segments
          .map(
            (segment) => {
              'segmentId': segment.segmentId,
              'startMinute': segment.startMinute,
              'endMinute': segment.endMinute,
              'durationMinutes': segment.durationMinutes,
              'mark': segment.mark.value,
              'absentUnits': segment.absentMinutes,
              'justificationStatus': segment.justificationStatus.value,
              'justifiedUnits': segment.justifiedMinutes,
            },
          )
          .toList(growable: false),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static AttendanceRecord recordFromMap(
    Map<String, dynamic> data, {
    required String expectedCourseId,
    required String expectedRecordId,
  }) {
    _requireExactFields(data, _recordFields, required: _recordRequiredFields);
    final sessionId = _string(data, 'sessionId');
    final rosterEntryId = _string(data, 'rosterEntryId');
    if (data['schemaVersion'] != 1 ||
        data['courseId'] != expectedCourseId ||
        data['sessionId'] is! String ||
        data['rosterEntryId'] is! String ||
        '$sessionId|$rosterEntryId' != expectedRecordId ||
        data['startMinute'] is! int ||
        data['endMinute'] is! int ||
        data['unitCount'] is! int ||
        data['absentUnits'] is! int ||
        data['inReviewUnits'] is! int ||
        data['justifiedUnits'] is! int) {
      throw const FormatException('Invalid attendance record.');
    }
    final rawSegments = data['segments'];
    final segments = <AttendanceRecordSegment>[];
    if (rawSegments != null) {
      if (rawSegments is! List) {
        throw const FormatException('Invalid attendance record segments.');
      }
      for (final raw in rawSegments) {
        if (raw is! Map) {
          throw const FormatException('Invalid attendance record segment.');
        }
        final segment = Map<String, dynamic>.from(raw);
        segments.add(
          AttendanceRecordSegment(
            segmentId: _string(segment, 'segmentId'),
            startMinute: _int(segment, 'startMinute'),
            endMinute: _int(segment, 'endMinute'),
            durationMinutes: _int(segment, 'durationMinutes'),
            mark: _mark(_string(segment, 'mark')),
            absentMinutes: _int(segment, 'absentUnits'),
            justificationStatus: _justificationStatus(
              _string(segment, 'justificationStatus'),
            ),
            justifiedMinutes: _int(segment, 'justifiedUnits'),
          ),
        );
      }
    }
    return AttendanceRecord(
      schemaVersion: 1,
      courseId: expectedCourseId,
      sessionId: sessionId,
      rosterEntryId: rosterEntryId,
      visibility: _recordVisibility(_string(data, 'visibility')),
      mode: AttendanceMode.fromValue(_string(data, 'mode')),
      scheduledDate: _academicDate(data['scheduledDate']),
      effectiveDate: _academicDate(data['effectiveDate']),
      startMinute: data['startMinute'] as int,
      endMinute: data['endMinute'] as int,
      unitCount: data['unitCount'] as int,
      absentUnits: data['absentUnits'] as int,
      inReviewUnits: data['inReviewUnits'] as int,
      justifiedUnits: data['justifiedUnits'] as int,
      result: _sessionResult(_string(data, 'result')),
      segments: segments,
      publishedAt: _dateTime(data['publishedAt']),
      updatedAt: _dateTime(data['updatedAt']),
    );
  }

  static Map<String, Object?> eventForCreate({
    required AttendanceSessionEvent event,
    required String uid,
  }) => {
    'kind': event.kind.value,
    if (event.rosterEntryId != null) 'rosterEntryId': event.rosterEntryId,
    'oldValue': event.oldValue,
    'newValue': event.newValue,
    'reason': event.reason,
    'changedAt': FieldValue.serverTimestamp(),
    'changedBy': uid,
  };

  static AttendanceSessionEvent eventFromMap(
    Map<String, dynamic> data, {
    required String expectedEventId,
  }) {
    _requireExactFields(
      data,
      _eventFields,
      required: _eventFields.difference({'rosterEntryId'}),
    );
    if (data['reason'] is! String ||
        data['changedBy'] is! String ||
        (data['rosterEntryId'] != null && data['rosterEntryId'] is! String) ||
        data['oldValue'] is! Map ||
        data['newValue'] is! Map) {
      throw const FormatException('Invalid attendance event.');
    }
    return AttendanceSessionEvent(
      eventId: expectedEventId,
      kind: AttendanceEventKind.fromValue(_string(data, 'kind')),
      rosterEntryId: data['rosterEntryId'] as String?,
      oldValue: Map<String, Object?>.from(data['oldValue'] as Map),
      newValue: Map<String, Object?>.from(data['newValue'] as Map),
      reason: data['reason'] as String,
      changedAt: _dateTime(data['changedAt']),
      changedBy: data['changedBy'] as String,
    );
  }

  static Map<String, Object?> _rosterMarkToMap(AttendanceRosterMark mark) => {
    'mark': mark.mark.value,
    'absentUnits': mark.absentUnits,
    'justificationStatus': mark.justificationStatus.value,
    'justifiedUnits': mark.justifiedUnits,
  };

  static AttendanceRosterMark _rosterMarkFromMap(Map<String, dynamic> data) {
    _requireExactFields(data, {
      'mark',
      'absentUnits',
      'justificationStatus',
      'justifiedUnits',
    });
    return AttendanceRosterMark(
      mark: _mark(_string(data, 'mark')),
      absentUnits: _int(data, 'absentUnits'),
      justificationStatus: _justificationStatus(
        _string(data, 'justificationStatus'),
      ),
      justifiedUnits: _int(data, 'justifiedUnits'),
    );
  }

  static AttendanceOccurrenceKind _occurrenceKind(String value) =>
      switch (value) {
        'planned' => AttendanceOccurrenceKind.planned,
        'cancelled' => AttendanceOccurrenceKind.cancelled,
        'rescheduled' => AttendanceOccurrenceKind.rescheduled,
        'additional' => AttendanceOccurrenceKind.additional,
        _ => throw FormatException('Unsupported occurrence kind: $value'),
      };

  static AttendanceSessionStatus _sessionStatus(String value) =>
      switch (value) {
        'preparing' => AttendanceSessionStatus.preparing,
        'inProgress' => AttendanceSessionStatus.inProgress,
        'closing' => AttendanceSessionStatus.closing,
        'finalized' => AttendanceSessionStatus.finalized,
        'voiding' => AttendanceSessionStatus.voiding,
        'restoring' => AttendanceSessionStatus.restoring,
        'voided' => AttendanceSessionStatus.voided,
        _ => throw FormatException('Unsupported session status: $value'),
      };

  static AttendanceMutationKind _mutationKind(String value) => switch (value) {
    'mark' => AttendanceMutationKind.mark,
    'correction' => AttendanceMutationKind.correction,
    'justification' => AttendanceMutationKind.justification,
    'rosterCorrection' => AttendanceMutationKind.rosterCorrection,
    'void' => AttendanceMutationKind.voidSession,
    'restore' => AttendanceMutationKind.restore,
    _ => throw FormatException('Unsupported attendance mutation: $value'),
  };

  static AttendanceRosterState _rosterState(String value) => switch (value) {
    'building' => AttendanceRosterState.building,
    'ready' => AttendanceRosterState.ready,
    _ => throw FormatException('Unsupported roster state: $value'),
  };

  static AttendanceMark _mark(String value) => switch (value) {
    'unmarked' => AttendanceMark.unmarked,
    'present' => AttendanceMark.present,
    'absent' => AttendanceMark.absent,
    _ => throw FormatException('Unsupported attendance mark: $value'),
  };

  static AttendanceJustificationStatus _justificationStatus(String value) =>
      switch (value) {
        'none' => AttendanceJustificationStatus.none,
        'inReview' => AttendanceJustificationStatus.inReview,
        'justified' => AttendanceJustificationStatus.justified,
        'notAccepted' => AttendanceJustificationStatus.notAccepted,
        _ => throw FormatException('Unsupported justification status: $value'),
      };

  static AttendanceSessionResult _sessionResult(String value) =>
      switch (value) {
        'unmarked' => AttendanceSessionResult.unmarked,
        'voided' => AttendanceSessionResult.voided,
        'present' => AttendanceSessionResult.present,
        'absent' => AttendanceSessionResult.absent,
        'partial' => AttendanceSessionResult.partial,
        'justified' => AttendanceSessionResult.justified,
        _ => throw FormatException('Unsupported attendance result: $value'),
      };

  static AttendanceRecordVisibility _recordVisibility(String value) =>
      switch (value) {
        'staged' => AttendanceRecordVisibility.staged,
        'published' => AttendanceRecordVisibility.published,
        _ => throw FormatException('Unsupported record visibility: $value'),
      };

  static AcademicDate _academicDate(Object? value) {
    if (value is! Timestamp) {
      throw const FormatException('An academic date must be a timestamp.');
    }
    return AcademicDate.fromUtcTimestamp(value.toDate().toUtc());
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    if (value is! Timestamp) {
      throw const FormatException('An audit time must be a timestamp.');
    }
    return value.toDate();
  }

  static String _string(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  static int _int(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! int) throw FormatException('$key must be an integer.');
    return value;
  }

  static void _requireExactFields(
    Map<String, dynamic> data,
    Set<String> allowed, {
    Set<String>? required,
  }) {
    final requiredFields = required ?? allowed;
    if (!data.keys.toSet().containsAll(requiredFields) ||
        data.keys.toSet().difference(allowed).isNotEmpty) {
      throw const FormatException('Unexpected attendance document fields.');
    }
  }
}
