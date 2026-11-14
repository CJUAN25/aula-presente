import '../../enrollments/domain/student_candidate.dart';
import 'excel_import_document.dart';

enum ExcelReviewStatus {
  eligible,
  unavailable,
  codeMismatch,
  duplicate,
  alreadyEnrolled,
  withdrawn,
  invalid,
  error,
}

class ExcelReviewedRow {
  const ExcelReviewedRow({
    required this.row,
    required this.status,
    required this.message,
    this.candidate,
  });

  final ExcelImportRow row;
  final ExcelReviewStatus status;
  final StudentCandidate? candidate;
  final String message;

  bool get selectable =>
      status == ExcelReviewStatus.eligible && candidate != null;
}

class ExcelReview {
  ExcelReview({required List<ExcelReviewedRow> rows})
    : rows = List.unmodifiable(rows);

  final List<ExcelReviewedRow> rows;

  int get eligibleCount => rows.where((row) => row.selectable).length;
  int count(ExcelReviewStatus status) =>
      rows.where((row) => row.status == status).length;
}

enum ExcelImportOutcome {
  enrolledNow,
  alreadyEnrolled,
  withdrawn,
  needsReview,
  failed,
}

class ExcelConfirmedRow {
  const ExcelConfirmedRow({
    required this.reviewed,
    required this.outcome,
    required this.message,
  });

  final ExcelReviewedRow reviewed;
  final ExcelImportOutcome outcome;
  final String message;
}

class ExcelImportResult {
  ExcelImportResult({required List<ExcelConfirmedRow> rows})
    : rows = List.unmodifiable(rows);

  final List<ExcelConfirmedRow> rows;

  int count(ExcelImportOutcome outcome) =>
      rows.where((row) => row.outcome == outcome).length;
  int get enrolledNow => count(ExcelImportOutcome.enrolledNow);
  int get alreadyEnrolled => count(ExcelImportOutcome.alreadyEnrolled);
  int get withdrawn => count(ExcelImportOutcome.withdrawn);
  int get needsReview => count(ExcelImportOutcome.needsReview);
  int get failed => count(ExcelImportOutcome.failed);
}
