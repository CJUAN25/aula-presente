import 'demo_record.dart';

abstract interface class DemoRecordsRepository {
  Stream<List<DemoRecord>> watchRecords();

  Future<DemoRecord?> getRecord(String id);

  Future<void> create({required String title, required String description});

  Future<void> update({
    required String id,
    required String title,
    required String description,
  });

  Future<void> delete(String id);
}

enum DemoRecordsFailureKind {
  signedOut,
  emailNotVerified,
  permissionDenied,
  network,
  notFound,
  invalidData,
  unknown,
}

class DemoRecordsFailure implements Exception {
  const DemoRecordsFailure(this.kind);

  final DemoRecordsFailureKind kind;
}
