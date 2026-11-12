import 'package:aula_presente/features/course_entry/data/firestore_course_entry_repository.dart';
import 'package:aula_presente/features/course_entry/domain/course_entry_failure.dart';
import 'package:aula_presente/features/course_entry/domain/join_request.dart';
import 'package:aula_presente/features/course_entry/domain/join_request_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'ABCD2345EFGHJKMN';
final _createdAt = Timestamp.fromDate(DateTime.utc(2026, 11, 5, 12));
final _updatedAt = Timestamp.fromDate(DateTime.utc(2026, 11, 5, 12));

void main() {
  test('lifetime status updates preserve code server creation and related documents', () async {
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course();
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
      firestore: store,
    );
    final initial = await repository.createOrGetInvitation(
      'course-1',
      validity: const Duration(days: 7),
    );
    expect(initial.validity, const Duration(days: 7));
    expect(
      store
          .documents['courses/course-1/invitation/current']?['validForSeconds'],
      604800,
    );
    final oldIndex = Map<String, dynamic>.from(
      store.documents['course_invites/${initial.code}']!,
    );
    store.transactionWrites.clear();
    final paused = await repository.pauseInvitation('course-1');
    expect(paused.status, 'paused');
    expect(paused.code, initial.code);
    expect(paused.createdAt, initial.createdAt);
    expect(
      store.transactionWrites.single.data.keys,
      unorderedEquals(['status', 'updatedAt']),
    );
    store.transactionWrites.clear();
    final edited = await repository.updateInvitationValidity(
      'course-1',
      const Duration(days: 30),
    );
    expect(edited.status, 'paused');
    expect(edited.expiresAt, initial.createdAt!.add(const Duration(days: 30)));
    expect(
      store.transactionWrites.single.path,
      'courses/course-1/invitation/current',
    );
    expect(
      store.transactionWrites.single.data.containsKey('createdAt'),
      isFalse,
    );
    store.transactionWrites.clear();
    expect(
      (await repository.reactivateInvitation('course-1')).status,
      'active',
    );
    store.transactionWrites.clear();
    await repository.deactivateInvitation('course-1');
    store.transactionWrites.clear();
    await expectLater(
      repository.reactivateInvitation('course-1'),
      throwsA(
        isA<CourseEntryFailure>().having(
          (e) => e.kind,
          'kind',
          CourseEntryFailureKind.invalidTransition,
        ),
      ),
    );
    expect(store.transactionWrites, isEmpty);
    expect(store.documents['course_invites/${initial.code}'], oldIndex);
    final renewed = await repository.renewInvitation(
      'course-1',
      validity: const Duration(hours: 1),
    );
    expect(renewed.code, isNot(initial.code));
    expect(renewed.validity, const Duration(hours: 1));
  });

  test('confirmed pause survives failed timestamp readback', () async {
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course()
      ..documents['courses/course-1/invitation/current'] = _currentInvitation()
      ..failInvitationReadback = true;
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
      firestore: store,
    );
    final paused = await repository.pauseInvitation('course-1');
    expect(paused.status, 'paused');
    expect(paused.code, _code);
    expect(store.transactionWrites, hasLength(1));
  });

  test('student revalidates an open preview after teacher pauses', () async {
    final auth = _Auth(_User('student-one', 'student@example.invalid'));
    final store = _Store()
      ..documents['users/student-one'] = _studentProfile()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course()
      ..documents['courses/course-1/invitation/current'] = _currentInvitation()
      ..documents['course_invites/$_code'] = _lookup()
      ..restrictStudentReads = true;
    final repository = FirestoreCourseEntryRepository(
      auth: auth,
      firestore: store,
    );
    final preview = await repository.findCourseByCode(_code);
    auth.currentUser = _User('teacher-one', 'teacher@example.invalid');
    store.restrictStudentReads = false;
    await repository.pauseInvitation('course-1');
    store.transactionWrites.clear();
    auth.currentUser = _User('student-one', 'student@example.invalid');
    store.restrictStudentReads = true;
    await expectLater(
      repository.requestJoin(preview.code),
      throwsA(
        isA<CourseEntryFailure>().having(
          (e) => e.kind,
          'kind',
          CourseEntryFailureKind.inviteUnavailable,
        ),
      ),
    );
    expect(store.transactionWrites, isEmpty);
  });

  test('profile denial remains distinct from unavailable code and diagnostics contain no identifiers', () async {
    final store = _Store()..documents['users/student-one'] = _studentProfile();
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('student-one', 'student@example.invalid')),
      firestore: store,
    );
    store.deniedReadPaths.add('users/student-one');
    await expectLater(
      repository.findCourseByCode(_code),
      throwsA(
        isA<CourseEntryFailure>()
            .having(
              (e) => e.kind,
              'kind',
              CourseEntryFailureKind.permissionDenied,
            )
            .having((e) => e.diagnosticStep, 'step', 'profile-get')
            .having((e) => e.diagnosticCode, 'code', 'permission-denied'),
      ),
    );
    store.deniedReadPaths.clear();
    store.deniedReadPaths.add('course_invites/$_code');
    await expectLater(
      repository.findCourseByCode(_code),
      throwsA(
        isA<CourseEntryFailure>()
            .having(
              (e) => e.kind,
              'kind',
              CourseEntryFailureKind.inviteUnavailable,
            )
            .having((e) => e.diagnosticStep, 'step', 'lookup-get'),
      ),
    );
  });

  test('generated and renewed code opens preview and submits without private reads', () async {
    final auth = _Auth(_User('teacher-one', 'teacher@example.invalid'));
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['users/student-one'] = _studentProfile()
      ..documents['users/student-two'] = {
        ..._studentProfile(),
        'email': 'second@example.invalid',
      }
      ..documents['courses/course-1'] = _course();
    final repository = FirestoreCourseEntryRepository(
      auth: auth,
      firestore: store,
    );
    final generated = await repository.createOrGetInvitation('course-1');
    store.transactionWrites.clear();
    store.restrictStudentReads = true;
    auth.currentUser = _User('student-one', 'student@example.invalid');
    final preview = await repository.findCourseByCode(
      generated.groupedCode.toLowerCase(),
    );
    expect(preview.code, generated.code);
    expect(
      (await repository.requestJoin(preview.code)).kind,
      JoinRequestResultKind.created,
    );
    store.transactionWrites.clear();
    store.restrictStudentReads = false;
    auth.currentUser = _User('teacher-one', 'teacher@example.invalid');
    final renewed = await repository.renewInvitation('course-1');
    expect(renewed.code, isNot(generated.code));
    store.transactionWrites.clear();
    store.restrictStudentReads = true;
    auth.currentUser = _User('student-two', 'second@example.invalid');
    expect(
      (await repository.findCourseByCode(renewed.groupedCode)).code,
      renewed.code,
    );
    expect(
      (await repository.requestJoin(renewed.groupedCode)).kind,
      JoinRequestResultKind.created,
    );
    await expectLater(
      repository.findCourseByCode(generated.code),
      throwsA(isA<CourseEntryFailure>()),
    );
  });

  test(
    'creates a new invitation as one atomic index and pointer write',
    () async {
      final store = _Store()
        ..documents['users/teacher-one'] = _teacherProfile()
        ..documents['courses/course-1'] = _course()
        ..documents['courses/course-1/invitation/current'] = null;
      final repository = FirestoreCourseEntryRepository(
        auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
        firestore: store,
      );

      final invitation = await repository.createOrGetInvitation('course-1');

      expect(invitation.courseId, 'course-1');
      expect(invitation.status, 'active');
      expect(invitation.code, hasLength(16));
      expect(
        invitation.code
            .split('')
            .every('23456789ABCDEFGHJKLMNPQRSTUVWXYZ'.contains),
        isTrue,
      );
      expect(invitation.createdAt, isNotNull);
      expect(store.transactionWrites, hasLength(2));
      expect(
        store.transactionWrites.map((write) => write.path).toSet(),
        containsAll([
          'courses/course-1/invitation/current',
          'course_invites/${invitation.code}',
        ]),
      );
      expect(store.transactionReads, [
        'courses/course-1',
        'courses/course-1/invitation/current',
      ]);
    },
  );

  test(
    'reuses an active stored invitation without comparing the phone clock',
    () async {
      final oldCreatedAt = Timestamp.fromDate(DateTime(2000, 1, 1));
      final store = _Store()
        ..documents['users/teacher-one'] = _teacherProfile()
        ..documents['courses/course-1'] = _course()
        ..documents['courses/course-1/invitation/current'] = {
          ..._currentInvitation(),
          'createdAt': oldCreatedAt,
          'updatedAt': oldCreatedAt,
        };
      final repository = FirestoreCourseEntryRepository(
        auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
        firestore: store,
      );

      final invitation = await repository.createOrGetInvitation('course-1');

      expect(invitation.code, _code);
      expect(invitation.state.name, 'active');
      expect(
        invitation.expiresAt,
        oldCreatedAt.toDate().add(const Duration(days: 14)),
      );
      expect(store.transactionWrites, isEmpty);
    },
  );

  test(
    'student request stores only brief snapshots and is idempotent',
    () async {
      final store = _Store()
        ..documents['users/student-one'] = _studentProfile()
        ..documents['course_invites/$_code'] = _lookup()
        ..documents['courses/course-1/invitation/current'] =
            _currentInvitation()
        ..documents['courses/course-1/enrollments/student-one'] = null
        ..documents['courses/course-1/join_requests/student-one'] = null;
      final repository = FirestoreCourseEntryRepository(
        auth: _Auth(_User('student-one', 'student@example.invalid')),
        firestore: store,
      );

      final created = await repository.requestJoin('abcd-2345-efgh-jkmn');

      expect(created.kind, JoinRequestResultKind.created);
      expect(created.request?.status, JoinRequestStatus.pending);
      expect(store.transactionWrites, hasLength(1));
      final requestWrite = store.transactionWrites.single;
      expect(requestWrite.path, 'courses/course-1/join_requests/student-one');
      expect(requestWrite.data.keys.toSet(), {
        'studentUid',
        'name',
        'email',
        'studentCode',
        'subject',
        'group',
        'period',
        'invitationCode',
        'status',
        'createdAt',
        'decidedBy',
        'decidedAt',
        'rejectionReason',
      });
      expect(requestWrite.data['invitationCode'], _code);
      expect(requestWrite.data['createdAt'], isA<FieldValue>());
      expect(requestWrite.data['status'], 'pending');

      store.transactionWrites.clear();
      final retried = await repository.requestJoin(_code);
      expect(retried.kind, JoinRequestResultKind.alreadyPending);
      expect(retried.request?.subject, 'Bases de Datos');
      expect(store.transactionWrites, isEmpty);
    },
  );

  test(
    'confirmed request remains successful if its optional readback fails',
    () async {
      final store = _Store()
        ..documents['users/student-one'] = _studentProfile()
        ..documents['course_invites/$_code'] = _lookup()
        ..documents['courses/course-1/invitation/current'] =
            _currentInvitation()
        ..documents['courses/course-1/enrollments/student-one'] = null
        ..documents['courses/course-1/join_requests/student-one'] = null
        ..failJoinRequestReadback = true;
      final repository = FirestoreCourseEntryRepository(
        auth: _Auth(_User('student-one', 'student@example.invalid')),
        firestore: store,
      );

      final result = await repository.requestJoin(_code);

      expect(result.kind, JoinRequestResultKind.created);
      expect(result.request, isNull);
      expect(
        store
            .documents['courses/course-1/join_requests/student-one']?['status'],
        'pending',
      );
    },
  );

  test('approval atomically writes request and canonical enrollment', () async {
    final request = _pendingRequest();
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course()
      ..documents['courses/course-1/join_requests/student-one'] = request
      ..documents['courses/course-1/enrollments/student-one'] = null;
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
      firestore: store,
    );

    final result = await repository.decideJoinRequest(
      courseId: 'course-1',
      studentUid: 'student-one',
      decision: JoinRequestDecision.approve,
    );

    expect(result.status, JoinDecisionResultStatus.approved);
    expect(result.enrollment?.courseId, 'course-1');
    expect(result.enrollment?.createdAt, isNull);
    expect(store.transactionWrites, hasLength(2));
    final enrollmentWrite = store.transactionWrites.singleWhere(
      (write) => write.path == 'courses/course-1/enrollments/student-one',
    );
    expect(enrollmentWrite.data.keys.toSet(), {
      'studentUid',
      'ownerUid',
      'name',
      'email',
      'studentCode',
      'subject',
      'group',
      'period',
      'status',
      'createdAt',
    });
    expect(enrollmentWrite.data['createdAt'], isA<FieldValue>());
    expect(enrollmentWrite.data['subject'], 'Bases de Datos');
    final requestUpdate = store.transactionWrites.singleWhere(
      (write) => write.path == 'courses/course-1/join_requests/student-one',
    );
    expect(requestUpdate.data['status'], 'approved');
    expect(requestUpdate.data['decidedBy'], 'teacher-one');
    expect(requestUpdate.data['decidedAt'], isA<FieldValue>());
    expect(requestUpdate.data['rejectionReason'], isNull);
  });

  test('rejection saves a reason without creating an enrollment', () async {
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course()
      ..documents['courses/course-1/join_requests/student-one'] =
          _pendingRequest()
      ..documents['courses/course-1/enrollments/student-one'] = null;
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
      firestore: store,
    );

    final result = await repository.decideJoinRequest(
      courseId: 'course-1',
      studentUid: 'student-one',
      decision: JoinRequestDecision.reject,
      rejectionReason: '  Grupo completo  ',
    );

    expect(result.status, JoinDecisionResultStatus.rejected);
    expect(result.request?.rejectionReason, 'Grupo completo');
    expect(store.transactionWrites, hasLength(1));
    expect(
      store.transactionWrites.single.path,
      'courses/course-1/join_requests/student-one',
    );
    expect(store.transactionWrites.single.data['status'], 'rejected');
    expect(store.transactionWrites.single.data['decidedAt'], isA<FieldValue>());
  });

  test('a real permission denial remains a permission failure', () async {
    final store = _Store()
      ..documents['users/teacher-one'] = _teacherProfile()
      ..documents['courses/course-1'] = _course()
      ..documents['courses/course-1/join_requests/student-one'] =
          _pendingRequest()
      ..documents['courses/course-1/enrollments/student-one'] = null
      ..onTransaction = () => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    final repository = FirestoreCourseEntryRepository(
      auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
      firestore: store,
    );

    await expectLater(
      repository.decideJoinRequest(
        courseId: 'course-1',
        studentUid: 'student-one',
        decision: JoinRequestDecision.approve,
      ),
      throwsA(
        isA<CourseEntryFailure>().having(
          (failure) => failure.kind,
          'kind',
          CourseEntryFailureKind.permissionDenied,
        ),
      ),
    );
  });

  test(
    'a denied invitation index write is not retried or mislabeled',
    () async {
      final store = _Store()
        ..documents['users/teacher-one'] = _teacherProfile()
        ..documents['courses/course-1'] = _course()
        ..documents['courses/course-1/invitation/current'] = null
        ..denyInviteIndexCreate = true;
      final repository = FirestoreCourseEntryRepository(
        auth: _Auth(_User('teacher-one', 'teacher@example.invalid')),
        firestore: store,
      );

      await expectLater(
        repository.createOrGetInvitation('course-1'),
        throwsA(
          isA<CourseEntryFailure>().having(
            (failure) => failure.kind,
            'kind',
            CourseEntryFailureKind.permissionDenied,
          ),
        ),
      );
      expect(store.transactionReads, [
        'courses/course-1',
        'courses/course-1/invitation/current',
      ]);
      expect(store.transactionWrites, isEmpty);
    },
  );
}

Map<String, dynamic> _course() => {
  'ownerUid': 'teacher-one',
  'subject': 'Bases de Datos',
  'group': 'G2',
  'period': '2026-2',
};

Map<String, dynamic> _teacherProfile() => {
  'name': 'Docente Uno',
  'email': 'teacher@example.invalid',
  'studentCode': null,
  'roles': ['student', 'teacher'],
};

Map<String, dynamic> _studentProfile() => {
  'name': 'Estudiante Uno',
  'email': 'student@example.invalid',
  'studentCode': '0012',
  'roles': ['student'],
};

Map<String, dynamic> _currentInvitation() => {
  'code': _code,
  'status': 'active',
  'createdAt': _createdAt,
  'updatedAt': _updatedAt,
};

Map<String, dynamic> _lookup() => {
  'courseId': 'course-1',
  'subject': 'Bases de Datos',
  'group': 'G2',
  'period': '2026-2',
  'createdAt': _createdAt,
};

Map<String, dynamic> _pendingRequest() => {
  'studentUid': 'student-one',
  'name': 'Estudiante Uno',
  'email': 'student@example.invalid',
  'studentCode': '0012',
  'subject': 'Bases de Datos',
  'group': 'G2',
  'period': '2026-2',
  'invitationCode': _code,
  'status': 'pending',
  'createdAt': _createdAt,
  'decidedBy': null,
  'decidedAt': null,
  'rejectionReason': null,
};

class _Auth implements FirebaseAuth {
  _Auth(this.currentUser);

  @override
  User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  _User(this.uid, this.email);

  @override
  final String uid;
  @override
  final String email;
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>?>{};
  final transactionReads = <String>[];
  final transactionWrites = <_Write>[];
  void Function()? onTransaction;
  bool failJoinRequestReadback = false;
  bool denyInviteIndexCreate = false;
  bool restrictStudentReads = false;
  bool failInvitationReadback = false;
  final deniedReadPaths = <String>{};

  void checkRead(String path) {
    if (deniedReadPaths.contains(path)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    if (!restrictStudentReads) return;
    if (path.endsWith('/invitation/current')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    if (path.startsWith('course_invites/')) {
      final invite = documents[path];
      final current =
          documents['courses/${invite?['courseId']}/invitation/current'];
      if (invite == null ||
          current?['code'] != path.split('/').last ||
          current?['status'] != 'active') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      }
    }
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionId) =>
      _Query(this, collectionId);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    onTransaction?.call();
    final transaction = _FakeTransaction(this);
    final result = await transactionHandler(transaction);
    for (final write in transactionWrites) {
      final data = _resolveMap(write.data);
      if (write.update) {
        documents[write.path] = {...?documents[write.path], ...data};
      } else {
        documents[write.path] = data;
      }
    }
    return result;
  }

  Map<String, dynamic> _resolveMap(Map<String, dynamic> input) => {
    for (final entry in input.entries)
      entry.key: entry.value is FieldValue ? _updatedAt : entry.value,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Query implements Query<Map<String, dynamic>> {
  _Query(this.store, this.path);

  final _Store store;
  final String path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.store, super.path);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _Reference(
    store,
    path == null || path.isEmpty ? this.path : '${this.path}/$path',
  );
}

// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.store, this.path);

  final _Store store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    store.checkRead(path);
    if (store.failInvitationReadback && path.endsWith('/invitation/current')) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (store.failJoinRequestReadback && path.contains('/join_requests/')) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    final value = store.documents[path];
    return value == null
        ? _MissingDocument(path)
        : _Document(store, path, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Write {
  const _Write(this.path, this.data, {this.update = false});

  final String path;
  final Map<String, dynamic> data;
  final bool update;
}

// ignore: subtype_of_sealed_class
class _FakeTransaction implements Transaction {
  _FakeTransaction(this.store);

  final _Store store;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    store.transactionReads.add(reference.path);
    store.checkRead(reference.path);
    final value = store.documents[reference.path];
    final snapshot = value == null
        ? _MissingDocument(reference.path)
        : _Document(store, reference.path, value);
    return snapshot as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    if (store.denyInviteIndexCreate &&
        reference.path.startsWith('course_invites/')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    store.transactionWrites.add(
      _Write(reference.path, Map<String, dynamic>.from(data as Map)),
    );
    return this;
  }

  @override
  Transaction update(
    DocumentReference<Object?> reference,
    Map<Object, Object?> data,
  ) {
    store.transactionWrites.add(
      _Write(reference.path, data.cast<String, dynamic>(), update: true),
    );
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MissingDocument implements DocumentSnapshot<Map<String, dynamic>> {
  _MissingDocument(this.path);

  final String path;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => false;
  @override
  Map<String, dynamic>? data() => null;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnimplementedError();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.store, this.path, this.value);

  final _Store store;
  final String path;
  final Map<String, dynamic> value;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => true;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _Reference(store, path);
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
