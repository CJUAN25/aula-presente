import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../schedule/domain/academic_date.dart';
import '../../schedule/domain/course_schedule.dart';
import '../../schedule/domain/weekly_block.dart';
import '../../attendance/domain/attendance_mode.dart';
import '../domain/course.dart';
import '../domain/course_creation_result.dart';
import '../domain/course_cursor.dart';
import '../domain/course_draft.dart';
import '../domain/course_failure.dart';
import '../domain/course_page.dart';
import '../domain/course_repository.dart';

/// Persists and reads a teacher's own courses from Cloud Firestore.
///
/// The owner UID always comes from Firebase Authentication. Server rules remain
/// authoritative for teacher access, owner filtering, and immutable courses.
class FirestoreCourseRepository implements CourseRepository {
  FirestoreCourseRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const Set<String> _parentFields = {
    'ownerUid',
    'subject',
    'group',
    'period',
    'program',
    'timezone',
    'startDate',
    'endDate',
    'weeklyBlockIds',
    'status',
    'schemaVersion',
    'createdAt',
    'updatedAt',
  };

  static const Set<String> _weeklyBlockFields = {
    'weekday',
    'startMinute',
    'endMinute',
    'room',
    'order',
  };

  static final RegExp _blockIdPattern = RegExp(r'^[A-Za-z0-9_-]{20,40}$');

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  CollectionReference<Map<String, dynamic>> _weeklyBlocks(String courseId) =>
      _courses.doc(courseId).collection('weekly_blocks');

  @override
  Future<CoursePage> getOwnCoursePage({
    CourseCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      if (pageSize < 1 || pageSize > 100) {
        throw const CourseFailure(CourseFailureKind.invalidCourse);
      }
      final uid = await _requireTeacherUid();
      return await _getOwnCoursePageFor(
        uid,
        cursor: cursor,
        pageSize: pageSize,
      );
    } on CourseFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseFailure(CourseFailureKind.invalidCourse, cause: error);
    }
  }

  @override
  Future<List<Course>> getAllOwnCourses({int pageSize = 25}) async {
    try {
      if (pageSize < 1 || pageSize > 100) {
        throw const CourseFailure(CourseFailureKind.invalidCourse);
      }
      final uid = await _requireTeacherUid();
      final courses = <Course>[];
      CourseCursor? cursor;
      do {
        final page = await _getOwnCoursePageFor(
          uid,
          cursor: cursor,
          pageSize: pageSize,
        );
        courses.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      _requireSameUser(uid);
      return List.unmodifiable(courses);
    } on CourseFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseFailure(CourseFailureKind.invalidCourse, cause: error);
    }
  }

  Future<CoursePage> _getOwnCoursePageFor(
    String uid, {
    required CourseCursor? cursor,
    required int pageSize,
  }) async {
    _requireSameUser(uid);
    Query<Map<String, dynamic>> query = _courses
        .where('ownerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize + 1);
    if (cursor != null) {
      query = query.startAfter([
        Timestamp.fromDate(cursor.createdAt),
        cursor.documentId,
      ]);
    }

    final snapshot = await query.get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    final hasMore = snapshot.docs.length > pageSize;
    final visibleDocs = snapshot.docs.take(pageSize).toList(growable: false);
    final items = <Course>[];
    for (final document in visibleDocs) {
      _requireSameUser(uid);
      final blockSnapshot = await _weeklyBlocks(document.id)
          .orderBy('order')
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      items.add(
        _courseFromDocument(
          document,
          blockDocuments: blockSnapshot.docs
              .cast<DocumentSnapshot<Map<String, dynamic>>>(),
          expectedOwnerUid: uid,
        ),
      );
    }
    final last = hasMore && visibleDocs.isNotEmpty ? items.last : null;

    return CoursePage(
      items: items,
      nextCursor: last?.createdAt == null
          ? null
          : CourseCursor(createdAt: last!.createdAt!, documentId: last.id),
    );
  }

  /// Reads an enrolled student's authorized course and its canonical blocks.
  /// Firestore rules check the student's enrollment for both parent and child
  /// reads; this method never widens teacher course-list queries.
  Future<Course> getEnrolledCourse(String courseId) async {
    try {
      if (courseId.isEmpty || courseId.contains('/')) {
        throw const CourseFailure(CourseFailureKind.invalidCourse);
      }
      final user = _auth.currentUser;
      if (user == null) {
        throw const CourseFailure(CourseFailureKind.unauthenticated);
      }
      final uid = user.uid;
      if (!user.emailVerified) {
        throw const CourseFailure(CourseFailureKind.emailNotVerified);
      }
      final reference = _courses.doc(courseId);
      final document = await reference.get(
        const GetOptions(source: Source.server),
      );
      _requireSameUser(uid);
      final data = document.data();
      if (!document.exists || data == null || data['ownerUid'] is! String) {
        throw const CourseFailure(CourseFailureKind.invalidCourse);
      }
      final blocks = await _weeklyBlocks(courseId)
          .orderBy('order')
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      return _courseFromDocument(
        document,
        blockDocuments: blocks.docs
            .cast<DocumentSnapshot<Map<String, dynamic>>>(),
        expectedOwnerUid: data['ownerUid'] as String,
      );
    } on CourseFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseFailure(CourseFailureKind.invalidCourse, cause: error);
    }
  }

  @override
  Future<CourseCreationResult> createCourse(CourseDraft draft) async {
    try {
      final normalizedDraft = draft.normalized();
      _validateDocumentId(normalizedDraft.id);
      if (normalizedDraft.attendanceMode == null) {
        throw const CourseFailure(CourseFailureKind.invalidCourse);
      }
      final uid = await _requireTeacherUid();
      final reference = _courses.doc(normalizedDraft.id);
      final attendanceConfigReference = reference
          .collection('attendance_config')
          .doc('current');
      final expectedFields = normalizedDraft.canonicalFields;
      final expectedBlockDocuments =
          normalizedDraft.canonicalWeeklyBlockDocuments;

      // The transaction reads the stable ID first. It returns the confirmed
      // create result without a read after commit, so a later permission or
      // navigation error cannot turn a committed write into a reported failure.
      return await _firestore.runTransaction<CourseCreationResult>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final existing = await transaction.get(reference);
        final existingAttendanceConfig = await transaction.get(
          attendanceConfigReference,
        );
        _requireSameUser(uid);

        if (existing.exists) {
          final data = existing.data();
          if (data == null || data['ownerUid'] != uid) {
            throw const CourseFailure(CourseFailureKind.permissionDenied);
          }
          // A retry must inspect children named by the stored parent, never
          // alternate IDs from the incoming draft. Rules intentionally deny
          // reads of child IDs that are not listed by an existing course.
          final rawBlockIds = data['weeklyBlockIds'];
          if (rawBlockIds is! List ||
              rawBlockIds.any((blockId) => blockId is! String)) {
            throw const CourseFailure(CourseFailureKind.idempotencyConflict);
          }
          final storedBlockIds = rawBlockIds.cast<String>();
          for (final blockId in storedBlockIds) {
            if (!_blockIdPattern.hasMatch(blockId)) {
              throw const CourseFailure(CourseFailureKind.idempotencyConflict);
            }
          }
          final existingBlockDocuments = await _readBlocksInTransaction(
            transaction,
            existing.id,
            storedBlockIds,
            expectedUid: uid,
          );
          _requireSameUser(uid);

          if (!_canonicalFieldsEqual(data, expectedFields, ownerUid: uid) ||
              !_canonicalBlockDocumentsEqual(
                existingBlockDocuments,
                expectedBlockDocuments,
              ) ||
              !_attendanceConfigMatches(
                existingAttendanceConfig.data(),
                normalizedDraft.attendanceMode,
                uid,
              )) {
            throw const CourseFailure(CourseFailureKind.idempotencyConflict);
          }
          final course = _courseFromData(
            id: existing.id,
            data: data,
            blockDocuments: existingBlockDocuments,
            expectedOwnerUid: uid,
          );
          return CourseCreationResult(course: course, wasAlreadyCreated: true);
        }

        for (final blockId in expectedBlockDocuments.keys) {
          _validateBlockDocumentId(blockId);
        }
        final existingBlockDocuments = await _readBlocksInTransaction(
          transaction,
          normalizedDraft.id,
          expectedBlockDocuments.keys,
          expectedUid: uid,
        );

        if (existingBlockDocuments.any((document) => document.exists)) {
          throw const CourseFailure(CourseFailureKind.idempotencyConflict);
        }
        if (existingAttendanceConfig.exists) {
          throw const CourseFailure(CourseFailureKind.idempotencyConflict);
        }

        _requireSameUser(uid);
        transaction.set(reference, {
          ...expectedFields,
          'ownerUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        for (final entry in expectedBlockDocuments.entries) {
          _requireSameUser(uid);
          transaction.set(
            _weeklyBlocks(normalizedDraft.id).doc(entry.key),
            entry.value,
          );
        }
        transaction.set(attendanceConfigReference, {
          'schemaVersion': 1,
          'mode': normalizedDraft.attendanceMode!.value,
          'sessionCount': 0,
          'lastSessionId': null,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });
        return CourseCreationResult(
          course: _courseFromDraft(normalizedDraft, ownerUid: uid),
          wasAlreadyCreated: false,
        );
      });
    } on CourseFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseFailure(CourseFailureKind.invalidCourse, cause: error);
    } on ArgumentError catch (error) {
      throw CourseFailure(CourseFailureKind.invalidCourse, cause: error);
    }
  }

  bool _attendanceConfigMatches(
    Map<String, dynamic>? data,
    AttendanceMode? expectedMode,
    String uid,
  ) =>
      data != null &&
      data['schemaVersion'] == 1 &&
      data['mode'] == expectedMode?.value &&
      data['sessionCount'] is int &&
      (data['sessionCount'] as int) >= 0 &&
      data['lastSessionId'] == null &&
      data['createdBy'] == uid &&
      data['updatedBy'] == uid &&
      data['createdAt'] is Timestamp &&
      data['updatedAt'] is Timestamp;

  Future<String> _requireTeacherUid() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const CourseFailure(CourseFailureKind.unauthenticated);
    }
    final uid = user.uid;
    if (!user.emailVerified) {
      throw const CourseFailure(CourseFailureKind.emailNotVerified);
    }

    final profile = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    final data = profile.data();
    if (!profile.exists || data == null || !_hasValidProfileShape(data, user)) {
      throw const CourseFailure(CourseFailureKind.profileInvalid);
    }
    final roles = data['roles'] as List<Object?>;
    if (!roles.contains('teacher')) {
      throw const CourseFailure(CourseFailureKind.teacherRoleRequired);
    }
    return uid;
  }

  bool _hasValidProfileShape(Map<String, dynamic> profile, User user) {
    const expectedKeys = {'name', 'email', 'studentCode', 'roles'};
    final roles = profile['roles'];
    final studentCode = profile['studentCode'];
    if (profile.keys.toSet().difference(expectedKeys).isNotEmpty ||
        profile.length != expectedKeys.length ||
        profile['name'] is! String ||
        (profile['name'] as String).isEmpty ||
        (profile['name'] as String).length > 100 ||
        profile['email'] is! String ||
        profile['email'] != user.email ||
        !(studentCode == null ||
            studentCode is String &&
                studentCode.isNotEmpty &&
                studentCode.length <= 40) ||
        roles is! List ||
        roles.isEmpty ||
        roles.length > 3) {
      return false;
    }

    final allowedRoles = {'student', 'teacher', 'admin'};
    return roles.every(
          (role) => role is String && allowedRoles.contains(role),
        ) &&
        roles.toSet().length == roles.length;
  }

  void _requireSameUser(String expectedUid) {
    if (_auth.currentUser?.uid != expectedUid) {
      throw const CourseFailure(CourseFailureKind.unauthenticated);
    }
  }

  void _validateDocumentId(String id) {
    if (id.isEmpty || id.contains('/')) {
      throw const CourseFailure(CourseFailureKind.invalidCourse);
    }
  }

  void _validateBlockDocumentId(String id) {
    if (!_blockIdPattern.hasMatch(id)) {
      throw const CourseFailure(CourseFailureKind.invalidCourse);
    }
  }

  Course _courseFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required List<DocumentSnapshot<Map<String, dynamic>>> blockDocuments,
    required String expectedOwnerUid,
  }) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Missing course document data.');
    }
    return _courseFromData(
      id: document.id,
      data: data,
      blockDocuments: blockDocuments,
      expectedOwnerUid: expectedOwnerUid,
    );
  }

  Course _courseFromData({
    required String id,
    required Map<String, dynamic> data,
    required List<DocumentSnapshot<Map<String, dynamic>>> blockDocuments,
    required String expectedOwnerUid,
  }) {
    final ownerUid = data['ownerUid'];
    final subject = data['subject'];
    final group = data['group'];
    final period = data['period'];
    final program = data['program'];
    final timezone = data['timezone'];
    final rawBlockIds = data['weeklyBlockIds'];
    final status = data['status'];
    final schemaVersion = data['schemaVersion'];
    if (ownerUid != expectedOwnerUid ||
        subject is! String ||
        subject.isEmpty ||
        subject.length > 120 ||
        group is! String ||
        group.isEmpty ||
        group.length > 40 ||
        period is! String ||
        period.isEmpty ||
        period.length > 32 ||
        program is! String ||
        program.isEmpty ||
        program.length > 120 ||
        timezone is! String ||
        timezone != CourseSchedule.academicTimezone ||
        rawBlockIds is! List ||
        status is! String ||
        status != 'planned' ||
        schemaVersion is! int ||
        schemaVersion != 1) {
      throw const FormatException('Invalid course document shape.');
    }

    if (!_hasExactlyKeys(data, _parentFields)) {
      throw const FormatException('Invalid course parent fields.');
    }
    final blockIds = <String>[];
    for (final value in rawBlockIds) {
      if (value is! String || !_blockIdPattern.hasMatch(value)) {
        throw const FormatException('Invalid weekly block ID list.');
      }
      blockIds.add(value);
    }
    if (blockIds.isEmpty ||
        blockIds.length > 8 ||
        blockIds.toSet().length != blockIds.length ||
        blockDocuments.length != blockIds.length) {
      throw const FormatException('Invalid weekly block collection.');
    }

    final blocks = <WeeklyBlock>[];
    for (var index = 0; index < blockIds.length; index++) {
      blocks.add(
        _weeklyBlockFromDocument(
          blockDocuments[index],
          expectedId: blockIds[index],
          expectedOrder: index,
        ),
      );
    }
    final startDate = _academicDateFromTimestamp(data['startDate']);
    final endDate = _academicDateFromTimestamp(data['endDate']);
    if (startDate.compareTo(endDate) > 0 ||
        startDate.daysUntil(endDate) > 365) {
      throw const FormatException('Invalid course date range.');
    }
    final schedule = CourseSchedule(
      startDate: startDate,
      endDate: endDate,
      weeklyBlocks: blocks,
      timezone: timezone,
    );
    final normalizedIds = schedule
        .normalized()
        .weeklyBlocks
        .map((block) => block.id)
        .toList(growable: false);
    for (var index = 0; index < blockIds.length; index++) {
      if (normalizedIds[index] != blockIds[index]) {
        throw const FormatException('Weekly block order is not canonical.');
      }
    }
    final createdAt = _requiredDateTime(data['createdAt']);
    final updatedAt = _requiredDateTime(data['updatedAt']);

    return Course(
      id: id,
      ownerUid: ownerUid as String,
      subject: subject,
      group: group,
      period: period,
      program: program,
      schedule: schedule,
      status: status,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  WeeklyBlock _weeklyBlockFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String expectedId,
    required int expectedOrder,
  }) {
    final value = document.data();
    if (value == null) {
      throw const FormatException('Missing course weekly block data.');
    }
    final weekday = value['weekday'];
    final startMinute = value['startMinute'];
    final endMinute = value['endMinute'];
    final room = value['room'];
    if (!document.exists ||
        document.id != expectedId ||
        !_blockIdPattern.hasMatch(document.id) ||
        !_hasExactlyKeys(value, _weeklyBlockFields) ||
        weekday is! int ||
        weekday < 1 ||
        weekday > 7 ||
        startMinute is! int ||
        startMinute < 0 ||
        startMinute >= 1440 ||
        endMinute is! int ||
        endMinute <= startMinute ||
        endMinute >= 1440 ||
        value['order'] != expectedOrder ||
        !(room == null || room is String && room.length <= 60)) {
      throw const FormatException('Invalid course weekly block.');
    }
    return WeeklyBlock(
      id: document.id,
      weekday: weekday,
      startTime: _minuteToTime(startMinute),
      endTime: _minuteToTime(endMinute),
      room: room as String?,
    );
  }

  String _minuteToTime(int minute) {
    final hour = (minute ~/ 60).toString().padLeft(2, '0');
    final remainder = (minute % 60).toString().padLeft(2, '0');
    return '$hour:$remainder';
  }

  bool _hasExactlyKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length && expected.every(value.containsKey);

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _readBlocksInTransaction(
    Transaction transaction,
    String courseId,
    Iterable<String> blockIds, {
    required String expectedUid,
  }) async {
    final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final blockId in blockIds) {
      _requireSameUser(expectedUid);
      final snapshot = await transaction.get(
        _weeklyBlocks(courseId).doc(blockId),
      );
      _requireSameUser(expectedUid);
      snapshots.add(snapshot);
    }
    return snapshots;
  }

  AcademicDate _academicDateFromTimestamp(Object? value) {
    if (value is! Timestamp) {
      throw const FormatException('Invalid course date timestamp.');
    }
    return AcademicDate.fromUtcTimestamp(value.toDate().toUtc());
  }

  DateTime _requiredDateTime(Object? value) {
    if (value is! Timestamp) {
      throw const FormatException('Invalid course audit timestamp.');
    }
    return value.toDate();
  }

  Course _courseFromDraft(CourseDraft draft, {required String ownerUid}) =>
      Course(
        id: draft.id,
        ownerUid: ownerUid,
        subject: draft.subject,
        group: draft.group,
        period: draft.period,
        program: draft.program,
        schedule: draft.schedule,
      );

  bool _canonicalFieldsEqual(
    Map<String, dynamic> stored,
    Map<String, Object?> expected, {
    required String ownerUid,
  }) {
    if (!_hasExactlyKeys(stored, _parentFields) ||
        stored['ownerUid'] != ownerUid ||
        stored['createdAt'] is! Timestamp ||
        stored['updatedAt'] is! Timestamp) {
      return false;
    }
    for (final entry in expected.entries) {
      if (!_deepEquals(stored[entry.key], entry.value)) return false;
    }
    return true;
  }

  bool _canonicalBlockDocumentsEqual(
    List<DocumentSnapshot<Map<String, dynamic>>> stored,
    Map<String, Map<String, Object?>> expected,
  ) {
    if (stored.length != expected.length) return false;
    final entries = expected.entries.toList(growable: false);
    for (var index = 0; index < entries.length; index++) {
      final document = stored[index];
      final expectedEntry = entries[index];
      final data = document.data();
      if (!document.exists ||
          document.id != expectedEntry.key ||
          data == null ||
          !_hasExactlyKeys(data, _weeklyBlockFields) ||
          !_deepEquals(data, expectedEntry.value)) {
        return false;
      }
    }
    return true;
  }

  bool _deepEquals(Object? stored, Object? expected) {
    if (stored is Timestamp) stored = stored.toDate().toUtc();
    if (expected is DateTime) expected = expected.toUtc();
    if (stored is List && expected is List) {
      if (stored.length != expected.length) return false;
      for (var index = 0; index < stored.length; index++) {
        if (!_deepEquals(stored[index], expected[index])) return false;
      }
      return true;
    }
    if (stored is Map && expected is Map) {
      if (stored.length != expected.length) return false;
      for (final key in expected.keys) {
        if (!stored.containsKey(key) ||
            !_deepEquals(stored[key], expected[key])) {
          return false;
        }
      }
      return true;
    }
    return stored == expected;
  }

  CourseFailure _translate(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' => CourseFailure(
        CourseFailureKind.permissionDenied,
        cause: error,
      ),
      'unauthenticated' => CourseFailure(
        CourseFailureKind.unauthenticated,
        cause: error,
      ),
      'network-request-failed' || 'unavailable' || 'deadline-exceeded' =>
        CourseFailure(CourseFailureKind.network, cause: error),
      _ => CourseFailure(CourseFailureKind.unknown, cause: error),
    };
  }
}
