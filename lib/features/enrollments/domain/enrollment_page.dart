import 'enrollment.dart';

class EnrollmentCursor {
  const EnrollmentCursor({required this.createdAt, required this.documentPath});

  final DateTime createdAt;
  final String documentPath;
}

class EnrollmentPage {
  EnrollmentPage({required List<Enrollment> items, required this.nextCursor})
    : items = List.unmodifiable(items);

  final List<Enrollment> items;
  final EnrollmentCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

class EnrollmentResult {
  const EnrollmentResult({
    required this.enrollment,
    required this.alreadyEnrolled,
  });

  final Enrollment enrollment;
  final bool alreadyEnrolled;
}
