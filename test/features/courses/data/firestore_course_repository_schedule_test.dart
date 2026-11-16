import 'package:aula_presente/features/courses/data/firestore_course_repository.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/courses/domain/course_failure.dart';
import 'package:aula_presente/features/schedule/application/schedule_conflict_detector.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

// These controlled SDK boundaries exercise the real Dart repository and its
// private decoder. No Firebase initialization, network or emulator is used.
void main() {
  test(
    'server-shaped Móvil blocks reach the comparator as Monday/Friday',
    () async {
      final store = _Store();
      final repository = FirestoreCourseRepository(
        auth: _Auth(),
        firestore: store,
      );

      final courses = await repository.getAllOwnCourses();
      final blocks = courses.single.schedule.weeklyBlocks;
      expect(blocks.map((b) => b.weekday), [1, 5]);
      expect(blocks.map((b) => b.startTime), ['08:00', '06:00']);
      expect(blocks.map((b) => b.endTime), ['10:00', '10:00']);
      expect(courses.single.schedule.startDate.isoDate, '2026-11-02');
      expect(courses.single.schedule.endDate.isoDate, '2026-11-15');
      expect(
        findScheduleConflicts(candidate: _logic(), existingCourses: courses),
        isEmpty,
      );
      expect(store.ownerFilters, ['synthetic-teacher']);
      expect(store.serverReads, [
        'users/synthetic-teacher',
        'courses',
        'courses/mobile/weekly_blocks',
      ]);
    },
  );

  test(
    'a different stored weekday is visible in the exact conflict witnesses',
    () async {
      final store = _Store()
        ..firstWeekday = 2
        ..secondWeekday = 4;
      final courses = await FirestoreCourseRepository(
        auth: _Auth(),
        firestore: store,
      ).getAllOwnCourses();
      final check = checkScheduleConflicts(
        candidate: _logic(),
        existingCourses: courses,
      );

      expect(check.conflicts.map((p) => p.candidateMeeting.date.isoDate), [
        '2026-11-03',
        '2026-11-05',
        '2026-11-10',
        '2026-11-12',
      ]);
      for (final pair in check.overlapPairs) {
        expect(pair.existingCourseId, 'mobile');
        expect(pair.existingMeeting.courseId, 'mobile');
        expect(pair.existingMeeting.date, pair.candidateMeeting.date);
        expect(pair.existingMeeting.weekday, pair.candidateMeeting.weekday);
      }
    },
  );

  test(
    'conflict agenda follows all pages and reads each course own children',
    () async {
      final store = _Store()..withSecondCourse = true;
      final courses = await FirestoreCourseRepository(
        auth: _Auth(),
        firestore: store,
      ).getAllOwnCourses(pageSize: 1);

      expect(courses.map((c) => c.id), ['mobile', 'older']);
      expect(store.cursors, [
        [Timestamp.fromDate(DateTime.utc(2026, 11, 1)), 'mobile'],
      ]);
      expect(
        store.serverReads,
        containsAllInOrder([
          'courses/mobile/weekly_blocks',
          'courses',
          'courses/older/weekly_blocks',
        ]),
      );
    },
  );

  test(
    'failed child read is propagated, not converted into an empty agenda',
    () async {
      final store = _Store()..failBlocks = true;
      final repository = FirestoreCourseRepository(
        auth: _Auth(),
        firestore: store,
      );
      await expectLater(
        repository.getAllOwnCourses(),
        throwsA(
          isA<CourseFailure>().having(
            (e) => e.kind,
            'kind',
            CourseFailureKind.network,
          ),
        ),
      );
    },
  );
  test(
    'account change during child read discards the previous session agenda',
    () async {
      final auth = _Auth();
      final store = _Store()
        ..onRead = (path) {
          if (path.endsWith('/weekly_blocks')) auth.user = null;
        };
      final repository = FirestoreCourseRepository(
        auth: auth,
        firestore: store,
      );

      await expectLater(
        repository.getAllOwnCourses(),
        throwsA(
          isA<CourseFailure>().having(
            (e) => e.kind,
            'kind',
            CourseFailureKind.unauthenticated,
          ),
        ),
      );
    },
  );
}

CourseDraft _logic() => CourseDraft(
  id: 'draft_logic_0000000001',
  subject: 'Synthetic',
  group: '01',
  period: 'test',
  program: 'test',
  attendanceMode: AttendanceMode.meeting,
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
    endDate: AcademicDate(year: 2026, month: 11, day: 15),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'logic_tuesday_block_01',
        weekday: 2,
        startTime: '08:00',
        endTime: '09:00',
      ),
      WeeklyBlock(
        id: 'logic_thursday_block01',
        weekday: 4,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);

class _Auth implements FirebaseAuth {
  User? user = _User();
  @override
  User? get currentUser => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'synthetic-teacher';
  @override
  String get email => 'synthetic@example.invalid';
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements FirebaseFirestore {
  int firstWeekday = 1;
  int secondWeekday = 5;
  bool withSecondCourse = false;
  bool failBlocks = false;
  void Function(String path)? onRead;
  final serverReads = <String>[];
  final ownerFilters = <Object?>[];
  final cursors = <List<Object?>>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  Map<String, dynamic> parent(String id) => {
    'ownerUid': 'synthetic-teacher',
    'subject': 'Synthetic',
    'group': '01',
    'period': 'test',
    'program': 'test',
    'timezone': 'America/Bogota',
    'startDate': Timestamp.fromDate(DateTime.utc(2026, 11, 2)),
    'endDate': Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
    'weeklyBlockIds': ['block_first_0000000001', 'block_second_000000001'],
    'status': 'planned',
    'schemaVersion': 1,
    'createdAt': Timestamp.fromDate(
      DateTime.utc(2026, 11, id == 'mobile' ? 1 : 0),
    ),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Intentional SDK test double; not an alternative Firestore implementation.
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path, {this.after = false});
  final _Store store;
  @override
  final String path;
  final bool after;

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
    expect(field, 'ownerUid');
    store.ownerFilters.add(isEqualTo);
    return this;
  }

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => this;
  @override
  Query<Map<String, dynamic>> limit(int limit) => this;
  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) {
    store.cursors.add(values.toList());
    return _Collection(store, path, after: true);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(store, '${this.path}/$path');
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    store.serverReads.add(path);
    store.onRead?.call(path);
    if (path == 'courses') {
      return _Snapshot([
        if (!after) _Document('mobile', store.parent('mobile')),
        if (store.withSecondCourse) _Document('older', store.parent('older')),
      ]);
    }
    if (store.failBlocks) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return _Snapshot([
      _Document('block_first_0000000001', {
        'weekday': store.firstWeekday,
        'startMinute': 480,
        'endMinute': 600,
        'room': null,
        'order': 0,
      }),
      _Document('block_second_000000001', {
        'weekday': store.secondWeekday,
        'startMinute': 360,
        'endMinute': 600,
        'room': null,
        'order': 1,
      }),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    store.serverReads.add(path);
    return _Document('synthetic-teacher', {
      'name': 'Synthetic',
      'email': 'synthetic@example.invalid',
      'studentCode': null,
      'roles': ['student', 'teacher'],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  bool get exists => true;
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
