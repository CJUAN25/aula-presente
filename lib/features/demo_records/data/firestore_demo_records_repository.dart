import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/demo_record.dart';
import '../domain/demo_records_repository.dart';

class FirestoreDemoRecordsRepository implements DemoRecordsRepository {
  FirestoreDemoRecordsRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _currentUserRecords() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const DemoRecordsFailure(DemoRecordsFailureKind.signedOut);
    }
    if (!user.emailVerified) {
      throw const DemoRecordsFailure(DemoRecordsFailureKind.emailNotVerified);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('demo_records');
  }

  @override
  Stream<List<DemoRecord>> watchRecords() async* {
    try {
      final query = _currentUserRecords().orderBy(
        'updatedAt',
        descending: true,
      );
      yield* query.snapshots().map(
        (snapshot) => snapshot.docs
            .map((document) => _fromDocument(document))
            .toList(growable: false),
      );
    } on DemoRecordsFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException {
      throw const DemoRecordsFailure(DemoRecordsFailureKind.invalidData);
    }
  }

  @override
  Future<DemoRecord?> getRecord(String id) async {
    try {
      final snapshot = await _currentUserRecords().doc(id).get();
      if (!snapshot.exists) return null;
      return _fromDocument(snapshot);
    } on DemoRecordsFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException {
      throw const DemoRecordsFailure(DemoRecordsFailureKind.invalidData);
    }
  }

  @override
  Future<void> create({
    required String title,
    required String description,
  }) async {
    try {
      await _currentUserRecords().add({
        'title': title.trim(),
        'description': description.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on DemoRecordsFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> update({
    required String id,
    required String title,
    required String description,
  }) async {
    try {
      await _currentUserRecords().doc(id).update({
        'title': title.trim(),
        'description': description.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on DemoRecordsFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _currentUserRecords().doc(id).delete();
    } on DemoRecordsFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  DemoRecord _fromDocument(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (data == null ||
        data['title'] is! String ||
        data['description'] is! String ||
        !_isTimestampOrPending(data['createdAt']) ||
        !_isTimestampOrPending(data['updatedAt'])) {
      throw const FormatException('Invalid demo record document.');
    }

    return DemoRecord(
      id: document.id,
      title: data['title'] as String,
      description: data['description'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool _isTimestampOrPending(Object? value) =>
      value == null || value is Timestamp;

  DemoRecordsFailure _translate(FirebaseException error) {
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' => const DemoRecordsFailure(
        DemoRecordsFailureKind.permissionDenied,
      ),
      'network-request-failed' || 'unavailable' || 'deadline-exceeded' =>
        const DemoRecordsFailure(DemoRecordsFailureKind.network),
      'not-found' => const DemoRecordsFailure(DemoRecordsFailureKind.notFound),
      _ => const DemoRecordsFailure(DemoRecordsFailureKind.unknown),
    };
  }
}
