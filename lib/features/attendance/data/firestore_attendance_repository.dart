import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../courses/domain/course.dart';
import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/enrollment_failure.dart';
import '../../enrollments/domain/enrollment_repository.dart';
import '../../enrollments/domain/enrollment_status_change.dart';
import '../../enrollments/domain/pending_enrollment.dart';
import '../../enrollments/domain/pending_enrollment_page.dart';
import '../../schedule/domain/academic_date.dart';
import '../application/attendance_record_calculator.dart';
import '../application/attendance_roster_resolver.dart';
import '../application/attendance_segment_factory.dart';
import '../application/attendance_validator.dart';
import '../domain/attendance_calendar_change.dart';
import '../domain/attendance_justification_request.dart';
import '../domain/attendance_config.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_mode.dart';
import '../domain/attendance_occurrence.dart';
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import '../domain/attendance_roster.dart';
import '../domain/attendance_segment.dart';
import '../domain/attendance_session.dart';
import '../domain/attendance_session_event.dart';
import 'attendance_firestore_codec.dart';
import 'attendance_operation_trace.dart';

/// Firestore adapter for manual attendance.
///
/// UIDs always come from Firebase Auth. Roster membership is built from the
/// complete C7 snapshot and all C7 status-event pages; a read or history error
/// prevents the session from becoming ready.
class FirestoreAttendanceRepository implements AttendanceRepository {
  FirestoreAttendanceRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.onTiming,
    required this._enrollments,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _pageSize = 100;
  static const int _writeChunkSize = 10;
  static const int _parallelReads = 6;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final EnrollmentRepository _enrollments;
  final AttendanceTiming? onTiming;

  // Only independent reads share a window. Pages and validation barriers
  // remain ordered, and a failed read prevents the roster from becoming ready.
  Future<void> _readInParallel<T>(
    Iterable<T> values,
    Future<void> Function(T) read,
  ) async {
    final items = values.toList(growable: false);
    for (var offset = 0; offset < items.length; offset += _parallelReads) {
      await Future.wait(items.skip(offset).take(_parallelReads).map(read));
    }
  }

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  DocumentReference<Map<String, dynamic>> _course(String courseId) =>
      _courses.doc(courseId);

  DocumentReference<Map<String, dynamic>> _config(String courseId) =>
      _course(courseId).collection('attendance_config').doc('current');

  CollectionReference<Map<String, dynamic>> _calendar(String courseId) =>
      _course(courseId).collection('attendance_calendar');

  CollectionReference<Map<String, dynamic>> _sessions(String courseId) =>
      _course(courseId).collection('attendance_sessions');

  DocumentReference<Map<String, dynamic>> _session(
    String courseId,
    String occurrenceId,
  ) => _sessions(courseId).doc(occurrenceId);

  CollectionReference<Map<String, dynamic>> _roster(
    String courseId,
    String occurrenceId,
  ) => _session(courseId, occurrenceId).collection('roster');

  CollectionReference<Map<String, dynamic>> _segments(
    String courseId,
    String occurrenceId,
  ) => _session(courseId, occurrenceId).collection('segments');

  CollectionReference<Map<String, dynamic>> _events(
    String courseId,
    String occurrenceId,
  ) => _session(courseId, occurrenceId).collection('events');

  CollectionReference<Map<String, dynamic>> _records(String courseId) =>
      _course(courseId).collection('attendance_records');

  @override
  Future<AttendanceConfig?> getConfig({required String courseId}) async {
    try {
      _validateId(courseId);
      final actor = await _requireTeacher();
      await _requireOwnedCourse(courseId, actor.uid);
      final snapshot = await _config(courseId)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) throw const FormatException('Missing config data.');
      return AttendanceFirestoreCodec.configFromMap(data);
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw AttendanceFailure(
        AttendanceFailureKind.invalidData,
        message: 'La configuración de asistencia no tiene un formato válido.',
      );
    }
  }

  @override
  Future<AttendanceConfig> setMode({
    required Course course,
    required AttendanceMode mode,
  }) async {
    try {
      _validateId(course.id);
      final actor = await _requireTeacher();
      if (course.ownerUid != actor.uid) {
        throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
      }
      final courseRef = _course(course.id);
      final configRef = _config(course.id);
      final result = await _firestore.runTransaction((transaction) async {
        final courseSnapshot = await transaction.get(courseRef);
        final configSnapshot = await transaction.get(configRef);
        _requireSameUser(actor.uid);
        _verifyCourseOwnerSnapshot(courseSnapshot, actor.uid);

        final current = configSnapshot.exists
            ? AttendanceFirestoreCodec.configFromMap(
                configSnapshot.data() ??
                    (throw const FormatException('Missing config data.')),
              )
            : null;
        AttendanceValidator.validateModeChange(
          current: current,
          nextMode: mode,
        );
        if (current != null) {
          if (current.mode == mode || current.sessionCount > 0) return current;
          transaction.update(
            configRef,
            AttendanceFirestoreCodec.updateConfig(mode: mode, uid: actor.uid),
          );
        } else {
          transaction.set(
            configRef,
            AttendanceFirestoreCodec.newConfig(mode: mode, uid: actor.uid),
          );
        }
        return AttendanceConfig(
          mode: mode,
          sessionCount: current?.sessionCount ?? 0,
          lastSessionId: current?.lastSessionId,
          createdAt: current?.createdAt,
          createdBy: current?.createdBy ?? actor.uid,
          updatedAt: null,
          updatedBy: actor.uid,
        );
      });
      _requireSameUser(actor.uid);
      return result;
    } on AttendanceFailure {
      rethrow;
    } on AttendanceValidationFailure catch (error) {
      throw AttendanceFailure(
        error.issue == AttendanceValidationIssue.modeAlreadyLocked
            ? AttendanceFailureKind.invalidTransition
            : AttendanceFailureKind.invalidInput,
        message:
            'La modalidad de asistencia no se puede cambiar en este estado.',
      );
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  Map<String, Object?> _publicCalendarData(Map<String, dynamic> source) => {
    for (final key in const [
      'occurrenceId',
      'kind',
      'originalDate',
      'effectiveDate',
      'startMinute',
      'endMinute',
      'version',
    ])
      key: source[key],
  };

  @override
  Future<List<AttendanceCalendarChange>> listCalendarChanges({
    required String courseId,
    bool forStudent = false,
  }) async {
    try {
      _validateId(courseId);
      final actor = forStudent
          ? await _requireStudent()
          : await _requireTeacher();
      if (!forStudent) await _requireOwnedCourse(courseId, actor.uid);
      final collection = forStudent
          ? _course(courseId).collection('student_calendar')
          : _calendar(courseId);
      final items = <AttendanceCalendarChange>[];
      Query<Map<String, dynamic>> query = collection
          .orderBy('effectiveDate')
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);
      while (true) {
        final page = await query.get(const GetOptions(source: Source.server));
        _requireSameUser(actor.uid);
        for (final document in page.docs) {
          items.add(
            AttendanceFirestoreCodec.calendarChangeFromMap(
              forStudent
                  ? {
                      ...document.data(),
                      'reason': '',
                      'createdAt': null,
                      'createdBy': '',
                      'updatedAt': null,
                      'updatedBy': '',
                    }
                  : document.data(),
              expectedOccurrenceId: document.id,
            ),
          );
        }
        if (page.docs.length < _pageSize) break;
        final last = page.docs.last;
        query = collection
            .orderBy('effectiveDate')
            .orderBy(FieldPath.documentId)
            .startAfter([last.data()['effectiveDate'], last.id])
            .limit(_pageSize);
      }
      if (!forStudent) {
        // Repair projections of pre-existing exceptions using the current
        // private source in each transaction, never a stale local snapshot.
        for (final item in items) {
          await _firestore.runTransaction((tx) async {
            final source = await tx.get(
              _calendar(courseId).doc(item.occurrenceId),
            );
            if (source.exists) {
              tx.set(
                _course(courseId)
                    .collection('student_calendar')
                    .doc(item.occurrenceId),
                _publicCalendarData(source.data()!),
              );
            }
          });
        }
      }
      return List.unmodifiable(items);
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceCalendarChange> saveCalendarChange({
    required Course course,
    required AttendanceCalendarChange change,
  }) async {
    try {
      _validateId(course.id);
      _validateId(change.occurrenceId);
      final actor = await _requireTeacher();
      if (course.ownerUid != actor.uid || change.occurrenceId.contains('/')) {
        throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
      }
      AttendanceValidator.validateCalendarChange(change);
      final calendarRef = _calendar(course.id).doc(change.occurrenceId);
      final courseRef = _course(course.id);
      final result = await _firestore.runTransaction((transaction) async {
        final courseSnapshot = await transaction.get(courseRef);
        final currentSnapshot = await transaction.get(calendarRef);
        _requireSameUser(actor.uid);
        _verifyCourseOwnerSnapshot(courseSnapshot, actor.uid);
        final previous = currentSnapshot.data();
        final nextVersion = currentSnapshot.exists
            ? (previous!['version'] as int) + 1
            : 1;
        transaction.set(calendarRef.collection('events').doc('$nextVersion'), {
          'oldValue': previous == null
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(previous),
          'newValue': previous == null
              ? AttendanceFirestoreCodec.calendarChangeForCreate(
                  change: change,
                  uid: actor.uid,
                )
              : {
                  ...previous,
                  ...AttendanceFirestoreCodec.calendarChangeForUpdate(
                    change: change,
                    uid: actor.uid,
                  ),
                },
          'changedAt': FieldValue.serverTimestamp(),
          'changedBy': actor.uid,
        });
        if (currentSnapshot.exists) {
          final current = AttendanceFirestoreCodec.calendarChangeFromMap(
            currentSnapshot.data() ??
                (throw const FormatException('Missing calendar change data.')),
            expectedOccurrenceId: change.occurrenceId,
          );
          if (change.version != current.version) {
            throw const AttendanceFailure(AttendanceFailureKind.staleSession);
          }
          final next = AttendanceCalendarChange(
            occurrenceId: change.occurrenceId,
            kind: change.kind,
            originalDate: change.originalDate,
            effectiveDate: change.effectiveDate,
            startMinute: change.startMinute,
            endMinute: change.endMinute,
            reason: change.reason.trim(),
            version: current.version + 1,
            createdAt: current.createdAt,
            createdBy: current.createdBy,
            updatedBy: actor.uid,
          );
          transaction.update(
            calendarRef,
            AttendanceFirestoreCodec.calendarChangeForUpdate(
              change: change,
              uid: actor.uid,
            ),
          );
          transaction.set(
            _course(course.id)
                .collection('student_calendar')
                .doc(change.occurrenceId),
            _publicCalendarData({
              ...AttendanceFirestoreCodec.calendarChangeForCreate(
                change: next,
                uid: actor.uid,
              ),
              'version': next.version,
            }),
          );
          return next;
        }
        if (change.version != 0 && change.version != 1) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        final next = AttendanceCalendarChange(
          occurrenceId: change.occurrenceId,
          kind: change.kind,
          originalDate: change.originalDate,
          effectiveDate: change.effectiveDate,
          startMinute: change.startMinute,
          endMinute: change.endMinute,
          reason: change.reason.trim(),
          version: 1,
          createdBy: actor.uid,
          updatedBy: actor.uid,
        );
        transaction.set(
          calendarRef,
          AttendanceFirestoreCodec.calendarChangeForCreate(
            change: next,
            uid: actor.uid,
          ),
        );
        transaction.set(
          _course(course.id)
              .collection('student_calendar')
              .doc(change.occurrenceId),
          _publicCalendarData({
            ...AttendanceFirestoreCodec.calendarChangeForCreate(
              change: next,
              uid: actor.uid,
            ),
            'version': next.version,
          }),
        );
        return next;
      });
      _requireSameUser(actor.uid);
      return result;
    } on AttendanceFailure {
      rethrow;
    } on AttendanceValidationFailure {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<List<AttendanceSession>> listSessions({
    required String courseId,
    required AcademicDate from,
    required AcademicDate to,
  }) async {
    try {
      _validateId(courseId);
      if (from.compareTo(to) > 0) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      final actor = await _requireTeacher();
      await _requireOwnedCourse(courseId, actor.uid);
      final fromTimestamp = Timestamp.fromDate(from.toUtcTimestamp());
      final toTimestamp = Timestamp.fromDate(to.toUtcTimestamp());
      final items = <AttendanceSession>[];
      Query<Map<String, dynamic>> query = _sessions(courseId)
          .where('scheduledDate', isGreaterThanOrEqualTo: fromTimestamp)
          .where('scheduledDate', isLessThanOrEqualTo: toTimestamp)
          .orderBy('scheduledDate')
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);
      while (true) {
        final page = await query.get(const GetOptions(source: Source.server));
        _requireSameUser(actor.uid);
        for (final document in page.docs) {
          items.add(
            AttendanceFirestoreCodec.sessionFromMap(
              document.data(),
              expectedCourseId: courseId,
              expectedOccurrenceId: document.id,
            ),
          );
        }
        if (page.docs.length < _pageSize) break;
        final last = page.docs.last;
        query = _sessions(courseId)
            .where('scheduledDate', isGreaterThanOrEqualTo: fromTimestamp)
            .where('scheduledDate', isLessThanOrEqualTo: toTimestamp)
            .orderBy('scheduledDate')
            .orderBy(FieldPath.documentId)
            .startAfter([last.data()['scheduledDate'], last.id])
            .limit(_pageSize);
      }
      return List.unmodifiable(items);
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceSession?> getSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      final actor = await _requireTeacher();
      await _requireOwnedCourse(courseId, actor.uid);
      final snapshot = await _session(
        courseId,
        occurrenceId,
      ).get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      if (!snapshot.exists) return null;
      return AttendanceFirestoreCodec.sessionFromMap(
        snapshot.data() ??
            (throw const FormatException('Missing attendance session data.')),
        expectedCourseId: courseId,
        expectedOccurrenceId: occurrenceId,
      );
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceSession> prepareSession({
    required Course course,
    required AttendanceOccurrence occurrence,
    String? lateRegistrationReason,
  }) async {
    final trace = AttendanceOperationTrace('preparar lista', onTiming: onTiming)
      ..start('comprobar la cuenta docente');
    try {
      _validateId(course.id);
      _validateId(occurrence.id);
      AttendanceValidator.validateCanPrepare(occurrence);
      final actor = await _requireTeacher();
      if (course.ownerUid != actor.uid || occurrence.courseId != course.id) {
        throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
      }
      final reason = lateRegistrationReason?.trim();
      final courseRef = _course(course.id);
      final configRef = _config(course.id);
      final sessionRef = _session(course.id, occurrence.id);
      final calendarRef = _calendar(course.id).doc(occurrence.id);

      trace.start('leer el borrador');
      final existing = await sessionRef.get(
        const GetOptions(source: Source.server),
      );
      _requireSameUser(actor.uid);
      AttendanceSession? previousPreparation;
      if (existing.exists) {
        final current = AttendanceFirestoreCodec.sessionFromMap(
          existing.data() ??
              (throw const FormatException('Missing attendance session data.')),
          expectedCourseId: course.id,
          expectedOccurrenceId: occurrence.id,
        );
        if (!_sameOccurrence(current, occurrence)) {
          throw const AttendanceFailure(AttendanceFailureKind.conflict);
        }
        if (current.status != AttendanceSessionStatus.preparing ||
            current.rosterState == AttendanceRosterState.ready) {
          return current;
        }
        previousPreparation = current;
      }
      if (AttendanceValidator.needsLateRegistrationReason(
        occurrence,
        nowUtc: DateTime.now().toUtc(),
        preparedAt: previousPreparation?.createdAt,
        storedReason: previousPreparation?.lateRegistrationReason,
      )) {
        _validateLateReason(occurrence, reason);
      }

      trace.start('leer la modalidad');
      final configSnapshot = await configRef.get(
        const GetOptions(source: Source.server),
      );
      _requireSameUser(actor.uid);
      if (!configSnapshot.exists) {
        throw const AttendanceFailure(
          AttendanceFailureKind.invalidTransition,
          message: 'El curso requiere elegir una modalidad de asistencia.',
        );
      }
      final config = AttendanceFirestoreCodec.configFromMap(
        configSnapshot.data() ??
            (throw const FormatException('Missing attendance config data.')),
      );
      trace.start('leer matrículas e historial');
      final source = await _loadRosterInputs(course.id, actor.uid);
      final resolution = AttendanceRosterResolver.resolveForDate(
        snapshot: source.snapshot,
        enrollmentEventsByStudentUid: source.enrollmentEventsByStudentUid,
        pendingEventsByEmail: source.pendingEventsByEmail,
        linkedAuthorizationsByStudentUid:
            source.linkedAuthorizationsByStudentUid,
        effectiveDate: occurrence.effectiveDate,
      );
      if (!resolution.canPrepareSession) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
          message: 'El historial de matrícula contiene identidades que requieren revisión.',
        );
      }
      final segments = config.mode == AttendanceMode.minutes
          ? AttendanceSegmentFactory.forOccurrence(occurrence)
          : const <AttendanceSegment>[];
      final entries = <AttendanceRosterEntry>[
        for (final identity in resolution.entries)
          AttendanceRosterEntry.unmarkedForMode(
            rosterEntryId: identity.rosterEntryId,
            displayName: identity.displayName,
            studentUid: identity.studentUid,
            mode: config.mode,
            segments: segments,
          ),
      ];

      trace.start('crear la sesión y actualizar el contador');
      final committed = await _firestore.runTransaction((transaction) async {
        final courseSnapshot = await transaction.get(courseRef);
        final currentConfigSnapshot = await transaction.get(configRef);
        final calendarSnapshot = await transaction.get(calendarRef);
        final currentSessionSnapshot = await transaction.get(sessionRef);
        _requireSameUser(actor.uid);
        _verifyCourseOwnerSnapshot(courseSnapshot, actor.uid);
        final currentConfig = currentConfigSnapshot.exists
            ? AttendanceFirestoreCodec.configFromMap(
                currentConfigSnapshot.data() ??
                    (throw const FormatException('Missing config data.')),
              )
            : null;
        if (currentConfig == null || currentConfig.mode != config.mode) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        _verifyOccurrenceStillCurrent(
          occurrence,
          calendarSnapshot: calendarSnapshot,
        );
        if (currentSessionSnapshot.exists) {
          final current = AttendanceFirestoreCodec.sessionFromMap(
            currentSessionSnapshot.data() ??
                (throw const FormatException('Missing session data.')),
            expectedCourseId: course.id,
            expectedOccurrenceId: occurrence.id,
          );
          if (!_sameOccurrence(current, occurrence) ||
              current.mode != config.mode) {
            throw const AttendanceFailure(AttendanceFailureKind.conflict);
          }
          if (current.status == AttendanceSessionStatus.preparing &&
              current.rosterState == AttendanceRosterState.building &&
              current.lateRegistrationReason == null &&
              reason != null) {
            _validateLateReason(occurrence, reason);
            transaction.update(sessionRef, {
              'lateRegistrationReason': reason,
              ..._versionUpdate(actor.uid, current.version),
            });
            return _copySession(
              current,
              version: current.version + 1,
              updatedBy: actor.uid,
              lateRegistrationReason: reason,
            );
          }
          return current;
        }
        final sessionData = AttendanceFirestoreCodec.newSession(
          occurrence: occurrence,
          mode: config.mode,
          uid: actor.uid,
          segmentIds: segments.map((segment) => segment.id).toList(),
          rosterCount: entries.length,
          lateRegistrationReason: reason,
        );
        transaction.set(sessionRef, sessionData);
        transaction.update(
          configRef,
          AttendanceFirestoreCodec.incrementConfigForSession(
            sessionCount: currentConfig.sessionCount,
            occurrenceId: occurrence.id,
            uid: actor.uid,
          ),
        );
        return AttendanceFirestoreCodec.sessionFromMap(
          _resolveServerSentinelsForImmediateResult(sessionData),
          expectedCourseId: course.id,
          expectedOccurrenceId: occurrence.id,
        );
      });
      _requireSameUser(actor.uid);
      if (committed.status != AttendanceSessionStatus.preparing ||
          committed.rosterState == AttendanceRosterState.ready) {
        return committed;
      }

      trace.start('guardar los tramos');
      await _materializeSegments(
        session: committed,
        expectedSegments: segments,
        uid: actor.uid,
      );
      trace.start('guardar la nómina');
      await _reconcileRoster(
        session: committed,
        expectedEntries: entries,
        uid: actor.uid,
      );
      trace.start('comprobar que la matrícula no cambió');
      await _verifyRosterSourceUnchanged(course.id, actor.uid, source);
      trace.start('confirmar la nómina preparada');
      final ready = await _markRosterReady(
        courseId: course.id,
        occurrenceId: occurrence.id,
        expectedEntryIds: entries.map((entry) => entry.rosterEntryId).toSet(),
        expectedSegmentIds: segments.map((segment) => segment.id).toSet(),
        uid: actor.uid,
      );
      return ready;
    } on AttendanceFailure {
      rethrow;
    } on AttendanceRosterResolutionFailure {
      throw const AttendanceFailure(
        AttendanceFailureKind.rosterHistoryNeedsReview,
        message: 'No se pudo reconstruir la pertenencia histórica del curso.',
      );
    } on AttendanceValidationFailure {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    } on EnrollmentFailure catch (error) {
      final failure = _translateEnrollmentFailure(error);
      throw AttendanceFailure(
        failure.kind,
        message:
            'No se pudo ${trace.phase} (${failure.kind.name}). Reintenta; el borrador confirmado se conserva.',
      );
    } on FirebaseException catch (error) {
      final failure = _translateFirebase(error);
      throw AttendanceFailure(
        failure.kind,
        message:
            'No se pudo ${trace.phase} (${error.code}). Puedes reintentar la misma clase.',
      );
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    } on ArgumentError {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    } finally {
      trace.finish();
    }
  }

  Future<_RosterBuildInput> _loadRosterInputs(
    String courseId,
    String uid,
  ) async {
    final snapshot = await _enrollments.loadCourseRosterSnapshot(
      courseId: courseId,
    );
    _requireSameUser(uid);
    if (!snapshot.complete) {
      throw const AttendanceFailure(
        AttendanceFailureKind.incompleteRoster,
        message: 'No se cargó toda la nómina del curso.',
      );
    }
    final enrollmentRows = <Enrollment>[
      ...snapshot.activeEnrollments,
      ...snapshot.withdrawnEnrollments,
    ];
    final pendingRows = <PendingEnrollment>[
      ...snapshot.pendingEnrollments,
      ...snapshot.withdrawnPendingEnrollments,
    ];
    for (final row in enrollmentRows) {
      if (row.courseId != courseId || row.ownerUid != uid) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
        );
      }
    }
    for (final row in pendingRows) {
      if (row.courseId != courseId || row.ownerUid != uid) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
        );
      }
    }

    final enrollmentEvents = <String, List<EnrollmentStatusEvent>>{};
    await _readInParallel(enrollmentRows, (row) async {
      enrollmentEvents[row.studentUid] = await _allEnrollmentEvents(
        courseId: courseId,
        studentUid: row.studentUid,
        uid: uid,
      );
    });

    final linkedByUid = <String, PendingEnrollment>{};
    final pendingEvents = <String, List<PendingEnrollmentStatusEvent>>{};
    final pendingEmails = <String>{};
    for (final row in pendingRows) {
      if (!pendingEmails.add(row.email)) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
          message: 'La nómina contiene una identidad de correo duplicada.',
        );
      }
    }
    await _readInParallel(pendingRows, (row) async {
      pendingEvents[row.email] = await _allPendingEvents(
        courseId: courseId,
        email: row.email,
        uid: uid,
      );
    });

    await _readInParallel(enrollmentRows, (enrollment) async {
      final linked = await _enrollments.getCoursePendingEnrollment(
        courseId: courseId,
        email: enrollment.email,
      );
      _requireSameUser(uid);
      if (linked == null || linked.status != 'linked') return;
      if (linked.courseId != courseId ||
          linked.ownerUid != uid ||
          linked.email != enrollment.email ||
          linked.studentUid != enrollment.studentUid ||
          linked.studentCode != enrollment.studentCode) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
          message: 'Una vinculación histórica no coincide con la matrícula canónica.',
        );
      }
      final canonicalRosterId =
          enrollment.rosterEntryId == null ||
              enrollment.rosterEntryId!.isEmpty ||
              enrollment.rosterEntryId!.startsWith('legacy:')
          ? 'legacy:${enrollment.studentUid}'
          : enrollment.rosterEntryId!;
      if (linked.rosterEntryId != enrollment.email ||
          (canonicalRosterId != 'legacy:${enrollment.studentUid}' &&
              canonicalRosterId != linked.rosterEntryId)) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
        );
      }
      if (linkedByUid.containsKey(enrollment.studentUid)) {
        throw const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
        );
      }
      linkedByUid[enrollment.studentUid] = linked;
      // Reuse history already loaded for this exact authorization in this
      // operation. No cache survives a preparation/retry or revalidation.
      pendingEvents[linked.email] ??= await _allPendingEvents(
        courseId: courseId,
        email: linked.email,
        uid: uid,
      );
    });

    final latestSnapshot = await _enrollments.loadCourseRosterSnapshot(
      courseId: courseId,
    );
    _requireSameUser(uid);
    if (!latestSnapshot.complete ||
        _rosterFingerprint(snapshot) != _rosterFingerprint(latestSnapshot)) {
      throw const AttendanceFailure(
        AttendanceFailureKind.staleSession,
        message: 'La nómina cambió mientras se preparaba la sesión.',
      );
    }
    await _readInParallel(enrollmentRows, (enrollment) async {
      final latestLinked = await _enrollments.getCoursePendingEnrollment(
        courseId: courseId,
        email: enrollment.email,
      );
      _requireSameUser(uid);
      if (!_sameLinkedAuthorization(
        linkedByUid[enrollment.studentUid],
        latestLinked?.status == 'linked' ? latestLinked : null,
      )) {
        throw const AttendanceFailure(
          AttendanceFailureKind.staleSession,
          message: 'La vinculación cambió mientras se preparaba la sesión.',
        );
      }
    });

    return _RosterBuildInput(
      snapshot: snapshot,
      enrollmentEventsByStudentUid: enrollmentEvents,
      pendingEventsByEmail: pendingEvents,
      linkedAuthorizationsByStudentUid: linkedByUid,
    );
  }

  Future<List<EnrollmentStatusEvent>> _allEnrollmentEvents({
    required String courseId,
    required String studentUid,
    required String uid,
  }) async {
    final events = <EnrollmentStatusEvent>[];
    EnrollmentHistoryCursor? cursor;
    do {
      final page = await _enrollments.listEnrollmentHistory(
        courseId: courseId,
        studentUid: studentUid,
        cursor: cursor,
        pageSize: _pageSize,
      );
      _requireSameUser(uid);
      events.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(events);
  }

  Future<List<PendingEnrollmentStatusEvent>> _allPendingEvents({
    required String courseId,
    required String email,
    required String uid,
  }) async {
    final events = <PendingEnrollmentStatusEvent>[];
    PendingEnrollmentHistoryCursor? cursor;
    do {
      final page = await _enrollments.listPendingEnrollmentHistory(
        courseId: courseId,
        email: email,
        cursor: cursor,
        pageSize: _pageSize,
      );
      _requireSameUser(uid);
      events.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(events);
  }

  Future<void> _materializeSegments({
    required AttendanceSession session,
    required List<AttendanceSegment> expectedSegments,
    required String uid,
  }) async {
    for (
      var offset = 0;
      offset < expectedSegments.length;
      offset += _writeChunkSize
    ) {
      final chunk = expectedSegments
          .skip(offset)
          .take(_writeChunkSize)
          .toList(growable: false);
      final sessionRef = _session(session.courseId, session.occurrenceId);
      final references = [
        for (final segment in chunk)
          _segments(session.courseId, session.occurrenceId).doc(segment.id),
      ];
      await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final segmentSnapshots = await Future.wait(
          references.map(transaction.get),
        );
        _requireSameUser(uid);
        final current = AttendanceFirestoreCodec.sessionFromMap(
          sessionSnapshot.data() ??
              (throw const FormatException('Missing attendance session.')),
          expectedCourseId: session.courseId,
          expectedOccurrenceId: session.occurrenceId,
        );
        if (current.status != AttendanceSessionStatus.preparing ||
            current.rosterState != AttendanceRosterState.building) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        var didWrite = false;
        for (var index = 0; index < chunk.length; index++) {
          final expected = chunk[index];
          final snapshot = segmentSnapshots[index];
          if (snapshot.exists) {
            final existing = AttendanceFirestoreCodec.segmentFromMap(
              snapshot.data() ??
                  (throw const FormatException('Missing segment data.')),
              expectedId: expected.id,
            );
            if (!_sameSegment(existing, expected)) {
              throw const AttendanceFailure(AttendanceFailureKind.conflict);
            }
            continue;
          }
          transaction.set(
            references[index],
            AttendanceFirestoreCodec.segmentForCreate(segment: expected),
          );
          didWrite = true;
        }
        if (didWrite) {
          transaction.update(sessionRef, _versionUpdate(uid, current.version));
        }
      });
      _requireSameUser(uid);
    }
  }

  Future<void> _reconcileRoster({
    required AttendanceSession session,
    required List<AttendanceRosterEntry> expectedEntries,
    required String uid,
  }) async {
    final expectedById = {
      for (final entry in expectedEntries) entry.rosterEntryId: entry,
    };
    if (expectedById.length != expectedEntries.length) {
      throw const AttendanceFailure(
        AttendanceFailureKind.rosterHistoryNeedsReview,
      );
    }

    for (
      var offset = 0;
      offset < expectedEntries.length;
      offset += _writeChunkSize
    ) {
      final chunk = expectedEntries
          .skip(offset)
          .take(_writeChunkSize)
          .toList(growable: false);
      final sessionRef = _session(session.courseId, session.occurrenceId);
      final references = [
        for (final entry in chunk)
          _roster(
            session.courseId,
            session.occurrenceId,
          ).doc(entry.rosterEntryId),
      ];
      await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshots = await Future.wait(references.map(transaction.get));
        _requireSameUser(uid);
        final current = AttendanceFirestoreCodec.sessionFromMap(
          sessionSnapshot.data() ??
              (throw const FormatException('Missing attendance session.')),
          expectedCourseId: session.courseId,
          expectedOccurrenceId: session.occurrenceId,
        );
        if (current.status != AttendanceSessionStatus.preparing ||
            current.rosterState != AttendanceRosterState.building) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        var didWrite = false;
        for (var index = 0; index < chunk.length; index++) {
          final expected = chunk[index];
          final snapshot = rowSnapshots[index];
          final reference = references[index];
          if (snapshot.exists) {
            final existing = AttendanceFirestoreCodec.rosterEntryFromMap(
              snapshot.data() ??
                  (throw const FormatException('Missing roster data.')),
              expectedRosterEntryId: expected.rosterEntryId,
              mode: current.mode,
            );
            if (!_isUnmarked(existing, current.mode)) {
              throw const AttendanceFailure(AttendanceFailureKind.conflict);
            }
            if (!_sameRosterIdentity(existing, expected)) {
              final replacement = _entryWithVersion(
                expected,
                existing.version + 1,
                updatedBy: uid,
              );
              transaction.update(
                reference,
                AttendanceFirestoreCodec.rosterDocument(
                  entry: replacement,
                  mode: current.mode,
                  uid: uid,
                ),
              );
              didWrite = true;
            }
            continue;
          }
          transaction.set(
            reference,
            AttendanceFirestoreCodec.rosterDocument(
              entry: expected,
              mode: current.mode,
              uid: uid,
            ),
          );
          didWrite = true;
        }
        if (didWrite) {
          transaction.update(sessionRef, _versionUpdate(uid, current.version));
        }
      });
      _requireSameUser(uid);
    }

    final currentRows = await _loadAllRoster(session, uid);
    final staleIds = currentRows
        .map((entry) => entry.rosterEntryId)
        .where((id) => !expectedById.containsKey(id))
        .toList(growable: false);
    for (var offset = 0; offset < staleIds.length; offset += _writeChunkSize) {
      final chunk = staleIds.skip(offset).take(_writeChunkSize).toList();
      final sessionRef = _session(session.courseId, session.occurrenceId);
      final references = [
        for (final id in chunk)
          _roster(session.courseId, session.occurrenceId).doc(id),
      ];
      await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshots = await Future.wait(references.map(transaction.get));
        _requireSameUser(uid);
        final current = AttendanceFirestoreCodec.sessionFromMap(
          sessionSnapshot.data() ??
              (throw const FormatException('Missing attendance session.')),
          expectedCourseId: session.courseId,
          expectedOccurrenceId: session.occurrenceId,
        );
        if (current.status != AttendanceSessionStatus.preparing ||
            current.rosterState != AttendanceRosterState.building) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        var didWrite = false;
        for (var index = 0; index < references.length; index++) {
          final snapshot = rowSnapshots[index];
          if (!snapshot.exists) continue;
          final existing = AttendanceFirestoreCodec.rosterEntryFromMap(
            snapshot.data() ??
                (throw const FormatException('Missing roster data.')),
            expectedRosterEntryId: chunk[index],
            mode: current.mode,
          );
          if (!_isUnmarked(existing, current.mode)) {
            throw const AttendanceFailure(AttendanceFailureKind.conflict);
          }
          transaction.delete(references[index]);
          didWrite = true;
        }
        if (didWrite) {
          transaction.update(sessionRef, _versionUpdate(uid, current.version));
        }
      });
      _requireSameUser(uid);
    }
  }

  Future<void> _verifyRosterSourceUnchanged(
    String courseId,
    String uid,
    _RosterBuildInput original,
  ) async {
    final latest = await _enrollments.loadCourseRosterSnapshot(
      courseId: courseId,
    );
    _requireSameUser(uid);
    if (!latest.complete ||
        _rosterFingerprint(original.snapshot) != _rosterFingerprint(latest)) {
      throw const AttendanceFailure(
        AttendanceFailureKind.staleSession,
        message: 'La nómina cambió mientras se materializaba la sesión.',
      );
    }
    await _readInParallel(
      [...latest.activeEnrollments, ...latest.withdrawnEnrollments],
      (enrollment) async {
        final linked = await _enrollments.getCoursePendingEnrollment(
          courseId: courseId,
          email: enrollment.email,
        );
        _requireSameUser(uid);
        final expected =
            original.linkedAuthorizationsByStudentUid[enrollment.studentUid];
        if (!_sameLinkedAuthorization(
          expected,
          linked?.status == 'linked' ? linked : null,
        )) {
          throw const AttendanceFailure(
            AttendanceFailureKind.staleSession,
            message: 'Cambió el historial de una vinculación del curso.',
          );
        }
      },
    );
  }

  Future<AttendanceSession> _markRosterReady({
    required String courseId,
    required String occurrenceId,
    required Set<String> expectedEntryIds,
    required Set<String> expectedSegmentIds,
    required String uid,
  }) async {
    final session = await _getOwnedSession(courseId, occurrenceId, uid);
    if (session.status != AttendanceSessionStatus.preparing) {
      return session;
    }
    if (session.rosterState == AttendanceRosterState.ready) return session;
    final entries = await _loadAllRoster(session, uid);
    final segments = await _loadAllSegments(session, uid);
    if (entries.map((entry) => entry.rosterEntryId).toSet().length !=
            expectedEntryIds.length ||
        !entries
            .map((entry) => entry.rosterEntryId)
            .toSet()
            .containsAll(expectedEntryIds) ||
        !expectedEntryIds.containsAll(
          entries.map((entry) => entry.rosterEntryId),
        ) ||
        segments.map((segment) => segment.id).toSet().length !=
            expectedSegmentIds.length ||
        !segments
            .map((segment) => segment.id)
            .toSet()
            .containsAll(expectedSegmentIds) ||
        !expectedSegmentIds.containsAll(
          segments.map((segment) => segment.id),
        ) ||
        entries.any((entry) => !_isUnmarked(entry, session.mode))) {
      throw const AttendanceFailure(
        AttendanceFailureKind.incompleteRoster,
        message: 'La nómina o sus tramos no quedaron completos en el servidor.',
      );
    }
    final sessionRef = _session(courseId, occurrenceId);
    return _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(sessionRef);
      _requireSameUser(uid);
      final current = AttendanceFirestoreCodec.sessionFromMap(
        currentSnapshot.data() ??
            (throw const FormatException('Missing attendance session.')),
        expectedCourseId: courseId,
        expectedOccurrenceId: occurrenceId,
      );
      if (current.status != AttendanceSessionStatus.preparing ||
          current.rosterState != AttendanceRosterState.building) {
        if (current.rosterState == AttendanceRosterState.ready) return current;
        throw const AttendanceFailure(AttendanceFailureKind.staleSession);
      }
      if (current.version != session.version) {
        throw const AttendanceFailure(AttendanceFailureKind.staleSession);
      }
      transaction.update(sessionRef, {
        'rosterState': AttendanceRosterState.ready.value,
        'rosterCount': entries.length,
        'markedCount': 0,
        'unmarkedCount': entries.length,
        ..._versionUpdate(uid, current.version),
      });
      return _copySession(
        current,
        rosterState: AttendanceRosterState.ready,
        rosterCount: entries.length,
        markedCount: 0,
        unmarkedCount: entries.length,
        version: current.version + 1,
        updatedBy: uid,
      );
    });
  }

  Future<List<AttendanceRosterEntry>> _loadAllRoster(
    AttendanceSession session,
    String uid,
  ) async {
    final entries = <AttendanceRosterEntry>[];
    Query<Map<String, dynamic>> query = _roster(
      session.courseId,
      session.occurrenceId,
    ).orderBy(FieldPath.documentId).limit(_pageSize);
    while (true) {
      final page = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      for (final document in page.docs) {
        entries.add(
          AttendanceFirestoreCodec.rosterEntryFromMap(
            document.data(),
            expectedRosterEntryId: document.id,
            mode: session.mode,
          ),
        );
      }
      if (page.docs.length < _pageSize) break;
      final last = page.docs.last.id;
      query = _roster(
        session.courseId,
        session.occurrenceId,
      ).orderBy(FieldPath.documentId).startAfter([last]).limit(_pageSize);
    }
    return List.unmodifiable(entries);
  }

  Future<List<AttendanceSegment>> _loadAllSegments(
    AttendanceSession session,
    String uid,
  ) async {
    if (session.mode == AttendanceMode.meeting) return const [];
    final segments = <AttendanceSegment>[];
    Query<Map<String, dynamic>> query = _segments(
      session.courseId,
      session.occurrenceId,
    ).orderBy('order').limit(_pageSize);
    var lastOrder = -1;
    while (true) {
      final page = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      for (final document in page.docs) {
        final segment = AttendanceFirestoreCodec.segmentFromMap(
          document.data(),
          expectedId: document.id,
        );
        if (segment.order <= lastOrder) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidData);
        }
        segments.add(segment);
        lastOrder = segment.order;
      }
      if (page.docs.length < _pageSize) break;
      query = _segments(
        session.courseId,
        session.occurrenceId,
      ).orderBy('order').startAfter([lastOrder]).limit(_pageSize);
    }
    return List.unmodifiable(segments);
  }

  Future<AttendanceSession> _getOwnedSession(
    String courseId,
    String occurrenceId,
    String uid,
  ) async {
    final snapshot = await _session(
      courseId,
      occurrenceId,
    ).get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    if (!snapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.notFound);
    }
    final session = AttendanceFirestoreCodec.sessionFromMap(
      snapshot.data() ??
          (throw const FormatException('Missing attendance session.')),
      expectedCourseId: courseId,
      expectedOccurrenceId: occurrenceId,
    );
    if (session.ownerUid != uid) {
      throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
    }
    return session;
  }

  bool _sameSegment(AttendanceSegment left, AttendanceSegment right) =>
      left.id == right.id &&
      left.order == right.order &&
      left.startMinute == right.startMinute &&
      left.endMinute == right.endMinute &&
      left.durationMinutes == right.durationMinutes;

  bool _hasReachedStart(AttendanceSession session, DateTime nowUtc) {
    final startUtc = session.effectiveDate.toUtcTimestamp().add(
      Duration(hours: 5, minutes: session.startMinute),
    );
    return !nowUtc.isBefore(startUtc);
  }

  AttendanceSession _parseSessionSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String courseId,
    required String occurrenceId,
  }) {
    if (!snapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.notFound);
    }
    return AttendanceFirestoreCodec.sessionFromMap(
      snapshot.data() ??
          (throw const FormatException('Missing attendance session.')),
      expectedCourseId: courseId,
      expectedOccurrenceId: occurrenceId,
    );
  }

  AttendanceRosterEntry _parseRosterSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    AttendanceSession session,
    String rosterEntryId,
  ) {
    if (!snapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.notFound);
    }
    return AttendanceFirestoreCodec.rosterEntryFromMap(
      snapshot.data() ??
          (throw const FormatException('Missing attendance roster entry.')),
      expectedRosterEntryId: rosterEntryId,
      mode: session.mode,
    );
  }

  void _requireMarkable(
    AttendanceSession session,
    String uid,
    AttendanceMode mode,
  ) {
    if (session.ownerUid != uid) {
      throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
    }
    if (session.mode != mode ||
        session.status != AttendanceSessionStatus.inProgress ||
        session.rosterState != AttendanceRosterState.ready ||
        session.unmarkedConfirmed) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidTransition);
    }
    if (!_hasReachedStart(session, DateTime.now().toUtc())) {
      throw const AttendanceFailure(
        AttendanceFailureKind.invalidTransition,
        message: 'La sesión todavía no llega a su hora de inicio.',
      );
    }
  }

  void _validateCounters(
    AttendanceSession session,
    int markedCount,
    int unmarkedCount,
  ) {
    if (markedCount < 0 ||
        unmarkedCount < 0 ||
        markedCount + unmarkedCount != session.rosterCount) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  bool _sameMark(AttendanceRosterMark left, AttendanceRosterMark right) =>
      left.mark == right.mark &&
      left.absentUnits == right.absentUnits &&
      left.justificationStatus == right.justificationStatus &&
      left.justifiedUnits == right.justifiedUnits;

  bool _sameRosterIdentity(
    AttendanceRosterEntry left,
    AttendanceRosterEntry right,
  ) =>
      left.rosterEntryId == right.rosterEntryId &&
      left.displayName == right.displayName &&
      left.studentUid == right.studentUid;

  bool _sameRosterMarks(
    AttendanceRosterEntry left,
    AttendanceRosterEntry right,
    AttendanceMode mode,
  ) {
    if (mode == AttendanceMode.meeting) {
      return left.meetingMark != null &&
          right.meetingMark != null &&
          _sameMark(left.meetingMark!, right.meetingMark!);
    }
    if (left.segmentMarks.keys.toSet().length != right.segmentMarks.length ||
        !left.segmentMarks.keys.toSet().containsAll(right.segmentMarks.keys)) {
      return false;
    }
    return left.segmentMarks.entries.every((item) {
      final other = right.segmentMarks[item.key];
      return other != null && _sameMark(item.value, other);
    });
  }

  bool _hasExactlyOneMarkChange(
    AttendanceRosterEntry before,
    AttendanceRosterEntry after,
    AttendanceMode mode,
  ) {
    if (mode == AttendanceMode.meeting) {
      return before.meetingMark != null &&
          after.meetingMark != null &&
          !_sameMark(before.meetingMark!, after.meetingMark!);
    }
    if (before.segmentMarks.length != after.segmentMarks.length ||
        !before.segmentMarks.keys.toSet().containsAll(
          after.segmentMarks.keys,
        )) {
      return false;
    }
    var changed = 0;
    for (final entry in before.segmentMarks.entries) {
      final next = after.segmentMarks[entry.key];
      if (next == null) return false;
      if (!_sameMark(entry.value, next)) changed++;
    }
    return changed == 1;
  }

  Map<String, Object?> _changedRosterValue(
    AttendanceRosterEntry current,
    AttendanceRosterEntry other,
    AttendanceMode mode,
  ) {
    if (mode == AttendanceMode.meeting) {
      final mark = current.meetingMark;
      if (mark == null || other.meetingMark == null) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidData);
      }
      return {'mark': _markValue(mark)};
    }
    for (final entry in current.segmentMarks.entries) {
      final next = other.segmentMarks[entry.key];
      if (next != null && !_sameMark(entry.value, next)) {
        return {'segmentId': entry.key, 'mark': _markValue(entry.value)};
      }
    }
    throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
  }

  bool _entryMatchesEventNewValue(
    AttendanceRosterEntry entry,
    Map<String, Object?> value,
    AttendanceMode mode,
  ) {
    if (mode == AttendanceMode.meeting) {
      final mark = entry.meetingMark;
      final raw = value['mark'];
      return value.length == 1 &&
          mark != null &&
          raw is Map &&
          _sameFlatMap(Map<String, Object?>.from(raw), _markValue(mark));
    }
    final segmentId = value['segmentId'];
    final raw = value['mark'];
    if (value.length != 2 ||
        segmentId is! String ||
        raw is! Map ||
        !entry.segmentMarks.containsKey(segmentId)) {
      return false;
    }
    return _sameFlatMap(
      Map<String, Object?>.from(raw),
      _markValue(entry.segmentMarks[segmentId]!),
    );
  }

  Map<String, Object?> _markValue(AttendanceRosterMark mark) => {
    'mark': mark.mark.value,
    'absentUnits': mark.absentUnits,
    'justificationStatus': mark.justificationStatus.value,
    'justifiedUnits': mark.justifiedUnits,
  };

  AttendanceRosterMark _markForEntry(
    AttendanceRosterEntry entry,
    AttendanceMode mode,
    String? segmentId,
  ) {
    if (mode == AttendanceMode.meeting) {
      if (segmentId != null || entry.meetingMark == null) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      return entry.meetingMark!;
    }
    if (segmentId == null || !entry.segmentMarks.containsKey(segmentId)) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
    return entry.segmentMarks[segmentId]!;
  }

  AttendanceRosterEntry _replaceEntryMark(
    AttendanceRosterEntry entry,
    AttendanceMode mode,
    String? segmentId,
    AttendanceRosterMark mark,
  ) {
    if (mode == AttendanceMode.meeting) {
      if (segmentId != null) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      return AttendanceRosterEntry(
        rosterEntryId: entry.rosterEntryId,
        displayName: entry.displayName,
        studentUid: entry.studentUid,
        meetingMark: mark,
        segmentMarks: const {},
        version: entry.version,
        updatedAt: entry.updatedAt,
        updatedBy: entry.updatedBy,
      );
    }
    if (segmentId == null || !entry.segmentMarks.containsKey(segmentId)) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
    final updatedMarks = Map<String, AttendanceRosterMark>.from(
      entry.segmentMarks,
    )..[segmentId] = mark;
    return AttendanceRosterEntry(
      rosterEntryId: entry.rosterEntryId,
      displayName: entry.displayName,
      studentUid: entry.studentUid,
      meetingMark: null,
      segmentMarks: updatedMarks,
      version: entry.version,
      updatedAt: entry.updatedAt,
      updatedBy: entry.updatedBy,
    );
  }

  bool _sameFlatMap(Map<String, Object?> left, Map<String, Object?> right) {
    if (left.length != right.length ||
        !left.keys.toSet().containsAll(right.keys)) {
      return false;
    }
    for (final key in left.keys) {
      final a = left[key];
      final b = right[key];
      if (a is Map && b is Map) {
        final leftNested = Map<String, Object?>.from(a);
        final rightNested = Map<String, Object?>.from(b);
        if (!_sameFlatMap(leftNested, rightNested)) return false;
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }

  Future<List<AttendanceSegment>> _readSegmentsInTransaction(
    Transaction transaction,
    AttendanceSession session,
    String uid,
  ) async {
    if (session.mode == AttendanceMode.meeting) return const [];
    final result = <AttendanceSegment>[];
    for (final id in session.segmentIds) {
      final snapshot = await transaction.get(
        _segments(session.courseId, session.occurrenceId).doc(id),
      );
      _requireSameUser(uid);
      if (!snapshot.exists) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }
      result.add(
        AttendanceFirestoreCodec.segmentFromMap(
          snapshot.data() ??
              (throw const FormatException('Missing attendance segment.')),
          expectedId: id,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  AttendanceRecord _parseRecordSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String courseId,
    required String recordId,
  }) {
    if (!snapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
    }
    return AttendanceFirestoreCodec.recordFromMap(
      snapshot.data() ??
          (throw const FormatException('Missing attendance record data.')),
      expectedCourseId: courseId,
      expectedRecordId: recordId,
    );
  }

  void _validateEventId(String value) {
    _validateId(value);
    if (value.length > 128) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  bool _isUnmarked(AttendanceRosterEntry entry, AttendanceMode mode) =>
      mode == AttendanceMode.meeting
      ? entry.meetingMark?.mark == AttendanceMark.unmarked
      : entry.segmentMarks.values.every(
          (mark) => mark.mark == AttendanceMark.unmarked,
        );

  AttendanceRosterEntry _entryWithVersion(
    AttendanceRosterEntry entry,
    int version, {
    required String updatedBy,
  }) => AttendanceRosterEntry(
    rosterEntryId: entry.rosterEntryId,
    displayName: entry.displayName,
    studentUid: entry.studentUid,
    meetingMark: entry.meetingMark,
    segmentMarks: entry.segmentMarks,
    version: version,
    updatedBy: updatedBy,
  );

  Map<String, Object?> _versionUpdate(String uid, int currentVersion) => {
    'version': currentVersion + 1,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  AttendanceSession _copySession(
    AttendanceSession current, {
    AttendanceSessionStatus? status,
    AttendanceRosterState? rosterState,
    int? rosterCount,
    int? markedCount,
    int? unmarkedCount,
    bool? unmarkedConfirmed,
    int? version,
    String? updatedBy,
    String? lastMutationRosterEntryId,
    AttendanceMutationKind? lastMutationKind,
    String? lastEventId,
    bool clearEventMarker = false,
    bool clearMutationMarker = false,
    bool clearConfirmationMetadata = false,
    DateTime? unmarkedConfirmedAt,
    String? unmarkedConfirmedBy,
    DateTime? finalizedAt,
    DateTime? voidedAt,
    String? reason,
    String? lateRegistrationReason,
  }) => AttendanceSession(
    courseId: current.courseId,
    ownerUid: current.ownerUid,
    occurrenceId: current.occurrenceId,
    occurrenceKind: current.occurrenceKind,
    mode: current.mode,
    status: status ?? current.status,
    rosterState: rosterState ?? current.rosterState,
    scheduledDate: current.scheduledDate,
    effectiveDate: current.effectiveDate,
    startMinute: current.startMinute,
    endMinute: current.endMinute,
    timezone: current.timezone,
    segmentIds: current.segmentIds,
    rosterCount: rosterCount ?? current.rosterCount,
    markedCount: markedCount ?? current.markedCount,
    unmarkedCount: unmarkedCount ?? current.unmarkedCount,
    unmarkedConfirmed: unmarkedConfirmed ?? current.unmarkedConfirmed,
    version: version ?? current.version,
    lastMutationRosterEntryId: clearMutationMarker
        ? null
        : lastMutationRosterEntryId ?? current.lastMutationRosterEntryId,
    lastMutationKind: clearMutationMarker
        ? null
        : lastMutationKind ?? current.lastMutationKind,
    lastEventId: clearEventMarker ? null : lastEventId ?? current.lastEventId,
    createdAt: current.createdAt,
    createdBy: current.createdBy,
    updatedAt: null,
    updatedBy: updatedBy ?? current.updatedBy,
    unmarkedConfirmedAt: clearConfirmationMetadata
        ? null
        : unmarkedConfirmedAt ?? current.unmarkedConfirmedAt,
    unmarkedConfirmedBy: clearConfirmationMetadata
        ? null
        : unmarkedConfirmedBy ?? current.unmarkedConfirmedBy,
    finalizedAt: finalizedAt ?? current.finalizedAt,
    voidedAt: voidedAt ?? current.voidedAt,
    reason: reason ?? current.reason,
    lateRegistrationReason:
        lateRegistrationReason ?? current.lateRegistrationReason,
  );

  @override
  Future<AttendanceSession> startSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(sessionRef);
        _requireSameUser(actor.uid);
        if (!snapshot.exists) {
          throw const AttendanceFailure(AttendanceFailureKind.notFound);
        }
        final current = AttendanceFirestoreCodec.sessionFromMap(
          snapshot.data() ??
              (throw const FormatException('Missing attendance session.')),
          expectedCourseId: courseId,
          expectedOccurrenceId: occurrenceId,
        );
        if (current.ownerUid != actor.uid) {
          throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
        }
        if (current.status == AttendanceSessionStatus.inProgress) {
          return current;
        }
        if (current.status != AttendanceSessionStatus.preparing ||
            current.rosterState != AttendanceRosterState.ready) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        if (current.markedCount != 0 ||
            current.unmarkedCount != current.rosterCount) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidData);
        }
        if (!_hasReachedStart(current, DateTime.now().toUtc())) return current;
        transaction.update(sessionRef, {
          'status': AttendanceSessionStatus.inProgress.value,
          ..._versionUpdate(actor.uid, current.version),
        });
        return _copySession(
          current,
          status: AttendanceSessionStatus.inProgress,
          version: current.version + 1,
          updatedBy: actor.uid,
        );
      });
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceRosterPage> listRoster({
    required AttendanceSession session,
    AttendanceRosterCursor? cursor,
    int pageSize = 25,
  }) async {
    final trace = AttendanceOperationTrace('ver lista', onTiming: onTiming)
      ..start('comprobar cuenta y sesión');
    try {
      _validatePageSize(pageSize);
      final actor = await _requireTeacher();
      final current = await _getOwnedSession(
        session.courseId,
        session.occurrenceId,
        actor.uid,
      );
      Query<Map<String, dynamic>> query = _roster(
        current.courseId,
        current.occurrenceId,
      ).orderBy(FieldPath.documentId);
      if (cursor != null) query = query.startAfter([cursor.rosterEntryId]);
      trace.start('leer página de nómina');
      final snapshot = await query
          .limit(pageSize + 1)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final entries = visible
          .map(
            (document) => AttendanceFirestoreCodec.rosterEntryFromMap(
              document.data(),
              expectedRosterEntryId: document.id,
              mode: current.mode,
            ),
          )
          .toList(growable: false);
      return AttendanceRosterPage(
        items: entries,
        nextCursor: hasMore && entries.isNotEmpty
            ? AttendanceRosterCursor(rosterEntryId: entries.last.rosterEntryId)
            : null,
      );
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    } finally {
      trace.finish();
    }
  }

  @override
  Future<AttendanceRosterEntry?> getRosterEntry({
    required AttendanceSession session,
    required String rosterEntryId,
  }) async {
    try {
      _validateId(rosterEntryId);
      final actor = await _requireTeacher();
      final current = await _getOwnedSession(
        session.courseId,
        session.occurrenceId,
        actor.uid,
      );
      final snapshot = await _roster(
        current.courseId,
        current.occurrenceId,
      ).doc(rosterEntryId).get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      if (!snapshot.exists) return null;
      return AttendanceFirestoreCodec.rosterEntryFromMap(
        snapshot.data() ??
            (throw const FormatException('Missing attendance roster entry.')),
        expectedRosterEntryId: rosterEntryId,
        mode: current.mode,
      );
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceSegmentPage> listSegments({
    required AttendanceSession session,
    AttendanceSegmentCursor? cursor,
    int pageSize = 25,
  }) async {
    final trace = AttendanceOperationTrace('ver tramos', onTiming: onTiming)
      ..start('comprobar cuenta y sesión');
    try {
      _validatePageSize(pageSize);
      final actor = await _requireTeacher();
      final current = await _getOwnedSession(
        session.courseId,
        session.occurrenceId,
        actor.uid,
      );
      if (current.mode == AttendanceMode.meeting) {
        return AttendanceSegmentPage(items: const [], nextCursor: null);
      }
      Query<Map<String, dynamic>> query = _segments(
        current.courseId,
        current.occurrenceId,
      ).orderBy('order');
      if (cursor != null) query = query.startAfter([cursor.order]);
      trace.start('leer página de tramos');
      final snapshot = await query
          .limit(pageSize + 1)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final segments = visible
          .map(
            (document) => AttendanceFirestoreCodec.segmentFromMap(
              document.data(),
              expectedId: document.id,
            ),
          )
          .toList(growable: false);
      return AttendanceSegmentPage(
        items: segments,
        nextCursor: hasMore && segments.isNotEmpty
            ? AttendanceSegmentCursor(order: segments.last.order)
            : null,
      );
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    } finally {
      trace.finish();
    }
  }

  @override
  Future<AttendanceSessionEventPage> listSessionEvents({
    required AttendanceSession session,
    AttendanceSessionEventCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      _validatePageSize(pageSize);
      final actor = await _requireTeacher();
      final current = await _getOwnedSession(
        session.courseId,
        session.occurrenceId,
        actor.uid,
      );
      Query<Map<String, dynamic>> query =
          _events(current.courseId, current.occurrenceId)
              .orderBy('changedAt', descending: true)
              .orderBy(FieldPath.documentId, descending: true);
      if (cursor != null) {
        query = query.startAfter([
          Timestamp.fromDate(cursor.changedAt),
          cursor.eventId,
        ]);
      }
      final snapshot = await query
          .limit(pageSize + 1)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final events = visible
          .map(
            (document) => AttendanceFirestoreCodec.eventFromMap(
              document.data(),
              expectedEventId: document.id,
            ),
          )
          .toList(growable: false);
      final last = events.isEmpty ? null : events.last;
      return AttendanceSessionEventPage(
        items: events,
        nextCursor: hasMore && last?.changedAt != null
            ? AttendanceSessionEventCursor(
                changedAt: last!.changedAt!,
                eventId: last.eventId,
              )
            : null,
      );
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceRosterMutationResult> setMeetingMark({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required AttendanceMark mark,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      _validateId(rosterEntryId);
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      final rowRef = _roster(courseId, occurrenceId).doc(rosterEntryId);
      return await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshot = await transaction.get(rowRef);
        _requireSameUser(actor.uid);
        final current = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        _requireMarkable(current, actor.uid, AttendanceMode.meeting);
        final oldEntry = _parseRosterSnapshot(
          rowSnapshot,
          current,
          rosterEntryId,
        );
        final oldMark = oldEntry.meetingMark!;
        final nextMark = AttendanceRosterMark(
          mark: mark,
          absentUnits: mark == AttendanceMark.absent ? 1 : 0,
          justificationStatus:
              mark == AttendanceMark.absent &&
                  oldMark.mark == AttendanceMark.absent
              ? oldMark.justificationStatus
              : AttendanceJustificationStatus.none,
          justifiedUnits:
              mark == AttendanceMark.absent &&
                  oldMark.mark == AttendanceMark.absent
              ? oldMark.justifiedUnits
              : 0,
        );
        if (_sameMark(oldMark, nextMark)) {
          return AttendanceRosterMutationResult(
            session: current,
            entry: oldEntry,
            alreadyApplied: true,
          );
        }
        final updatedEntry = AttendanceRosterEntry(
          rosterEntryId: oldEntry.rosterEntryId,
          displayName: oldEntry.displayName,
          studentUid: oldEntry.studentUid,
          meetingMark: nextMark,
          segmentMarks: const {},
          version: oldEntry.version + 1,
          updatedBy: actor.uid,
        );
        final wasMarked = oldMark.mark != AttendanceMark.unmarked;
        final isMarked = mark != AttendanceMark.unmarked;
        final nextMarked =
            current.markedCount + (isMarked ? 1 : 0) - (wasMarked ? 1 : 0);
        final nextUnmarked =
            current.unmarkedCount + (wasMarked ? 1 : 0) - (isMarked ? 1 : 0);
        _validateCounters(current, nextMarked, nextUnmarked);
        final updatedSession = _copySession(
          current,
          markedCount: nextMarked,
          unmarkedCount: nextUnmarked,
          version: current.version + 1,
          updatedBy: actor.uid,
          lastMutationRosterEntryId: rosterEntryId,
          lastMutationKind: AttendanceMutationKind.mark,
          clearEventMarker: true,
        );
        transaction.update(
          rowRef,
          AttendanceFirestoreCodec.rosterDocument(
            entry: updatedEntry,
            mode: current.mode,
            uid: actor.uid,
          ),
        );
        transaction.update(sessionRef, {
          'markedCount': nextMarked,
          'unmarkedCount': nextUnmarked,
          'lastMutationRosterEntryId': rosterEntryId,
          'lastMutationKind': AttendanceMutationKind.mark.value,
          'lastEventId': null,
          ..._versionUpdate(actor.uid, current.version),
        });
        return AttendanceRosterMutationResult(
          session: updatedSession,
          entry: updatedEntry,
          alreadyApplied: false,
        );
      });
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceRosterMutationResult> setSegmentMark({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String segmentId,
    required AttendanceMark mark,
    int? absentUnits,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      _validateId(rosterEntryId);
      _validateId(segmentId);
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      final rowRef = _roster(courseId, occurrenceId).doc(rosterEntryId);
      final segmentRef = _segments(courseId, occurrenceId).doc(segmentId);
      return await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshot = await transaction.get(rowRef);
        final segmentSnapshot = await transaction.get(segmentRef);
        _requireSameUser(actor.uid);
        final current = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        _requireMarkable(current, actor.uid, AttendanceMode.minutes);
        if (!current.segmentIds.contains(segmentId)) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
        }
        if (!segmentSnapshot.exists) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidData);
        }
        final segment = AttendanceFirestoreCodec.segmentFromMap(
          segmentSnapshot.data() ??
              (throw const FormatException('Missing segment data.')),
          expectedId: segmentId,
        );
        final oldEntry = _parseRosterSnapshot(
          rowSnapshot,
          current,
          rosterEntryId,
        );
        final oldMark = oldEntry.segmentMarks[segmentId];
        if (oldMark == null) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidData);
        }
        final units = switch (mark) {
          AttendanceMark.absent => absentUnits ?? segment.durationMinutes,
          AttendanceMark.present || AttendanceMark.unmarked => 0,
        };
        if (units < 0 ||
            units > segment.durationMinutes ||
            mark == AttendanceMark.absent && units == 0 ||
            mark != AttendanceMark.absent &&
                absentUnits != null &&
                absentUnits != 0) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
        }
        final nextMark = AttendanceRosterMark(
          mark: mark,
          absentUnits: units,
          justificationStatus:
              mark == AttendanceMark.absent &&
                  oldMark.mark == AttendanceMark.absent
              ? oldMark.justificationStatus
              : AttendanceJustificationStatus.none,
          justifiedUnits:
              mark == AttendanceMark.absent &&
                  oldMark.mark == AttendanceMark.absent
              ? oldMark.justifiedUnits
              : 0,
        );
        if (_sameMark(oldMark, nextMark)) {
          return AttendanceRosterMutationResult(
            session: current,
            entry: oldEntry,
            alreadyApplied: true,
          );
        }
        final nextMarks = Map<String, AttendanceRosterMark>.from(
          oldEntry.segmentMarks,
        )..[segmentId] = nextMark;
        final updatedEntry = AttendanceRosterEntry(
          rosterEntryId: oldEntry.rosterEntryId,
          displayName: oldEntry.displayName,
          studentUid: oldEntry.studentUid,
          meetingMark: null,
          segmentMarks: nextMarks,
          version: oldEntry.version + 1,
          updatedBy: actor.uid,
        );
        final wasMarked = oldEntry.segmentMarks.values.every(
          (item) => item.mark != AttendanceMark.unmarked,
        );
        final isMarked = nextMarks.values.every(
          (item) => item.mark != AttendanceMark.unmarked,
        );
        final nextMarked =
            current.markedCount + (isMarked ? 1 : 0) - (wasMarked ? 1 : 0);
        final nextUnmarked =
            current.unmarkedCount + (wasMarked ? 1 : 0) - (isMarked ? 1 : 0);
        _validateCounters(current, nextMarked, nextUnmarked);
        final updatedSession = _copySession(
          current,
          markedCount: nextMarked,
          unmarkedCount: nextUnmarked,
          version: current.version + 1,
          updatedBy: actor.uid,
          lastMutationRosterEntryId: rosterEntryId,
          lastMutationKind: AttendanceMutationKind.mark,
          clearEventMarker: true,
        );
        transaction.update(
          rowRef,
          AttendanceFirestoreCodec.rosterDocument(
            entry: updatedEntry,
            mode: current.mode,
            uid: actor.uid,
          ),
        );
        transaction.update(sessionRef, {
          'markedCount': nextMarked,
          'unmarkedCount': nextUnmarked,
          'lastMutationRosterEntryId': rosterEntryId,
          'lastMutationKind': AttendanceMutationKind.mark.value,
          'lastEventId': null,
          ..._versionUpdate(actor.uid, current.version),
        });
        return AttendanceRosterMutationResult(
          session: updatedSession,
          entry: updatedEntry,
          alreadyApplied: false,
        );
      });
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceFinalizeResult> finalizeSession({
    required String courseId,
    required String occurrenceId,
    required bool confirmUnmarked,
  }) async {
    var writeConfirmed = false;
    AttendanceSession? knownSession;
    final trace = AttendanceOperationTrace('finalizar', onTiming: onTiming)
      ..start('comprobar cuenta y sesión');
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      final actor = await _requireTeacher();
      var session = await _getOwnedSession(courseId, occurrenceId, actor.uid);
      knownSession = session;
      final alreadyFinalized =
          session.status == AttendanceSessionStatus.finalized;
      if (alreadyFinalized) writeConfirmed = true;
      if (!alreadyFinalized &&
          (session.status == AttendanceSessionStatus.voiding ||
              session.status == AttendanceSessionStatus.voided ||
              session.status == AttendanceSessionStatus.preparing)) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidTransition);
      }
      if (session.rosterState != AttendanceRosterState.ready) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }

      trace.start('leer nómina y tramos');
      var entries = await _loadAllRoster(session, actor.uid);
      var segments = await _loadAllSegments(session, actor.uid);
      var unmarkedEntries = entries
          .where((entry) => !_isEntryFullyMarked(entry, session.mode))
          .toList(growable: false);
      var firstMissingChunkApplied = false;
      var firstMissingChunkSize = 0;
      if (entries.length != session.rosterCount ||
          !_countersMatch(session, entries.length, unmarkedEntries.length)) {
        throw const AttendanceFailure(
          AttendanceFailureKind.incompleteRoster,
          message: 'La nómina de la sesión está incompleta o cambió.',
        );
      }
      if (alreadyFinalized &&
          (unmarkedEntries.isNotEmpty ||
              session.markedCount != session.rosterCount ||
              session.unmarkedCount != 0)) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }
      if (unmarkedEntries.isNotEmpty &&
          !alreadyFinalized &&
          !confirmUnmarked &&
          !session.unmarkedConfirmed) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: unmarkedEntries.length,
          session: session,
          confirmationRequired: true,
          writeConfirmed: false,
        );
      }

      trace.start('confirmar cierre y marcas pendientes');
      final sessionRef = _session(courseId, occurrenceId);
      if (!alreadyFinalized &&
          session.status == AttendanceSessionStatus.inProgress &&
          unmarkedEntries.isEmpty) {
        final before = session;
        session = await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(sessionRef);
          _requireSameUser(actor.uid);
          final current = _parseSessionSnapshot(
            snapshot,
            courseId: courseId,
            occurrenceId: occurrenceId,
          );
          if (current.version != before.version ||
              current.status != AttendanceSessionStatus.inProgress ||
              current.markedCount != current.rosterCount ||
              current.unmarkedCount != 0) {
            throw const AttendanceFailure(AttendanceFailureKind.staleSession);
          }
          transaction.update(sessionRef, {
            'status': AttendanceSessionStatus.closing.value,
            ..._versionUpdate(actor.uid, current.version),
          });
          return _copySession(
            current,
            status: AttendanceSessionStatus.closing,
            version: current.version + 1,
            updatedBy: actor.uid,
          );
        });
        writeConfirmed = true;
        knownSession = session;
      } else if (!alreadyFinalized &&
          session.status == AttendanceSessionStatus.inProgress &&
          unmarkedEntries.isNotEmpty) {
        final firstChunk = unmarkedEntries.take(_writeChunkSize).toList();
        final before = session;
        session = await _applyMissingMarkChunk(
          session: before,
          rows: firstChunk,
          segments: segments,
          uid: actor.uid,
          beginClosing: true,
          confirmUnmarked: true,
        );
        firstMissingChunkApplied = true;
        firstMissingChunkSize = firstChunk.length;
        writeConfirmed = true;
        knownSession = session;
      }

      if (!alreadyFinalized &&
          session.status == AttendanceSessionStatus.closing &&
          unmarkedEntries.isNotEmpty) {
        if (!session.unmarkedConfirmed && !confirmUnmarked) {
          return AttendanceFinalizeResult(
            status: writeConfirmed
                ? AttendanceFinalizeStatus.reviewRequired
                : AttendanceFinalizeStatus.notConfirmed,
            unmarkedCount: unmarkedEntries.length,
            session: session,
            confirmationRequired: true,
            writeConfirmed: writeConfirmed,
          );
        }
        final remaining = unmarkedEntries
            .skip(firstMissingChunkApplied ? firstMissingChunkSize : 0)
            .toList(growable: false);
        for (
          var offset = 0;
          offset < remaining.length;
          offset += _writeChunkSize
        ) {
          final chunk = remaining
              .skip(offset)
              .take(_writeChunkSize)
              .toList(growable: false);
          session = await _applyMissingMarkChunk(
            session: session,
            rows: chunk,
            segments: segments,
            uid: actor.uid,
            beginClosing: false,
            confirmUnmarked: true,
          );
          writeConfirmed = true;
          knownSession = session;
        }
      }

      if (!alreadyFinalized) {
        trace.start('revalidar nómina y marcas');
        session = await _getOwnedSession(courseId, occurrenceId, actor.uid);
        knownSession = session;
        entries = await _loadAllRoster(session, actor.uid);
        segments = await _loadAllSegments(session, actor.uid);
      }
      if ((!alreadyFinalized &&
              session.status != AttendanceSessionStatus.closing) ||
          entries.length != session.rosterCount ||
          entries.any((entry) => !_isEntryFullyMarked(entry, session.mode)) ||
          session.markedCount != session.rosterCount ||
          session.unmarkedCount != 0) {
        throw const AttendanceFailure(
          AttendanceFailureKind.incompleteRoster,
          message: 'La confirmación de faltantes todavía no se completó.',
        );
      }

      final records = <AttendanceRecord>[
        for (final entry in entries)
          AttendanceRecordCalculator.fromRosterEntry(
            session: session,
            entry: entry,
            segments: segments,
          ),
      ];
      if (!alreadyFinalized) {
        trace.start('preparar resultados privados');
        session = await _stageRecords(session, records, actor.uid);
        knownSession = session;
        writeConfirmed = true;
        trace.start('verificar resultados privados');
        await _verifyRecordSet(
          session: session,
          records: records,
          uid: actor.uid,
          allowStaged: true,
          allowPublished: false,
        );

        trace.start('finalizar sesión');
        final closingSession = await _getOwnedSession(
          courseId,
          occurrenceId,
          actor.uid,
        );
        knownSession = closingSession;
        if (closingSession.status != AttendanceSessionStatus.closing ||
            closingSession.markedCount != closingSession.rosterCount ||
            closingSession.unmarkedCount != 0 ||
            closingSession.version != session.version ||
            closingSession.rosterCount != records.length) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        session = await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(sessionRef);
          _requireSameUser(actor.uid);
          final current = _parseSessionSnapshot(
            snapshot,
            courseId: courseId,
            occurrenceId: occurrenceId,
          );
          if (current.version != closingSession.version ||
              current.status != AttendanceSessionStatus.closing ||
              current.markedCount != current.rosterCount ||
              current.unmarkedCount != 0 ||
              current.rosterCount != records.length) {
            throw const AttendanceFailure(AttendanceFailureKind.staleSession);
          }
          transaction.update(sessionRef, {
            'status': AttendanceSessionStatus.finalized.value,
            'finalizedAt': FieldValue.serverTimestamp(),
            ..._versionUpdate(actor.uid, current.version),
          });
          return _copySession(
            current,
            status: AttendanceSessionStatus.finalized,
            version: current.version + 1,
            updatedBy: actor.uid,
          );
        });
        knownSession = session;
        writeConfirmed = true;
      } else {
        trace.start('verificar resultados existentes');
        await _verifyRecordSet(
          session: session,
          records: records,
          uid: actor.uid,
          allowStaged: true,
          allowPublished: true,
        );
      }

      trace.start('publicar resultados');
      session = await _publishRecords(session, records, actor.uid);
      knownSession = session;
      trace.start('verificar publicación');
      await _verifyRecordSet(
        session: session,
        records: records,
        uid: actor.uid,
        allowStaged: false,
        allowPublished: true,
      );
      return AttendanceFinalizeResult(
        status: AttendanceFinalizeStatus.confirmed,
        unmarkedCount: 0,
        session: session,
        writeConfirmed: true,
      );
    } on AttendanceFailure catch (error) {
      if (knownSession?.status == AttendanceSessionStatus.finalized) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession!.unmarkedCount,
          session: knownSession,
          writeConfirmed: true,
          publicationPending: true,
          failureKind: error.kind,
        );
      }
      if (error.kind == AttendanceFailureKind.permissionDenied ||
          error.kind == AttendanceFailureKind.unauthenticated ||
          error.kind == AttendanceFailureKind.profileInvalid ||
          error.kind == AttendanceFailureKind.teacherRoleRequired) {
        rethrow;
      }
      if (knownSession?.status == AttendanceSessionStatus.closing) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession!.unmarkedCount,
          session: knownSession,
          writeConfirmed: writeConfirmed,
        );
      }
      if (writeConfirmed) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession?.unmarkedCount ?? 0,
          session: knownSession,
          writeConfirmed: true,
        );
      }
      rethrow;
    } on FirebaseException catch (error) {
      final translated = _translateFirebase(error);
      if (knownSession?.status == AttendanceSessionStatus.finalized) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession!.unmarkedCount,
          session: knownSession,
          writeConfirmed: true,
          publicationPending: true,
          failureKind: translated.kind,
        );
      }
      if (translated.kind == AttendanceFailureKind.permissionDenied ||
          translated.kind == AttendanceFailureKind.unauthenticated) {
        throw AttendanceFailure(
          translated.kind,
          message:
              'No se pudo ${trace.phase} (${error.code}). Reintenta la misma sesión; las marcas guardadas se conservan.',
        );
      }
      return AttendanceFinalizeResult(
        status: writeConfirmed
            ? AttendanceFinalizeStatus.reviewRequired
            : AttendanceFinalizeStatus.notConfirmed,
        unmarkedCount: knownSession?.unmarkedCount ?? 0,
        session: knownSession,
        writeConfirmed: writeConfirmed,
      );
    } on FormatException {
      if (knownSession?.status == AttendanceSessionStatus.finalized) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession!.unmarkedCount,
          session: knownSession,
          writeConfirmed: true,
          publicationPending: true,
          failureKind: AttendanceFailureKind.invalidData,
        );
      }
      if (writeConfirmed) {
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: knownSession?.unmarkedCount ?? 0,
          session: knownSession,
          writeConfirmed: true,
        );
      }
      rethrow;
    } finally {
      trace.finish();
    }
  }

  Future<AttendanceSession> _applyMissingMarkChunk({
    required AttendanceSession session,
    required List<AttendanceRosterEntry> rows,
    required List<AttendanceSegment> segments,
    required String uid,
    required bool beginClosing,
    required bool confirmUnmarked,
  }) async {
    if (rows.isEmpty) return session;
    final sessionRef = _session(session.courseId, session.occurrenceId);
    final rowRefs = [
      for (final entry in rows)
        _roster(
          session.courseId,
          session.occurrenceId,
        ).doc(entry.rosterEntryId),
    ];
    return _firestore.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final rowSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in rowRefs) {
        rowSnapshots.add(await transaction.get(ref));
      }
      _requireSameUser(uid);
      final current = _parseSessionSnapshot(
        sessionSnapshot,
        courseId: session.courseId,
        occurrenceId: session.occurrenceId,
      );
      final requiredStatus = beginClosing
          ? AttendanceSessionStatus.inProgress
          : AttendanceSessionStatus.closing;
      if (current.status != requiredStatus ||
          current.version != session.version ||
          current.rosterState != AttendanceRosterState.ready) {
        throw const AttendanceFailure(AttendanceFailureKind.staleSession);
      }
      if (beginClosing && rows.isNotEmpty && !confirmUnmarked) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      var updatedCount = 0;
      for (var index = 0; index < rows.length; index++) {
        final ref = rowRefs[index];
        final snapshot = rowSnapshots[index];
        final oldEntry = _parseRosterSnapshot(
          snapshot,
          current,
          rows[index].rosterEntryId,
        );
        if (_isEntryFullyMarked(oldEntry, current.mode)) continue;
        final nextEntry = _markEntryAbsent(oldEntry, current, segments, uid);
        transaction.update(
          ref,
          AttendanceFirestoreCodec.rosterDocument(
            entry: nextEntry,
            mode: current.mode,
            uid: uid,
          ),
        );
        updatedCount++;
      }
      if (updatedCount == 0) {
        if (beginClosing && current.unmarkedCount == 0) {
          transaction.update(sessionRef, {
            'status': AttendanceSessionStatus.closing.value,
            ..._versionUpdate(uid, current.version),
          });
          return _copySession(
            current,
            status: AttendanceSessionStatus.closing,
            version: current.version + 1,
            updatedBy: uid,
          );
        }
        return current;
      }
      final nextMarked = current.markedCount + updatedCount;
      final nextUnmarked = current.unmarkedCount - updatedCount;
      _validateCounters(current, nextMarked, nextUnmarked);
      final sessionUpdate = <String, Object?>{
        'status': AttendanceSessionStatus.closing.value,
        'markedCount': nextMarked,
        'unmarkedCount': nextUnmarked,
        ..._versionUpdate(uid, current.version),
      };
      final updatedSession = _copySession(
        current,
        status: AttendanceSessionStatus.closing,
        markedCount: nextMarked,
        unmarkedCount: nextUnmarked,
        unmarkedConfirmed: current.unmarkedConfirmed || confirmUnmarked,
        unmarkedConfirmedAt:
            current.unmarkedConfirmedAt == null && confirmUnmarked
            ? null
            : current.unmarkedConfirmedAt,
        unmarkedConfirmedBy:
            current.unmarkedConfirmedBy ?? (confirmUnmarked ? uid : null),
        version: current.version + 1,
        updatedBy: uid,
      );
      if (confirmUnmarked && !current.unmarkedConfirmed) {
        sessionUpdate['unmarkedConfirmed'] = true;
        sessionUpdate['unmarkedConfirmedAt'] = FieldValue.serverTimestamp();
        sessionUpdate['unmarkedConfirmedBy'] = uid;
      }
      transaction.update(sessionRef, sessionUpdate);
      return updatedSession;
    });
  }

  AttendanceRosterEntry _markEntryAbsent(
    AttendanceRosterEntry entry,
    AttendanceSession session,
    List<AttendanceSegment> segments,
    String uid,
  ) {
    if (session.mode == AttendanceMode.meeting) {
      return AttendanceRosterEntry(
        rosterEntryId: entry.rosterEntryId,
        displayName: entry.displayName,
        studentUid: entry.studentUid,
        meetingMark: const AttendanceRosterMark(
          mark: AttendanceMark.absent,
          absentUnits: 1,
          justificationStatus: AttendanceJustificationStatus.none,
          justifiedUnits: 0,
        ),
        segmentMarks: const {},
        version: entry.version + 1,
        updatedBy: uid,
      );
    }
    final marks = Map<String, AttendanceRosterMark>.from(entry.segmentMarks);
    for (final segment in segments) {
      final current = marks[segment.id];
      if (current == null) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidData);
      }
      if (current.mark == AttendanceMark.unmarked) {
        marks[segment.id] = AttendanceRosterMark(
          mark: AttendanceMark.absent,
          absentUnits: segment.durationMinutes,
          justificationStatus: AttendanceJustificationStatus.none,
          justifiedUnits: 0,
        );
      }
    }
    return AttendanceRosterEntry(
      rosterEntryId: entry.rosterEntryId,
      displayName: entry.displayName,
      studentUid: entry.studentUid,
      meetingMark: null,
      segmentMarks: marks,
      version: entry.version + 1,
      updatedBy: uid,
    );
  }

  void _validateVoidEvent(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String eventId,
    required String uid,
    required String reason,
  }) {
    if (!snapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.staleSession);
    }
    final event = AttendanceFirestoreCodec.eventFromMap(
      snapshot.data() ?? (throw const FormatException('Missing void event.')),
      expectedEventId: eventId,
    );
    const allowedPreviousStatuses = {
      'preparing',
      'inProgress',
      'closing',
      'finalized',
    };
    if (event.kind != AttendanceEventKind.voidSession ||
        event.rosterEntryId != null ||
        event.changedBy != uid ||
        event.changedAt == null ||
        event.reason != reason ||
        event.oldValue.length != 1 ||
        !allowedPreviousStatuses.contains(event.oldValue['status']) ||
        event.newValue.length != 1 ||
        event.newValue['status'] != AttendanceSessionStatus.voided.value) {
      throw const AttendanceFailure(AttendanceFailureKind.staleSession);
    }
  }

  bool _isEntryFullyMarked(AttendanceRosterEntry entry, AttendanceMode mode) =>
      mode == AttendanceMode.meeting
      ? entry.meetingMark?.mark != null &&
            entry.meetingMark!.mark != AttendanceMark.unmarked
      : entry.segmentMarks.isNotEmpty &&
            entry.segmentMarks.values.every(
              (mark) => mark.mark != AttendanceMark.unmarked,
            );

  bool _countersMatch(
    AttendanceSession session,
    int rosterCount,
    int unmarkedCount,
  ) =>
      session.rosterCount == rosterCount &&
      session.unmarkedCount == unmarkedCount &&
      session.markedCount == rosterCount - unmarkedCount;

  bool _sameRecordContent(AttendanceRecord actual, AttendanceRecord expected) {
    if (actual.courseId != expected.courseId ||
        actual.sessionId != expected.sessionId ||
        actual.rosterEntryId != expected.rosterEntryId ||
        actual.mode != expected.mode ||
        actual.scheduledDate != expected.scheduledDate ||
        actual.effectiveDate != expected.effectiveDate ||
        actual.startMinute != expected.startMinute ||
        actual.endMinute != expected.endMinute ||
        actual.unitCount != expected.unitCount ||
        actual.absentUnits != expected.absentUnits ||
        actual.inReviewUnits != expected.inReviewUnits ||
        actual.justifiedUnits != expected.justifiedUnits ||
        actual.result != expected.result ||
        actual.segments.length != expected.segments.length) {
      return false;
    }
    for (var index = 0; index < actual.segments.length; index++) {
      final left = actual.segments[index];
      final right = expected.segments[index];
      if (left.segmentId != right.segmentId ||
          left.startMinute != right.startMinute ||
          left.endMinute != right.endMinute ||
          left.durationMinutes != right.durationMinutes ||
          left.mark != right.mark ||
          left.absentMinutes != right.absentMinutes ||
          left.justificationStatus != right.justificationStatus ||
          left.justifiedMinutes != right.justifiedMinutes) {
        return false;
      }
    }
    return true;
  }

  Future<void> _verifyRecordSet({
    required AttendanceSession session,
    required List<AttendanceRecord> records,
    required String uid,
    required bool allowStaged,
    required bool allowPublished,
  }) async {
    if (records.length != session.rosterCount) {
      throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
    }
    await _readInParallel(records, (expected) async {
      final snapshot = await _records(session.courseId)
          .doc(expected.recordId)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!snapshot.exists) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }
      final actual = AttendanceFirestoreCodec.recordFromMap(
        snapshot.data() ??
            (throw const FormatException('Missing attendance record.')),
        expectedCourseId: session.courseId,
        expectedRecordId: expected.recordId,
      );
      if (!_sameRecordContent(actual, expected)) {
        throw const AttendanceFailure(AttendanceFailureKind.conflict);
      }
      if (actual.visibility == AttendanceRecordVisibility.staged) {
        if (!allowStaged || actual.publishedAt != null) {
          throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
        }
      } else if (actual.visibility == AttendanceRecordVisibility.published) {
        if (!allowPublished || actual.publishedAt == null) {
          throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
        }
      } else {
        throw const AttendanceFailure(AttendanceFailureKind.invalidData);
      }
    });
  }

  Future<AttendanceSession> _stageRecords(
    AttendanceSession session,
    List<AttendanceRecord> records,
    String uid,
  ) async {
    for (var offset = 0; offset < records.length; offset += _writeChunkSize) {
      final chunk = records
          .skip(offset)
          .take(_writeChunkSize)
          .toList(growable: false);
      for (final record in chunk) {
        _validateId(record.recordId);
      }
      final sessionRef = _session(session.courseId, session.occurrenceId);
      final refs = [
        for (final record in chunk)
          _records(session.courseId).doc(record.recordId),
      ];
      session = await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final recordSnapshots = await Future.wait(refs.map(transaction.get));
        _requireSameUser(uid);
        final current = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: session.courseId,
          occurrenceId: session.occurrenceId,
        );
        if (current.ownerUid != uid ||
            current.status != AttendanceSessionStatus.closing) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        var didWrite = false;
        for (var index = 0; index < chunk.length; index++) {
          final expected = chunk[index];
          final snapshot = recordSnapshots[index];
          if (snapshot.exists) {
            final actual = AttendanceFirestoreCodec.recordFromMap(
              snapshot.data() ??
                  (throw const FormatException('Missing attendance record.')),
              expectedCourseId: session.courseId,
              expectedRecordId: expected.recordId,
            );
            if (!_sameRecordContent(actual, expected) ||
                actual.visibility == AttendanceRecordVisibility.staged &&
                    actual.publishedAt != null) {
              throw const AttendanceFailure(AttendanceFailureKind.conflict);
            }
            continue;
          }
          transaction.set(
            refs[index],
            AttendanceFirestoreCodec.stagedRecord(expected),
          );
          didWrite = true;
        }
        if (didWrite) {
          transaction.update(sessionRef, _versionUpdate(uid, current.version));
        }
        return didWrite
            ? _copySession(
                current,
                version: current.version + 1,
                updatedBy: uid,
              )
            : current;
      });
      _requireSameUser(uid);
    }
    return session;
  }

  Future<AttendanceSession> _publishRecords(
    AttendanceSession session,
    List<AttendanceRecord> records,
    String uid,
  ) async {
    for (var offset = 0; offset < records.length; offset += _writeChunkSize) {
      final chunk = records
          .skip(offset)
          .take(_writeChunkSize)
          .toList(growable: false);
      final sessionRef = _session(session.courseId, session.occurrenceId);
      final refs = [
        for (final record in chunk)
          _records(session.courseId).doc(record.recordId),
      ];
      session = await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final recordSnapshots = await Future.wait(refs.map(transaction.get));
        _requireSameUser(uid);
        final current = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: session.courseId,
          occurrenceId: session.occurrenceId,
        );
        if (current.ownerUid != uid ||
            current.status != AttendanceSessionStatus.finalized) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        for (var index = 0; index < chunk.length; index++) {
          final expected = chunk[index];
          final snapshot = recordSnapshots[index];
          if (!snapshot.exists) {
            throw const AttendanceFailure(
              AttendanceFailureKind.incompleteRoster,
            );
          }
          final actual = AttendanceFirestoreCodec.recordFromMap(
            snapshot.data() ??
                (throw const FormatException('Missing attendance record.')),
            expectedCourseId: session.courseId,
            expectedRecordId: expected.recordId,
          );
          if (!_sameRecordContent(actual, expected)) {
            throw const AttendanceFailure(AttendanceFailureKind.conflict);
          }
          if (actual.visibility == AttendanceRecordVisibility.published) {
            if (actual.publishedAt == null) {
              throw const AttendanceFailure(AttendanceFailureKind.invalidData);
            }
            continue;
          }
          if (actual.visibility != AttendanceRecordVisibility.staged) {
            throw const AttendanceFailure(AttendanceFailureKind.invalidData);
          }
          transaction.update(
            refs[index],
            AttendanceFirestoreCodec.publishRecordUpdate(),
          );
        }
        // Student publication is row-level. The finalized parent is read by
        // this transaction, while each projection changes atomically on its
        // own. This avoids requiring a parent-status lookup in student list
        // rules and makes each student's result all-or-nothing.
        return current;
      });
      _requireSameUser(uid);
    }
    return session;
  }

  @override
  Future<AttendanceSession> voidSession({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required String reason,
  }) async {
    var operationStarted = false;
    AttendanceSession? knownSession;
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      _validateId(operationId);
      final normalizedReason = reason.trim();
      if (normalizedReason.length > 500) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      final eventRef = _events(courseId, occurrenceId).doc(operationId);
      final started = await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final eventSnapshot = await transaction.get(eventRef);
        _requireSameUser(actor.uid);
        final current = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        if (current.ownerUid != actor.uid) {
          throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
        }
        if (current.status == AttendanceSessionStatus.voided) {
          if (current.reason == normalizedReason &&
              current.lastEventId == operationId) {
            _validateVoidEvent(
              eventSnapshot,
              eventId: operationId,
              uid: actor.uid,
              reason: normalizedReason,
            );
            return current;
          }
          throw const AttendanceFailure(AttendanceFailureKind.conflict);
        }
        if (current.status == AttendanceSessionStatus.voiding) {
          if (current.reason != normalizedReason ||
              current.lastEventId != operationId) {
            throw const AttendanceFailure(AttendanceFailureKind.conflict);
          }
          _validateVoidEvent(
            eventSnapshot,
            eventId: operationId,
            uid: actor.uid,
            reason: normalizedReason,
          );
          return current;
        }
        if (eventSnapshot.exists) {
          _validateVoidEvent(
            eventSnapshot,
            eventId: operationId,
            uid: actor.uid,
            reason: normalizedReason,
          );
          throw const AttendanceFailure(AttendanceFailureKind.conflict);
        }
        final event = AttendanceSessionEvent(
          eventId: operationId,
          kind: AttendanceEventKind.voidSession,
          changedAt: null,
          changedBy: actor.uid,
          reason: normalizedReason,
          oldValue: {'status': current.status.value},
          newValue: {'status': AttendanceSessionStatus.voided.value},
        );
        final directVoid = current.status == AttendanceSessionStatus.preparing;
        final nextStatus = directVoid
            ? AttendanceSessionStatus.voided
            : AttendanceSessionStatus.voiding;
        transaction.update(sessionRef, {
          'status': nextStatus.value,
          'reason': normalizedReason,
          if (directVoid) 'voidedAt': FieldValue.serverTimestamp(),
          'lastMutationRosterEntryId': null,
          'lastMutationKind': AttendanceMutationKind.voidSession.value,
          'lastEventId': operationId,
          ..._versionUpdate(actor.uid, current.version),
        });
        transaction.set(
          eventRef,
          AttendanceFirestoreCodec.eventForCreate(event: event, uid: actor.uid),
        );
        return _copySession(
          current,
          status: nextStatus,
          version: current.version + 1,
          updatedBy: actor.uid,
          lastMutationRosterEntryId: null,
          lastMutationKind: AttendanceMutationKind.voidSession,
          lastEventId: operationId,
          reason: normalizedReason,
          voidedAt: directVoid ? null : current.voidedAt,
        );
      });
      knownSession = started;
      if (started.status == AttendanceSessionStatus.voided) return started;
      operationStarted = true;

      final entries = await _loadAllRoster(started, actor.uid);
      if (entries.length != started.rosterCount ||
          started.rosterState != AttendanceRosterState.ready) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }
      final segments = await _loadAllSegments(started, actor.uid);
      final voidRecords = <AttendanceRecord>[
        for (final entry in entries)
          AttendanceRecordCalculator.voidedForRosterEntry(
            session: started,
            entry: entry,
            segments: segments,
          ),
      ];
      var workingSession = started;
      for (
        var offset = 0;
        offset < voidRecords.length;
        offset += _writeChunkSize
      ) {
        final chunk = voidRecords
            .skip(offset)
            .take(_writeChunkSize)
            .toList(growable: false);
        final currentRef = _session(courseId, occurrenceId);
        final refs = [
          for (final record in chunk) _records(courseId).doc(record.recordId),
        ];
        workingSession = await _firestore.runTransaction((transaction) async {
          final sessionSnapshot = await transaction.get(currentRef);
          final eventSnapshot = await transaction.get(eventRef);
          final recordSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final reference in refs) {
            recordSnapshots.add(await transaction.get(reference));
          }
          _requireSameUser(actor.uid);
          final latest = _parseSessionSnapshot(
            sessionSnapshot,
            courseId: courseId,
            occurrenceId: occurrenceId,
          );
          if (latest.status != AttendanceSessionStatus.voiding ||
              latest.lastEventId != started.lastEventId ||
              latest.reason != normalizedReason ||
              latest.version != started.version) {
            throw const AttendanceFailure(AttendanceFailureKind.staleSession);
          }
          _validateVoidEvent(
            eventSnapshot,
            eventId: operationId,
            uid: actor.uid,
            reason: normalizedReason,
          );
          for (var index = 0; index < chunk.length; index++) {
            final expected = chunk[index];
            final snapshot = recordSnapshots[index];
            if (snapshot.exists) {
              final actual = AttendanceFirestoreCodec.recordFromMap(
                snapshot.data() ??
                    (throw const FormatException('Missing attendance record.')),
                expectedCourseId: courseId,
                expectedRecordId: expected.recordId,
              );
              if (actual.result == AttendanceSessionResult.voided &&
                  actual.visibility == AttendanceRecordVisibility.published &&
                  _sameRecordContent(actual, expected)) {
                continue;
              }
            }
            final voidData = AttendanceFirestoreCodec.voidedPublishedRecord(
              expected,
            );
            // Preserve the publication timestamp of an existing published row.
            // Replace the projection so minutes-mode segment details disappear.
            if (snapshot.exists &&
                snapshot.data()?['visibility'] == 'published') {
              voidData['publishedAt'] = snapshot.data()!['publishedAt'];
            }
            transaction.set(refs[index], voidData);
          }
          return latest;
        });
        knownSession = workingSession;
        _requireSameUser(actor.uid);
      }

      final verifiedSession = await _getOwnedSession(
        courseId,
        occurrenceId,
        actor.uid,
      );
      if (verifiedSession.status != AttendanceSessionStatus.voiding ||
          verifiedSession.lastEventId != started.lastEventId ||
          verifiedSession.reason != normalizedReason ||
          verifiedSession.version != started.version ||
          voidRecords.length != verifiedSession.rosterCount) {
        throw const AttendanceFailure(AttendanceFailureKind.staleSession);
      }
      for (final expected in voidRecords) {
        final snapshot = await _records(courseId)
            .doc(expected.recordId)
            .get(const GetOptions(source: Source.server));
        _requireSameUser(actor.uid);
        if (!snapshot.exists) {
          throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
        }
        final actual = AttendanceFirestoreCodec.recordFromMap(
          snapshot.data()!,
          expectedCourseId: courseId,
          expectedRecordId: expected.recordId,
        );
        if (actual.visibility != AttendanceRecordVisibility.published ||
            actual.result != AttendanceSessionResult.voided ||
            !_sameRecordContent(actual, expected)) {
          throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
        }
      }
      final finalSession = await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(sessionRef);
        final eventSnapshot = await transaction.get(eventRef);
        _requireSameUser(actor.uid);
        final current = _parseSessionSnapshot(
          snapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        _validateVoidEvent(
          eventSnapshot,
          eventId: operationId,
          uid: actor.uid,
          reason: normalizedReason,
        );
        if (current.status == AttendanceSessionStatus.voided &&
            current.version == verifiedSession.version + 1 &&
            current.reason == normalizedReason &&
            current.lastEventId == started.lastEventId) {
          return current;
        }
        if (current.version != verifiedSession.version ||
            current.status != AttendanceSessionStatus.voiding ||
            current.lastEventId != started.lastEventId ||
            current.reason != normalizedReason) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        transaction.update(sessionRef, {
          'status': AttendanceSessionStatus.voided.value,
          'voidedAt': FieldValue.serverTimestamp(),
          ..._versionUpdate(actor.uid, current.version),
        });
        return _copySession(
          current,
          status: AttendanceSessionStatus.voided,
          version: current.version + 1,
          updatedBy: actor.uid,
          lastMutationRosterEntryId: null,
          lastMutationKind: AttendanceMutationKind.voidSession,
          lastEventId: current.lastEventId,
          reason: normalizedReason,
        );
      });
      return finalSession;
    } on AttendanceFailure catch (error) {
      if (error.kind == AttendanceFailureKind.permissionDenied ||
          error.kind == AttendanceFailureKind.unauthenticated ||
          error.kind == AttendanceFailureKind.profileInvalid ||
          error.kind == AttendanceFailureKind.teacherRoleRequired) {
        rethrow;
      }
      if (operationStarted && knownSession != null) return knownSession;
      rethrow;
    } on FirebaseException catch (error) {
      final translated = _translateFirebase(error);
      if (translated.kind == AttendanceFailureKind.permissionDenied ||
          translated.kind == AttendanceFailureKind.unauthenticated) {
        throw translated;
      }
      if (operationStarted && knownSession != null) return knownSession;
      throw translated;
    } on FormatException {
      if (operationStarted && knownSession != null) return knownSession;
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  @override
  Future<AttendanceRosterMutationResult> correctRosterEntry({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required AttendanceRosterEntry replacement,
    required String reason,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      _validateEventId(operationId);
      final normalizedReason = reason.trim();
      if (normalizedReason.length > 500) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      final rowRef = _roster(
        courseId,
        occurrenceId,
      ).doc(replacement.rosterEntryId);
      final recordRef = _records(courseId)
          .doc('$occurrenceId|${replacement.rosterEntryId}');
      final eventRef = _events(courseId, occurrenceId).doc(operationId);
      return await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshot = await transaction.get(rowRef);
        final recordSnapshot = await transaction.get(recordRef);
        final eventSnapshot = await transaction.get(eventRef);
        _requireSameUser(actor.uid);
        final session = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        if (session.ownerUid != actor.uid) {
          throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
        }
        if (session.status != AttendanceSessionStatus.finalized ||
            session.rosterState != AttendanceRosterState.ready) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        final previous = _parseRosterSnapshot(
          rowSnapshot,
          session,
          replacement.rosterEntryId,
        );
        if (!_sameRosterIdentity(previous, replacement)) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
        }
        final retryOfCommittedCorrection =
            eventSnapshot.exists &&
            replacement.version < previous.version &&
            _sameRosterMarks(previous, replacement, session.mode);
        if (replacement.version != previous.version &&
            !retryOfCommittedCorrection) {
          throw AttendanceFailure(
            eventSnapshot.exists
                ? AttendanceFailureKind.conflict
                : AttendanceFailureKind.invalidInput,
          );
        }
        final segments = await _readSegmentsInTransaction(
          transaction,
          session,
          actor.uid,
        );
        final expectedRecord = AttendanceRecordCalculator.fromRosterEntry(
          session: session,
          entry: replacement,
          segments: segments,
        );
        if (eventSnapshot.exists) {
          final event = AttendanceFirestoreCodec.eventFromMap(
            eventSnapshot.data() ??
                (throw const FormatException('Missing audit event data.')),
            expectedEventId: operationId,
          );
          final storedRecord = _parseRecordSnapshot(
            recordSnapshot,
            courseId: courseId,
            recordId: recordRef.id,
          );
          if (event.kind == AttendanceEventKind.correction &&
              event.rosterEntryId == replacement.rosterEntryId &&
              event.reason == normalizedReason &&
              event.changedBy == actor.uid &&
              _entryMatchesEventNewValue(
                replacement,
                event.newValue,
                session.mode,
              ) &&
              _sameRosterMarks(previous, replacement, session.mode) &&
              _sameRecordContent(storedRecord, expectedRecord)) {
            return AttendanceRosterMutationResult(
              session: session,
              entry: previous,
              alreadyApplied: true,
            );
          }
          throw const AttendanceFailure(AttendanceFailureKind.conflict);
        }
        if (_sameRosterMarks(previous, replacement, session.mode)) {
          return AttendanceRosterMutationResult(
            session: session,
            entry: previous,
            alreadyApplied: true,
          );
        }
        if (!_hasExactlyOneMarkChange(previous, replacement, session.mode)) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
        }
        final oldValue = _changedRosterValue(
          previous,
          replacement,
          session.mode,
        );
        final newValue = _changedRosterValue(
          replacement,
          previous,
          session.mode,
        );
        final existingRecord = _parseRecordSnapshot(
          recordSnapshot,
          courseId: courseId,
          recordId: recordRef.id,
        );
        if (existingRecord.visibility != AttendanceRecordVisibility.published) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        final updatedEntry = _entryWithVersion(
          replacement,
          previous.version + 1,
          updatedBy: actor.uid,
        );
        final event = AttendanceSessionEvent(
          eventId: operationId,
          kind: AttendanceEventKind.correction,
          rosterEntryId: replacement.rosterEntryId,
          oldValue: oldValue,
          newValue: newValue,
          reason: normalizedReason,
          changedAt: null,
          changedBy: actor.uid,
        );
        transaction.update(
          rowRef,
          AttendanceFirestoreCodec.rosterDocument(
            entry: updatedEntry,
            mode: session.mode,
            uid: actor.uid,
          ),
        );
        transaction.update(
          recordRef,
          AttendanceFirestoreCodec.auditedRecordUpdate(expectedRecord),
        );
        transaction.set(
          eventRef,
          AttendanceFirestoreCodec.eventForCreate(event: event, uid: actor.uid),
        );
        transaction.update(sessionRef, {
          'lastMutationRosterEntryId': replacement.rosterEntryId,
          'lastMutationKind': AttendanceMutationKind.correction.value,
          'lastEventId': operationId,
          ..._versionUpdate(actor.uid, session.version),
        });
        return AttendanceRosterMutationResult(
          session: _copySession(
            session,
            version: session.version + 1,
            updatedBy: actor.uid,
            lastMutationRosterEntryId: replacement.rosterEntryId,
            lastMutationKind: AttendanceMutationKind.correction,
            lastEventId: operationId,
          ),
          entry: updatedEntry,
          alreadyApplied: false,
        );
      });
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    } on ArgumentError {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  @override
  Future<AttendanceRosterMutationResult> decideJustification({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String? segmentId,
    required String operationId,
    required AttendanceJustificationStatus status,
    required int justifiedUnits,
    required String reason,
  }) => _decideJustification(
    courseId: courseId,
    occurrenceId: occurrenceId,
    rosterEntryId: rosterEntryId,
    segmentId: segmentId,
    operationId: operationId,
    status: status,
    justifiedUnits: justifiedUnits,
    reason: reason,
  );

  Future<AttendanceRosterMutationResult> _decideJustification({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String? segmentId,
    required String operationId,
    required AttendanceJustificationStatus status,
    required int justifiedUnits,
    AttendanceJustificationRequest? submission,
    required String reason,
  }) async {
    try {
      _validateId(courseId);
      _validateId(occurrenceId);
      _validateId(rosterEntryId);
      _validateEventId(operationId);
      final normalizedReason = reason.trim();
      if (normalizedReason.length > 500) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      final actor = await _requireTeacher();
      final sessionRef = _session(courseId, occurrenceId);
      final rowRef = _roster(courseId, occurrenceId).doc(rosterEntryId);
      final recordRef = _records(courseId).doc('$occurrenceId|$rosterEntryId');
      final eventRef = _events(courseId, occurrenceId).doc(operationId);
      return await _firestore.runTransaction((transaction) async {
        final sessionSnapshot = await transaction.get(sessionRef);
        final rowSnapshot = await transaction.get(rowRef);
        final recordSnapshot = await transaction.get(recordRef);
        final eventSnapshot = await transaction.get(eventRef);
        final requestRef = submission == null
            ? null
            : _course(courseId)
                  .collection('attendance_requests')
                  .doc(submission.id);
        final requestSnapshot = requestRef == null
            ? null
            : await transaction.get(requestRef);
        _requireSameUser(actor.uid);
        if (submission != null && requestSnapshot != null) {
          final currentRequest = _parseRequest(requestSnapshot);
          if (currentRequest.sessionId != occurrenceId ||
              currentRequest.rosterEntryId != rosterEntryId ||
              currentRequest.segmentId != segmentId) {
            throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
          }
          if (currentRequest.status != AttendanceRequestStatus.pending) {
            if ((currentRequest.status == AttendanceRequestStatus.approved) !=
                (status == AttendanceJustificationStatus.justified)) {
              throw const AttendanceFailure(AttendanceFailureKind.conflict);
            }
            return AttendanceRosterMutationResult(
              session: _parseSessionSnapshot(
                sessionSnapshot,
                courseId: courseId,
                occurrenceId: occurrenceId,
              ),
              entry: _parseRosterSnapshot(
                rowSnapshot,
                _parseSessionSnapshot(
                  sessionSnapshot,
                  courseId: courseId,
                  occurrenceId: occurrenceId,
                ),
                rosterEntryId,
              ),
              alreadyApplied: true,
            );
          }
        }
        final session = _parseSessionSnapshot(
          sessionSnapshot,
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        if (session.ownerUid != actor.uid) {
          throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
        }
        if (session.status != AttendanceSessionStatus.finalized ||
            session.rosterState != AttendanceRosterState.ready) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        final previous = _parseRosterSnapshot(
          rowSnapshot,
          session,
          rosterEntryId,
        );
        final oldMark = _markForEntry(previous, session.mode, segmentId);
        if ((oldMark.mark != AttendanceMark.absent ||
                oldMark.absentUnits <= 0) &&
            !(submission != null &&
                oldMark.mark == AttendanceMark.present &&
                status == AttendanceJustificationStatus.notAccepted)) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        if (submission != null) {
          justifiedUnits = status == AttendanceJustificationStatus.justified
              ? oldMark.absentUnits
              : 0;
        }
        if (status == AttendanceJustificationStatus.none ||
            justifiedUnits < 0 ||
            justifiedUnits > oldMark.absentUnits ||
            status == AttendanceJustificationStatus.justified &&
                justifiedUnits == 0 ||
            status != AttendanceJustificationStatus.justified &&
                justifiedUnits != 0) {
          throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
        }
        final nextMark = oldMark.mark == AttendanceMark.present
            ? oldMark
            : AttendanceRosterMark(
                mark: oldMark.mark,
                absentUnits: oldMark.absentUnits,
                justificationStatus: status,
                justifiedUnits: justifiedUnits,
              );
        final currentValue = _markValue(oldMark);
        final nextValue = _markValue(nextMark);
        final oldValue = {
          'mark': currentValue,
          if (submission != null) 'requestStatus': 'pending',
        };
        final newValue = {
          'mark': nextValue,
          if (submission != null)
            'requestStatus': status == AttendanceJustificationStatus.justified
                ? 'approved'
                : 'rejected',
        };
        final segments = await _readSegmentsInTransaction(
          transaction,
          session,
          actor.uid,
        );
        final nextEntry = _replaceEntryMark(
          previous,
          session.mode,
          segmentId,
          nextMark,
        );
        final expectedRecord = AttendanceRecordCalculator.fromRosterEntry(
          session: session,
          entry: nextEntry,
          segments: segments,
        );
        if (eventSnapshot.exists) {
          final event = AttendanceFirestoreCodec.eventFromMap(
            eventSnapshot.data() ??
                (throw const FormatException('Missing audit event data.')),
            expectedEventId: operationId,
          );
          final storedRecord = _parseRecordSnapshot(
            recordSnapshot,
            courseId: courseId,
            recordId: recordRef.id,
          );
          if (event.kind == AttendanceEventKind.justification &&
              event.rosterEntryId == rosterEntryId &&
              event.reason == normalizedReason &&
              event.changedBy == actor.uid &&
              _sameFlatMap(event.newValue, newValue) &&
              _sameMark(
                _markForEntry(previous, session.mode, segmentId),
                nextMark,
              ) &&
              _sameRecordContent(storedRecord, expectedRecord)) {
            return AttendanceRosterMutationResult(
              session: session,
              entry: previous,
              alreadyApplied: true,
            );
          }
          throw const AttendanceFailure(AttendanceFailureKind.conflict);
        }
        if (submission == null && _sameMark(oldMark, nextMark)) {
          return AttendanceRosterMutationResult(
            session: session,
            entry: previous,
            alreadyApplied: true,
          );
        }
        final existingRecord = _parseRecordSnapshot(
          recordSnapshot,
          courseId: courseId,
          recordId: recordRef.id,
        );
        if (existingRecord.visibility != AttendanceRecordVisibility.published) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        final updatedEntry = _entryWithVersion(
          nextEntry,
          previous.version + 1,
          updatedBy: actor.uid,
        );
        final event = AttendanceSessionEvent(
          eventId: operationId,
          kind: AttendanceEventKind.justification,
          rosterEntryId: rosterEntryId,
          oldValue: oldValue,
          newValue: newValue,
          reason: normalizedReason,
          changedAt: null,
          changedBy: actor.uid,
        );
        if (requestRef != null) {
          transaction.update(requestRef, {
            'status': status == AttendanceJustificationStatus.justified
                ? 'approved'
                : 'rejected',
            'decidedAt': FieldValue.serverTimestamp(),
            'decidedBy': actor.uid,
            'eventId': operationId,
          });
        }
        transaction.update(
          rowRef,
          AttendanceFirestoreCodec.rosterDocument(
            entry: updatedEntry,
            mode: session.mode,
            uid: actor.uid,
          ),
        );
        transaction.update(
          recordRef,
          AttendanceFirestoreCodec.auditedRecordUpdate(expectedRecord),
        );
        transaction.set(
          eventRef,
          AttendanceFirestoreCodec.eventForCreate(event: event, uid: actor.uid),
        );
        transaction.update(sessionRef, {
          'lastMutationRosterEntryId': rosterEntryId,
          'lastMutationKind': AttendanceMutationKind.justification.value,
          'lastEventId': operationId,
          ..._versionUpdate(actor.uid, session.version),
        });
        return AttendanceRosterMutationResult(
          session: _copySession(
            session,
            version: session.version + 1,
            updatedBy: actor.uid,
            lastMutationRosterEntryId: rosterEntryId,
            lastMutationKind: AttendanceMutationKind.justification,
            lastEventId: operationId,
          ),
          entry: updatedEntry,
          alreadyApplied: false,
        );
      });
    } on AttendanceFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    } on ArgumentError {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  @override
  Future<AttendanceRecordPage> listMyAttendanceRecords({
    required String courseId,
    AttendanceRecordCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      _validateId(courseId);
      _validatePageSize(pageSize);
      final actor = await _requireStudent();
      final enrollment = await _enrollments.getCourseEnrollment(
        courseId: courseId,
        studentUid: actor.uid,
      );
      _requireSameUser(actor.uid);
      if (enrollment.status != 'active' ||
          enrollment.ownerUid.isEmpty ||
          enrollment.studentUid != actor.uid) {
        throw const AttendanceFailure(AttendanceFailureKind.notFound);
      }
      final rosterEntryId =
          enrollment.rosterEntryId == null ||
              enrollment.rosterEntryId!.trim().isEmpty
          ? 'legacy:${actor.uid}'
          : enrollment.rosterEntryId!;
      Query<Map<String, dynamic>> query = _records(courseId)
          .where('rosterEntryId', isEqualTo: rosterEntryId)
          .where(
            'visibility',
            isEqualTo: AttendanceRecordVisibility.published.value,
          )
          .orderBy('effectiveDate', descending: true)
          .orderBy(FieldPath.documentId, descending: true);
      if (cursor != null) {
        query = query.startAfter([
          Timestamp.fromDate(cursor.effectiveDate.toUtcTimestamp()),
          cursor.recordId,
        ]);
      }
      final snapshot = await query
          .limit(pageSize + 1)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(actor.uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final records = visible
          .map(
            (document) => AttendanceFirestoreCodec.recordFromMap(
              document.data(),
              expectedCourseId: courseId,
              expectedRecordId: document.id,
            ),
          )
          .toList(growable: false);
      if (records.any(
        (record) =>
            record.rosterEntryId != rosterEntryId ||
            record.visibility != AttendanceRecordVisibility.published,
      )) {
        throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
      }
      final last = records.isEmpty ? null : records.last;
      return AttendanceRecordPage(
        items: records,
        nextCursor: hasMore && last != null
            ? AttendanceRecordCursor(
                effectiveDate: last.effectiveDate,
                recordId: last.recordId,
              )
            : null,
      );
    } on AttendanceFailure {
      rethrow;
    } on EnrollmentFailure catch (error) {
      throw _translateEnrollmentFailure(error);
    } on FirebaseException catch (error) {
      throw _translateFirebase(error);
    } on FormatException {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
  }

  CollectionReference<Map<String, dynamic>> _requests(String courseId) =>
      _course(courseId).collection('attendance_requests');

  AttendanceJustificationRequest _parseRequest(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null ||
        data.keys.toSet().difference({
          'sessionId',
          'rosterEntryId',
          'studentUid',
          'segmentId',
          'text',
          'status',
          'createdAt',
          'decidedAt',
          'decidedBy',
          'eventId',
        }).isNotEmpty ||
        data['sessionId'] is! String ||
        data['rosterEntryId'] is! String ||
        data['studentUid'] is! String ||
        data['text'] is! String ||
        !['pending', 'approved', 'rejected'].contains(data['status']) ||
        (data['segmentId'] != null && data['segmentId'] is! String)) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidData);
    }
    return AttendanceJustificationRequest(
      id: snapshot.id,
      sessionId: data['sessionId'],
      rosterEntryId: data['rosterEntryId'],
      studentUid: data['studentUid'],
      segmentId: data['segmentId'],
      text: data['text'],
      status: AttendanceRequestStatus.values.byName(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
      decidedBy: data['decidedBy'],
    );
  }

  Future<String> _ownRequestIdentity(AttendanceRecord record) async {
    final actor = await _requireStudent();
    final enrollment = await _enrollments.getCourseEnrollment(
      courseId: record.courseId,
      studentUid: actor.uid,
    );
    _requireSameUser(actor.uid);
    final identity = enrollment.rosterEntryId ?? 'legacy:${actor.uid}';
    if (enrollment.status != 'active' || identity != record.rosterEntryId) {
      throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
    }
    return actor.uid;
  }

  @override
  Future<AttendanceJustificationRequest?> getMyJustification({
    required AttendanceRecord record,
    required String? segmentId,
  }) async {
    try {
      final uid = await _ownRequestIdentity(record);
      final ref = _requests(record.courseId).doc(
        AttendanceJustificationRequest.documentId(
          record.sessionId,
          record.rosterEntryId,
          segmentId,
        ),
      );
      final result = await ref.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      return result.exists ? _parseRequest(result) : null;
    } on FirebaseException catch (e) {
      throw _translateFirebase(e);
    }
  }

  @override
  Future<AttendanceJustificationRequest> submitJustification({
    required AttendanceRecord record,
    required String? segmentId,
    required String text,
  }) async {
    try {
      final uid = await _ownRequestIdentity(record);
      final message = text.trim();
      if (message.isEmpty || message.length > 500) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
      }
      final ref = _requests(record.courseId).doc(
        AttendanceJustificationRequest.documentId(
          record.sessionId,
          record.rosterEntryId,
          segmentId,
        ),
      );
      return await _firestore.runTransaction((tx) async {
        final existing = await tx.get(ref);
        final source = await tx.get(
          _records(record.courseId).doc(record.recordId),
        );
        _requireSameUser(uid);
        if (existing.exists) return _parseRequest(existing);
        final actual = _parseRecordSnapshot(
          source,
          courseId: record.courseId,
          recordId: record.recordId,
        );
        final validAbsence = actual.mode == AttendanceMode.meeting
            ? segmentId == null &&
                  actual.absentUnits > 0 &&
                  actual.justifiedUnits == 0
            : actual.segments.any(
                (s) =>
                    s.segmentId == segmentId &&
                    s.mark == AttendanceMark.absent &&
                    s.absentMinutes > 0 &&
                    s.justifiedMinutes == 0,
              );
        if (!validAbsence ||
            actual.result == AttendanceSessionResult.voided ||
            actual.visibility != AttendanceRecordVisibility.published) {
          throw const AttendanceFailure(
            AttendanceFailureKind.invalidTransition,
          );
        }
        tx.set(ref, {
          'sessionId': actual.sessionId,
          'rosterEntryId': actual.rosterEntryId,
          'studentUid': uid,
          'segmentId': segmentId,
          'text': message,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'decidedAt': null,
          'decidedBy': null,
          'eventId': null,
        });
        return AttendanceJustificationRequest(
          id: ref.id,
          sessionId: actual.sessionId,
          rosterEntryId: actual.rosterEntryId,
          studentUid: uid,
          segmentId: segmentId,
          text: message,
          status: AttendanceRequestStatus.pending,
        );
      });
    } on FirebaseException catch (e) {
      throw _translateFirebase(e);
    }
  }

  @override
  Future<List<AttendanceJustificationRequest>> listJustificationRequests({
    required String courseId,
    required String occurrenceId,
  }) async {
    try {
      final actor = await _requireTeacher();
      await _requireOwnedCourse(courseId, actor.uid);
      final result = <AttendanceJustificationRequest>[];
      String? cursor;
      while (true) {
        Query<Map<String, dynamic>> query = _requests(courseId)
            .where('sessionId', isEqualTo: occurrenceId)
            .orderBy(FieldPath.documentId)
            .limit(100);
        if (cursor != null) query = query.startAfter([cursor]);
        final page = await query.get(const GetOptions(source: Source.server));
        _requireSameUser(actor.uid);
        result.addAll(page.docs.map(_parseRequest));
        if (page.docs.length < 100) break;
        cursor = page.docs.last.id;
      }
      return result;
    } on FirebaseException catch (e) {
      throw _translateFirebase(e);
    }
  }

  @override
  Future<void> decideJustificationRequest({
    required String courseId,
    required AttendanceJustificationRequest request,
    required bool approve,
  }) async {
    await _decideJustification(
      courseId: courseId,
      occurrenceId: request.sessionId,
      rosterEntryId: request.rosterEntryId,
      segmentId: request.segmentId,
      operationId: _events(courseId, request.sessionId).doc().id,
      status: approve
          ? AttendanceJustificationStatus.justified
          : AttendanceJustificationStatus.notAccepted,
      justifiedUnits: 0,
      reason: '',
      submission: request,
    );
  }

  @override
  Future<AttendanceSession> restoreSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    final trace = AttendanceOperationTrace(
      'restaurar asistencia',
      onTiming: onTiming,
    )..start('comprobar cuenta y sesión');
    try {
      final actor = await _requireTeacher();
      final ref = _session(courseId, occurrenceId);
      var session = await _getOwnedSession(courseId, occurrenceId, actor.uid);
      if (session.status == AttendanceSessionStatus.finalized &&
          session.lastMutationKind == AttendanceMutationKind.restore) {
        return session;
      }
      if (session.finalizedAt == null ||
          ![
            AttendanceSessionStatus.voided,
            AttendanceSessionStatus.restoring,
          ].contains(session.status)) {
        throw const AttendanceFailure(AttendanceFailureKind.invalidTransition);
      }
      if (session.status == AttendanceSessionStatus.voided) {
        final eventRef = _events(courseId, occurrenceId).doc();
        session = await _firestore.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          final current = _parseSessionSnapshot(
            snapshot,
            courseId: courseId,
            occurrenceId: occurrenceId,
          );
          if (current.status == AttendanceSessionStatus.restoring) {
            return current;
          }
          if (current.status != AttendanceSessionStatus.voided ||
              current.finalizedAt == null) {
            throw const AttendanceFailure(
              AttendanceFailureKind.invalidTransition,
            );
          }
          tx.set(
            eventRef,
            AttendanceFirestoreCodec.eventForCreate(
              event: AttendanceSessionEvent(
                eventId: eventRef.id,
                kind: AttendanceEventKind.restore,
                changedAt: null,
                changedBy: actor.uid,
                reason: '',
                oldValue: {'status': 'voided'},
                newValue: {'status': 'finalized'},
              ),
              uid: actor.uid,
            ),
          );
          tx.update(ref, {
            'status': 'restoring',
            'lastMutationKind': 'restore',
            'lastEventId': eventRef.id,
            'lastMutationRosterEntryId': null,
            ..._versionUpdate(actor.uid, current.version),
          });
          return _copySession(
            current,
            status: AttendanceSessionStatus.restoring,
            version: current.version + 1,
            updatedBy: actor.uid,
            lastMutationKind: AttendanceMutationKind.restore,
            lastEventId: eventRef.id,
            lastMutationRosterEntryId: null,
          );
        });
      }
      trace.start('leer marcas conservadas');
      final roster = await _loadAllRoster(session, actor.uid);
      final segments = await _loadAllSegments(session, actor.uid);
      if (roster.length != session.rosterCount ||
          roster.any(
            (e) => session.mode == AttendanceMode.meeting
                ? e.meetingMark!.mark == AttendanceMark.unmarked
                : e.segmentMarks.values.any(
                    (m) => m.mark == AttendanceMark.unmarked,
                  ),
          )) {
        throw const AttendanceFailure(AttendanceFailureKind.incompleteRoster);
      }
      final expected = roster
          .map(
            (entry) => AttendanceRecordCalculator.fromRosterEntry(
              session: session,
              entry: entry,
              segments: segments,
            ),
          )
          .toList();
      trace.start('restaurar resultados');
      for (
        var offset = 0;
        offset < expected.length;
        offset += _writeChunkSize
      ) {
        final chunk = expected.skip(offset).take(_writeChunkSize).toList();
        await _firestore.runTransaction((tx) async {
          final current = _parseSessionSnapshot(
            await tx.get(ref),
            courseId: courseId,
            occurrenceId: occurrenceId,
          );
          final snapshots = await Future.wait(
            chunk.map((r) => tx.get(_records(courseId).doc(r.recordId))),
          );
          _requireSameUser(actor.uid);
          if (current.status != AttendanceSessionStatus.restoring ||
              current.version != session.version ||
              current.lastEventId != session.lastEventId) {
            throw const AttendanceFailure(AttendanceFailureKind.staleSession);
          }
          for (var i = 0; i < chunk.length; i++) {
            final actual = _parseRecordSnapshot(
              snapshots[i],
              courseId: courseId,
              recordId: chunk[i].recordId,
            );
            if (_sameRecordContent(actual, chunk[i])) continue;
            final data = AttendanceFirestoreCodec.stagedRecord(chunk[i]);
            data['visibility'] = 'published';
            data['publishedAt'] = snapshots[i].data()!['publishedAt'];
            data['updatedAt'] = FieldValue.serverTimestamp();
            tx.set(_records(courseId).doc(chunk[i].recordId), data);
          }
        });
      }
      trace.start('verificar resultados restaurados');
      await _verifyRecordSet(
        session: session,
        records: expected,
        uid: actor.uid,
        allowStaged: false,
        allowPublished: true,
      );
      return await _firestore.runTransaction((tx) async {
        final current = _parseSessionSnapshot(
          await tx.get(ref),
          courseId: courseId,
          occurrenceId: occurrenceId,
        );
        _requireSameUser(actor.uid);
        if (current.status == AttendanceSessionStatus.finalized &&
            current.lastEventId == session.lastEventId) {
          return current;
        }
        if (current.status != AttendanceSessionStatus.restoring ||
            current.version != session.version ||
            current.lastEventId != session.lastEventId) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
        tx.update(ref, {
          'status': 'finalized',
          ..._versionUpdate(actor.uid, current.version),
        });
        return _copySession(
          current,
          status: AttendanceSessionStatus.finalized,
          version: current.version + 1,
          updatedBy: actor.uid,
          lastMutationKind: AttendanceMutationKind.restore,
          lastEventId: current.lastEventId,
          lastMutationRosterEntryId: null,
        );
      });
    } on FirebaseException catch (e) {
      throw _translateFirebase(e);
    } finally {
      trace.finish();
    }
  }

  Future<_Actor> _requireTeacher() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AttendanceFailure(AttendanceFailureKind.unauthenticated);
    }
    if (!user.emailVerified) {
      throw const AttendanceFailure(AttendanceFailureKind.emailNotVerified);
    }
    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(user.uid);
    final data = profile.data();
    if (!profile.exists || data == null || !_validProfile(data, user)) {
      throw const AttendanceFailure(AttendanceFailureKind.profileInvalid);
    }
    final roles = data['roles'] as List<Object?>;
    if (!roles.contains('teacher')) {
      throw const AttendanceFailure(AttendanceFailureKind.teacherRoleRequired);
    }
    return _Actor(user.uid, user.email!);
  }

  Future<_Actor> _requireStudent() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AttendanceFailure(AttendanceFailureKind.unauthenticated);
    }
    if (!user.emailVerified) {
      throw const AttendanceFailure(AttendanceFailureKind.emailNotVerified);
    }
    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(user.uid);
    final data = profile.data();
    if (!profile.exists || data == null || !_validProfile(data, user)) {
      throw const AttendanceFailure(AttendanceFailureKind.profileInvalid);
    }
    final roles = data['roles'] as List<Object?>;
    if (!roles.contains('student')) {
      throw const AttendanceFailure(AttendanceFailureKind.studentRoleRequired);
    }
    return _Actor(user.uid, user.email!);
  }

  bool _validProfile(Map<String, dynamic> profile, User user) {
    const expected = {'name', 'email', 'studentCode', 'roles'};
    final roles = profile['roles'];
    final code = profile['studentCode'];
    return profile.keys.toSet().difference(expected).isEmpty &&
        profile.keys.toSet().containsAll(expected) &&
        profile['name'] is String &&
        (profile['name'] as String).trim().isNotEmpty &&
        (profile['name'] as String).length <= 100 &&
        profile['email'] == user.email &&
        (code == null ||
            code is String && code.isNotEmpty && code.length <= 40) &&
        roles is List &&
        roles.isNotEmpty &&
        roles.length <= 3 &&
        roles.every(
          (role) =>
              role is String &&
              const {'student', 'teacher', 'admin'}.contains(role),
        ) &&
        roles.toSet().length == roles.length;
  }

  Future<void> _requireOwnedCourse(String courseId, String uid) async {
    final snapshot = await _course(courseId)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    _verifyCourseOwnerSnapshot(snapshot, uid);
  }

  void _verifyCourseOwnerSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String uid,
  ) {
    if (!snapshot.exists || snapshot.data()?['ownerUid'] != uid) {
      throw const AttendanceFailure(AttendanceFailureKind.notFound);
    }
  }

  void _requireSameUser(String expectedUid) {
    if (_auth.currentUser?.uid != expectedUid) {
      throw const AttendanceFailure(AttendanceFailureKind.unauthenticated);
    }
  }

  void _validateId(String value) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > _pageSize) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  void _validateLateReason(AttendanceOccurrence occurrence, String? reason) {
    if (reason != null && reason.length > 500) {
      throw const AttendanceFailure(AttendanceFailureKind.invalidInput);
    }
  }

  bool _sameOccurrence(
    AttendanceSession session,
    AttendanceOccurrence occurrence,
  ) =>
      session.courseId == occurrence.courseId &&
      session.occurrenceId == occurrence.id &&
      session.occurrenceKind == occurrence.kind &&
      session.scheduledDate == occurrence.scheduledDate &&
      session.effectiveDate == occurrence.effectiveDate &&
      session.startMinute == occurrence.startMinute &&
      session.endMinute == occurrence.endMinute &&
      session.timezone == occurrence.timezone;

  void _verifyOccurrenceStillCurrent(
    AttendanceOccurrence occurrence, {
    required DocumentSnapshot<Map<String, dynamic>> calendarSnapshot,
  }) {
    if (occurrence.kind == AttendanceOccurrenceKind.planned) {
      if (calendarSnapshot.exists) {
        final change = AttendanceFirestoreCodec.calendarChangeFromMap(
          calendarSnapshot.data() ??
              (throw const FormatException('Missing calendar change data.')),
          expectedOccurrenceId: occurrence.id,
        );
        if (change.kind == AttendanceCalendarChangeKind.cancelled ||
            change.originalDate != occurrence.scheduledDate ||
            change.effectiveDate != occurrence.effectiveDate ||
            change.startMinute != occurrence.startMinute ||
            change.endMinute != occurrence.endMinute) {
          throw const AttendanceFailure(AttendanceFailureKind.staleSession);
        }
      }
      return;
    }
    if (!calendarSnapshot.exists) {
      throw const AttendanceFailure(AttendanceFailureKind.staleSession);
    }
    final change = AttendanceFirestoreCodec.calendarChangeFromMap(
      calendarSnapshot.data() ??
          (throw const FormatException('Missing calendar change data.')),
      expectedOccurrenceId: occurrence.id,
    );
    if (change.kind == AttendanceCalendarChangeKind.cancelled ||
        change.effectiveDate != occurrence.effectiveDate ||
        change.startMinute != occurrence.startMinute ||
        change.endMinute != occurrence.endMinute) {
      throw const AttendanceFailure(AttendanceFailureKind.staleSession);
    }
  }

  String _rosterFingerprint(CourseRosterSnapshot snapshot) {
    final rows = <String>[];
    for (final row in [
      ...snapshot.activeEnrollments,
      ...snapshot.withdrawnEnrollments,
    ]) {
      rows.add(
        'E|${row.courseId}|${row.studentUid}|${row.ownerUid}|${row.status}|${row.email}|${row.studentCode}|${row.name}|${row.rosterEntryId}|${row.effectiveStartDate?.isoDate}|${row.createdAt?.toUtc().toIso8601String()}|${row.lastStatusEventId}|${row.lastStatusChangedAt?.toUtc().toIso8601String()}',
      );
    }
    for (final row in [
      ...snapshot.pendingEnrollments,
      ...snapshot.withdrawnPendingEnrollments,
    ]) {
      rows.add(
        'P|${row.courseId}|${row.ownerUid}|${row.status}|${row.email}|${row.studentCode}|${row.name}|${row.rosterEntryId}|${row.studentUid}|${row.effectiveStartDate.isoDate}|${row.authorizedAt.toUtc().toIso8601String()}|${row.linkedAt?.toUtc().toIso8601String()}|${row.lastEventId}|${row.lastStatusChangedAt?.toUtc().toIso8601String()}',
      );
    }
    rows.sort();
    return rows.join('\n');
  }

  bool _sameLinkedAuthorization(
    PendingEnrollment? first,
    PendingEnrollment? second,
  ) {
    if (first == null || second == null) return first == null && second == null;
    return first.courseId == second.courseId &&
        first.ownerUid == second.ownerUid &&
        first.status == second.status &&
        first.email == second.email &&
        first.studentCode == second.studentCode &&
        first.name == second.name &&
        first.rosterEntryId == second.rosterEntryId &&
        first.studentUid == second.studentUid &&
        first.effectiveStartDate == second.effectiveStartDate &&
        first.authorizedAt == second.authorizedAt &&
        first.linkedAt == second.linkedAt &&
        first.lastEventId == second.lastEventId &&
        first.lastStatusChangedAt == second.lastStatusChangedAt;
  }

  AttendanceFailure _translateEnrollmentFailure(EnrollmentFailure error) =>
      switch (error.kind) {
        EnrollmentFailureKind.permissionDenied => const AttendanceFailure(
          AttendanceFailureKind.permissionDenied,
        ),
        EnrollmentFailureKind.network => const AttendanceFailure(
          AttendanceFailureKind.unavailable,
        ),
        EnrollmentFailureKind.unauthenticated => const AttendanceFailure(
          AttendanceFailureKind.unauthenticated,
        ),
        EnrollmentFailureKind.emailNotVerified => const AttendanceFailure(
          AttendanceFailureKind.emailNotVerified,
        ),
        EnrollmentFailureKind.profileInvalid => const AttendanceFailure(
          AttendanceFailureKind.profileInvalid,
        ),
        EnrollmentFailureKind.teacherRoleRequired => const AttendanceFailure(
          AttendanceFailureKind.teacherRoleRequired,
        ),
        EnrollmentFailureKind.invalidData => const AttendanceFailure(
          AttendanceFailureKind.rosterHistoryNeedsReview,
        ),
        _ => const AttendanceFailure(AttendanceFailureKind.incompleteRoster),
      };

  AttendanceFailure _translateFirebase(FirebaseException error) =>
      switch (error.code) {
        'permission-denied' => const AttendanceFailure(
          AttendanceFailureKind.permissionDenied,
        ),
        'unauthenticated' => const AttendanceFailure(
          AttendanceFailureKind.unauthenticated,
        ),
        'not-found' => const AttendanceFailure(AttendanceFailureKind.notFound),
        'failed-precondition' => const AttendanceFailure(
          AttendanceFailureKind.unavailable,
          message: 'Firestore todavía no permite completar esta consulta.',
        ),
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
          const AttendanceFailure(AttendanceFailureKind.unavailable),
        _ => const AttendanceFailure(AttendanceFailureKind.unavailable),
      };

  Map<String, dynamic> _resolveServerSentinelsForImmediateResult(
    Map<String, Object?> input,
  ) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      result[entry.key] = entry.value is FieldValue ? null : entry.value;
    }
    return result;
  }
}

class _Actor {
  const _Actor(this.uid, this.email);

  final String uid;
  final String email;
}

class _RosterBuildInput {
  const _RosterBuildInput({
    required this.snapshot,
    required this.enrollmentEventsByStudentUid,
    required this.pendingEventsByEmail,
    required this.linkedAuthorizationsByStudentUid,
  });

  final CourseRosterSnapshot snapshot;
  final Map<String, List<EnrollmentStatusEvent>> enrollmentEventsByStudentUid;
  final Map<String, List<PendingEnrollmentStatusEvent>> pendingEventsByEmail;
  final Map<String, PendingEnrollment> linkedAuthorizationsByStudentUid;
}
