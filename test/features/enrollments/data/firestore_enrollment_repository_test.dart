import 'package:aula_presente/features/enrollments/data/firestore_enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'student query filters own UID and continues beyond 25 results',
    () async {
      final store = _Store();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth(),
        firestore: store,
      );

      final first = await repository.listMyCourses(pageSize: 25);
      expect(first.items, hasLength(25));
      expect(first.hasMore, isTrue);
      expect(first.items.first.studentUid, 'student-one');
      expect(first.items.first.courseId, 'course-00');
      expect(store.uidFilters, ['student-one']);
      expect(store.serverReads, contains('users/student-one'));
      expect(store.serverReads, contains('enrollments'));

      final second = await repository.listMyCourses(
        pageSize: 25,
        cursor: first.nextCursor,
      );
      expect(second.items, hasLength(1));
      expect(second.items.single.courseId, 'course-25');
      expect(second.hasMore, isFalse);
      expect(store.uidFilters, ['student-one', 'student-one']);
      expect(store.startAfters.single.last, first.nextCursor!.documentPath);
    },
  );

  test('account change during query discards previous account data', () async {
    final auth = _Auth();
    final store = _Store()..onQuery = () => auth.user = null;
    final repository = FirestoreEnrollmentRepository(
      auth: auth,
      firestore: store,
    );
    await expectLater(
      repository.listMyCourses(),
      throwsA(
        isA<EnrollmentFailure>().having(
          (error) => error.kind,
          'kind',
          EnrollmentFailureKind.unauthenticated,
        ),
      ),
    );
  });

  test(
    'directory publication uses verified profile and server timestamp',
    () async {
      final store = _Store();
      final auth = _Auth();
      final repository = FirestoreEnrollmentRepository(
        auth: auth,
        firestore: store,
      );
      await repository.ensureStudentDirectoryEntry();
      expect(store.writtenPath, 'student_directory/student@example.invalid');
      expect(store.writtenFields!.keys.toSet(), {
        'uid',
        'name',
        'email',
        'studentCode',
        'updatedAt',
      });
      expect(store.writtenFields!['uid'], 'student-one');
      expect(store.writtenFields!['studentCode'], '0012');
      expect(store.writtenFields!['updatedAt'], isA<FieldValue>());
    },
  );

  test(
    'enrollment transaction writes once and retry returns existing ID',
    () async {
      final store = _Store();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      const candidate = StudentCandidate(
        uid: 'student-one',
        name: 'Student One',
        email: 'student@example.invalid',
        studentCode: '0012',
      );

      final first = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: candidate,
      );
      expect(first.alreadyEnrolled, isFalse);
      expect(first.enrollment.createdAt, isNull);
      expect(store.transactionWriteCount, 1);
      expect(
        store.transactionWritePath,
        'courses/course-00/enrollments/student-one',
      );
      expect(store.transactionWrite!.keys.toSet(), {
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
      expect(store.transactionWrite!['createdAt'], isA<FieldValue>());
      expect(store.transactionReads, [
        'courses/course-00',
        'courses/course-00/enrollments/student-one',
        'student_directory/student@example.invalid',
      ]);

      store.transactionReads.clear();
      store.directoryAvailable = false;
      final again = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: candidate,
      );
      expect(again.alreadyEnrolled, isTrue);
      expect(again.enrollment.studentUid, 'student-one');
      expect(again.enrollment.createdAt, isNotNull);
      expect(store.transactionWriteCount, 1);
      expect(store.transactionReads, [
        'courses/course-00',
        'courses/course-00/enrollments/student-one',
      ]);
    },
  );
}

class _Auth implements FirebaseAuth {
  User? user = _User();
  @override
  User? get currentUser => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'student-one';
  @override
  String get email => 'student@example.invalid';
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TeacherUser extends _User {
  @override
  String get uid => 'teacher-one';
  @override
  String get email => 'teacher@example.invalid';
}

class _Store implements FirebaseFirestore {
  final uidFilters = <Object?>[];
  final startAfters = <List<Object?>>[];
  final serverReads = <String>[];
  void Function()? onQuery;
  String? writtenPath;
  Map<String, dynamic>? writtenFields;
  Map<String, dynamic>? transactionWrite;
  String? transactionWritePath;
  int transactionWriteCount = 0;
  final transactionReads = <String>[];
  Map<String, dynamic>? existingEnrollment;
  bool directoryAvailable = true;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionId) =>
      _Query(this, collectionId, page: 0);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final result = await transactionHandler(_FakeTransaction(this));
    if (transactionWrite != null && existingEnrollment == null) {
      existingEnrollment = {
        ...transactionWrite!,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
      };
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Query implements Query<Map<String, dynamic>> {
  _Query(this.store, this.path, {required this.page, this.maximum = 100});

  final _Store store;
  final String path;
  final int page;
  final int maximum;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    expect(field, 'studentUid');
    store.uidFilters.add(isEqualTo);
    return this;
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    expect(descending, isTrue);
    return this;
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) =>
      _Query(store, path, page: page, maximum: limit);

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) {
    store.startAfters.add(values.toList());
    return _Query(store, path, page: 1, maximum: maximum);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    store.serverReads.add(path);
    store.onQuery?.call();
    return _Snapshot([
      for (
        var index = page == 0 ? 0 : 25;
        index < (page == 0 ? 26 : 26) && index < (page == 0 ? maximum : 26);
        index++
      )
        _Document(
          store,
          'courses/course-${index.toString().padLeft(2, '0')}/enrollments/student-one',
          {
            'studentUid': 'student-one',
            'ownerUid': 'teacher-one',
            'name': 'Student One',
            'email': 'student@example.invalid',
            'studentCode': '0012',
            'subject': 'Course $index',
            'group': 'G1',
            'period': '2026-2',
            'status': 'active',
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 30 - index)),
          },
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.store, super.path) : super(page: 0);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(store, '${this.path}/$path');
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
    store.serverReads.add(path);
    if (path == 'users/student-one') {
      return _Document(store, path, {
        'name': 'Student One',
        'email': 'student@example.invalid',
        'studentCode': '0012',
        'roles': ['student'],
      });
    }
    if (path == 'users/teacher-one') {
      return _Document(store, path, {
        'name': 'Teacher One',
        'email': 'teacher@example.invalid',
        'studentCode': null,
        'roles': ['student', 'teacher'],
      });
    }
    throw StateError('Unexpected document read: $path');
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    store.writtenPath = path;
    store.writtenFields = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransaction implements Transaction {
  _FakeTransaction(this.store);
  final _Store store;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    final path = reference.path;
    store.transactionReads.add(path);
    Map<String, dynamic>? value;
    if (path == 'courses/course-00') {
      value = {
        'ownerUid': 'teacher-one',
        'subject': 'Course 0',
        'group': 'G1',
        'period': '2026-2',
      };
    } else if (path == 'student_directory/student@example.invalid') {
      if (store.directoryAvailable) {
        value = {
          'uid': 'student-one',
          'name': 'Student One',
          'email': 'student@example.invalid',
          'studentCode': '0012',
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
        };
      }
    } else if (path == 'courses/course-00/enrollments/student-one') {
      value = store.existingEnrollment;
    } else {
      throw StateError('Unexpected transaction read: $path');
    }
    final doc = value == null
        ? _MissingDocument(path)
        : _Document(store, path, value);
    return doc as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    store.transactionWritePath = reference.path;
    store.transactionWrite = data as Map<String, dynamic>;
    store.transactionWriteCount++;
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

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
